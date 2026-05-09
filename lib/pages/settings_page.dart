// lib/pages/settings_page.dart
import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/settings_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/settings.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/section_card.dart';
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
                child: Text(l.settingsPlaceholderPhase2,
                    style: TextStyle(
                        color: Theme.of(context).gacha.textMuted)),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.settingsAccountManagement,
                child: Text(l.settingsPlaceholderPhase2,
                    style: TextStyle(
                        color: Theme.of(context).gacha.textMuted)),
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
