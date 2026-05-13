// lib/pages/settings_page.dart
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/accounts_bundle.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/accounts_export.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/accounts_import.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/settings_storage.dart';
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
    final settings = ref.watch(settingsProvider);
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
                  current: settings.themeMode,
                  onChanged: notifier.setThemeMode,
                  l: l,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.settingsLanguage,
                icon: Icons.language,
                child: _LocaleDropdown(
                  current: settings.locale,
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
    final asyncMeta = ref.watch(localeMetadataProvider);
    return asyncMeta.when(
      data: (metadata) {
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
      },
      loading: () => const SizedBox(
        height: 56,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Text('Failed to load locale metadata: $e'),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.settingsAboutVersion(version)),
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
            const AppLink(
              url: 'https://genshininfo.reh.tw/',
              child: Text('原神資訊站 Genshin Impact Info'),
            ),
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
              url: 'https://genshininfo.reh.tw/',
              semanticLabel: '原神資訊站 Genshin Impact Info',
              height: 64,
            ),
          ],
        ),
      ],
    );
  }
}

class _DataManagement extends ConsumerWidget {
  const _DataManagement();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final state = ref.watch(wishRepositoryProvider);
    final hasData = state.byUid.isNotEmpty;

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
          onPressed: state.activeUid == null
              ? null
              : () => _clearActive(context, ref, state.activeUid!),
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
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(
      ctx,
    ).showSnackBar(SnackBar(content: Text(l.settingsExportSuccess(loc.path))));
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
    );
    if (ok != true) return;
    if (!ctx.mounted) return;

    final result = await ref
        .read(wishRepositoryProvider.notifier)
        .importAccounts(filteredBundle);
    if (!ctx.mounted) return;

    final SnackBar snack;
    if (result.failedUids.isEmpty) {
      snack = SnackBar(
        content: Text(
          l.settingsImportSuccess(result.successAccounts, result.totalRecords),
        ),
      );
    } else {
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
    );
    if (ok != true) return;
    await ref.read(wishRepositoryProvider.notifier).clearAll();
  }
}

String _two(int n) => n.toString().padLeft(2, '0');
