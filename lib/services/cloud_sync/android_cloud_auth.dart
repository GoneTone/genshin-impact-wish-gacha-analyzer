import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_auth.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_sync_config.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/google_authorization_gateway.dart';

/// Android 的 [CloudAuth]：以 Play services 授權 API 取短效通行證，不保存 refresh token。
class AndroidCloudAuth implements CloudAuth {
  /// 建立 [AndroidCloudAuth]。
  AndroidCloudAuth({required this.gateway, required this.baseClientFactory});

  /// 授權 API 的最小介面。
  final GoogleAuthorizationGateway gateway;

  /// 建立底層 HTTP client 的工廠（測試注入 MockClient 用）。
  final http.Client Function() baseClientFactory;

  /// Logger 實例（授權流程）。
  static final _log = Logger('cloudsync.auth');

  /// 通行證的假定有效期；Google 實際約 1 小時，留 5 分鐘餘裕。
  static const _tokenLifetime = Duration(minutes: 55);

  /// 通行證短效且不保存，每輪同步都重新還原。
  @override
  bool get keepsClientAcrossRounds => false;

  /// 以 [token] 建立帶 Bearer 憑證的 client，close 時連同底層 client 一併關閉。
  http.Client _clientFor(String token) => authenticatedClient(
    baseClientFactory(),
    AccessCredentials(
      AccessToken('Bearer', token, DateTime.now().toUtc().add(_tokenLifetime)),
      null,
      cloudSyncScopes,
    ),
    closeUnderlyingClient: true,
  );

  /// 取得並驗證通行證（以 userinfo 確認未被撤銷）；回傳 client 與 email。
  ///
  /// 通行證被 API 拒絕（401）時清掉系統快取並以同一種方式重取一次；
  /// 第二次仍被拒（同樣清掉快取）：[interactive] 為 true 拋出錯誤，否則回 null。靜默拿不到時回 null。
  Future<({http.Client client, String email})?> _verifiedToken({
    required bool interactive,
  }) async {
    for (var attempt = 0; ; attempt++) {
      final token = interactive
          ? await gateway.interactiveToken()
          : await gateway.silentToken();
      if (token == null) return null;
      final client = _clientFor(token);
      try {
        return (client: client, email: await fetchCloudEmail(client));
      } catch (e) {
        client.close();
        if (!isInvalidToken(e)) rethrow;
        final finalAttempt = attempt >= 1;
        _log.info(
          finalAttempt
              ? 'android token still rejected after retry, clearing cache'
              : 'android token rejected (401), clearing cache and retrying',
        );
        await _bestEffort('stale token clear', () => gateway.clearToken(token));
        if (finalAttempt) {
          if (interactive) rethrow;
          return null;
        }
      }
    }
  }

  /// 跳授權畫面取得並驗證通行證；不保存任何東西，[CloudLinkResult.commit] 為 no-op。
  @override
  Future<CloudLinkResult> link({
    required void Function(String url) openUrl,
    String? postAuthPage,
  }) async {
    _log.info('android link start');
    final verified = await _verifiedToken(interactive: true);
    if (verified == null) {
      throw StateError('interactive authorization returned no token');
    }
    _log.info('android link ok');
    return CloudLinkResult(
      client: verified.client,
      email: verified.email,
      commit: () async {},
    );
  }

  /// 靜默取得通行證；帳號與 [expectedEmail] 不符時拋 [CloudReauthRequiredException]。
  @override
  Future<http.Client?> restoreClient({required String expectedEmail}) async {
    final verified = await _verifiedToken(interactive: false);
    if (verified == null) {
      _log.info('android restore: needs user interaction');
      return null;
    }
    if (verified.email != expectedEmail) {
      verified.client.close();
      _log.warning('android restore: account mismatch, relink required');
      throw const CloudReauthRequiredException();
    }
    _log.info('android restore ok');
    return verified.client;
  }

  /// 盡力清掉快取的通行證並登出 Play services，不撤銷。
  @override
  Future<void> unlink() async {
    await _bestEffort('unlink: play services cleanup', () async {
      final token = await gateway.silentToken();
      if (token != null) await gateway.clearToken(token);
    });
    await _bestEffort('unlink: play services cleanup', gateway.signOut);
    _log.info('android unlink done (local only)');
  }

  /// 執行 Play services 清理步驟 [label]；失敗只記 log 並放行（不阻擋忘記此裝置或重試取新通行證）。
  Future<void> _bestEffort(String label, Future<void> Function() step) async {
    try {
      await step();
    } catch (e, st) {
      _log.warning('android $label failed (ignored)', e, st);
    }
  }
}
