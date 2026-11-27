import 'package:google_sign_in/google_sign_in.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_auth.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_sync_config.dart';

/// [e] 是否為使用者主動取消授權。
///
/// google_sign_in_android 7.2.18 不看 resultCode，Activity 被取消（按返回）時
/// 會以 ApiException 狀態碼 16（CANCELED）浮出為 [GoogleSignInExceptionCode.unknownError]，
/// 因此除了 canceled 之外還要比對描述中的狀態碼形式（不依賴英文字樣）。
bool isUserCancellation(GoogleSignInException e) =>
    e.code == GoogleSignInExceptionCode.canceled ||
    (e.code == GoogleSignInExceptionCode.unknownError &&
        (e.description?.contains('SDK reported an exception: 16:') ?? false));

/// google_sign_in 授權 API 的最小介面（測試替換用）。
abstract class GoogleAuthorizationGateway {
  /// 不跳任何畫面取得通行證；需要使用者操作時回 null。
  Future<String?> silentToken();

  /// 跳帳號選擇／授權畫面取得通行證；使用者取消時拋 [CloudLinkCancelledException]。
  Future<String> interactiveToken();

  /// 清掉系統快取的這張通行證。
  Future<void> clearToken(String token);

  /// 清掉本機登入狀態（不撤銷）。
  Future<void> signOut();
}

/// 以 google_sign_in 的授權 API（Play services）實作 [GoogleAuthorizationGateway]。
class PluginGoogleAuthorizationGateway implements GoogleAuthorizationGateway {
  /// 進行中或已完成的初始化；失敗時重設為 null 以便下次重試。
  Future<void>? _init;

  /// 確保 [GoogleSignIn.instance] 已初始化後回傳其授權 client。
  Future<GoogleSignInAuthorizationClient> _client() async {
    try {
      await (_init ??= GoogleSignIn.instance.initialize());
    } catch (_) {
      _init = null;
      rethrow;
    }
    return GoogleSignIn.instance.authorizationClient;
  }

  /// 以 `authorizationForScopes` 靜默取得通行證。
  @override
  Future<String?> silentToken() async {
    final auth = await (await _client()).authorizationForScopes(
      cloudSyncScopes,
    );
    return auth?.accessToken;
  }

  /// 以 `authorizeScopes` 跳畫面取得通行證；使用者取消轉為 [CloudLinkCancelledException]。
  @override
  Future<String> interactiveToken() async {
    final client = await _client();
    try {
      return (await client.authorizeScopes(cloudSyncScopes)).accessToken;
    } on GoogleSignInException catch (e) {
      if (isUserCancellation(e)) {
        // 設定錯誤也可能表現為取消，原因留給 log 辨別。
        throw CloudLinkCancelledException('${e.code.name}: ${e.description}');
      }
      rethrow;
    }
  }

  /// 以 `clearAuthorizationToken` 清掉 [token] 的系統快取。
  @override
  Future<void> clearToken(String token) async =>
      (await _client()).clearAuthorizationToken(accessToken: token);

  /// 呼叫 [GoogleSignIn.signOut] 清掉本機登入狀態。
  @override
  Future<void> signOut() async {
    await _client();
    await GoogleSignIn.instance.signOut();
  }
}
