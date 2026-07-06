import 'dart:async';
import 'dart:io';

import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:http/http.dart' as http;

import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_sync_remote.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/google_auth_service.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/token_store.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_storage.dart';
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

  /// 非 null 時 `signIn` 會在回傳 session 前 await 此 future，供測試卡住授權流程
  /// （例如驗證 cancelLink 對「尚在等待中」授權的丟棄行為）。
  Future<void>? signInGate;

  /// 記錄 `revokeToken` 被呼叫過的 refresh token 清單。
  final List<String> revokedTokens = [];

  /// 模擬登入：呼叫 openUrl 後（視 [signInGate] 等待）回傳成功 session（refresh token 交由呼叫端寫入）。
  @override
  Future<CloudAuthSession> signIn(
    void Function(String url) openUrl, {
    String? postAuthPage,
  }) async {
    openUrl('https://accounts.google.com/consent');
    if (signInGate != null) await signInGate;
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

  /// 模擬 revoke：記錄被 revoke 的 token，供測試斷言。
  @override
  Future<void> revokeToken(String refreshToken) async {
    revokedTokens.add(refreshToken);
  }
}

/// 記錄呼叫的 fake 遠端。
class FakeRemote implements CloudSyncRemote {
  /// 雲端檔內容；null = 不存在。
  String? content;

  /// upload 次數。
  int uploads = 0;

  /// 非 null 時 `download` 會先 await 此 completer 的 future，供測試卡住同步輪
  /// （驗證 single-flight／pendingRerun 行為）。
  Completer<void>? downloadGate;

  /// 非 null 時 `download` 直接拋出此例外（模擬中途失去權限等錯誤）。
  Object? downloadError;

  /// 回傳目前雲端檔內容；視 [downloadGate]／[downloadError] 而定。
  @override
  Future<String?> download() async {
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

/// 純記憶體版 [GachaStorage]：所有讀寫皆走記憶體 Map，不碰真實檔案系統。
///
/// 用於需要在 `fakeAsync` 虛擬時鐘下驅動真實 [Timer] 的測試——真實檔案
/// I/O 由背景執行緒完成，其完成通知不受 `FakeAsync.elapse` 控制，在
/// 同步的 fakeAsync callback 內永遠等不到；換成純記憶體實作後，所有
/// Future 都只透過 microtask 完成，`flushMicrotasks` 才能確實推進到底。
class InMemoryGachaStorage extends GachaStorage {
  /// 建立 [InMemoryGachaStorage]（[baseDir] 僅為滿足父類建構子，不會被使用）。
  InMemoryGachaStorage() : super(Directory.systemTemp);

  /// 記憶體內的帳號資料，key 為 uid。
  final Map<String, BannerStorage> _data = {};

  /// 記憶體內的已擷取 URL，key 為 uid。
  final Map<String, String> _capturedUrls = {};

  /// 讀取 [uid] 的祈願資料；不存在時回傳 null。
  @override
  Future<BannerStorage?> load(String uid) async => _data[uid];

  /// 寫入 [data]（覆蓋同 uid 的既有資料）。
  @override
  Future<void> save(BannerStorage data) async => _data[data.uid] = data;

  /// 回傳目前已知的所有 UID。
  @override
  Future<List<String>> listKnownUids() async => _data.keys.toList();

  /// 讀取 [uid] 的已擷取 URL；不存在時回傳 null。
  @override
  Future<String?> loadCapturedUrl(String uid) async => _capturedUrls[uid];

  /// 寫入 [uid] 的已擷取 URL。
  @override
  Future<void> saveCapturedUrl(String uid, String url) async =>
      _capturedUrls[uid] = url;

  /// 刪除 [uid] 的已擷取 URL。
  @override
  Future<void> deleteCapturedUrl(String uid) async => _capturedUrls.remove(uid);

  /// 刪除 [uid] 的所有資料（帳號資料＋已擷取 URL）。
  @override
  Future<void> delete(String uid) async {
    _data.remove(uid);
    _capturedUrls.remove(uid);
  }

  /// 清除所有帳號資料與已擷取 URL。
  @override
  Future<void> clearAll() async {
    _data.clear();
    _capturedUrls.clear();
  }
}
