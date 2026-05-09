import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/wish_pity.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

class PityCard extends StatefulWidget {
  const PityCard({
    super.key,
    required this.label,
    required this.pity,
    required this.accent,
    this.isEndedPool = false,
  });

  final String label;
  final Pity pity;
  final Color accent;

  /// 新手池 20 抽結束 → 顯示「已結束」狀態。
  final bool isEndedPool;

  @override
  State<PityCard> createState() => _PityCardState();
}

class _PityCardState extends State<PityCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final l = AppLocalizations.of(context)!;
    final p = widget.pity;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final phase = _phase(p);

    final accent = phase == _Phase.guaranteed
        ? tokens.stateWarning
        : widget.accent;

    return Container(
      constraints: const BoxConstraints(minHeight: 80),
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        border: Border(left: BorderSide(color: accent, width: 3)),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.label.toUpperCase(),
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l.pityCurrent(p.current, p.threshold),
            style: TextStyle(
              fontSize: AppFontSize.display,
              fontWeight: FontWeight.w800,
              color: tokens.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
              height: 1.1,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          _ProgressBar(
            progress: p.progress,
            phase: phase,
            accent: accent,
            tokens: tokens,
            breath: reduceMotion ? null : _breath,
          ),
          const SizedBox(height: AppSpacing.xs),
          _Subtitle(
            phase: phase,
            pity: p,
            isEndedPool: widget.isEndedPool,
            tokens: tokens,
            l: l,
          ),
        ],
      ),
    );
  }

  _Phase _phase(Pity p) {
    if (widget.isEndedPool) return _Phase.ended;
    final ratio = p.progress;
    if (ratio >= 1.0 || p.distance == 0) return _Phase.guaranteed;
    if (ratio >= 0.7) return _Phase.close;
    return _Phase.normal;
  }
}

enum _Phase { normal, close, guaranteed, ended }

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.progress,
    required this.phase,
    required this.accent,
    required this.tokens,
    required this.breath,
  });
  final double progress;
  final _Phase phase;
  final Color accent;
  final GachaTokens tokens;
  final AnimationController? breath;

  @override
  Widget build(BuildContext context) {
    Widget bar = Container(
      height: 8,
      decoration: BoxDecoration(
        color: tokens.borderSubtle,
        borderRadius: BorderRadius.circular(4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: progress.clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: phase == _Phase.normal
                    ? [accent.withValues(alpha: 0.7), accent]
                    : [tokens.fourStar, accent],
              ),
            ),
          ),
        ),
      ),
    );

    if (breath != null && phase == _Phase.close) {
      bar = AnimatedBuilder(
        animation: breath!,
        builder: (_, child) => Opacity(
          opacity: 0.7 + 0.3 * breath!.value,
          child: child,
        ),
        child: bar,
      );
    }
    return bar;
  }
}

class _Subtitle extends StatelessWidget {
  const _Subtitle({
    required this.phase,
    required this.pity,
    required this.isEndedPool,
    required this.tokens,
    required this.l,
  });
  final _Phase phase;
  final Pity pity;
  final bool isEndedPool;
  final GachaTokens tokens;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (text, color) = switch (phase) {
      _Phase.ended => (l.pityBeginnerEnded, tokens.textMuted),
      _Phase.guaranteed => (l.pityGuaranteed, tokens.stateWarning),
      _Phase.close => (l.pityClose, tokens.stateWarning),
      _Phase.normal => pity.lastFiveStarAt == null
          ? (l.pityNoFiveStar, tokens.textMuted)
          : (l.pityDistance(pity.distance), tokens.textMuted),
    };

    return Text(
      text,
      style: theme.textTheme.bodyMedium?.copyWith(color: color),
    );
  }
}
