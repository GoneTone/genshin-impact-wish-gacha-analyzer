import 'dart:async';

import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:http/http.dart' as http;

import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_auth.dart';
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
  /// 建立 [FakeAuthService]，以 [store] 作為底層 token store；
  /// [baseClientFactory] 供測試計數底層 HTTP client 的建立。
  FakeAuthService(this.store, {http.Client Function()? baseClientFactory})
    : super(
        tokenStore: store,
        baseClientFactory: baseClientFactory ?? http.Client.new,
      );

  /// 供斷言的 token store。
  final InMemoryTokenStore store;

  /// restore 是否要拋 invalid_grant（reauth）。
  bool restoreThrowsReauth = false;

  /// 非 null 時 `signIn` 會在回傳 session 前 await 此 future，供測試卡住授權流程
  /// （例如驗證 cancelLink 對「尚在等待中」授權的丟棄行為）。
  Future<void>? signInGate;

  /// signIn 是否要模擬「授權未含必要 scope」而拋 [CloudScopeMissingException]。
  bool signInThrowsScopeMissing = false;

  /// signIn 是否要模擬使用者取消而拋 [CloudLinkCancelledException]。
  bool signInThrowsCancelled = false;

  /// restore() 被呼叫的次數，供斷言「不重複還原」用。
  int restoreCalls = 0;

  /// 被撤銷的 refresh token 清單；App 已不向 Google 撤銷，供斷言恆為空。
  final List<String> revokedTokens = [];

  /// 模擬登入：呼叫 openUrl 後（視 [signInGate] 等待）回傳成功 session（refresh token 交由呼叫端寫入）。
  @override
  Future<CloudAuthSession> signIn(
    void Function(String url) openUrl, {
    String? postAuthPage,
  }) async {
    openUrl('https://accounts.google.com/consent');
    if (signInGate != null) await signInGate;
    if (signInThrowsCancelled) {
      throw const CloudLinkCancelledException('canceled');
    }
    if (signInThrowsScopeMissing) throw const CloudScopeMissingException();
    return CloudAuthSession(
      client: FakeAuthClient(),
      email: 'u@example.com',
      refreshToken: 'refresh-1',
    );
  }

  /// 模擬還原：依 [restoreThrowsReauth] 與 store 內容回傳。
  @override
  Future<AuthClient?> restore() async {
    restoreCalls++;
    if (restoreThrowsReauth) throw const CloudReauthRequiredException();
    if (store.token == null) return null;
    return FakeAuthClient();
  }

  /// 模擬登出：清除 store 內 token。
  @override
  Future<void> signOut() async => store.deleteRefreshToken();
}

/// 記錄呼叫的 fake 遠端。
class FakeRemote implements CloudSyncRemote {
  /// 雲端檔內容；null = 不存在。
  String? content;

  /// upload 次數。
  int uploads = 0;

  /// download 次數（雲端已是最新時會跳過 upload，輪數要靠它數）。
  int downloads = 0;

  /// 非 null 時 `download` 會先 await 此 completer 的 future，供測試卡住同步輪
  /// （驗證 single-flight／pendingRerun 行為）。
  Completer<void>? downloadGate;

  /// 非 null 時 `download` 直接拋出此例外（模擬中途失去權限等錯誤）。
  Object? downloadError;

  /// 回傳目前雲端檔內容；視 [downloadGate]／[downloadError] 而定。
  @override
  Future<String?> download() async {
    downloads++;
    if (downloadGate != null) await downloadGate!.future;
    if (downloadError != null) throw downloadError!;
    return content;
  }

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
