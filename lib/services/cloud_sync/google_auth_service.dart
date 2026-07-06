import 'package:googleapis/oauth2/v2.dart' as oauth2;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_sync_config.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/token_store.dart';

/// refresh token 已失效（使用者於 Google 端撤銷授權），需要重新連結時拋出。
class CloudReauthRequiredException implements Exception {
  /// 建立 [CloudReauthRequiredException]。
  const CloudReauthRequiredException();

  @override
  String toString() => 'CloudReauthRequiredException';
}

/// 授權結果未包含必要的 Drive scope（使用者在 Google 逐項授權頁漏勾）時拋出。
class CloudScopeMissingException implements Exception {
  /// 建立 [CloudScopeMissingException]。
  const CloudScopeMissingException();

  @override
  String toString() => 'CloudScopeMissingException';
}

/// 判斷例外是否為 OAuth `invalid_grant`（refresh token 被撤銷／過期）。
bool isInvalidGrant(Object e) => e.toString().contains('invalid_grant');

/// 判斷例外是否為 API 回報的「token 缺必要權限」。
///
/// 覆蓋兩種真實錯誤表面：googleapis_auth 的 `AuthenticatedClient` 對帶
/// `www-authenticate` header 的回應直接拋 `insufficient_scope`（生產環境
/// 實測主要路徑）；無該 header 時 googleapis 走 `DetailedApiRequestError`，
/// 訊息為 `insufficient authentication scopes` 或結構化 reason。
bool isInsufficientScope(Object e) {
  final s = e.toString();
  return s.contains('insufficient_scope') ||
      s.contains('insufficient authentication scopes') ||
      s.contains('ACCESS_TOKEN_SCOPE_INSUFFICIENT');
}

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

/// Google OAuth 授權服務：登入（系統瀏覽器 loopback）、以 refresh token 還原、登出。
class GoogleAuthService {
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
      // token；此時當場 revoke 並拋出，讓使用者立刻得知要重新授權，
      // 而不是等第一輪同步 403 才發現。
      final granted = client.credentials.scopes;
      if (!hasRequiredCloudScopes(granted)) {
        _log.warning(
          'signIn: drive.appdata not granted (granted=${granted.join(' ')})',
        );
        await revokeToken(refresh);
        throw const CloudScopeMissingException();
      }
      final email = await _fetchEmail(client);
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

  /// 登出：向 Google revoke（盡力而為，失敗不阻擋）並刪除本機 refresh token。
  Future<void> signOut() async {
    final refresh = await tokenStore.readRefreshToken();
    if (refresh != null) {
      await revokeToken(refresh);
    }
    await tokenStore.deleteRefreshToken();
    _log.info('signOut done');
  }

  /// 向 Google revoke 指定的 refresh token（盡力而為，失敗僅記警告不拋出；
  /// 絕不把 token 內容寫進 log）。
  Future<void> revokeToken(String refreshToken) async {
    final base = baseClientFactory();
    try {
      final res = await base.post(
        Uri.parse('https://oauth2.googleapis.com/revoke'),
        body: {'token': refreshToken},
      );
      if (res.statusCode == 200) {
        _log.info('revoke ok');
      } else {
        _log.warning('revoke failed (ignored): HTTP ${res.statusCode}');
      }
    } catch (e) {
      _log.warning('revoke failed (ignored): $e');
    } finally {
      base.close();
    }
  }

  /// 以 userinfo API 取得已授權帳號的 email。
  Future<String> _fetchEmail(http.Client client) async {
    final info = await oauth2.Oauth2Api(client).userinfo.get();
    final email = info.email;
    if (email == null || email.isEmpty) {
      throw StateError('userinfo returned no email');
    }
    return email;
  }
}
