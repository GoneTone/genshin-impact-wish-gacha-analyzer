// lib/pages/contributors_page.dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/cards/section_card.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/page_header.dart';

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
                child: const SizedBox.shrink(),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.contributorsTesters,
                child: const SizedBox.shrink(),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.contributorsGithubContributors,
                child: const SizedBox.shrink(),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionCard(
                title: l.contributorsTranslationReviewer,
                child: const SizedBox.shrink(),
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
