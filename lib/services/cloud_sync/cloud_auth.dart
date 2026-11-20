import 'package:googleapis/oauth2/v2.dart' as oauth2;
import 'package:googleapis_auth/googleapis_auth.dart'
    show AccessDeniedException;
import 'package:http/http.dart' as http;

/// 一次互動式連結的結果；呼叫端確認結果仍有效後才 [commit]。
class CloudLinkResult {
  /// 建立 [CloudLinkResult]。
  const CloudLinkResult({
    required this.client,
    required this.email,
    required this.commit,
  });

  /// 已授權的 HTTP client；用畢由呼叫端 close。
  final http.Client client;

  /// 已連結帳號的 email。
  final String email;

  /// 持久化本次授權（Windows：寫入 refresh token；Android：no-op）。
  final Future<void> Function() commit;
}

/// 使用者在授權畫面取消時拋出。
class CloudLinkCancelledException implements Exception {
  /// 建立 [CloudLinkCancelledException]。
  const CloudLinkCancelledException(this.reason);

  /// 取消原因，僅供 log（例如 GoogleSignInExceptionCode 名稱）。
  final String reason;

  @override
  String toString() => 'CloudLinkCancelledException($reason)';
}

/// 雲端同步的授權介面，依平台各自實作。
abstract class CloudAuth {
  /// 這個實作的 client 能否跨多輪同步沿用。
  bool get keepsClientAcrossRounds;

  /// 互動式連結：[openUrl] 收到授權頁 URL 時開啟瀏覽器；[postAuthPage] 為授權成功後顯示的 HTML。
  Future<CloudLinkResult> link({
    required void Function(String url) openUrl,
    String? postAuthPage,
  });

  /// 還原已連結帳號的授權 client；無法靜默還原時回 null 或拋 `CloudReauthRequiredException`。
  Future<http.Client?> restoreClient({required String expectedEmail});

  /// 中斷連結：只忘記本機，不向 Google 撤銷。
  Future<void> unlink();
}

/// 以已授權的 [client] 呼叫 userinfo 取 email；沒有 email 時拋 [StateError]。
Future<String> fetchCloudEmail(http.Client client) async {
  final info = await oauth2.Oauth2Api(client).userinfo.get();
  final email = info.email;
  if (email == null || email.isEmpty) {
    throw StateError('userinfo returned no email');
  }
  return email;
}

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

/// 判斷例外是否為 API 拒絕 access token（已撤銷／失效）。
///
/// 兩種表面：googleapis 的 `DetailedApiRequestError` 401；或 `AuthenticatedClient`
/// 遇 `www-authenticate: ... error="invalid_token"` 直接拋的 `AccessDeniedException`。
bool isInvalidToken(Object e) =>
    (e is oauth2.DetailedApiRequestError && e.status == 401) ||
    (e is AccessDeniedException && e.message.contains('invalid_token'));
