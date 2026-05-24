import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';

/// 顯示祈願資料更新進度的 dialog，包含 [LinearProgressIndicator] 與各狀態文字。
class UpdateProgressDialog extends ConsumerWidget {
  /// 建立 [UpdateProgressDialog]。
  const UpdateProgressDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<UpdateProgress?>(
      gachaRepositoryProvider.select((s) => s.progress),
      (prev, next) {
        if (next == null && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
    );
    final progress = ref.watch(
      gachaRepositoryProvider.select((s) => s.progress),
    );
    final notifier = ref.read(gachaRepositoryProvider.notifier);
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;

    return PopScope(
      canPop: false,
      child: AppDialog(
        // size 預設 sm，符合短訊息 + LinearProgressIndicator 語意。
        title: _Title(progress: progress, l: l, tokens: tokens),
        content: _Body(progress: progress, l: l),
        actions: _actions(context, progress, notifier, l),
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

/// Dialog 標題列：依 [progress] 狀態切換圖示、顏色與文字。
class _Title extends StatelessWidget {
  /// 建立 [_Title]。
  const _Title({required this.progress, required this.l, required this.tokens});

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
      WaitingForCapture() => (
        Icons.hourglass_top,
        tokens.textPrimary,
        l.progressWaiting,
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
        Text(text),
      ],
    );
  }
}

/// Dialog 內容區：依 [progress] 狀態切換進度列、說明文字或結果摘要。
class _Body extends StatelessWidget {
  /// 建立 [_Body]。
  const _Body({required this.progress, required this.l});

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
      WaitingForCapture(:final isFallback) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const LinearProgressIndicator(),
          const SizedBox(height: AppSpacing.l),
          Text(l.progressOpenGameHint),
          if (isFallback) ...[
            const SizedBox(height: AppSpacing.s),
            Text(l.progressFallbackHint, style: theme.textTheme.bodySmall),
          ],
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
      UpdateCompleted(:final totalNewRecords, :final failedBanners) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.progressDoneSummary(totalNewRecords)),
          if (failedBanners.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s),
            Text(
              l.progressPartialFailed(
                failedBanners.map(resolveBannerName).join('、'),
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
