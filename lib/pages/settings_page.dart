// lib/pages/settings_page.dart
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/data_export.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/data_import.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/settings_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/wish_repository.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
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
                child: const _AccountManagement(),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.settingsAbout,
                child: _AboutContent(),
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

class _LocaleDropdown extends StatelessWidget {
  const _LocaleDropdown({
    required this.current,
    required this.onChanged,
    required this.l,
  });
  final AppLocale current;
  final ValueChanged<AppLocale> onChanged;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<AppLocale>(
      initialValue: current,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: [
        DropdownMenuItem(
            value: AppLocale.system, child: Text(l.settingsLocaleSystem)),
        DropdownMenuItem(
            value: AppLocale.zhHant, child: Text(l.settingsLocaleZhHant)),
        DropdownMenuItem(
            value: AppLocale.zhHans, child: Text(l.settingsLocaleZhHans)),
        DropdownMenuItem(value: AppLocale.en, child: Text(l.settingsLocaleEn)),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class _AboutContent extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final version = ref.watch(appVersionProvider);
    return Text(l.settingsAboutVersion(version));
  }
}

class _DataManagement extends ConsumerWidget {
  const _DataManagement();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final state = ref.watch(wishRepositoryProvider);
    final activeData = state.activeData;
    final hasData = state.byUid.isNotEmpty;

    return Wrap(
      spacing: AppSpacing.s,
      runSpacing: AppSpacing.s,
      children: [
        OutlinedButton.icon(
          onPressed: activeData == null
              ? null
              : () => _exportJson(context, activeData),
          icon: const Icon(Icons.download_outlined, size: 18),
          label: Text(l.settingsExportJson),
        ),
        OutlinedButton.icon(
          onPressed: activeData == null
              ? null
              : () => _exportCsv(context, activeData),
          icon: const Icon(Icons.table_chart_outlined, size: 18),
          label: Text(l.settingsExportCsv),
        ),
        OutlinedButton.icon(
          onPressed: () => _import(context, ref),
          icon: const Icon(Icons.upload_outlined, size: 18),
          label: Text(l.settingsImportJson),
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

  Future<void> _exportJson(BuildContext ctx, BannerStorage data) async {
    final l = AppLocalizations.of(ctx)!;
    final loc = await getSaveLocation(
      suggestedName: 'wish_${data.uid}.json',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
    );
    if (loc == null) return;
    await File(loc.path).writeAsString(exportJson(data));
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text(l.settingsExportSuccess(loc.path)),
    ));
  }

  Future<void> _exportCsv(BuildContext ctx, BannerStorage data) async {
    final l = AppLocalizations.of(ctx)!;
    final loc = await getSaveLocation(
      suggestedName: 'wish_${data.uid}.csv',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV', extensions: ['csv']),
      ],
    );
    if (loc == null) return;
    await File(loc.path).writeAsString(exportCsv(data));
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text(l.settingsExportSuccess(loc.path)),
    ));
  }

  Future<void> _import(BuildContext ctx, WidgetRef ref) async {
    final l = AppLocalizations.of(ctx)!;
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
    );
    if (file == null) return;
    final text = await file.readAsString();
    try {
      final data = importJson(text);
      await ref.read(wishRepositoryProvider.notifier).importData(data);
      if (!ctx.mounted) return;
      final count =
          data.banners.values.fold<int>(0, (n, list) => n + list.length);
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text(l.settingsImportSuccess(data.uid, count)),
      ));
    } on FormatException catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text(l.settingsImportFailed(e.message)),
      ));
    }
  }

  Future<void> _clearActive(
      BuildContext ctx, WidgetRef ref, String uid) async {
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

class _AccountManagement extends ConsumerWidget {
  const _AccountManagement();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final tokens = Theme.of(context).gacha;
    final state = ref.watch(wishRepositoryProvider);
    final notifier = ref.read(wishRepositoryProvider.notifier);
    final uids = state.byUid.keys.toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (uids.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
            child: Text(l.accountListEmpty,
                style: TextStyle(color: tokens.textMuted)),
          )
        else
          for (final uid in uids)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(
                            uid,
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          if (uid == state.activeUid) ...[
                            const SizedBox(width: AppSpacing.s),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.s, vertical: 2),
                              decoration: BoxDecoration(
                                color: tokens.accentPrimary
                                    .withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                l.accountActiveTag,
                                style: TextStyle(
                                  color: tokens.accentPrimary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ]),
                        const SizedBox(height: 2),
                        Text(
                          l.accountLastUpdated(
                            DateFormat('yyyy-MM-dd HH:mm').format(
                                state.byUid[uid]!.lastUpdated.toLocal()),
                          ),
                          style: TextStyle(
                              color: tokens.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (uid != state.activeUid)
                    TextButton(
                      onPressed: () => notifier.setActiveUid(uid),
                      child: Text(l.accountSetActive),
                    ),
                  TextButton(
                    onPressed: () => _remove(context, ref, uid),
                    child: Text(
                      l.accountRemove,
                      style: TextStyle(color: tokens.stateDanger),
                    ),
                  ),
                ],
              ),
            ),
        const Divider(),
        const SizedBox(height: AppSpacing.s),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => notifier.forceRecaptureAndUpdate(),
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(l.accountRecapture),
          ),
        ),
      ],
    );
  }

  Future<void> _remove(
      BuildContext ctx, WidgetRef ref, String uid) async {
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
    await ref.read(wishRepositoryProvider.notifier).removeUid(uid);
  }
}
