import 'package:flutter/material.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/layout.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

/// 嵌入文字的佔位標記字元（Unicode 物件替代字元）。
const _iconMarker = '\uFFFC';

/// 空白狀態佔位元件，支援滿屏置中與縮小版兩種佈局。
class EmptyState extends StatelessWidget {
  /// 建立 [EmptyState]。
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.messageSpan,
    this.action,
    this.compact = false,
  });

  /// 主要圖示。
  final IconData icon;

  /// 標題文字。
  final String title;

  /// 說明文字（可選）。
  final String? message;

  /// 富文字說明（可選）；有值時優先於 [message]。
  final InlineSpan? messageSpan;

  /// 操作按鈕（可選）。
  final Widget? action;

  /// 縮小版:用於「頁面內某個 section 的空位佔位」(icon 40px + 邊框框出範圍),
  /// 非滿屏置中。
  final bool compact;

  /// 未同步狀態的空白佔位（雲端離線圖示 + 提示文字）。
  factory EmptyState.noSync(BuildContext context, {Widget? action}) {
    final l = AppLocalizations.of(context)!;
    final message = l.emptyNoSyncMessage(_iconMarker);
    final at = message.indexOf(_iconMarker);
    return EmptyState(
      icon: Icons.cloud_off_outlined,
      title: l.emptyNoSyncTitle,
      message: at < 0 ? message : null,
      messageSpan: at < 0
          ? null
          : TextSpan(
              children: [
                TextSpan(text: message.substring(0, at)),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: _UpdateButtonGlyph(label: l.actionUpdate),
                ),
                TextSpan(text: message.substring(at + _iconMarker.length)),
              ],
            ),
      action: action,
    );
  }

  /// `title` 可選 override 既定 `l.emptyNoRecords`,讓不同 section 共用此 factory。
  /// `compact: true` 時改為縮小版邊框 placeholder,非滿屏。
  factory EmptyState.noRecords(
    BuildContext context, {
    String? title,
    bool compact = false,
  }) {
    final l = AppLocalizations.of(context)!;
    return EmptyState(
      icon: Icons.inbox_outlined,
      title: title ?? l.emptyNoRecords,
      compact: compact,
    );
  }

  /// 無篩選結果的空白佔位（搜尋關閉圖示）。
  factory EmptyState.noFiltered(BuildContext context, {Widget? action}) {
    final l = AppLocalizations.of(context)!;
    return EmptyState(
      icon: Icons.search_off_outlined,
      title: l.emptyNoFilterMatch,
      action: action,
    );
  }

  /// 依 [messageSpan]／[message] 組出說明文字；兩者皆無則回傳 null。
  Widget? _buildMessage(ThemeData theme) {
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: theme.gacha.textMuted,
    );
    if (messageSpan != null) return Text.rich(messageSpan!, style: style);
    if (message != null) return Text(message!, style: style);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final messageWidget = _buildMessage(theme);

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.xl,
          horizontal: AppSpacing.l,
        ),
        decoration: BoxDecoration(
          color: tokens.surfaceCard,
          border: Border.all(color: tokens.borderSubtle),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: tokens.textMuted),
            const SizedBox(height: AppSpacing.s),
            Text(title, style: theme.textTheme.titleMedium),
            if (messageWidget != null) ...[
              const SizedBox(height: AppSpacing.xs),
              messageWidget,
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.m),
              action!,
            ],
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 72, color: tokens.textMuted),
          const SizedBox(height: AppSpacing.l),
          Text(title, style: theme.textTheme.titleLarge),
          if (messageWidget != null) ...[
            const SizedBox(height: AppSpacing.s),
            messageWidget,
          ],
          if (action != null) ...[
            const SizedBox(height: AppSpacing.l),
            action!,
          ],
        ],
      ),
    );
  }
}

/// 內嵌在說明文字裡、仿右上更新鈕外觀的裝飾圖案（手機為圓形圖示鈕，電腦為膠囊按鈕）。
class _UpdateButtonGlyph extends StatelessWidget {
  /// 建立 [_UpdateButtonGlyph]，[label] 供螢幕閱讀器朗讀。
  const _UpdateButtonGlyph({required this.label});

  /// 更新鈕的文字標籤。
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = DefaultTextStyle.of(context).style.fontSize ?? 14;
    final fontSize = MediaQuery.textScalerOf(context).scale(base);
    final icon = Icon(
      Icons.refresh,
      size: fontSize * 1.1,
      color: scheme.onPrimary,
    );
    final Widget glyph;
    if (isCompactLayout(context)) {
      glyph = DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.primary,
          shape: BoxShape.circle,
        ),
        child: Padding(padding: EdgeInsets.all(fontSize * 0.25), child: icon),
      );
    } else {
      glyph = DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(fontSize),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: fontSize * 0.7,
            vertical: fontSize * 0.25,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              SizedBox(width: fontSize * 0.4),
              Text(
                label,
                style: TextStyle(
                  fontSize: base,
                  fontWeight: FontWeight.w600,
                  color: scheme.onPrimary,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Semantics(label: label, excludeSemantics: true, child: glyph);
  }
}
