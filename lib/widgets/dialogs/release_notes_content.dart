import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/app_release_checker.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/utils/github_release_linkify.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/relative_time_text.dart';

/// 單一 release 的內容卡片：版本標題 + 發布時間 + Markdown body。
/// 由 `NewVersionDialog` 與 `CurrentReleaseDialog` 共用。
class ReleaseNotesContent extends StatelessWidget {
  /// 建立 [ReleaseNotesContent]。
  const ReleaseNotesContent({super.key, required this.release});

  /// 要呈現的 release 資料。
  final AppRelease release;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tokens = theme.gacha;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  release.tagName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                RelativeTimeText(
                  time: release.publishedAt,
                  templateBuilder: l.updateReleasedAt,
                  useDateOnly: true,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s),
            Divider(height: 1, color: tokens.borderSubtle),
            const SizedBox(height: AppSpacing.s),
            if (release.body.isNotEmpty)
              MarkdownBlock(
                data: linkifyGithubReferences(release.body),
                config: releaseNotesMarkdownConfig(theme),
                generator: releaseNotesMarkdownGenerator(),
              ),
          ],
        ),
      ),
    );
  }
}

/// 依 [theme] 亮暗模式建立 markdown 渲染設定，統一連結樣式。
MarkdownConfig releaseNotesMarkdownConfig(ThemeData theme) {
  final base = theme.brightness == Brightness.dark
      ? MarkdownConfig.darkConfig
      : MarkdownConfig.defaultConfig;
  return base.copy(
    configs: [LinkConfig(style: TextStyle(color: linkBaseColor(theme)))],
  );
}

/// 建立 release notes 專用的 Markdown generator，覆寫連結節點為 [_ReleaseLinkNode]。
///
/// markdown_widget 內建的 `LinkNode` 會在每個連結尾端硬塞一個空白 `TextSpan`
/// （其原始碼註解標為待 Flutter 修正的 workaround），導致連結後緊接文字時多
/// 一個空格（例 `@GoneTone  in`）。改用 [_ReleaseLinkNode] 移除該尾端空白，
/// 讓顯示與 GitHub 一致。
MarkdownGenerator releaseNotesMarkdownGenerator() => MarkdownGenerator(
  generators: [
    SpanNodeGeneratorWithTag(
      tag: MarkdownTag.a.name,
      generator: (e, config, visitor) =>
          _ReleaseLinkNode(e.attributes, config.a),
    ),
  ],
);

/// 與內建 `LinkNode` 行為相同，但移除其在連結尾端附加的多餘空白 `TextSpan`。
///
/// 透過 `super.build()` 重用上游的點擊與樣式邏輯，僅在結果為「最後一個 child
/// 是純空白 `TextSpan`」時剝掉它；若上游日後移除該 workaround，最後一個 child
/// 不再是空白，便自動 no-op，不會把連結與後文黏在一起。
class _ReleaseLinkNode extends LinkNode {
  /// 建立 [_ReleaseLinkNode]。
  _ReleaseLinkNode(super.attributes, super.linkConfig);

  @override
  InlineSpan build() {
    final span = super.build();
    if (span is! TextSpan) return span;
    final children = span.children;
    if (children == null || children.isEmpty) return span;
    final last = children.last;
    final hasTrailingSpace =
        last is TextSpan && last.text == ' ' && last.children == null;
    if (!hasTrailingSpace) return span;
    return TextSpan(
      text: span.text,
      style: span.style,
      recognizer: span.recognizer,
      children: children.sublist(0, children.length - 1),
    );
  }
}
