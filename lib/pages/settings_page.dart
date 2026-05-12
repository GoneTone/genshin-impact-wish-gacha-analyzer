// lib/pages/settings_page.dart
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/all_accounts_bundle.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/all_accounts_export.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/all_accounts_import.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/settings_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/localization_metadata.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/account_management.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/section_card.dart';
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
              PageHeader(title: l.settingsTitle),
              SectionCard(
                title: l.settingsAppearance,
                child: _ThemeRadios(
                  current: settings.themeMode,
                  onChanged: notifier.setThemeMode,
                  l: l,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.settingsLanguage,
                child: _LocaleDropdown(
                  current: settings.locale,
                  onChanged: notifier.setLocale,
                  l: l,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.settingsDataManagement,
                child: const _DataManagement(),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.settingsAccountManagement,
                child: const AccountManagement(),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(title: l.settingsAbout, child: const _AboutContent()),
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
    final version = ref.watch(appVersionProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text(l.settingsAboutVersion(version))],
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
          onPressed: !hasData ? null : () => _exportAll(context, ref),
          icon: const Icon(Icons.download_outlined, size: 18),
          label: Text(l.settingsExportAll),
        ),
        OutlinedButton.icon(
          onPressed: () => _importAll(context, ref),
          icon: const Icon(Icons.upload_outlined, size: 18),
          label: Text(l.settingsImportAll),
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

  Future<void> _exportAll(BuildContext ctx, WidgetRef ref) async {
    final l = AppLocalizations.of(ctx)!;
    final wish = ref.read(wishRepositoryProvider);
    final settings = ref.read(settingsProvider);
    final appVersion = ref.read(appVersionProvider);

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

    final text = exportAllAccounts(
      byUid: wish.byUid,
      uidOrder: settings.uidOrder,
      uidAliases: settings.uidAliases,
      lastActiveUid: settings.lastActiveUid,
      appVersion: appVersion,
      now: now,
    );
    await File(loc.path).writeAsString(text);
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text(l.settingsExportAllSuccess(loc.path))),
    );
  }

  Future<void> _importAll(BuildContext ctx, WidgetRef ref) async {
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
        SnackBar(content: Text(l.settingsImportAllFailed(e.toString()))),
      );
      return;
    }

    final AllAccountsBundle bundle;
    try {
      bundle = importAllAccounts(text);
    } on FormatException catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(content: Text(l.settingsImportAllFailed(e.message))),
      );
      return;
    }

    // Build dialog body.
    final existing = ref.read(wishRepositoryProvider).byUid.keys.toSet();
    final incoming = bundle.accounts.map((a) => a.data.uid).toList();
    final conflicts = incoming.where(existing.contains).toList();
    final preserved = existing.where((u) => !incoming.contains(u)).toList()
      ..sort();

    var totalRecords = 0;
    for (final a in bundle.accounts) {
      for (final list in a.data.banners.values) {
        totalRecords += list.length;
      }
    }

    final buf = StringBuffer()
      ..writeln(l.settingsImportConfirmIntro(incoming.length, totalRecords));
    for (final a in bundle.accounts) {
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

    if (!ctx.mounted) return;
    final ok = await showConfirmTypeDialog(
      context: ctx,
      title: l.settingsImportConfirmTitle,
      body: buf.toString(),
      expectedText: 'IMPORT',
      cancelLabel: l.confirmCancel,
      confirmLabel: l.confirmDelete,
    );
    if (ok != true) return;
    if (!ctx.mounted) return;

    final result = await ref
        .read(wishRepositoryProvider.notifier)
        .importAllAccounts(bundle);
    if (!ctx.mounted) return;

    final SnackBar snack;
    if (result.failedUids.isEmpty) {
      snack = SnackBar(
        content: Text(
          l.settingsImportAllSuccess(
            result.successAccounts,
            result.totalRecords,
          ),
        ),
      );
    } else {
      snack = SnackBar(
        content: Text(
          l.settingsImportAllPartial(
            result.successAccounts,
            bundle.accounts.length,
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
