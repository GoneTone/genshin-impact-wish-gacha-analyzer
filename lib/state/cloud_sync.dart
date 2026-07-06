import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/accounts_export.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_sync_config.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_sync_remote.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_sync_service.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/google_auth_service.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/token_store.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';

/// 雲端同步的即時狀態。
enum CloudSyncPhase {
  /// 閒置（未連結時也是此狀態，連結與否由 settings 的 email 判斷）。
  idle,

  /// 等待使用者在瀏覽器完成授權。
  awaitingConsent,

  /// 同步進行中。
  syncing,

  /// 最近一輪同步失敗（原因見 [CloudSyncState.errorToken]）。
  error,

  /// refresh token 已失效，需要重新連結。
  reauthRequired,
}

/// [CloudSyncNotifier] 的狀態快照。
@immutable
class CloudSyncState {
  /// 建立 [CloudSyncState]。
  const CloudSyncState({this.phase = CloudSyncPhase.idle, this.errorToken});

  /// 目前階段。
  final CloudSyncPhase phase;

  /// phase == error 時的原因 token
  /// （'network'｜'busy'｜'schemaTooNew'｜'authFailed'｜'scopeMissing'），
  /// UI 端解 i18n。
  final String? errorToken;
}

/// [TokenStore] provider，預設 DPAPI 安全儲存。
final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

/// [GoogleAuthService] provider。
final googleAuthServiceProvider = Provider<GoogleAuthService>(
  (ref) => GoogleAuthService(
    tokenStore: ref.watch(tokenStoreProvider),
    baseClientFactory: http.Client.new,
  ),
);

/// 以授權 client 建立 [CloudSyncRemote] 的工廠 provider。
final cloudSyncRemoteFactoryProvider =
    Provider<CloudSyncRemote Function(http.Client)>(
      (ref) => DriveSyncRemote.new,
    );

/// 開啟授權頁 URL 的 provider（測試 override 成 no-op）。
final cloudSyncUrlOpenerProvider = Provider<void Function(String url)>(
  (ref) =>
      (url) => unawaited(launchUrl(Uri.parse(url))),
);

/// 把主視窗帶回前景（還原最小化＋show＋focus）的 provider（測試 override 成 no-op）。
///
/// Windows 防搶焦點政策可能把 focus 降級成工作列閃爍，屬預期行為。
/// 呼叫端 fire-and-forget，失敗只記 log，不讓例外流進 unhandled zone。
final windowForegroundProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    try {
      if (await windowManager.isMinimized()) await windowManager.restore();
      await windowManager.show();
      await windowManager.focus();
    } catch (e) {
      Logger('cloudsync.sync').warning('bring-to-foreground failed: $e');
    }
  },
);

/// [CloudSyncNotifier] 的 Riverpod provider。
final cloudSyncProvider = NotifierProvider<CloudSyncNotifier, CloudSyncState>(
  CloudSyncNotifier.new,
);

/// 雲端同步狀態管理：連結／登出、四個觸發入口、5 秒 debounce 與單飛鎖。
class CloudSyncNotifier extends Notifier<CloudSyncState> {
  /// Logger 實例（同步流程）。
  static final _log = Logger('cloudsync.sync');

  /// 目前的授權 client；null = 尚未還原或未連結。
  AuthClient? _client;

  /// 資料變動觸發的 debounce timer。
  Timer? _debounce;

  /// 單飛鎖：一輪同步進行中。
  bool _syncing = false;

  /// 進行中又被觸發 → 結束後補跑一輪。
  bool _pendingRerun = false;

  /// 上次上傳內容的指紋，供資料變動觸發的跳過判斷。
  String? _lastFingerprint;

  /// 授權流程世代號；cancelLink／unlink 時遞增以拋棄過期的授權結果。
  int _authGeneration = 0;

  @override
  CloudSyncState build() {
    ref.onDispose(() {
      _debounce?.cancel();
      _client?.close();
    });
    ref.listen(
      gachaRepositoryProvider.select((s) => s.byUid),
      (_, _) => _onLocalChange(),
    );
    ref.listen(
      settingsProvider.select((s) => s.uidAliases),
      (_, _) => _onLocalChange(),
    );
    return const CloudSyncState();
  }

  /// 是否已連結雲端帳號。
  bool get _linked => ref.read(settingsProvider).cloudAccountEmail != null;

  /// App 啟動入口：已連結則還原授權，開關開啟時靜默跑一輪。
  Future<void> start() async {
    if (!isCloudSyncConfigured) return;
    await ref.read(settingsProvider.notifier).waitForLoad();
    if (!ref.mounted || !_linked) return;
    // 沒等本機 bootstrap 完成就同步，byUid 會是空的，雲端內容會把本機檔案當「全新」覆蓋掉。
    await ref.read(gachaRepositoryProvider.notifier).waitForBootstrap();
    if (!ref.mounted) return;
    try {
      await _ensureClient();
    } on CloudReauthRequiredException {
      state = const CloudSyncState(phase: CloudSyncPhase.reauthRequired);
      return;
    } catch (e) {
      _log.warning('startup restore failed: $e');
      state = const CloudSyncState(
        phase: CloudSyncPhase.error,
        errorToken: 'network',
      );
      return;
    }
    if (!ref.mounted) return;
    if (ref.read(settingsProvider).cloudAutoSyncEnabled) {
      await syncNow(manual: false, trigger: 'startup');
    }
  }

  /// 連結 Google 帳號：開瀏覽器授權，成功後存 email 並立即同步一輪。
  ///
  /// [postAuthPage] 為授權成功後瀏覽器顯示的自訂 HTML，由 UI 端以當前
  /// 語言產生（notifier 拿不到 AppLocalizations）。
  Future<void> link({String? postAuthPage}) async {
    if (!isCloudSyncConfigured) return;
    if (state.phase == CloudSyncPhase.awaitingConsent) return;
    final gen = ++_authGeneration;
    state = const CloudSyncState(phase: CloudSyncPhase.awaitingConsent);
    final auth = ref.read(googleAuthServiceProvider);
    final openUrl = ref.read(cloudSyncUrlOpenerProvider);
    try {
      final session = await auth.signIn(openUrl, postAuthPage: postAuthPage);
      if (!ref.mounted || gen != _authGeneration) {
        // 取消後在瀏覽器遲到完成的授權：拋棄 client、revoke 該次 grant，不寫入 token store。
        session.client.close();
        unawaited(auth.revokeToken(session.refreshToken));
        return;
      }
      await ref
          .read(tokenStoreProvider)
          .writeRefreshToken(session.refreshToken);
      _client?.close();
      _client = session.client;
      await ref.read(settingsProvider.notifier).setCloudAccount(session.email);
      if (!ref.mounted) return;
      state = const CloudSyncState();
      await syncNow(manual: true, trigger: 'link');
    } on CloudScopeMissingException {
      if (!ref.mounted || gen != _authGeneration) return;
      _log.warning('link failed: required Drive scope not granted');
      state = const CloudSyncState(
        phase: CloudSyncPhase.error,
        errorToken: 'scopeMissing',
      );
    } catch (e) {
      if (!ref.mounted || gen != _authGeneration) return;
      _log.warning('link failed: $e');
      state = const CloudSyncState(
        phase: CloudSyncPhase.error,
        errorToken: 'authFailed',
      );
    }
  }

  /// 取消進行中的授權等待（拋棄結果，回到閒置）。
  void cancelLink() {
    if (state.phase != CloudSyncPhase.awaitingConsent) return;
    _authGeneration++;
    state = const CloudSyncState();
    _log.info('link cancelled');
  }

  /// 中斷連結：revoke＋刪 token＋清 settings；本機與雲端資料皆保留。
  Future<void> unlink() async {
    _authGeneration++;
    _debounce?.cancel();
    await ref.read(googleAuthServiceProvider).signOut();
    if (!ref.mounted) return;
    _client?.close();
    _client = null;
    _lastFingerprint = null;
    await ref.read(settingsProvider.notifier).clearCloudAccount();
    if (!ref.mounted) return;
    state = const CloudSyncState();
  }

  /// 切換自動同步；開啟時立即補跑一輪。
  Future<void> setAutoSync(bool value) async {
    await ref.read(settingsProvider.notifier).setCloudAutoSyncEnabled(value);
    if (!ref.mounted) return;
    if (value && _linked) await syncNow(manual: false, trigger: 'autoSyncOn');
  }

  /// 把 [uid] 排入待雲端移除清單並立即同步（離線時清單留待下輪補刪）。
  Future<void> queueCloudRemoval(String uid) async {
    await ref.read(settingsProvider.notifier).addCloudPendingRemoval(uid);
    if (!ref.mounted) return;
    _debounce?.cancel();
    await syncNow(manual: false, trigger: 'removal');
  }

  /// 跑一輪同步。[manual] 僅影響 log 標記；[trigger] 為觸發來源標籤
  /// （startup／dataChange／removal／link／manual...，spec §10），
  /// 錯誤一律以狀態列呈現（spec §9）。
  ///
  /// reauthRequired 時直接返回：restore 保證失敗，重試只會空轉並讓狀態列閃爍，
  /// 只有重新連結（[link]）能離開此狀態。
  Future<void> syncNow({
    required bool manual,
    String trigger = 'manual',
  }) async {
    if (!isCloudSyncConfigured || !_linked) return;
    if (state.phase == CloudSyncPhase.reauthRequired) return;
    if (_syncing) {
      _pendingRerun = true;
      return;
    }
    _syncing = true;
    state = const CloudSyncState(phase: CloudSyncPhase.syncing);
    _log.info('sync round start trigger=$trigger manual=$manual');
    ImportResult? mergeResult;
    try {
      await _ensureClient();
      final settings = ref.read(settingsProvider);
      final pending = settings.cloudPendingRemovals;
      final outcome = await runSyncRound(
        remote: ref.read(cloudSyncRemoteFactoryProvider)(_client!),
        pendingRemovals: pending,
        applyRemote: (bundle) async {
          mergeResult = await ref
              .read(gachaRepositoryProvider.notifier)
              .importBundleForCloudSync(bundle);
        },
        exportLocal: _exportLocal,
        clearPendingRemovals: (uids) => ref
            .read(settingsProvider.notifier)
            .removeCloudPendingRemovals(uids),
      );
      if (!ref.mounted) return;
      switch (outcome) {
        case CloudSyncSuccess(:final uploadedFingerprint):
          _lastFingerprint = uploadedFingerprint;
          await ref
              .read(settingsProvider.notifier)
              .setCloudLastSyncedAt(DateTime.now().toUtc());
          if (!ref.mounted) return;
          state = const CloudSyncState();
          if ((mergeResult?.addedRecords ?? 0) > 0) {
            // 雲端合併出新記錄（如第二台電腦首次同步）→ 補抓缺漏的物品
            // 圖示與詳情，走進度對話框讓使用者看到狀態，結束顯示補圖摘要。
            unawaited(
              ref
                  .read(gachaRepositoryProvider.notifier)
                  .fetchItemImagesForCloudSync(),
            );
          }
        case CloudSyncSkippedSchemaTooNew():
          state = const CloudSyncState(
            phase: CloudSyncPhase.error,
            errorToken: 'schemaTooNew',
          );
      }
    } on CloudReauthRequiredException {
      if (!ref.mounted) return;
      state = const CloudSyncState(phase: CloudSyncPhase.reauthRequired);
    } on CloudSyncBusyException {
      if (!ref.mounted) return;
      _log.info('sync deferred: repository busy');
      state = const CloudSyncState(
        phase: CloudSyncPhase.error,
        errorToken: 'busy',
      );
      // busy 那輪未完成合併（可能已下載但沒套用的雲端內容），指紋防空轉
      // 機制不該吃掉這輪補救重試，故清空指紋讓 debounce 到點時一定真的跑。
      _lastFingerprint = null;
      _scheduleDebounced();
    } catch (e, st) {
      if (!ref.mounted) return;
      if (isInsufficientScope(e)) {
        // 既存 token 缺 Drive 權限（早期授權漏勾）：重試必敗，比照授權失效
        // 進 reauthRequired 停止自動同步，狀態列指引使用者重新連結並勾選。
        _log.warning('sync round failed: insufficient scope, relink required');
        state = const CloudSyncState(
          phase: CloudSyncPhase.reauthRequired,
          errorToken: 'scopeMissing',
        );
        return;
      }
      if (isInvalidGrant(e)) {
        // client 已建立時（_ensureClient 短路）續期失敗不會經過
        // GoogleAuthService.restore()，該處的攔截接不到，需在此另外攔截，
        // 否則會落入下方 network 分支並無限重試、狀態列訊息也會誤導使用者。
        _log.warning(
          'sync round failed: invalid_grant mid-session, relink required',
        );
        _client?.close();
        _client = null;
        state = const CloudSyncState(phase: CloudSyncPhase.reauthRequired);
        return;
      }
      _log.warning('sync round failed', e, st);
      state = const CloudSyncState(
        phase: CloudSyncPhase.error,
        errorToken: 'network',
      );
    } finally {
      _syncing = false;
      if (_pendingRerun && ref.mounted) {
        _pendingRerun = false;
        unawaited(syncNow(manual: false, trigger: 'rerun'));
      }
    }
  }

  /// 還原授權 client（已有就直接用）；無 token 視同需要重新連結。
  Future<void> _ensureClient() async {
    if (_client != null) return;
    final restored = await ref.read(googleAuthServiceProvider).restore();
    if (restored == null) throw const CloudReauthRequiredException();
    _client = restored;
  }

  /// 本機資料（byUid／別名）變動時排程 debounce 同步。
  ///
  /// reauthRequired 時不排程：只有重新連結（[link]）能離開此狀態。
  void _onLocalChange() {
    if (!isCloudSyncConfigured || !_linked) return;
    if (state.phase == CloudSyncPhase.reauthRequired) return;
    if (!ref.read(settingsProvider).cloudAutoSyncEnabled) return;
    if (ref.read(gachaRepositoryProvider).isBootstrapping) return;
    _scheduleDebounced();
  }

  /// 5 秒後跑一輪；到點時指紋沒變就跳過（避免同步自身的合併寫入造成空轉輪）。
  void _scheduleDebounced() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 5), () {
      if (!ref.mounted || !_linked) return;
      if (syncFingerprint(_exportLocal()) == _lastFingerprint) return;
      unawaited(syncNow(manual: false, trigger: 'dataChange'));
    });
  }

  /// 把本機全帳號打包成與手動匯出同格式的 bundle JSON。
  String _exportLocal() {
    final gacha = ref.read(gachaRepositoryProvider);
    final settings = ref.read(settingsProvider);
    return exportAccounts(
      byUid: gacha.byUid,
      uidOrder: settings.uidOrder,
      uidAliases: settings.uidAliases,
      lastActiveUid: gacha.activeUid,
      appVersion: ref.read(appVersionProvider),
      now: DateTime.now(),
    );
  }
}
