import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_auth.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_sync_config.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/token_store.dart';

/// 檢查實際授予的 [granted] scopes 是否含雲端同步必要的 `drive.appdata`。
///
/// 只檢查 Drive scope：email 即使漏授，Google 也可能以
/// `userinfo.email` 等別名回傳，且缺 email 會在取 userinfo 時另行失敗。
bool hasRequiredCloudScopes(Iterable<String> granted) =>
    granted.contains('https://www.googleapis.com/auth/drive.appdata');

/// 以既存 refresh token 建立「已過期」的種子憑證，供 refreshCredentials 換新 access token。
AccessCredentials buildResumeCredentials(String refreshToken) =>
    AccessCredentials(
      AccessToken(
        'Bearer',
        '',
        DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      ),
      refreshToken,
      cloudSyncScopes,
    );

/// 登入成功的授權會話：可用的 [AuthClient]、帳號 email 與 refresh token。
class CloudAuthSession {
  /// 建立 [CloudAuthSession]。
  const CloudAuthSession({
    required this.client,
    required this.email,
    required this.refreshToken,
  });

  /// 自動續期的授權 HTTP client；用畢由呼叫端 close。
  final AuthClient client;

  /// 已連結帳號的 email。
  final String email;

  /// 本次授權取得的 refresh token；由呼叫端決定是否持久化。
  final String refreshToken;
}

/// 包住 [AutoRefreshingAuthClient]，close 時連同自建的底層 base client 一併關閉。
class _OwningAuthClient extends http.BaseClient implements AuthClient {
  /// 建立 [_OwningAuthClient]。
  _OwningAuthClient(this._inner, this._base);

  /// 實際的自動續期授權 client。
  final AutoRefreshingAuthClient _inner;

  /// 自建的底層 client，close 時一併關閉。
  final http.Client _base;

  /// 目前的授權憑證（委派給內部 client）。
  @override
  AccessCredentials get credentials => _inner.credentials;

  /// 發送授權請求（委派給內部 client）。
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request);

  /// 關閉授權 client 與底層 HTTP client。
  @override
  void close() {
    _inner.close();
    _base.close();
    super.close();
  }
}

/// Google OAuth 授權服務（Windows）：登入（系統瀏覽器 loopback）、以 refresh token 還原、登出。
///
/// 登出只刪本機 token，不向 Google 撤銷授權（撤銷會讓同一 Cloud 專案下所有裝置失效）。
class GoogleAuthService implements CloudAuth {
  /// 建立 [GoogleAuthService]。
  GoogleAuthService({
    required this.tokenStore,
    required this.baseClientFactory,
  });

  /// refresh token 的安全儲存。
  final TokenStore tokenStore;

  /// 建立底層 HTTP client 的工廠（測試注入 MockClient 用）。
  final http.Client Function() baseClientFactory;

  /// Logger 實例（授權流程）。
  static final _log = Logger('cloudsync.auth');

  /// OAuth 用戶端識別。
  static final _clientId = ClientId(cloudSyncClientId, cloudSyncClientSecret);

  /// 走 installed-app loopback 流程登入：[openUrl] 收到授權頁 URL 時開啟系統瀏覽器。
  ///
  /// [postAuthPage] 為授權成功後瀏覽器顯示的自訂 HTML（null 用套件預設英文頁）；
  /// 失敗路徑的回應頁套件未開放自訂。
  /// 回傳的 session 帶著 refresh token，是否寫入 [tokenStore] 交由呼叫端決定
  /// （避免取消連結後遲到的授權結果覆蓋較新的 token；見 [CloudAuthSession]）。
  Future<CloudAuthSession> signIn(
    void Function(String url) openUrl, {
    String? postAuthPage,
  }) async {
    _log.info('signIn start');
    final client = await clientViaUserConsent(
      _clientId,
      cloudSyncScopes,
      openUrl,
      customPostAuthPage: postAuthPage,
    );
    try {
      final refresh = client.credentials.refreshToken;
      if (refresh == null) {
        throw StateError('OAuth flow returned no refresh token');
      }
      // Google 逐項授權（granular consent）允許使用者漏勾 Drive 權限並照樣發
      // token；此時直接拋出（不撤銷），讓使用者立刻得知要重新授權，
      // 而不是等第一輪同步 403 才發現。
      final granted = client.credentials.scopes;
      if (!hasRequiredCloudScopes(granted)) {
        _log.warning(
          'signIn: drive.appdata not granted (granted=${granted.join(' ')})',
        );
        throw const CloudScopeMissingException();
      }
      final email = await fetchCloudEmail(client);
      _log.info('signIn ok');
      return CloudAuthSession(
        client: client,
        email: email,
        refreshToken: refresh,
      );
    } catch (e) {
      client.close();
      rethrow;
    }
  }

  /// 以已存的 refresh token 還原授權 client；無 token 回 null。
  ///
  /// token 已被撤銷（invalid_grant）時拋 [CloudReauthRequiredException]。
  Future<AuthClient?> restore() async {
    final refresh = await tokenStore.readRefreshToken();
    if (refresh == null) {
      _log.info('restore: no stored token');
      return null;
    }
    final base = baseClientFactory();
    try {
      final refreshed = await refreshCredentials(
        _clientId,
        buildResumeCredentials(refresh),
        base,
      );
      _log.info('restore ok');
      return _OwningAuthClient(
        autoRefreshingClient(_clientId, refreshed, base),
        base,
      );
    } catch (e) {
      base.close();
      if (isInvalidGrant(e)) {
        _log.warning('restore: invalid_grant, reauth required');
        throw const CloudReauthRequiredException();
      }
      rethrow;
    }
  }

  /// 登出：只刪除本機 refresh token，不向 Google 撤銷。
  Future<void> signOut() async {
    await tokenStore.deleteRefreshToken();
    _log.info('signOut done (local only)');
  }

  /// refresh token 會自動續期，client 可跨多輪同步沿用。
  @override
  bool get keepsClientAcrossRounds => true;

  /// 走 [signIn] 連結；[CloudLinkResult.commit] 才把 refresh token 寫入 [tokenStore]。
  @override
  Future<CloudLinkResult> link({
    required void Function(String url) openUrl,
    String? postAuthPage,
  }) async {
    final session = await signIn(openUrl, postAuthPage: postAuthPage);
    return CloudLinkResult(
      client: session.client,
      email: session.email,
      commit: () => tokenStore.writeRefreshToken(session.refreshToken),
    );
  }

  /// 以已存的 refresh token 還原（見 [restore]）；[expectedEmail] 不使用。
  @override
  Future<http.Client?> restoreClient({required String expectedEmail}) =>
      restore();

  /// 中斷連結（見 [signOut]）。
  @override
  Future<void> unlink() => signOut();
}
