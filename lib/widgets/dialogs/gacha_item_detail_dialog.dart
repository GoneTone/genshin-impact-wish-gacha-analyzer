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
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';

/// 頌願卡池 gachaType 集合 — 永遠不可點。
const _odesGachaTypes = {'2000', '1000'};

/// 判斷 [record] 是否在 dialog 內有東西可顯示。需 icon 檔到位且
/// `record.lang` 的 gallery 有任一張 cache 檔到位。
bool hasHoYoWikiContent(WidgetRef ref, GachaRecord record) {
  if (_odesGachaTypes.contains(record.gachaType)) return false;
  final index = ref.watch(hoyowikiIndexProvider);
  final id = index.lookupId(name: record.name, lang: record.lang);
  if (id == null) return false;
  final entry = index.lookupEntry(id);
  if (entry == null) return false;
  final cacheDir = ref.watch(hoyowikiCacheDirProvider);

  if (entry.iconUrl.isEmpty) return false;
  if (!hoyowikiIconCacheFile(
    baseDir: cacheDir,
    id: id,
    url: entry.iconUrl,
  ).existsSync()) {
    return false;
  }

  final gallery = entry.galleryByLang[record.lang];
  if (gallery == null) return false;

  bool ready(String url) =>
      url.isNotEmpty &&
      hoyowikiGalleryCacheFile(
        baseDir: cacheDir,
        id: id,
        url: url,
      ).existsSync();

  if (ready(gallery.picUrl)) return true;
  return gallery.list.any((it) => ready(it.imgUrl));
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

class _GachaItemDetailDialogState extends ConsumerState<GachaItemDetailDialog> {
  int _selectedIndex = 0;

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
    final gallery = entry?.galleryByLang[record.lang];

    File? iconFile;
    if (id != null && entry != null && entry.iconUrl.isNotEmpty) {
      final f = hoyowikiIconCacheFile(
        baseDir: cacheDir,
        id: id,
        url: entry.iconUrl,
      );
      if (f.existsSync()) iconFile = f;
    }

    // chip 順序：list 全部 + pic（最後）
    final chipEntries = <_GalleryChipEntry>[];
    if (gallery != null) {
      for (final it in gallery.list) {
        chipEntries.add(
          _GalleryChipEntry(
            label: it.key,
            url: it.imgUrl,
            descHtml: it.imgDescHtml,
          ),
        );
      }
      if (gallery.picUrl.isNotEmpty) {
        chipEntries.add(
          _GalleryChipEntry(
            label: l.galleryCardLabel,
            url: gallery.picUrl,
            descHtml: '',
          ),
        );
      }
    }

    final clampedIndex = chipEntries.isEmpty
        ? -1
        : _selectedIndex.clamp(0, chipEntries.length - 1);
    final current = clampedIndex >= 0 ? chipEntries[clampedIndex] : null;

    File? currentFile;
    if (id != null && current != null) {
      final f = hoyowikiGalleryCacheFile(
        baseDir: cacheDir,
        id: id,
        url: current.url,
      );
      if (f.existsSync()) currentFile = f;
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
          if (chipEntries.length > 1)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < chipEntries.length; i++)
                  ChoiceChip(
                    label: Text(chipEntries[i].label),
                    selected: i == clampedIndex,
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
                  errorBuilder: (_, e, st) {
                    Logger('gacha.hoyowiki.detail').warning(
                      'gallery image errorBuilder id=$id url=${current?.url}',
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
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.actionClose),
        ),
      ],
    );
  }
}

/// 內部：單一 chip 條目（chip 標籤 + 對應圖片 URL + 描述 HTML）。
class _GalleryChipEntry {
  /// 建立 [_GalleryChipEntry]。
  const _GalleryChipEntry({
    required this.label,
    required this.url,
    required this.descHtml,
  });

  /// chip 顯示的文字（list[i].key 或 app i18n galleryCardLabel）。
  final String label;

  /// 對應圖片 URL（用於推導 cache file path）。
  final String url;

  /// 描述 HTML；trim 後為空則不繪描述區。
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
