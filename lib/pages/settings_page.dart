// lib/pages/settings_page.dart
import 'dart:async' show unawaited;
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/log_service.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/app_repo.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/team_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/accounts_bundle.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/accounts_export.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/accounts_import.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/file_reveal.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/settings_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/app_release.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/localization_metadata.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/uid_ordering.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/banner_link.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/account_management.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/section_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/accounts_picker_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/confirm_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/page_header.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final localePref = ref.watch(settingsProvider.select((s) => s.locale));
    final notifier = ref.read(settingsProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(title: l.settingsTitle, icon: Icons.settings_outlined),
              SectionCard(
                title: l.settingsAppearance,
                icon: Icons.palette_outlined,
                child: _ThemeRadios(
                  current: themeMode,
                  onChanged: notifier.setThemeMode,
                  l: l,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.settingsLanguage,
                icon: Icons.language,
                child: _LocaleDropdown(
                  current: localePref,
                  onChanged: notifier.setLocale,
                  l: l,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.settingsDataManagement,
                icon: Icons.folder_outlined,
                child: const _DataManagement(),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.settingsAccountManagement,
                icon: Icons.manage_accounts_outlined,
                child: const AccountManagement(),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.settingsLogs,
                icon: Icons.bug_report_outlined,
                child: const _LogsSection(),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.settingsAbout,
                icon: Icons.info_outline,
                child: const _AboutContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeRadios extends StatelessWidget {
  const _ThemeRadios({
    required this.current,
    required this.onChanged,
    required this.l,
  });
  final AppThemeMode current;
  final ValueChanged<AppThemeMode> onChanged;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    return RadioGroup<AppThemeMode>(
      groupValue: current,
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
      child: Column(
        children: [
          for (final entry in {
            AppThemeMode.system: l.settingsThemeSystem,
            AppThemeMode.dark: l.settingsThemeDark,
            AppThemeMode.light: l.settingsThemeLight,
          }.entries)
            RadioListTile<AppThemeMode>(
              title: Text(entry.value),
              value: entry.key,
              contentPadding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }
}

class _LocaleDropdown extends ConsumerWidget {
  const _LocaleDropdown({
    required this.current,
    required this.onChanged,
    required this.l,
  });
  final LanguagePreference current;
  final ValueChanged<LanguagePreference> onChanged;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metadata = ref.watch(localeMetadataProvider);
    final sorted = sortedLocaleMetadata(metadata);
    final selectableTags = metadata.keys.toSet();
    // 防禦：使用者過去可能存了 supportedLocales 已不存在的代碼（例如
    // 整併前的 "pt-BR"）。若 current 不在當前 dropdown 選項裡，顯示為
    // SystemLanguage 避免 DropdownButtonFormField 因 value 找不到對應
    // 項目而 assert failed。
    final effectiveCurrent =
        current is SystemLanguage ||
            (current is LocaleLanguage &&
                selectableTags.contains((current as LocaleLanguage).code))
        ? current
        : const SystemLanguage();
    return DropdownButtonFormField<LanguagePreference>(
      initialValue: effectiveCurrent,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: [
        DropdownMenuItem(
          value: const SystemLanguage(),
          child: Text(l.settingsLocaleSystem),
        ),
        for (final entry in sorted)
          DropdownMenuItem(
            value: LocaleLanguage(entry.key),
            child: Text(entry.value.nativeName),
          ),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class _AboutContent extends ConsumerWidget {
  const _AboutContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final version = ref.watch(appVersionProvider);

    ref.listen<ReleaseCheckState>(appReleaseProvider, (prev, next) {
      if (next is ReleaseUpToDate) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.updateAlreadyLatest)));
      } else if (next is ReleaseCheckFailed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.updateCheckFailed(_resolveReason(l, next.reason))),
          ),
        );
      }
    });

    final releaseState = ref.watch(appReleaseProvider);
    final checking = releaseState is ReleaseChecking;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(l.settingsAboutVersion(version))),
            const SizedBox(width: AppSpacing.s),
            OutlinedButton.icon(
              onPressed: checking
                  ? null
                  : () => ref
                        .read(appReleaseProvider.notifier)
                        .check(manual: true),
              icon: checking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 18),
              label: Text(checking ? l.updateChecking : l.updateCheckButton),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(Icons.code, size: 16, color: theme.gacha.textSecondary),
            const SizedBox(width: AppSpacing.xs),
            const Text('Developed by '),
            const AppLink(
              url: 'https://github.com/GoneTone',
              child: Text('GoneTone'),
            ),
            const Text(' ('),
            const AppLink(url: TeamInfo.websiteUrl, child: Text(TeamInfo.name)),
            const Text(')'),
          ],
        ),
        const SizedBox(height: AppSpacing.l),
        Wrap(
          spacing: AppSpacing.l,
          runSpacing: AppSpacing.l,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: const [
            BannerLink(
              assetPath: 'assets/banners/gonetone_banner.png',
              url: 'https://blog.reh.tw/',
              semanticLabel: '旋風之音 GoneTone',
              height: 64,
            ),
            BannerLink(
              assetPath: 'assets/banners/genshin_info_banner.png',
              url: TeamInfo.websiteUrl,
              semanticLabel: TeamInfo.name,
              height: 64,
            ),
          ],
        ),
      ],
    );
  }

  /// 把 notifier 給的 token 轉成 i18n 字串。
  /// Token 格式：
  ///   - "network" / "timeout" / "rateLimited" / "format"
  ///   - "server:&lt;status&gt;"（status 為 HTTP code）
  String _resolveReason(AppLocalizations l, String token) {
    if (token == 'network') return l.updateErrorNetwork;
    if (token == 'timeout') return l.updateErrorTimeout;
    if (token == 'rateLimited') return l.updateErrorRateLimited;
    if (token == 'format') return l.updateErrorFormat;
    if (token.startsWith('server:')) {
      final status = token.substring('server:'.length);
      return l.updateErrorServer(status);
    }
    return token;
  }
}

class _DataManagement extends ConsumerWidget {
  const _DataManagement();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final hasData = ref.watch(
      wishRepositoryProvider.select((s) => s.byUid.isNotEmpty),
    );
    final activeUid = ref.watch(
      wishRepositoryProvider.select((s) => s.activeUid),
    );

    return Wrap(
      spacing: AppSpacing.s,
      runSpacing: AppSpacing.s,
      children: [
        OutlinedButton.icon(
          onPressed: !hasData ? null : () => _export(context, ref),
          icon: const Icon(Icons.download_outlined, size: 18),
          label: Text(l.settingsExportAccounts),
        ),
        OutlinedButton.icon(
          onPressed: () => _import(context, ref),
          icon: const Icon(Icons.upload_outlined, size: 18),
          label: Text(l.settingsImportAccounts),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).gacha.stateDanger,
            foregroundColor: Colors.white,
          ),
          onPressed: activeUid == null
              ? null
              : () => _clearActive(context, ref, activeUid),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: Text(l.settingsClearActive),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).gacha.stateDanger,
            foregroundColor: Colors.white,
          ),
          onPressed: !hasData ? null : () => _clearAll(context, ref),
          icon: const Icon(Icons.delete_forever_outlined, size: 18),
          label: Text(l.settingsClearAll),
        ),
      ],
    );
  }

  Future<void> _export(BuildContext ctx, WidgetRef ref) async {
    final l = AppLocalizations.of(ctx)!;
    final wish = ref.read(wishRepositoryProvider);
    final settings = ref.read(settingsProvider);
    final appVersion = ref.read(appVersionProvider);

    final ordered = mergeUidOrder(
      knownUids: wish.byUid.keys,
      customOrder: settings.uidOrder,
      lastUpdatedOf: (u) => wish.byUid[u]!.lastUpdated,
    );

    final entries = [
      for (final uid in ordered)
        AccountPickerEntry(
          uid: uid,
          alias: settings.uidAliases[uid],
          lastUpdated: wish.byUid[uid]!.lastUpdated,
          recordCount: wish.byUid[uid]!.allRecords.length,
        ),
    ];
    final picked = await showAccountsPickerDialog(
      context: ctx,
      title: l.settingsExportSelectTitle,
      confirmLabel: l.confirmExport,
      entries: entries,
    );
    if (picked == null || picked.isEmpty) return;
    if (!ctx.mounted) return;

    final now = DateTime.now();
    final stamp =
        '${now.year}-${_two(now.month)}-${_two(now.day)}_'
        '${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';

    final loc = await getSaveLocation(
      suggestedName: 'genshin_wish_backup_$stamp.json',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
    );
    if (loc == null) return;

    final pickedSet = picked.toSet();
    final filteredByUid = {
      for (final e in wish.byUid.entries)
        if (pickedSet.contains(e.key)) e.key: e.value,
    };
    final filteredAliases = {
      for (final e in settings.uidAliases.entries)
        if (pickedSet.contains(e.key)) e.key: e.value,
    };
    final filteredOrder = settings.uidOrder
        .where(pickedSet.contains)
        .toList(growable: false);
    final lastActive = pickedSet.contains(settings.lastActiveUid)
        ? settings.lastActiveUid
        : null;

    final text = exportAccounts(
      byUid: filteredByUid,
      uidOrder: filteredOrder,
      uidAliases: filteredAliases,
      lastActiveUid: lastActive,
      appVersion: appVersion,
      now: now,
    );
    await File(loc.path).writeAsString(text);
    Logger('accounts.io').info(
      'export: uids=${pickedSet.length} '
      'records=${filteredByUid.values.fold<int>(0, (a, b) => a + b.allRecords.length)}',
    );
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(
      ctx,
    ).showSnackBar(SnackBar(content: Text(l.settingsExportSuccess(loc.path))));
    unawaited(revealInFileManager(loc.path));
  }

  Future<void> _import(BuildContext ctx, WidgetRef ref) async {
    final l = AppLocalizations.of(ctx)!;
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
    );
    if (file == null) return;

    final String text;
    try {
      text = await file.readAsString();
    } catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(l.settingsImportFailed(e.toString()))),
      );
      return;
    }

    final AccountsBundle bundle;
    try {
      bundle = importAccounts(text);
    } on FormatException catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(l.settingsImportFailed(e.message))),
      );
      return;
    }

    // Picker：列出檔案內的帳號讓使用者勾選。
    final existing = ref.read(wishRepositoryProvider).byUid.keys.toSet();
    final entries = [
      for (final a in bundle.accounts)
        AccountPickerEntry(
          uid: a.data.uid,
          alias: a.alias,
          lastUpdated: a.data.lastUpdated,
          recordCount: a.data.allRecords.length,
          badge: existing.contains(a.data.uid)
              ? l.settingsImportOverwriteBadge
              : null,
        ),
    ];
    if (!ctx.mounted) return;
    final picked = await showAccountsPickerDialog(
      context: ctx,
      title: l.settingsImportSelectTitle,
      confirmLabel: l.confirmContinue,
      entries: entries,
    );
    if (picked == null || picked.isEmpty) return;
    if (!ctx.mounted) return;

    final pickedSet = picked.toSet();
    final filteredBundle = AccountsBundle(
      exportedAt: bundle.exportedAt,
      appVersion: bundle.appVersion,
      lastActiveUid: pickedSet.contains(bundle.lastActiveUid)
          ? bundle.lastActiveUid
          : null,
      accounts: bundle.accounts
          .where((a) => pickedSet.contains(a.data.uid))
          .toList(growable: false),
    );

    // Confirm dialog：以 filteredBundle 重新計算 incoming / conflicts / preserved。
    final incoming = filteredBundle.accounts
        .map((a) => a.data.uid)
        .toList(growable: false);
    final conflicts = incoming.where(existing.contains).toList(growable: false);
    final preserved = (existing.toSet()..removeAll(incoming)).toList()..sort();

    var totalRecords = 0;
    for (final a in filteredBundle.accounts) {
      for (final list in a.data.banners.values) {
        totalRecords += list.length;
      }
    }

    final buf = StringBuffer()
      ..writeln(l.settingsImportConfirmIntro(incoming.length, totalRecords));
    for (final a in filteredBundle.accounts) {
      final alias = a.alias;
      buf.writeln(
        alias == null || alias.isEmpty
            ? '  • ${a.data.uid}'
            : '  • ${a.data.uid} ($alias)',
      );
    }
    buf.writeln();
    if (conflicts.isEmpty) {
      buf.writeln(l.settingsImportConfirmNoConflict);
    } else {
      buf.writeln(l.settingsImportConfirmOverwriteHeader);
      for (final uid in conflicts) {
        buf.writeln('  • $uid');
      }
    }
    if (preserved.isNotEmpty) {
      buf.writeln();
      buf.writeln(l.settingsImportConfirmPreserveFooter(preserved.join(', ')));
    }
    buf.writeln();
    buf.write(l.settingsImportConfirmWarning);

    final ok = await showConfirmTypeDialog(
      context: ctx,
      title: l.settingsImportConfirmTitle,
      body: buf.toString(),
      expectedText: 'IMPORT',
      cancelLabel: l.confirmCancel,
      confirmLabel: l.confirmImport,
      confirmIcon: Icons.check,
    );
    if (ok != true) return;
    if (!ctx.mounted) return;

    final result = await ref
        .read(wishRepositoryProvider.notifier)
        .importAccounts(filteredBundle);
    if (!ctx.mounted) return;

    final SnackBar snack;
    if (result.failedUids.isEmpty) {
      Logger('accounts.io').info(
        'import: success=${result.successAccounts} '
        'records=${result.totalRecords}',
      );
      snack = SnackBar(
        content: Text(
          l.settingsImportSuccess(result.successAccounts, result.totalRecords),
        ),
      );
    } else {
      Logger('accounts.io').warning(
        'import partial: success=${result.successAccounts} '
        'failed=[${result.failedUids.join(",")}]',
      );
      snack = SnackBar(
        content: Text(
          l.settingsImportPartial(
            result.successAccounts,
            filteredBundle.accounts.length,
            result.failedUids.join(', '),
          ),
        ),
      );
    }
    ScaffoldMessenger.of(ctx).showSnackBar(snack);
  }

  Future<void> _clearActive(BuildContext ctx, WidgetRef ref, String uid) async {
    final l = AppLocalizations.of(ctx)!;
    final ok = await showConfirmTypeDialog(
      context: ctx,
      title: l.confirmTitle,
      body: l.confirmClearActiveBody(uid),
      expectedText: uid,
      cancelLabel: l.confirmCancel,
      confirmLabel: l.confirmDelete,
      confirmIcon: Icons.delete_outline,
    );
    if (ok != true) return;
    await ref.read(wishRepositoryProvider.notifier).clearActive();
  }

  Future<void> _clearAll(BuildContext ctx, WidgetRef ref) async {
    final l = AppLocalizations.of(ctx)!;
    final ok = await showConfirmTypeDialog(
      context: ctx,
      title: l.confirmTitle,
      body: l.confirmClearAllBody,
      expectedText: 'DELETE',
      cancelLabel: l.confirmCancel,
      confirmLabel: l.confirmDelete,
      confirmIcon: Icons.delete_outline,
    );
    if (ok != true) return;
    await ref.read(wishRepositoryProvider.notifier).clearAll();
  }
}

class _LogsSection extends ConsumerWidget {
  const _LogsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.settingsLogsHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.gacha.textMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.m),
        Wrap(
          spacing: AppSpacing.s,
          runSpacing: AppSpacing.s,
          children: [
            OutlinedButton.icon(
              onPressed: () => _reportIssue(),
              icon: const Icon(Icons.bug_report_outlined, size: 18),
              label: Text(l.settingsLogsReport),
            ),
            OutlinedButton.icon(
              onPressed: () => _export(context, ref),
              icon: const Icon(Icons.download_outlined, size: 18),
              label: Text(l.settingsLogsExport),
            ),
            OutlinedButton.icon(
              onPressed: () => _openFolder(context, ref),
              icon: const Icon(Icons.folder_open_outlined, size: 18),
              label: Text(l.settingsLogsOpenFolder),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: theme.gacha.stateDanger,
                foregroundColor: Colors.white,
              ),
              onPressed: () => _clear(context, ref),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(l.settingsLogsClear),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _export(BuildContext ctx, WidgetRef ref) async {
    final l = AppLocalizations.of(ctx)!;
    final log = ref.read(logServiceProvider);
    final appVersion = ref.read(appVersionProvider);
    final settings = ref.read(settingsProvider);

    final now = DateTime.now();
    final stamp =
        '${now.year}-${_two(now.month)}-${_two(now.day)}_'
        '${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';

    final loc = await getSaveLocation(
      suggestedName: 'gwga_logs_$stamp.log',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Log', extensions: ['log']),
      ],
    );
    if (loc == null) return;

    final bundle = await log.buildExportBundle(
      appVersion: appVersion,
      osDescription:
          '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      localeTag: Platform.localeName,
      themeMode: settings.themeMode.name,
    );
    await File(loc.path).writeAsString(bundle);
    Logger(
      'accounts.io',
    ).info('logs exported: ${loc.path} (${bundle.length} bytes)');
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text(l.settingsLogsExportSuccess(loc.path))),
    );
    unawaited(revealInFileManager(loc.path));
  }

  Future<void> _openFolder(BuildContext ctx, WidgetRef ref) async {
    final log = ref.read(logServiceProvider);
    final uri = Uri.file(log.logsDir.path);
    if (!await launchUrl(uri)) {
      Logger('ui.link').warning('openLogsFolder: launchUrl returned false');
    }
  }

  Future<void> _reportIssue() async {
    final uri = Uri.parse('${AppRepo.githubUrl}/issues/new/choose');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      Logger('ui.link').warning('reportIssue: launchUrl returned false');
    }
  }

  Future<void> _clear(BuildContext ctx, WidgetRef ref) async {
    final l = AppLocalizations.of(ctx)!;
    final ok = await showConfirmTypeDialog(
      context: ctx,
      title: l.confirmTitle,
      body: l.settingsLogsClearConfirmBody,
      expectedText: 'CLEAR',
      cancelLabel: l.confirmCancel,
      confirmLabel: l.confirmDelete,
      confirmIcon: Icons.delete_outline,
    );
    if (ok != true) return;
    if (!ctx.mounted) return;
    await ref.read(logServiceProvider).clearAll();
    Logger('accounts.io').info('logs cleared by user');
  }
}

String _two(int n) => n.toString().padLeft(2, '0');
