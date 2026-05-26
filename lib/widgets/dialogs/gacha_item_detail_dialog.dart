import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';

/// 頌願卡池 gachaType 集合 — 永遠不可點。
const _odesGachaTypes = {'2000', '1000'};

/// 判斷 [record] 是否在 dialog 內有東西可顯示。可點性放寬為「icon 檔在即可」
/// — gallery 可能因為武器頁等 entry 沒有 `gallery_character` module 而為空，
/// 此時 dialog 仍會顯示 icon 大圖（chip 列只有 Icon 一個項目，自動隱藏 chip 列）。
bool hasHoYoWikiContent(WidgetRef ref, GachaRecord record) {
  if (_odesGachaTypes.contains(record.gachaType)) return false;
  final index = ref.watch(hoyowikiIndexProvider);
  final id = index.lookupId(name: record.name, lang: record.lang);
  if (id == null) return false;
  final entry = index.lookupEntry(id);
  if (entry == null) return false;
  if (entry.iconUrl.isEmpty) return false;
  final cacheDir = ref.watch(hoyowikiCacheDirProvider);
  return hoyowikiIconCacheFile(
    baseDir: cacheDir,
    id: id,
    url: entry.iconUrl,
  ).existsSync();
}

/// 物品 dialog — title 為 icon + 名稱；content 為頂部 chip 列 +
/// 中央 gallery 圖（含 GIF）+ 下方 imgDesc HTML 描述。
class GachaItemDetailDialog extends ConsumerStatefulWidget {
  /// 建立 [GachaItemDetailDialog]。
  const GachaItemDetailDialog({super.key, required this.record});

  /// 要顯示的卡池 record。
  final GachaRecord record;

  @override
  ConsumerState<GachaItemDetailDialog> createState() =>
      _GachaItemDetailDialogState();
}

/// [GachaItemDetailDialog] 的 state：維護 chip 列當前選中索引。
class _GachaItemDetailDialogState extends ConsumerState<GachaItemDetailDialog> {
  /// 當前選中 chip 的 index；點 chip 時 setState 更新；超出範圍由 `clampedIndex` 收斂。
  int _selectedIndex = 0;

  /// 已排程預載的圖檔路徑；避免每次 setState 重新呼叫 precacheImage。
  final Set<String> _precachedPaths = {};

  /// 將 chip 對應圖預載入 ImageCache，讓首次顯示與切 chip 不必等 codec async
  /// decode（這是「第一次讀圖會閃一下」的根因）。
  void _precacheChipImages(
    BuildContext context,
    List<_GalleryChipEntry> entries,
  ) {
    for (final e in entries) {
      if (_precachedPaths.add(e.file.path)) {
        precacheImage(FileImage(e.file), context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final record = widget.record;

    final index = ref.watch(hoyowikiIndexProvider);
    final cacheDir = ref.watch(hoyowikiCacheDirProvider);
    final id = index.lookupId(name: record.name, lang: record.lang);
    final entry = id == null ? null : index.lookupEntry(id);
    final page = entry?.pageByLang[record.lang];
    final gallery = page?.gallery;
    final desc = page?.desc ?? '';
    final tags = page?.tags ?? const <String>[];

    File? iconFile;
    if (id != null && entry != null && entry.iconUrl.isNotEmpty) {
      final f = hoyowikiIconCacheFile(
        baseDir: cacheDir,
        id: id,
        url: entry.iconUrl,
      );
      if (f.existsSync()) iconFile = f;
    }

    // chip 順序：gallery list → pic 卡片 → Icon。各 chip 只有 cache 檔存在才加。
    // Icon chip 永遠最後一個（hasHoYoWikiContent 已保證 icon 存在；此處仍 defensively check）。
    final chipEntries = <_GalleryChipEntry>[];
    if (id != null) {
      if (gallery != null) {
        for (final it in gallery.list) {
          final f = hoyowikiGalleryCacheFile(
            baseDir: cacheDir,
            id: id,
            url: it.imgUrl,
          );
          if (f.existsSync()) {
            chipEntries.add(
              _GalleryChipEntry(
                label: it.key,
                file: f,
                descHtml: it.imgDescHtml,
              ),
            );
          }
        }
        if (gallery.picUrl.isNotEmpty) {
          final f = hoyowikiGalleryCacheFile(
            baseDir: cacheDir,
            id: id,
            url: gallery.picUrl,
          );
          if (f.existsSync()) {
            chipEntries.add(
              _GalleryChipEntry(
                label: l.galleryCardLabel,
                file: f,
                descHtml: '',
              ),
            );
          }
        }
      }
      if (iconFile != null) {
        chipEntries.add(
          _GalleryChipEntry(
            label: l.galleryIconLabel,
            file: iconFile,
            descHtml: '',
          ),
        );
      }
    }

    final clampedIndex = chipEntries.isEmpty
        ? -1
        : _selectedIndex.clamp(0, chipEntries.length - 1);
    final current = clampedIndex >= 0 ? chipEntries[clampedIndex] : null;
    final currentFile = current?.file;

    // 排程所有 chip 圖預載；ImageCache 已 dedupe + 我們也記 _precachedPaths
    // 雙保險避免重排。post-frame 是避開 build 內直接 schedule async 的 lint。
    if (chipEntries.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _precacheChipImages(context, chipEntries);
      });
    }

    final nameColor = switch (record.rankType) {
      5 => tokens.fiveStar,
      4 => tokens.fourStar,
      _ => tokens.textPrimary,
    };

    return AppDialog(
      size: AppDialogSize.md,
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (iconFile != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Image.file(
                iconFile,
                width: 64,
                height: 64,
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.name,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: nameColor,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (desc.trim().isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 120),
                    child: SingleChildScrollView(
                      child: Html(
                        data: desc,
                        style: {
                          'body': Style(
                            fontSize: FontSize(
                              theme.textTheme.bodyMedium?.fontSize ?? 14,
                            ),
                            color: tokens.textSecondary,
                            margin: Margins.zero,
                            padding: HtmlPaddings.zero,
                          ),
                          'p': Style(margin: Margins.zero),
                        },
                      ),
                    ),
                  ),
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final t in tags)
                        Chip(
                          label: Text(t),
                          // 用 textPrimary 加 alpha 做半透明色塊：dark 主題
                          // 疊出比表面亮一階的灰、light 主題疊出比表面暗一
                          // 階的灰，兩個情境下都自動跟 dialog 背景拉開層次。
                          // 0.15 alpha 經對比測試在兩主題下都有明確色塊感。
                          backgroundColor: tokens.textPrimary.withValues(
                            alpha: 0.15,
                          ),
                          side: BorderSide.none,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.all(
                              Radius.circular(AppRadius.sm),
                            ),
                          ),
                          labelStyle: theme.textTheme.bodySmall?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s,
                          ),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (chipEntries.length > 1)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < chipEntries.length; i++)
                  ChoiceChip(
                    label: Text(chipEntries[i].label),
                    selected: i == clampedIndex,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _selectedIndex = i),
                  ),
              ],
            ),
          if (chipEntries.length > 1) const SizedBox(height: 12),
          if (currentFile != null)
            Flexible(
              fit: FlexFit.loose,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Image.file(
                  currentFile,
                  key: ValueKey(currentFile.path),
                  fit: BoxFit.contain,
                  alignment: Alignment.topCenter,
                  // 切 chip / 同圖重 build 時保留前一張 frame，等新 frame
                  // 解碼完才換；配合 precacheImage 消除「閃一下」。
                  gaplessPlayback: true,
                  errorBuilder: (_, e, st) {
                    Logger('gacha.hoyowiki.detail').warning(
                      'gallery image errorBuilder id=$id path=${currentFile.path}',
                      e,
                      st,
                    );
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          if (current != null && current.descHtml.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(child: Html(data: current.descHtml)),
            ),
          ],
        ],
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.open_in_new, size: 18),
          label: Text(l.actionViewOnHoYoWiki),
          onPressed: id == null
              ? null
              : () {
                  Logger('gacha.hoyowiki.detail').info('open wiki id=$id');
                  openExternalUrl(
                    Uri.parse('https://wiki.hoyolab.com/pc/genshin/entry/$id'),
                  );
                },
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.actionClose),
        ),
      ],
    );
  }
}

/// 內部：單一 chip 條目（chip 標籤 + pre-resolved 本地圖檔 + 描述 HTML）。
class _GalleryChipEntry {
  /// 建立 [_GalleryChipEntry]。
  const _GalleryChipEntry({
    required this.label,
    required this.file,
    required this.descHtml,
  });

  /// chip 顯示的文字（list[i].key、galleryCardLabel 或 galleryIconLabel）。
  final String label;

  /// 該 chip 對應的本地 cache 檔（icon 走 hoyowikiIconCacheFile、其餘走 gallery hash）；
  /// 在 build 時就 resolve 並 existsSync 過濾，所以此處保證實體存在。
  final File file;

  /// 描述 HTML；trim 後為空則不繪描述區（pic / icon 均為空）。
  final String descHtml;
}

/// 顯示 [GachaItemDetailDialog]。
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

/// 把任意 [child] 包成可點區塊；[hasHoYoWikiContent] 為 false 時 passthrough。
class GachaItemTapTarget extends ConsumerWidget {
  /// 建立 [GachaItemTapTarget]。
  const GachaItemTapTarget({
    super.key,
    required this.record,
    required this.child,
  });

  /// 對應 record。
  final GachaRecord record;

  /// 子 widget。
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!hasHoYoWikiContent(ref, record)) return child;
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
