import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/app_repo.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/app_release_checker.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/current_release.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/release_notes_content.dart';

/// 顯示「目前版本」對應 GitHub Release 內容的 dialog，整合 loading／data／
/// error 三態，並依錯誤類型提供合理的後續操作（重試或開 Releases 頁面）。
class CurrentReleaseDialog extends ConsumerWidget {
  /// 建立 [CurrentReleaseDialog]，[version] 為要查詢的版本字串
  /// （pubspec／`PackageInfo` 版本，可帶 build metadata，例如 `1.1.0+2`）。
  const CurrentReleaseDialog({super.key, required this.version});

  /// 要查詢的版本字串。
  final String version;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final async = ref.watch(currentReleaseProvider(version));

    return AppDialog(
      size: AppDialogSize.lg,
      scrollable: true,
      title: Row(
        children: [
          Icon(Icons.description_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.s),
          Expanded(child: Text(l.currentReleaseTitle)),
        ],
      ),
      content: async.when(
        loading: () => const _LoadingSkeleton(),
        data: (release) => ReleaseNotesContent(release: release),
        error: (e, _) =>
            _ErrorBlock(error: e as ReleaseCheckError, version: version),
      ),
      actions: _actionsFor(context, ref, l, async),
    );
  }

  /// 依目前 [async] 狀態組出對應的 dialog 底部按鈕清單。
  List<Widget> _actionsFor(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l,
    AsyncValue<AppRelease> async,
  ) {
    final closeButton = TextButton(
      onPressed: () => Navigator.of(context).pop(),
      child: Text(l.actionClose),
    );

    return async.when(
      loading: () => [closeButton],
      data: (release) => [
        closeButton,
        FilledButton.icon(
          icon: const Icon(Icons.open_in_new),
          label: Text(l.currentReleaseOpenOnGithub),
          onPressed: () async {
            await openExternalUrl(Uri.parse(release.htmlUrl));
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
      ],
      error: (e, _) {
        final err = e as ReleaseCheckError;
        final terminalError =
            err is ReleaseCheckNotFound || err is ReleaseCheckRateLimited;
        if (terminalError) {
          return [
            closeButton,
            FilledButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: Text(l.currentReleaseOpenReleasesPage),
              onPressed: () async {
                await openExternalUrl(
                  Uri.parse('${AppRepo.githubUrl}/releases'),
                );
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ];
        }
        return [
          closeButton,
          FilledButton.icon(
            icon: const Icon(Icons.refresh),
            label: Text(l.actionRetry),
            onPressed: () => ref.invalidate(currentReleaseProvider(version)),
          ),
        ];
      },
    );
  }
}

/// 三態 loading 狀態下的灰色占位卡片，視覺極簡（不引入 shimmer 套件）。
class _LoadingSkeleton extends StatelessWidget {
  /// 建立 [_LoadingSkeleton]。
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _bar(width: 120, height: 24, color: tokens.borderSubtle),
            const SizedBox(height: AppSpacing.s),
            _bar(width: double.infinity, height: 1, color: tokens.borderSubtle),
            const SizedBox(height: AppSpacing.s),
            _bar(
              width: double.infinity,
              height: 14,
              color: tokens.borderSubtle,
            ),
            const SizedBox(height: AppSpacing.xs),
            _bar(
              width: double.infinity,
              height: 14,
              color: tokens.borderSubtle,
            ),
            const SizedBox(height: AppSpacing.xs),
            _bar(width: 240, height: 14, color: tokens.borderSubtle),
          ],
        ),
      ),
    );
  }

  /// 畫一個指定尺寸與顏色的圓角矩形占位。
  Widget _bar({
    required double width,
    required double height,
    required Color color,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

/// 三態 error 狀態下的訊息區塊，把 [error] 對應到 i18n 字串並顯示在 icon 旁。
class _ErrorBlock extends StatelessWidget {
  /// 建立 [_ErrorBlock]。
  const _ErrorBlock({required this.error, required this.version});

  /// 來自 provider 的錯誤物件。
  final ReleaseCheckError error;

  /// 目前查詢的版本字串，用於 not-found 訊息插值。
  final String version;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    final message = _messageFor(l, error);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error),
          const SizedBox(width: AppSpacing.s),
          Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }

  /// 把 [ReleaseCheckError] 子類對應到既有 `update*` i18n 字串，
  /// 維持與「檢查更新」流程的訊息一致性。
  String _messageFor(AppLocalizations l, ReleaseCheckError e) {
    return switch (e) {
      ReleaseCheckNotFound() => l.currentReleaseNotFound(version),
      ReleaseCheckNetwork() => l.updateErrorNetwork,
      ReleaseCheckTimeout() => l.updateErrorTimeout,
      ReleaseCheckRateLimited() => l.updateErrorRateLimited,
      ReleaseCheckServer(:final status) => l.updateErrorServer(
        status.toString(),
      ),
      ReleaseCheckFormat() => l.updateErrorFormat,
    };
  }
}
