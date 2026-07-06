import 'dart:async' show unawaited;
import 'dart:convert' show HtmlEscape;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_sync_config.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/cloud_sync.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/confirm_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/relative_time_text.dart';

/// 產生授權成功後瀏覽器顯示的完成頁 HTML（依當前 UI 語言在地化）。
///
/// 頁面完全自足（inline style、隨系統深淺色），文案經 HTML escape。
/// OAuth 流程在 token 交換成功即回這頁，不管使用者有沒有勾雲端硬碟權限；
/// 幸好 Google 的回跳 URL 帶有實際授予的 `scope` 參數，頁內 JS 據此在
/// 缺 drive.appdata 時切換成「缺少權限」指引，避免誤報授權完成。
String _buildPostAuthPage(AppLocalizations l, String lang) {
  const esc = HtmlEscape();
  final title = esc.convert(l.cloudSyncPostAuthTitle);
  final body = esc.convert(l.cloudSyncPostAuthBody);
  final missingTitle = esc.convert(l.cloudSyncPostAuthScopeMissingTitle);
  final missingBody = esc.convert(l.cloudSyncPostAuthScopeMissingBody);
  return '''
<!DOCTYPE html>
<html lang="$lang">
<head>
<meta charset="utf-8">
<title>$title</title>
<style>
  body { margin: 0; min-height: 100vh; display: flex; align-items: center;
         justify-content: center; font-family: system-ui, sans-serif;
         background: #14161a; color: #e6e9ef; }
  @media (prefers-color-scheme: light) {
    body { background: #f5f6f8; color: #1c1e21; }
  }
  main { text-align: center; padding: 2.5rem 3rem; max-width: 32rem; }
  .mark { font-size: 3rem; }
  h1 { font-size: 1.4rem; margin: 0.75rem 0 0.5rem; }
  p { margin: 0; opacity: 0.75; }
</style>
</head>
<body>
<main id="ok">
  <div class="mark">&#9989;</div>
  <h1>$title</h1>
  <p>$body</p>
</main>
<main id="scope-missing" hidden>
  <div class="mark">&#9888;&#65039;</div>
  <h1>$missingTitle</h1>
  <p>$missingBody</p>
</main>
<script>
  // Google 回跳帶 scope=實際授予的權限清單；缺 drive.appdata 時切換文案。
  // 參數缺席時保守維持成功文案（app 端另有 scope 驗證兜底）。
  var scope = new URLSearchParams(location.search).get('scope');
  if (scope !== null && scope.indexOf('drive.appdata') === -1) {
    document.getElementById('ok').hidden = true;
    document.getElementById('scope-missing').hidden = false;
  }
</script>
</body>
</html>
''';
}

/// 以當前 context 的語言組出完成頁並發起連結。
void _linkWithLocalizedPage(BuildContext context, WidgetRef ref) {
  final l = AppLocalizations.of(context)!;
  final lang = Localizations.localeOf(context).toLanguageTag();
  unawaited(
    ref
        .read(cloudSyncProvider.notifier)
        .link(postAuthPage: _buildPostAuthPage(l, lang)),
  );
}

/// 設定頁「雲端同步」區塊：連結 Google 帳號、自動同步開關、立即同步與中斷連結。
class CloudSyncSection extends ConsumerWidget {
  /// 建立 [CloudSyncSection]。
  const CloudSyncSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;

    if (!isCloudSyncConfigured) {
      return Text(
        l.cloudSyncUnconfigured,
        style: TextStyle(color: tokens.textMuted),
      );
    }

    // 授權等待結束（成功、失敗、缺 scope 皆同）時把視窗帶回前景，
    // 使用者在瀏覽器按完「允許」不必自己切回 app 看結果。
    ref.listen(cloudSyncProvider, (prev, next) {
      final leftConsent =
          prev?.phase == CloudSyncPhase.awaitingConsent &&
          next.phase != CloudSyncPhase.awaitingConsent;
      if (leftConsent) unawaited(ref.read(windowForegroundProvider)());
    });

    final email = ref.watch(
      settingsProvider.select((s) => s.cloudAccountEmail),
    );
    final sync = ref.watch(cloudSyncProvider);

    if (email == null) {
      return _UnlinkedView(l: l, sync: sync);
    }
    return _LinkedView(l: l, email: email, sync: sync);
  }
}

/// 未連結狀態：說明文字＋連結按鈕（授權等待中顯示 spinner 與取消）。
class _UnlinkedView extends ConsumerWidget {
  /// 建立 [_UnlinkedView]。
  const _UnlinkedView({required this.l, required this.sync});

  /// 當前 i18n 字串實例。
  final AppLocalizations l;

  /// 當前同步狀態（含階段與錯誤 token）。
  final CloudSyncState sync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).gacha;
    final awaiting = sync.phase == CloudSyncPhase.awaitingConsent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.cloudSyncIntro, style: TextStyle(color: tokens.textSecondary)),
        if (sync.phase == CloudSyncPhase.error) ...[
          const SizedBox(height: AppSpacing.s),
          Text(
            sync.errorToken == 'scopeMissing'
                ? l.cloudSyncErrorScopeMissing
                : l.cloudSyncErrorAuthFailed,
            style: TextStyle(color: tokens.stateDanger),
          ),
        ],
        const SizedBox(height: AppSpacing.m),
        if (awaiting)
          _AwaitingConsentRow(l: l)
        else
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => _linkWithLocalizedPage(context, ref),
              icon: const Icon(Icons.link, size: 18),
              label: Text(l.cloudSyncLink),
            ),
          ),
      ],
    );
  }
}

/// 等待瀏覽器授權中的提示列：spinner＋說明＋取消，未連結與重連兩處共用。
class _AwaitingConsentRow extends ConsumerWidget {
  /// 建立 [_AwaitingConsentRow]。
  const _AwaitingConsentRow({required this.l});

  /// 當前 i18n 字串實例。
  final AppLocalizations l;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).gacha;
    return Row(
      children: [
        const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: AppSpacing.m),
        Expanded(
          child: Text(
            l.cloudSyncAwaitingConsent,
            style: TextStyle(color: tokens.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () => ref.read(cloudSyncProvider.notifier).cancelLink(),
          child: Text(l.actionCancel),
        ),
      ],
    );
  }
}

/// 已連結狀態：email、自動同步開關、同步狀態列、立即同步與中斷連結。
class _LinkedView extends ConsumerWidget {
  /// 建立 [_LinkedView]。
  const _LinkedView({required this.l, required this.email, required this.sync});

  /// 當前 i18n 字串實例。
  final AppLocalizations l;

  /// 已連結帳號 email。
  final String email;

  /// 當前同步狀態。
  final CloudSyncState sync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).gacha;
    final autoSync = ref.watch(
      settingsProvider.select((s) => s.cloudAutoSyncEnabled),
    );
    final lastSyncedAt = ref.watch(
      settingsProvider.select((s) => s.cloudLastSyncedAt),
    );
    final syncing = sync.phase == CloudSyncPhase.syncing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.cloudSyncLinkedAs(email)),
        const SizedBox(height: AppSpacing.s),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l.cloudSyncAutoToggle),
          subtitle: Text(
            l.cloudSyncAutoToggleHint,
            style: TextStyle(color: tokens.textMuted, fontSize: 12),
          ),
          value: autoSync,
          onChanged: (v) => ref.read(cloudSyncProvider.notifier).setAutoSync(v),
        ),
        const SizedBox(height: AppSpacing.s),
        // 重連（reauthRequired → link）等待授權期間顯示與未連結態相同的
        // 等待列，取代狀態列與動作鈕，避免按了重連卻看似沒反應。
        if (sync.phase == CloudSyncPhase.awaitingConsent) ...[
          _AwaitingConsentRow(l: l),
        ] else ...[
          _StatusLine(l: l, sync: sync, lastSyncedAt: lastSyncedAt),
          const SizedBox(height: AppSpacing.m),
          Wrap(
            spacing: AppSpacing.m,
            runSpacing: AppSpacing.s,
            children: [
              FilledButton.icon(
                onPressed: syncing
                    ? null
                    : () => ref
                          .read(cloudSyncProvider.notifier)
                          .syncNow(manual: true),
                icon: syncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_sync, size: 18),
                label: Text(l.cloudSyncNow),
              ),
              if (sync.phase == CloudSyncPhase.reauthRequired)
                FilledButton.icon(
                  onPressed: () => _linkWithLocalizedPage(context, ref),
                  icon: const Icon(Icons.link, size: 18),
                  label: Text(l.cloudSyncLink),
                ),
              OutlinedButton.icon(
                onPressed: () => _confirmUnlink(context, ref),
                icon: const Icon(Icons.link_off, size: 18),
                label: Text(l.cloudSyncUnlink),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// 彈出中斷連結確認框，確認後執行 unlink。
  Future<void> _confirmUnlink(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context)!;
    final ok = await showConfirmDialog(
      context: context,
      title: l.cloudSyncUnlinkConfirmTitle,
      body: l.cloudSyncUnlinkConfirmBody,
      cancelLabel: l.actionCancel,
      confirmLabel: l.cloudSyncUnlink,
      confirmIcon: Icons.link_off,
    );
    if (ok != true) return;
    await ref.read(cloudSyncProvider.notifier).unlink();
  }
}

/// 同步狀態列：依 phase 顯示上次同步時間或錯誤原因。
class _StatusLine extends StatelessWidget {
  /// 建立 [_StatusLine]。
  const _StatusLine({
    required this.l,
    required this.sync,
    required this.lastSyncedAt,
  });

  /// 當前 i18n 字串實例。
  final AppLocalizations l;

  /// 當前同步狀態。
  final CloudSyncState sync;

  /// 上次同步成功時間。
  final DateTime? lastSyncedAt;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).gacha;
    switch (sync.phase) {
      case CloudSyncPhase.reauthRequired:
        return Text(
          sync.errorToken == 'scopeMissing'
              ? l.cloudSyncErrorScopeMissing
              : l.cloudSyncReauthRequired,
          style: TextStyle(color: tokens.stateDanger),
        );
      case CloudSyncPhase.error:
        final text = switch (sync.errorToken) {
          'busy' => l.cloudSyncErrorBusy,
          'schemaTooNew' => l.cloudSyncErrorSchemaTooNew,
          'authFailed' => l.cloudSyncErrorAuthFailed,
          'scopeMissing' => l.cloudSyncErrorScopeMissing,
          _ => l.cloudSyncErrorNetwork,
        };
        return Text(text, style: TextStyle(color: tokens.stateDanger));
      case CloudSyncPhase.idle:
      case CloudSyncPhase.syncing:
      case CloudSyncPhase.awaitingConsent:
        final at = lastSyncedAt;
        if (at == null) {
          return Text(
            l.cloudSyncNeverSynced,
            style: TextStyle(color: tokens.textMuted),
          );
        }
        return RelativeTimeText(
          time: at,
          templateBuilder: l.cloudSyncLastSynced,
          style: TextStyle(color: tokens.textMuted),
        );
    }
  }
}
