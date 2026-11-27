import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/app_info.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/contributors.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/localization_metadata.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/layout.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/section_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/page_header.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/translator_text.dart';

/// 貢獻者清單頁，列出專案領導、測試者、翻譯者等資訊。
class ContributorsPage extends StatelessWidget {
  /// 建立 [ContributorsPage]。
  const ContributorsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: EdgeInsets.all(pagePaddingOf(context)),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: l.contributorsTitle,
                subtitle: l.contributorsSubtitle,
                icon: Icons.volunteer_activism_outlined,
              ),
              SectionCard(
                title: l.contributorsProjectLeader,
                icon: Icons.workspace_premium_outlined,
                child: const _ContributorChips(projectLeaders),
              ),
              const SizedBox(height: AppSpacing.m),
              SectionCard(
                title: l.contributorsTesters,
                icon: Icons.bug_report_outlined,
                child: const _ContributorChips(testers),
              ),
              const SizedBox(height: AppSpacing.m),
              SectionCard(
                title: l.contributorsGithubContributors,
                icon: Icons.groups_outlined,
                child: const TranslatorText(
                  raw:
                      '<a href="$githubContributorsUrl">$githubContributorsUrl</a>',
                ),
              ),
              const SizedBox(height: AppSpacing.m),
              SectionCard(
                title: l.contributorsTranslationReviewer,
                icon: Icons.translate,
                child: const _ContributorChips(translationReviewers),
              ),
              const SizedBox(height: AppSpacing.m),
              SectionCard(
                title: l.contributorsTranslatedLanguages,
                icon: Icons.public,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _LanguageList(),
                    const SizedBox(height: AppSpacing.m),
                    Text(l.contributorsHelpTranslate),
                    const SizedBox(height: AppSpacing.s),
                    const TranslatorText(
                      raw:
                          '<a href="$translationCrowdinUrl">$translationCrowdinUrl</a>',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.m),
              SectionCard(
                title: l.contributorsProjectLicense,
                icon: Icons.gavel_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const TranslatorText(
                      raw: '<a href="$licenseUrl">MIT License</a>',
                    ),
                    const SizedBox(height: AppSpacing.m),
                    const _ThirdPartyLicensesButton(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 開啟 Flutter 內建授權頁的按鈕，列出 App 用到的套件授權。
class _ThirdPartyLicensesButton extends ConsumerWidget {
  /// 建立 [_ThirdPartyLicensesButton]。
  const _ThirdPartyLicensesButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    return OutlinedButton.icon(
      onPressed: () => showLicensePage(
        context: context,
        applicationName: l.appName,
        applicationVersion: ref.read(appVersionProvider),
        // Flutter 的授權頁把名稱、圖示、版本直接疊在一起，間距要自己補
        applicationIcon: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Image.asset(
              'assets/icons/app_icon.png',
              width: 64,
              height: 64,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
        useRootNavigator: true,
      ),
      icon: const Icon(Icons.integration_instructions_outlined, size: 18),
      label: Text(l.contributorsOpenSourceLicenses),
    );
  }
}

/// 以 [Wrap] 排列一組 [Contributor]，有連結者用 [AppLink] 包裝。
class _ContributorChips extends StatelessWidget {
  const _ContributorChips(this.items);

  /// 要顯示的貢獻者清單。
  final List<Contributor> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.m,
      runSpacing: AppSpacing.s,
      children: [
        for (final c in items)
          if (c.url == null)
            Text(c.name)
          else
            AppLink(url: c.url!, child: Text(c.name)),
      ],
    );
  }
}

/// 已翻譯語言清單，每行顯示語言原生名稱與翻譯者（如有）。
class _LanguageList extends ConsumerWidget {
  const _LanguageList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metadata = ref.watch(localeMetadataProvider);
    final sorted = sortedLocaleMetadata(metadata);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in sorted)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: entry.value.translator.isEmpty
                ? Text(entry.value.nativeName)
                // 語言名稱長或字級放大時，翻譯者改排到下一行，不擠出右緣；放得下時仍同一行。
                : Wrap(
                    children: [
                      Text('${entry.value.nativeName} — '),
                      TranslatorText(raw: entry.value.translator),
                    ],
                  ),
          ),
      ],
    );
  }
}
