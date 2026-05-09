// lib/widgets/update_progress_dialog.dart
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

class UpdateProgressDialog extends ConsumerWidget {
  const UpdateProgressDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<UpdateProgress?>(
      wishRepositoryProvider.select((s) => s.progress),
      (prev, next) {
        if (next == null && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
    );
    final progress = ref.watch(
        wishRepositoryProvider.select((s) => s.progress));
    final notifier = ref.read(wishRepositoryProvider.notifier);
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;

    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: _Title(progress: progress, l: l, tokens: tokens),
        content: _Body(progress: progress, l: l),
        actions: _actions(context, progress, notifier, l),
      ),
    );
  }

  List<Widget> _actions(
    BuildContext ctx,
    UpdateProgress? p,
    WishRepository r,
    AppLocalizations l,
  ) {
    return switch (p) {
      WaitingForCapture() => [
          TextButton(
            onPressed: () async {
              await r.cancelCapture();
            },
            child: Text(l.actionCancel),
          ),
        ],
      FetchingBanner() => const <Widget>[],
      UpdateCompleted() ||
      UpdateFailed() =>
        [
          TextButton(
            onPressed: r.clearProgress,
            child: Text(l.actionClose),
          ),
        ],
      null => const <Widget>[],
    };
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.progress, required this.l, required this.tokens});
  final UpdateProgress? progress;
  final AppLocalizations l;
  final GachaTokens tokens;

  @override
  Widget build(BuildContext context) {
    final (icon, color, text) = switch (progress) {
      WaitingForCapture() => (Icons.hourglass_top, tokens.textPrimary, l.progressWaiting),
      FetchingBanner() => (Icons.cloud_download_outlined, tokens.textPrimary, l.progressFetching),
      UpdateCompleted() => (Icons.check_circle, tokens.stateSuccess, l.progressDone),
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

class _Body extends StatelessWidget {
  const _Body({required this.progress, required this.l});
  final UpdateProgress? progress;
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
          _ => key,
        };

    return switch (progress) {
      WaitingForCapture(:final isFallback) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LinearProgressIndicator(),
            const SizedBox(height: AppSpacing.l),
            Text(l.progressOpenGameHint),
            if (isFallback) ...[
              const SizedBox(height: AppSpacing.s),
              Text(l.progressFallbackHint,
                  style: theme.textTheme.bodySmall),
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
            Text(l.progressPageStatus(pageIndex, newRecordsSoFar),
                style: theme.textTheme.bodySmall),
          ],
        ),
      UpdateCompleted(
        :final totalNewRecords,
        :final failedBanners,
      ) =>
        Column(
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

  String _resolveError(UpdateError error, AppLocalizations l) =>
      switch (error) {
        UpdateErrorAuthExpired() => l.errorAuthExpired,
        UpdateErrorRateLimited() => l.errorRateLimited,
        UpdateErrorServer(:final details) => l.errorServer(details),
        UpdateErrorNoRecords() => l.errorNoRecords,
        UpdateErrorOther(:final message) => message,
      };
}
