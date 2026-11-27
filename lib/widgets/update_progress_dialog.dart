import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/platform.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/android_log_wait_body.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/game_dir_help_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/manual_url_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/game_dir_picker.dart';

/// 顯示祈願資料更新進度的 dialog，包含 [LinearProgressIndicator] 與各狀態文字。
class UpdateProgressDialog extends ConsumerWidget {
  /// 建立 [UpdateProgressDialog]。
  const UpdateProgressDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void closeSelf() {
      final route = ModalRoute.of(context);
      // route 已離開 stack 時 popUntil 永遠比不到，會把所有頁面 pop 光。
      if (route == null || !route.isActive) return;
      // 上面可能疊著說明視窗，先收回到自己這層再關，避免多 pop 底下的頁面。
      final nav = Navigator.of(context);
      nav.popUntil((r) => r == route);
      if (nav.canPop()) nav.pop();
    }

    ref.listen<UpdateProgress?>(
      gachaRepositoryProvider.select((s) => s.progress),
      (prev, next) {
        if (next == null) closeSelf();
      },
    );
    final progress = ref.watch(
      gachaRepositoryProvider.select((s) => s.progress),
    );
    final notifier = ref.read(gachaRepositoryProvider.notifier);
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;
    final android = ref.watch(isAndroidProvider);

    return _CloseIfIdleOnOpen(
      close: closeSelf,
      child: PopScope(
        canPop: false,
        child: AppDialog(
          // size 預設 sm，符合短訊息 + LinearProgressIndicator 語意。
          // 手機橫向高度只剩約 390，等待畫面放不下，要能捲動。
          scrollable: true,
          // 進行中的更新只能用下方按鈕取消，不給 ✕ 直接關窗。
          showCloseButton: false,
          title: _Title(
            progress: progress,
            l: l,
            tokens: tokens,
            android: android,
          ),
          content: _Body(progress: progress, l: l, android: android),
          actions: _actions(context, progress, notifier, l),
        ),
      ),
    );
  }

  /// 依 [p] 狀態回傳對應的操作按鈕列表。
  List<Widget> _actions(
    BuildContext ctx,
    UpdateProgress? p,
    GachaRepository r,
    AppLocalizations l,
  ) {
    return switch (p) {
      Preparing() => [
        TextButton.icon(
          onPressed: r.cancelPreparing,
          icon: const Icon(Icons.close, size: 18),
          label: Text(l.actionCancel),
        ),
      ],
      WaitingForCapture() => [
        TextButton.icon(
          onPressed: () async {
            await r.cancelCapture();
          },
          icon: const Icon(Icons.close, size: 18),
          label: Text(l.actionCancel),
        ),
      ],
      FetchingBanner() => const <Widget>[],
      FetchingHoYoWiki() => const <Widget>[],
      ConvertingDataLanguage() => const <Widget>[],
      UpdateCompleted() || UpdateFailed() => [
        TextButton.icon(
          onPressed: r.clearProgress,
          icon: const Icon(Icons.close, size: 18),
          label: Text(l.actionClose),
        ),
      ],
      null => const <Widget>[],
    };
  }
}

/// dialog 第一次建構後若進度已經是 null 就呼叫 [close]。
///
/// 流程很快結束時（例如轉換資料語言沒東西要轉），進度可能在 dialog 建構前就被清掉，
/// [UpdateProgressDialog] 的 listen 收不到那次變化，dialog 會留著空白內容。
/// 只在開啟時檢查一次：之後的清空由 listen 處理，避免在別的頁面推上來後誤關。
class _CloseIfIdleOnOpen extends ConsumerStatefulWidget {
  /// 建立 [_CloseIfIdleOnOpen]。
  const _CloseIfIdleOnOpen({required this.close, required this.child});

  /// 關閉 dialog 的動作。
  final VoidCallback close;

  /// dialog 內容。
  final Widget child;

  @override
  ConsumerState<_CloseIfIdleOnOpen> createState() => _CloseIfIdleOnOpenState();
}

/// [_CloseIfIdleOnOpen] 的狀態：只在第一幀後檢查一次。
class _CloseIfIdleOnOpenState extends ConsumerState<_CloseIfIdleOnOpen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(gachaRepositoryProvider).progress == null) {
        widget.close();
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Dialog 標題列：依 [progress] 狀態切換圖示、顏色與文字。
class _Title extends StatelessWidget {
  /// 建立 [_Title]。
  const _Title({
    required this.progress,
    required this.l,
    required this.tokens,
    required this.android,
  });

  /// 是否為 Android（等待時標題改為「等待祈願紀錄...」）。
  final bool android;

  /// 當前更新進度狀態。
  final UpdateProgress? progress;

  /// 國際化字串。
  final AppLocalizations l;

  /// 主題色彩 token。
  final GachaTokens tokens;

  @override
  Widget build(BuildContext context) {
    final (icon, color, text) = switch (progress) {
      Preparing() => (
        Icons.hourglass_empty,
        tokens.textPrimary,
        l.progressPreparing,
      ),
      WaitingForCapture(
        :final logAccessUnavailable,
        :final checkingLogAccess,
      ) =>
        (
          logAccessUnavailable == null
              ? Icons.hourglass_top
              : Icons.info_outline,
          tokens.textPrimary,
          !android
              ? l.progressWaiting
              : checkingLogAccess
              ? l.progressCheckingLogAccess
              : logAccessUnavailable == null
              ? l.progressWaitingLog
              : l.progressLogUnavailableTitle,
        ),
      FetchingBanner() => (
        Icons.cloud_download_outlined,
        tokens.textPrimary,
        l.progressFetching,
      ),
      FetchingHoYoWiki() => (
        Icons.image_outlined,
        tokens.textPrimary,
        l.progressFetching,
      ),
      ConvertingDataLanguage() => (
        Icons.translate_outlined,
        tokens.textPrimary,
        l.settingsDataLanguageUnifying,
      ),
      UpdateCompleted() => (
        Icons.check_circle,
        tokens.stateSuccess,
        l.progressDone,
      ),
      UpdateFailed() => (Icons.error, tokens.stateDanger, l.progressFailed),
      null => (Icons.info_outline, tokens.textMuted, ''),
    };
    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: AppSpacing.s),
        Flexible(child: Text(text)),
      ],
    );
  }
}

/// Dialog 內容區：依 [progress] 狀態切換進度列、說明文字或結果摘要。
class _Body extends StatelessWidget {
  /// 建立 [_Body]。
  const _Body({required this.progress, required this.l, required this.android});

  /// 是否為 Android（等待畫面改用 [AndroidLogWaitBody]）。
  final bool android;

  /// 當前更新進度狀態。
  final UpdateProgress? progress;

  /// 國際化字串。
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;

    String resolveBannerName(String key) => switch (key) {
      'gachaTypeCharacter' => l.gachaTypeCharacter,
      'gachaTypeWeapon' => l.gachaTypeWeapon,
      'gachaTypeChronicled' => l.gachaTypeChronicled,
      'gachaTypeStandard' => l.gachaTypeStandard,
      'gachaTypeBeginner' => l.gachaTypeBeginner,
      'gachaTypeOdesEvent' => l.gachaTypeOdesEvent,
      'gachaTypeOdesStandard' => l.gachaTypeOdesStandard,
      _ => key,
    };

    return switch (progress) {
      Preparing() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const LinearProgressIndicator(),
          const SizedBox(height: AppSpacing.l),
          Text(l.progressPreparingHint),
        ],
      ),
      ConvertingDataLanguage() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const LinearProgressIndicator(),
          const SizedBox(height: AppSpacing.l),
          Text(l.progressConvertingHint),
        ],
      ),
      final WaitingForCapture p when android => AndroidLogWaitBody(progress: p),
      WaitingForCapture(
        :final isFallback,
        :final captureUnavailable,
        :final gameDirMissing,
      ) =>
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LinearProgressIndicator(),
            const SizedBox(height: AppSpacing.l),
            Text(l.progressOpenGameHint),
            if (isFallback) ...[
              const SizedBox(height: AppSpacing.s),
              Text(l.progressFallbackHint, style: theme.textTheme.bodySmall),
            ],
            if (captureUnavailable) ...[
              const SizedBox(height: AppSpacing.s),
              Text(
                gameDirMissing
                    ? l.progressCaptureUnavailableNoGameDirHint
                    : l.progressCaptureUnavailableHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.stateWarning,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.s),
            // 提示已說明原因並直接給選資料夾按鈕，「沒有反應？」連結此時多餘，二擇一。
            if (captureUnavailable && gameDirMissing)
              const _ChooseGameDirButton()
            else
              TextButton(
                onPressed: () => showGameDirHelpDialog(context),
                child: Text(
                  l.progressNotDetectedLink,
                  textAlign: TextAlign.center,
                ),
              ),
            TextButton(
              onPressed: () => showManualUrlDialog(context),
              child: Text(l.manualUrlEntry, textAlign: TextAlign.center),
            ),
          ],
        ),
      FetchingBanner(
        :final displayName,
        :final pageIndex,
        :final newRecordsSoFar,
      ) =>
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LinearProgressIndicator(),
            const SizedBox(height: AppSpacing.l),
            Text(l.progressFetchingBanner(resolveBannerName(displayName))),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l.progressPageStatus(pageIndex, newRecordsSoFar),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      FetchingHoYoWiki(:final phase, :final doneCount, :final totalCount) =>
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(
              value: totalCount == 0 ? null : doneCount / totalCount,
            ),
            const SizedBox(height: AppSpacing.l),
            Text(switch (phase) {
              HoYoWikiPhase.searching => l.updateProgressHoyoWikiSearching(
                doneCount,
                totalCount,
              ),
              HoYoWikiPhase.fetchingEntries =>
                l.updateProgressHoyoWikiFetchingEntries(doneCount, totalCount),
              HoYoWikiPhase.downloading => l.updateProgressHoyoWikiDownloading(
                doneCount,
                totalCount,
              ),
            }),
          ],
        ),
      UpdateCompleted(
        :final totalNewRecords,
        :final failedBanners,
        :final hoYoWikiImagesDownloaded,
        :final importSummary,
        :final hoyoWikiEntriesRefreshed,
        :final hoyoWikiStaleItemsPruned,
        :final wirelessDebuggingLeftOn,
      ) =>
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (importSummary != null) ...[
              Text(
                l.progressDoneImportSummary(
                  importSummary.successAccounts,
                  importSummary.addedRecords,
                  importSummary.duplicateRecords,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(l.progressDoneImagesSummary(hoYoWikiImagesDownloaded)),
            ] else if (hoyoWikiEntriesRefreshed != null) ...[
              Text(l.progressDoneItemDataSummary(hoyoWikiEntriesRefreshed)),
              if (hoYoWikiImagesDownloaded > 0) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l.progressDoneItemDataImagesSummary(hoYoWikiImagesDownloaded),
                ),
              ],
              if (hoyoWikiStaleItemsPruned > 0) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l.progressDoneItemDataPrunedSummary(hoyoWikiStaleItemsPruned),
                ),
              ],
            ] else ...[
              Text(l.progressDoneSummary(totalNewRecords)),
              const SizedBox(height: AppSpacing.xs),
              Text(l.progressDoneImagesSummary(hoYoWikiImagesDownloaded)),
            ],
            if (failedBanners.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s),
              Text(
                l.progressPartialFailed(
                  failedBanners.map(resolveBannerName).join('、'),
                ),
                style: TextStyle(color: tokens.stateDanger),
              ),
            ],
            if (wirelessDebuggingLeftOn) ...[
              const SizedBox(height: AppSpacing.s),
              Text(
                l.progressWirelessLeftOnHint,
                style: TextStyle(color: tokens.stateWarning),
              ),
            ],
            if (importSummary != null &&
                importSummary.failedUids.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s),
              Text(
                l.progressPartialImportFailed(
                  importSummary.failedUids.join(', '),
                ),
                style: TextStyle(color: tokens.stateDanger),
              ),
            ],
          ],
        ),
      UpdateFailed(:final error) => Text(_resolveError(error, l)),
      null => const SizedBox.shrink(),
    };
  }

  /// 將 [UpdateError] 轉為對應的本地化錯誤訊息。
  String _resolveError(UpdateError error, AppLocalizations l) =>
      switch (error) {
        UpdateErrorAuthExpired() => l.errorAuthExpired,
        UpdateErrorRateLimited() => l.errorRateLimited,
        UpdateErrorServer(:final details) => l.errorServer(details),
        UpdateErrorNoRecords() => l.errorNoRecords,
        UpdateErrorOther(:final message) => message,
        UpdateErrorWipeHoYoWikiCache(:final detail) =>
          l.updateErrorWipeHoyoWikiCache(detail),
      };
}

/// 攔截失效且找不到遊戲資料夾時，在等待畫面直接選擇遊戲資料夾的按鈕；選錯時在下方顯示錯誤。
class _ChooseGameDirButton extends ConsumerStatefulWidget {
  /// 建立 [_ChooseGameDirButton]。
  const _ChooseGameDirButton();

  @override
  ConsumerState<_ChooseGameDirButton> createState() =>
      _ChooseGameDirButtonState();
}

/// [_ChooseGameDirButton] 的狀態，記錄上次選擇是否無效。
class _ChooseGameDirButtonState extends ConsumerState<_ChooseGameDirButton> {
  /// 上次選到的資料夾找不到遊戲。
  bool _invalid = false;

  /// 開啟選資料夾流程；成功後監看會接上，等待畫面自動換掉這顆按鈕。
  Future<void> _choose() async {
    final outcome = await pickGameDirAndRewatch(ref);
    if (!mounted || outcome == GameDirPickOutcome.cancelled) return;
    setState(() => _invalid = outcome == GameDirPickOutcome.invalid);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.icon(
          onPressed: _choose,
          icon: const Icon(Icons.folder_open, size: 18),
          label: Text(l.actionChooseGameDir),
        ),
        if (_invalid) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            l.gameDirInvalid,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).gacha.stateDanger),
          ),
        ],
      ],
    );
  }
}
