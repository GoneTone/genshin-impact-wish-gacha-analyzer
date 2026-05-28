import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:http/http.dart' as http;

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/app_release_checker.dart';
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
  /// 建立 [ReleaseAvailable]，[releases] 為所有比當前更新的版本（降序）。
  const ReleaseAvailable(this.releases);

  /// 比當前版本更新的版本列表（降序）。
  final List<AppRelease> releases;
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

    final List<AppRelease> releases;
    try {
      releases = await fetchNewerReleases(
        currentVersion: currentVersion,
        client: client,
      );
    } on ReleaseCheckError catch (e) {
      if (manual) {
        Logger('release').warning('release check failed (manual): $e');
        state = ReleaseCheckFailed(_localizeError(e));
      } else {
        Logger('release').warning('release check failed (silent): $e');
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

  /// 將 [tagName] 存入設定，下次自動檢查時跳過該版本。
  Future<void> skipVersion(String tagName) async {
    await ref.read(settingsProvider.notifier).setSkippedReleaseTag(tagName);
  }

  /// 把 service error 轉成穩定 token，UI 端拿 token 解 i18n。
  String _localizeError(ReleaseCheckError e) => switch (e) {
    ReleaseCheckNetwork() => 'network',
    ReleaseCheckTimeout() => 'timeout',
    ReleaseCheckRateLimited() => 'rateLimited',
    ReleaseCheckServer(:final status) => 'server:$status',
    ReleaseCheckFormat() => 'format',
    // fetchNewerReleases 走 /releases（list endpoint）不會 404，此分支
    // 為 sealed exhaustiveness 而存在；真正消費 404 的是
    // CurrentReleaseDialog（fetchReleaseByVersion 流）。
    ReleaseCheckNotFound() => 'format',
  };
}

/// [AppReleaseNotifier] 的 Riverpod provider。
final appReleaseProvider =
    NotifierProvider<AppReleaseNotifier, ReleaseCheckState>(
      AppReleaseNotifier.new,
    );
