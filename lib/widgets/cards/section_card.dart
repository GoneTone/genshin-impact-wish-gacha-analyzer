// lib/widgets/cards/section_card.dart
import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.l),
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        border: Border.all(color: tokens.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.m),
          child,
        ],
      ),
    );
  }
}
