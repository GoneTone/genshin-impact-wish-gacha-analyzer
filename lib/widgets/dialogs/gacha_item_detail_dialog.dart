import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';

/// 頌願卡池 gachaType 集合 — 永遠不可點（對應 GachaItemIcon 內 _odesGachaTypes）。
const _odesGachaTypes = {'2000', '1000'};

/// 判斷 [record] 是否在 dialog 內有東西可顯示（至少有 icon 或 header 任一個
/// HoyoWiki 圖片快取到本機）。頌願卡池一律 false。
bool hasHoyoWikiContent(WidgetRef ref, GachaRecord record) {
  if (_odesGachaTypes.contains(record.gachaType)) return false;
  final index = ref.watch(hoyowikiIndexProvider);
  final id = index.lookupId(name: record.name, lang: record.lang);
  if (id == null) return false;
  final entry = index.lookupEntry(id);
  if (entry == null) return false;
  final cacheDir = ref.watch(hoyowikiCacheDirProvider);

  bool fileReady(String url, HoyoWikiImageKind kind) =>
      url.isNotEmpty &&
      hoyowikiCacheFile(
        baseDir: cacheDir,
        id: id,
        kind: kind,
        url: url,
      ).existsSync();

  return fileReady(entry.iconUrl, HoyoWikiImageKind.icon) ||
      fileReady(entry.headerImgUrl, HoyoWikiImageKind.header);
}

/// 點擊物品 icon / 名稱時彈出的 dialog；顯示 icon + 名稱（top）+ HoyoWiki
/// header 大圖（bottom）。缺哪個就不顯示哪個；`AppDialogSize.md` 寬度，
/// header 用 `Flexible + BoxFit.contain` 吃剩餘高度，保證不撐爆視窗。
class GachaItemDetailDialog extends ConsumerWidget {
  /// 建立 [GachaItemDetailDialog]。
  const GachaItemDetailDialog({super.key, required this.record});

  /// 要顯示的卡池 record。
  final GachaRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tokens = theme.gacha;

    final index = ref.watch(hoyowikiIndexProvider);
    final cacheDir = ref.watch(hoyowikiCacheDirProvider);
    final id = index.lookupId(name: record.name, lang: record.lang);
    final entry = id == null ? null : index.lookupEntry(id);

    File? iconFile;
    File? headerFile;
    if (id != null && entry != null) {
      if (entry.iconUrl.isNotEmpty) {
        final f = hoyowikiCacheFile(
          baseDir: cacheDir,
          id: id,
          kind: HoyoWikiImageKind.icon,
          url: entry.iconUrl,
        );
        if (f.existsSync()) iconFile = f;
      }
      if (entry.headerImgUrl.isNotEmpty) {
        final f = hoyowikiCacheFile(
          baseDir: cacheDir,
          id: id,
          kind: HoyoWikiImageKind.header,
          url: entry.headerImgUrl,
        );
        if (f.existsSync()) headerFile = f;
      }
    }

    final nameColor = switch (record.rankType) {
      5 => tokens.fiveStar,
      4 => tokens.fourStar,
      _ => tokens.textPrimary,
    };

    return AppDialog(
      size: AppDialogSize.md,
      title: Row(
        children: [
          if (iconFile != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Image.file(
                iconFile,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, e, st) {
                  Logger(
                    'gacha.hoyowiki.detail',
                  ).warning('icon errorBuilder id=$id', e, st);
                  return const SizedBox.shrink();
                },
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              record.name,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: nameColor,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (headerFile != null)
            Flexible(
              fit: FlexFit.loose,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Image.file(
                  headerFile,
                  fit: BoxFit.contain,
                  alignment: Alignment.topCenter,
                  errorBuilder: (_, e, st) {
                    Logger(
                      'gacha.hoyowiki.detail',
                    ).warning('header errorBuilder id=$id', e, st);
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.actionClose),
        ),
      ],
    );
  }
}

/// 顯示 [GachaItemDetailDialog]。集中 log 與 [showDialog] 呼叫。
Future<void> showGachaItemDetailDialog(
  BuildContext context,
  GachaRecord record,
) {
  Logger('gacha.hoyowiki.detail').info(
    'open name=${record.name} lang=${record.lang} rank=${record.rankType}',
  );
  return showDialog<void>(
    context: context,
    builder: (_) => GachaItemDetailDialog(record: record),
  );
}

/// 把任意 [child]（通常是 icon + 名稱 Row/Column）包成可點區塊；
/// [hasHoyoWikiContent] 為 false 時 passthrough，不加任何 hit affordance。
class GachaItemTapTarget extends ConsumerWidget {
  /// 建立 [GachaItemTapTarget]。
  const GachaItemTapTarget({
    super.key,
    required this.record,
    required this.child,
  });

  /// 對應的卡池 record；由 [hasHoyoWikiContent] 判定可點性。
  final GachaRecord record;

  /// 被包裝的子 widget（icon + 名稱組合）。
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!hasHoyoWikiContent(ref, record)) return child;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showGachaItemDetailDialog(context, record),
        child: child,
      ),
    );
  }
}
