import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:http/http.dart' as http;

import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_sync_remote.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/google_auth_service.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/token_store.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_capture.dart';

/// 測試用 in-memory token store。
class InMemoryTokenStore implements TokenStore {
  /// 目前存放的 token。
  String? token;

  /// 讀取目前存放的 token。
  @override
  Future<String?> readRefreshToken() async => token;

  /// 寫入 token。
  @override
  Future<void> writeRefreshToken(String t) async => token = t;

  /// 清除 token。
  @override
  Future<void> deleteRefreshToken() async => token = null;
}

/// 不發真請求的 fake AuthClient。
class FakeAuthClient extends http.BaseClient implements AuthClient {
  /// 憑證（測試不使用）。
  @override
  AccessCredentials get credentials => throw UnimplementedError();

  /// 發送請求（測試不使用）。
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw UnimplementedError();
}

/// 可程式化行為的 fake 授權服務。
class FakeAuthService extends GoogleAuthService {
  /// 建立 [FakeAuthService]。
  FakeAuthService(this.store)
    : super(tokenStore: store, baseClientFactory: http.Client.new);

  /// 供斷言的 token store。
  final InMemoryTokenStore store;

  /// restore 是否要拋 invalid_grant（reauth）。
  bool restoreThrowsReauth = false;

  /// 模擬登入：呼叫 openUrl 後直接回傳成功 session（refresh token 交由呼叫端寫入）。
  @override
  Future<CloudAuthSession> signIn(
    void Function(String url) openUrl, {
    String? postAuthPage,
  }) async {
    openUrl('https://accounts.google.com/consent');
    return CloudAuthSession(
      client: FakeAuthClient(),
      email: 'u@example.com',
      refreshToken: 'refresh-1',
    );
  }

  /// 模擬還原：依 [restoreThrowsReauth] 與 store 內容回傳。
  @override
  Future<AuthClient?> restore() async {
    if (restoreThrowsReauth) throw const CloudReauthRequiredException();
    if (store.token == null) return null;
    return FakeAuthClient();
  }

  /// 模擬登出：清除 store 內 token。
  @override
  Future<void> signOut() async => store.deleteRefreshToken();

  /// 模擬 revoke：no-op。
  @override
  Future<void> revokeToken(String refreshToken) async {}
}

/// 記錄呼叫的 fake 遠端。
class FakeRemote implements CloudSyncRemote {
  /// 雲端檔內容；null = 不存在。
  String? content;

  /// upload 次數。
  int uploads = 0;

  /// 回傳目前雲端檔內容。
  @override
  Future<String?> download() async => content;

  /// 記錄上傳並更新內容。
  @override
  Future<void> upload(String json) async {
    uploads++;
    content = json;
  }
}

/// 不會被觸發的 fake capture。
class FakeCapture implements GachaCapture {
  /// 回傳永遠無結果的 capture session。
  @override
  CaptureSession start() =>
      CaptureSession(result: Future.value(null), cancel: () async {});
}
