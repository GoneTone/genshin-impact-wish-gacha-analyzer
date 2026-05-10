import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

class Pager extends StatelessWidget {
  const Pager({
    super.key,
    required this.page,
    required this.totalPages,
    required this.onChanged,
  });

  final int page; // 0-based
  final int totalPages;
  final void Function(int) onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final canPrev = page > 0;
    final canNext = page + 1 < totalPages;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: l.pagerFirst,
          onPressed: canPrev ? () => onChanged(0) : null,
          icon: const Icon(Icons.first_page),
        ),
        IconButton(
          tooltip: l.actionPrevPage,
          onPressed: canPrev ? () => onChanged(page - 1) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        const SizedBox(width: AppSpacing.s),
        DropdownButton<int>(
          value: page,
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
          items: [
            for (var i = 0; i < totalPages; i++)
              DropdownMenuItem(value: i, child: Text('${i + 1} / $totalPages')),
          ],
        ),
        const SizedBox(width: AppSpacing.s),
        IconButton(
          tooltip: l.actionNextPage,
          onPressed: canNext ? () => onChanged(page + 1) : null,
          icon: const Icon(Icons.chevron_right),
        ),
        IconButton(
          tooltip: l.pagerLast,
          onPressed: canNext ? () => onChanged(totalPages - 1) : null,
          icon: const Icon(Icons.last_page),
        ),
      ],
    );
  }
}
