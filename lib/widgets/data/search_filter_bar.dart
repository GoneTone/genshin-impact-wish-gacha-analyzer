import 'dart:async';

import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/wish_filter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/record_filter.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

class SearchFilterBar extends StatefulWidget {
  const SearchFilterBar({
    super.key,
    required this.state,
    required this.onFilterChanged,
    required this.onSortChanged,
    required this.onClear,
  });

  final RecordFilterState state;
  final ValueChanged<RecordFilter> onFilterChanged;
  final ValueChanged<RecordSort> onSortChanged;
  final VoidCallback onClear;

  @override
  State<SearchFilterBar> createState() => _SearchFilterBarState();
}

class _SearchFilterBarState extends State<SearchFilterBar> {
  late final TextEditingController _ctrl;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.state.filter.query);
  }

  @override
  void didUpdateWidget(covariant SearchFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.filter.query != _ctrl.text) {
      _ctrl.text = widget.state.filter.query;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      widget.onFilterChanged(widget.state.filter.copyWith(query: text));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Wrap(
      spacing: AppSpacing.s,
      runSpacing: AppSpacing.s,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 240,
          child: TextField(
            controller: _ctrl,
            decoration: InputDecoration(
              hintText: l.filterSearchHint,
              prefixIcon: const Icon(Icons.search, size: 18),
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.m, vertical: AppSpacing.s),
              isDense: true,
            ),
            onChanged: _onQueryChanged,
          ),
        ),
        DropdownButton<RarityFilter>(
          value: widget.state.filter.rarity,
          onChanged: (v) {
            if (v != null) {
              widget.onFilterChanged(
                  widget.state.filter.copyWith(rarity: v));
            }
          },
          items: [
            DropdownMenuItem(
                value: RarityFilter.all,
                child: Text(l.filterRarityAll)),
            DropdownMenuItem(
                value: RarityFilter.fiveStar,
                child: Text(l.filterRarityFiveStar)),
            DropdownMenuItem(
                value: RarityFilter.fourStar,
                child: Text(l.filterRarityFourStar)),
          ],
        ),
        DropdownButton<KindFilter>(
          value: widget.state.filter.kind,
          onChanged: (v) {
            if (v != null) {
              widget.onFilterChanged(
                  widget.state.filter.copyWith(kind: v));
            }
          },
          items: [
            DropdownMenuItem(
                value: KindFilter.all, child: Text(l.filterKindAll)),
            DropdownMenuItem(
                value: KindFilter.character,
                child: Text(l.filterKindCharacter)),
            DropdownMenuItem(
                value: KindFilter.weapon,
                child: Text(l.filterKindWeapon)),
          ],
        ),
        DropdownButton<RecordSort>(
          value: widget.state.sort,
          onChanged: (v) {
            if (v != null) widget.onSortChanged(v);
          },
          items: [
            DropdownMenuItem(
                value: RecordSort.timeDesc,
                child: Text(l.sortByTimeDesc)),
            DropdownMenuItem(
                value: RecordSort.timeAsc,
                child: Text(l.sortByTimeAsc)),
            DropdownMenuItem(
                value: RecordSort.rarityDesc,
                child: Text(l.sortByRarityDesc)),
            DropdownMenuItem(
                value: RecordSort.rarityAsc,
                child: Text(l.sortByRarityAsc)),
            DropdownMenuItem(
                value: RecordSort.name, child: Text(l.sortByName)),
          ],
        ),
        if (widget.state.filter.hasAny)
          TextButton.icon(
            onPressed: widget.onClear,
            icon: const Icon(Icons.clear, size: 16),
            label: Text(l.filterClear),
          ),
      ],
    );
  }
}
