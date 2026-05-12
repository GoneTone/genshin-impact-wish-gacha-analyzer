// lib/pages/contributors_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/contributors.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/localization_metadata.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/section_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/page_header.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/translator_text.dart';

class ContributorsPage extends StatelessWidget {
  const ContributorsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: l.contributorsTitle,
                subtitle: l.contributorsSubtitle,
              ),
              SectionCard(
                title: l.contributorsProjectLeader,
                child: const _ContributorChips(projectLeaders),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.contributorsTesters,
                child: const _ContributorChips(testers),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.contributorsGithubContributors,
                child: const TranslatorText(
                  raw:
                      '<a href="$githubContributorsUrl">$githubContributorsUrl</a>',
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.contributorsTranslationReviewer,
                child: const _ContributorChips(translationReviewers),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.contributorsTranslatedLanguages,
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
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.contributorsProjectLicense,
                child: const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContributorChips extends StatelessWidget {
  const _ContributorChips(this.items);
  final List<Contributor> items;

  @override
  Widget build(BuildContext context) {
    final linkColor = Theme.of(context).colorScheme.primary;
    return Wrap(
      spacing: AppSpacing.m,
      runSpacing: AppSpacing.s,
      children: [
        for (final c in items)
          if (c.url == null)
            Text(c.name)
          else
            InkWell(
              onTap: () => _open(c.url!),
              child: Text(
                c.name,
                style: TextStyle(
                  color: linkColor,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
      ],
    );
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _LanguageList extends ConsumerWidget {
  const _LanguageList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncMeta = ref.watch(localeMetadataProvider);
    return asyncMeta.when(
      data: (metadata) {
        final sorted = sortedLocaleMetadata(metadata);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in sorted)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: entry.value.translator.isEmpty
                    ? Text(entry.value.nativeName)
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${entry.value.nativeName} — '),
                          Expanded(
                            child: TranslatorText(raw: entry.value.translator),
                          ),
                        ],
                      ),
              ),
          ],
        );
      },
      loading: () => const SizedBox(
        height: 56,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Text('Failed to load locale metadata: $e'),
    );
  }
}
