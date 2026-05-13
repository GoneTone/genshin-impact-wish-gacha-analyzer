// lib/state/app_release.dart
//
// 版本檢查狀態管理。啟動自動 + 設定頁手動兩個入口共用同一個 notifier。
// 失敗時 `manual=false` 靜默（僅 debugPrint），`manual=true` 才把錯誤
// 推給 UI。i18n localize 在這層完成；service 端保持純函式。

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/app_release_checker.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';

export 'package:genshin_impact_wish_gacha_analyzer/services/app_release_checker.dart'
    show AppRelease;

sealed class ReleaseCheckState {
  const ReleaseCheckState();
}

class ReleaseIdle extends ReleaseCheckState {
  const ReleaseIdle();
}

class ReleaseChecking extends ReleaseCheckState {
  const ReleaseChecking();
}

class ReleaseUpToDate extends ReleaseCheckState {
  const ReleaseUpToDate();
}

class ReleaseAvailable extends ReleaseCheckState {
  const ReleaseAvailable(this.releases);
  final List<AppRelease> releases;
}

class ReleaseCheckFailed extends ReleaseCheckState {
  const ReleaseCheckFailed(this.reason);
  final String reason;
}

/// 預設 `http.Client()`；測試 override 用 `MockClient`。
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

class AppReleaseNotifier extends Notifier<ReleaseCheckState> {
  @override
  ReleaseCheckState build() => const ReleaseIdle();

  Future<void> check({required bool manual}) async {
    if (state is ReleaseChecking) return; // 防 re-entrancy
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
        state = ReleaseCheckFailed(_localizeError(e));
      } else {
        debugPrint('[app_release] silent failure: $e');
        state = const ReleaseIdle();
      }
      return;
    }

    if (releases.isEmpty) {
      state = manual ? const ReleaseUpToDate() : const ReleaseIdle();
      return;
    }

    if (!manual) {
      final skipped = ref.read(settingsProvider).skippedReleaseTag;
      if (skipped != null && releases.first.tagName == skipped) {
        state = const ReleaseIdle();
        return;
      }
    }

    state = ReleaseAvailable(releases);
  }

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
  };
}

final appReleaseProvider =
    NotifierProvider<AppReleaseNotifier, ReleaseCheckState>(
      AppReleaseNotifier.new,
    );
