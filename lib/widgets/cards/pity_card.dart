import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/gacha_pity.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

/// 顯示單一稀有度的保底進度卡片，包含抽數、進度條與副標題。
class PityCard extends StatefulWidget {
  const PityCard({
    super.key,
    required this.label,
    required this.rank,
    required this.pity,
    required this.accent,
    this.isEndedPool = false,
  });

  /// 卡片標籤（顯示於最上方，轉 uppercase）。
  final String label;

  /// 該 pity 對應的稀有度（5 / 4 / 3 / 2）。
  /// 用來決定「暫無 N★」副文字裡的 N。
  final int rank;

  /// 保底狀態資料。
  final Pity pity;

  /// 左側邊條與進度條的主色。
  final Color accent;

  /// 新手池 20 抽結束 → 顯示「已結束」狀態。
  final bool isEndedPool;

  @override
  State<PityCard> createState() => _PityCardState();
}

/// State for [PityCard]; 管理「快保底」閃爍動畫的 [AnimationController]。
class _PityCardState extends State<PityCard>
    with SingleTickerProviderStateMixin {
  /// 用於進度條閃爍效果的動畫控制器（`close` phase 時啟動）。
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
          Text(widget.label.toUpperCase(), style: theme.textTheme.labelSmall),
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
            rank: widget.rank,
            isEndedPool: widget.isEndedPool,
            tokens: tokens,
            l: l,
          ),
        ],
      ),
    );
  }

  /// 依 [Pity] 狀態判斷目前顯示階段。
  _Phase _phase(Pity p) {
    if (widget.isEndedPool) return _Phase.ended;
    if (p.progress >= 1.0 || p.distance == 0) return _Phase.guaranteed;
    // 5★ 池（threshold 90）：剩餘 20 抽以內顯示「快保底」。
    // 4★ 池（threshold 10）等較小的池子用 30% 作為比例門檻。
    final closeAt = p.threshold > 20 ? 20 : (p.threshold * 0.3).ceil();
    if (p.distance <= closeAt) return _Phase.close;
    return _Phase.normal;
  }
}

/// 保底卡片的顯示階段，決定顏色與副標題文案。
enum _Phase { normal, close, guaranteed, ended }

/// 保底進度條；`close` phase 時加入呼吸閃爍動畫。
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.progress,
    required this.phase,
    required this.accent,
    required this.tokens,
    required this.breath,
  });

  /// 目前保底進度（0.0–1.0）。
  final double progress;

  /// 決定漸層顏色與是否啟動閃爍動畫的階段。
  final _Phase phase;

  /// 進度條右端顏色。
  final Color accent;

  /// 主題 token。
  final GachaTokens tokens;

  /// 閃爍動畫控制器；null 表示使用者開啟了 reduce motion 或非 close phase。
  final AnimationController? breath;

  @override
  Widget build(BuildContext context) {
    Widget bar = Container(
      width: double.infinity,
      height: 8,
      decoration: BoxDecoration(
        color: tokens.borderSubtle,
        borderRadius: BorderRadius.circular(4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: progress.clamp(0.0, 1.0),
          heightFactor: 1.0,
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
        builder: (_, child) =>
            Opacity(opacity: 0.7 + 0.3 * breath!.value, child: child),
        child: bar,
      );
    }
    return bar;
  }
}

/// 保底卡片底部副標題，依 [_Phase] 顯示對應文案與可選平均間隔。
class _Subtitle extends StatelessWidget {
  const _Subtitle({
    required this.phase,
    required this.pity,
    required this.rank,
    required this.isEndedPool,
    required this.tokens,
    required this.l,
  });

  /// 決定顯示文案與顏色的階段。
  final _Phase phase;

  /// 保底狀態資料，用於距離與平均間隔文案。
  final Pity pity;

  /// 稀有度，用於「暫無 N★」文案。
  final int rank;

  /// 是否為已結束的新手池。
  final bool isEndedPool;

  /// 主題 token。
  final GachaTokens tokens;

  /// 在地化資源。
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (text, color) = switch (phase) {
      _Phase.ended => (l.pityBeginnerEnded, tokens.textMuted),
      _Phase.guaranteed => (l.pityGuaranteed, tokens.stateWarning),
      _Phase.close => (l.pityClose(pity.distance), tokens.stateWarning),
      _Phase.normal =>
        pity.lastRecordAt == null
            ? (l.pityNoMainRarity(l.rarityStar(rank)), tokens.textMuted)
            : (l.pityDistance(pity.distance), tokens.textMuted),
    };

    final baseStyle = theme.textTheme.bodyMedium;
    final avg = pity.averageInterval;
    final showAverage = pity.hitCount >= 1 && avg != null;

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: text,
            style: baseStyle?.copyWith(color: color),
          ),
          if (showAverage)
            TextSpan(
              text: ' · ${l.pityAverageInterval(avg.toStringAsFixed(2))}',
              style: baseStyle?.copyWith(color: tokens.textMuted),
            ),
        ],
      ),
      style: baseStyle,
    );
  }
}
