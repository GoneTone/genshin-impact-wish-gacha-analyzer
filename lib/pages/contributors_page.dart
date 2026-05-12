// lib/pages/contributors_page.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/contributors.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
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
                child: const SizedBox.shrink(),
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
