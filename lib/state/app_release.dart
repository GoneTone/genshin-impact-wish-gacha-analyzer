import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:http/http.dart' as http;
import 'package:pub_semver/pub_semver.dart';

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/android_version_code.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/app_release_checker.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/play_update.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/platform.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';

export 'package:genshin_impact_wish_gacha_analyzer/services/app_release_checker.dart'
    show AppRelease;

/// 版本檢查狀態：閒置、檢查中、最新、有新版、失敗。
sealed class ReleaseCheckState {
  const ReleaseCheckState();
}

/// 尚未發起版本檢查。
class ReleaseIdle extends ReleaseCheckState {
  /// 建立 [ReleaseIdle]。
  const ReleaseIdle();
}

/// 版本檢查進行中。
class ReleaseChecking extends ReleaseCheckState {
  /// 建立 [ReleaseChecking]。
  const ReleaseChecking();
}

/// 已是最新版本。
class ReleaseUpToDate extends ReleaseCheckState {
  /// 建立 [ReleaseUpToDate]。
  const ReleaseUpToDate();
}

/// 有可用的新版本。
class ReleaseAvailable extends ReleaseCheckState {
  /// 建立 [ReleaseAvailable]，[releases] 為所有比當前更新的版本（降序）；
  /// Android 時為不超過 [playTag] 的子集，可能為空。
  const ReleaseAvailable(this.releases, {this.playTag});

  /// 比當前版本更新的版本列表（降序）；Android 取不到說明時可能為空。
  final List<AppRelease> releases;

  /// Android 由 Play 版本代碼換算出的 tag；Windows 為 null。
  final String? playTag;
}

/// 版本檢查失敗。
class ReleaseCheckFailed extends ReleaseCheckState {
  /// 建立 [ReleaseCheckFailed]，[reason] 為 i18n token。
  const ReleaseCheckFailed(this.reason);

  /// 失敗原因的 i18n token（如 `'network'`、`'timeout'`）。
  final String reason;
}

/// 預設 `http.Client()`；測試 override 用 `MockClient`。
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// 版本檢查狀態管理。啟動自動 + 設定頁手動兩個入口共用同一個 notifier。
/// 失敗時 `manual=false` 靜默，`manual=true` 才把錯誤推給 UI。
/// i18n localize 在這層完成；service 端保持純函式。
class AppReleaseNotifier extends Notifier<ReleaseCheckState> {
  @override
  ReleaseCheckState build() => const ReleaseIdle();

  /// 發起版本檢查；[manual] 為 true 時失敗會推錯誤給 UI。
  Future<void> check({required bool manual}) async {
    if (state is ReleaseChecking) return; // 防 re-entrancy
    Logger('release').info('release check start manual=$manual');
    state = const ReleaseChecking();
    final currentVersion = ref.read(appVersionProvider);
    final client = ref.read(httpClientProvider);

    if (ref.read(isAndroidProvider)) {
      await _checkAndroid(manual: manual, currentVersion: currentVersion);
      return;
    }

    final List<AppRelease> releases;
    try {
      releases = await fetchNewerReleases(
        currentVersion: currentVersion,
        client: client,
      );
    } on ReleaseCheckError catch (e, st) {
      if (manual) {
        Logger('release').warning('release check failed (manual)', e, st);
        state = ReleaseCheckFailed(_localizeError(e));
      } else {
        Logger('release').warning('release check failed (silent)', e, st);
        state = const ReleaseIdle();
      }
      return;
    }

    if (releases.isEmpty) {
      Logger('release').info('release check: up-to-date');
      state = manual ? const ReleaseUpToDate() : const ReleaseIdle();
      return;
    }

    Logger('release').info(
      'release check: ${releases.length} newer release(s), '
      'latest=${releases.first.tagName}',
    );

    if (!manual) {
      final skipped = ref.read(settingsProvider).skippedReleaseTag;
      if (skipped != null && releases.first.tagName == skipped) {
        state = const ReleaseIdle();
        return;
      }
    }

    state = ReleaseAvailable(releases);
  }

  /// Android 檢查流程：由 Play 判斷有無新版，GitHub 僅提供更新說明。
  Future<void> _checkAndroid({
    required bool manual,
    required String currentVersion,
  }) async {
    final log = Logger('release');
    final PlayUpdateInfo info;
    try {
      info = await ref.read(playUpdateGatewayProvider).check();
    } catch (e, st) {
      log.warning('play update check failed', e, st);
      state = manual ? const ReleaseCheckFailed('play') : const ReleaseIdle();
      return;
    }
    final code = info.availableVersionCode;
    final tag = code == null ? null : tagForAndroidVersionCode(code);
    log.info(
      'play update check: available=${info.available} code=$code tag=$tag '
      'flexibleAllowed=${info.flexibleAllowed} '
      'installStatus=${info.installStatus.name}',
    );
    if (!info.available) {
      state = manual ? const ReleaseUpToDate() : const ReleaseIdle();
      return;
    }
    if (tag == null) {
      log.warning('play version code $code has no tag mapping');
      state = manual ? const ReleaseUpToDate() : const ReleaseIdle();
      return;
    }
    if (!manual && ref.read(settingsProvider).skippedReleaseTag == tag) {
      state = const ReleaseIdle();
      return;
    }

    var releases = <AppRelease>[];
    try {
      final newer = await fetchNewerReleases(
        currentVersion: currentVersion,
        client: ref.read(httpClientProvider),
      );
      final playVersion = Version.parse(tag.substring(1));
      releases = newer
          .where((r) => Version.parse(r.version) <= playVersion)
          .toList();
    } catch (e, st) {
      // Android 的更新說明只是附加資訊，任何錯誤（含 TLS 等未轉換的例外）都照樣提示新版。
      log.info('release notes unavailable, prompting without notes', e, st);
    }
    state = ReleaseAvailable(releases, playTag: tag);
  }

  /// 將 [tagName] 存入設定，下次自動檢查時跳過該版本。
  Future<void> skipVersion(String tagName) async {
    await ref.read(settingsProvider.notifier).setSkippedReleaseTag(tagName);
  }

  /// 把 service error 轉成穩定 token，UI 端拿 token 解 i18n。
  ///
  /// 注意：此 helper 目前**只**服務 [fetchNewerReleases] 流（list
  /// endpoint，不會 404）。`ReleaseCheckNotFound` 由 `CurrentReleaseDialog`
  /// 走 `fetchReleaseByVersion` 自行 i18n。若日後要把這個 helper 接到
  /// 任何**可能 404** 的新流程，請先加上專屬的 `notFound` token 與對應
  /// i18n 字串，再來修這個 switch；別偷懶 fallback 成 `'format'`，否則
  /// 404 會被使用者看成「格式錯誤」。
  String _localizeError(ReleaseCheckError e) => switch (e) {
    ReleaseCheckNetwork() => 'network',
    ReleaseCheckTimeout() => 'timeout',
    ReleaseCheckRateLimited() => 'rateLimited',
    ReleaseCheckServer(:final status) => 'server:$status',
    ReleaseCheckFormat() => 'format',
    ReleaseCheckNotFound() => throw UnsupportedError(
      'AppReleaseNotifier._localizeError received ReleaseCheckNotFound. '
      'This error is only producible by fetchReleaseByVersion (currently '
      'consumed by CurrentReleaseDialog, which does its own i18n). '
      'If you are reusing _localizeError for a flow that can hit 404, '
      'add a proper "notFound" token and i18n string instead.',
    ),
  };
}

/// [AppReleaseNotifier] 的 Riverpod provider。
final appReleaseProvider =
    NotifierProvider<AppReleaseNotifier, ReleaseCheckState>(
      AppReleaseNotifier.new,
    );
