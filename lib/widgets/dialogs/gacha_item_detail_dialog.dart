import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/image_clipboard_save.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_cache_usage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_link.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/app_html.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/app_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/dialog_toast.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/gallery_chip_bar.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/zoomable_image_overlay.dart';

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

/// [GachaItemDetailDialog] 的 state：維護 chip 列當前選中索引與 lazy 下載狀態。
class _GachaItemDetailDialogState extends ConsumerState<GachaItemDetailDialog> {
  /// 當前選中 chip 的 index；點 chip 時 setState 更新；超出範圍由 `clampedIndex` 收斂。
  int _selectedIndex = 0;

  /// 已排程 precacheImage 的本地圖檔路徑；避免每次 setState 重新呼叫。
  final Set<String> _precachedPaths = {};

  /// 是否已有 precache 排程於下一個 frame；避免每次 setState 重排相同 callback。
  bool _precacheScheduled = false;

  /// 每張 gallery 圖的下載／載入狀態，key 為「該圖的本地 cache 檔絕對路徑」。
  /// 同 URL 撞同 hash → 自然共用同一 entry，跨 chip 自然 dedup。
  final Map<String, _GalleryLoadState> _loadStates = {};

  /// initState 後使用的 http client（dispose 時 close 中斷 in-flight 請求）。
  late final http.Client _client;

  /// 該 dialog 的 logger。
  static final _log = Logger('gacha.hoyowiki.detail');

  @override
  void initState() {
    super.initState();
    _client = http.Client();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  /// 對 [url] 做 lazy 下載；成功寫入 cache 並 setState 為 [_GalleryReady]；
  /// 失敗 setState 為 [_GalleryFailed]。重複呼叫（例如重試）安全。
  Future<void> _fetchAndCache({
    required String id,
    required String url,
    required File file,
  }) async {
    final fetcher = ref.read(hoyowikiFetcherProvider);
    try {
      final bytes = await fetcher.downloadImage(url, _client);
      if (bytes == null) {
        if (!mounted) return;
        setState(() {
          _loadStates[file.path] = _GalleryFailed(
            const FormatException('downloadImage returned null'),
          );
        });
        _log.warning('lazy fetch returned null id=$id url=${sanitizeUrl(url)}');
        return;
      }
      await writeHoYoWikiCacheImage(file: file, bytes: bytes);
      if (!mounted) return;
      setState(() {
        _loadStates[file.path] = _GalleryReady(file);
      });
      ref.invalidate(hoyowikiCacheUsageProvider);
      _log.info(
        'lazy fetch ok id=$id bytes=${bytes.length} '
        'path=${sanitizeFsPath(file.path)}',
      );
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _loadStates[file.path] = _GalleryFailed(e);
      });
      _log.warning('lazy fetch failed id=$id url=${sanitizeUrl(url)}', e, st);
    }
  }

  /// 只 precache [_GalleryReady] 的圖檔；未下載完的 chip 略過。
  void _precacheChipImages(
    BuildContext context,
    List<_GalleryChipEntry> entries,
  ) {
    for (final e in entries) {
      final st = _loadStates[e.file.path];
      if (st is! _GalleryReady) continue;
      if (_precachedPaths.add(e.file.path)) {
        precacheImage(FileImage(e.file), context);
      }
    }
  }

  /// 重抓某 chip 的圖：先 evict 既有 ImageCache、切回 loading，再依類別重抓。
  ///
  /// 路徑不變的重抓必須 evict，否則 ready 圖重建後仍讀到舊快取。
  /// 同時供失敗狀態的「重試」按鈕與圖片選單的「重抓圖片」共用。
  void _refetchEntry(_GalleryChipEntry e) {
    PaintingBinding.instance.imageCache.evict(FileImage(e.file));
    _precachedPaths.remove(e.file.path);
    setState(() => _loadStates[e.file.path] = const _GalleryLoading());
    switch (e.kind) {
      case _ChipKind.galleryList:
      case _ChipKind.galleryPic:
        unawaited(
          _fetchAndCache(
            id: _extractIdFromPath(e.file.path) ?? '',
            url: e.url,
            file: e.file,
          ),
        );
      case _ChipKind.icon:
        unawaited(_refetchIcon(url: e.url, file: e.file));
    }
  }

  /// 重抓 icon：重新下載 [url] 覆蓋 [file]，成功後 evict + bumpCacheRevision，
  /// 讓 dialog 標題縮圖與記錄列表 [GachaItemIcon] 同步顯示新 icon。
  ///
  /// 失敗時保留磁碟既有 icon（writeHoYoWikiCacheImage 失敗不覆寫），
  /// chip 狀態轉 failed（沿用既有失敗 UI 的重試按鈕）。
  Future<void> _refetchIcon({required String url, required File file}) async {
    final fetcher = ref.read(hoyowikiFetcherProvider);
    try {
      final bytes = await fetcher.downloadImage(url, _client);
      if (bytes == null) {
        if (!mounted) return;
        setState(() {
          _loadStates[file.path] = _GalleryFailed(
            const FormatException('downloadImage returned null'),
          );
        });
        _log.warning('icon refetch null url=${sanitizeUrl(url)}');
        return;
      }
      await writeHoYoWikiCacheImage(file: file, bytes: bytes);
      if (!mounted) return;
      PaintingBinding.instance.imageCache.evict(FileImage(file));
      setState(() => _loadStates[file.path] = _GalleryReady(file));
      ref.read(hoyowikiIndexProvider.notifier).bumpCacheRevision();
      ref.invalidate(hoyowikiCacheUsageProvider);
      _log.info(
        'icon refetch ok bytes=${bytes.length} '
        'path=${sanitizeFsPath(file.path)}',
      );
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _loadStates[file.path] = _GalleryFailed(e));
      _log.warning('icon refetch failed url=${sanitizeUrl(url)}', e, st);
    }
  }

  /// 圖片選單項目（複製圖片 / 儲存圖片 / --- / 重抓圖片）；右上角按鈕與右鍵選單共用。
  List<PopupMenuEntry<String>> _imageMenuItems(AppLocalizations l) => [
    PopupMenuItem(
      value: 'copy',
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.copy, size: 20),
        title: Text(l.actionCopyImage),
      ),
    ),
    PopupMenuItem(
      value: 'save',
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.save_alt, size: 20),
        title: Text(l.actionSaveImage),
      ),
    ),
    const PopupMenuDivider(),
    PopupMenuItem(
      value: 'refetch',
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.refresh, size: 20),
        title: Text(l.actionRefetchImage),
      ),
    ),
  ];

  /// 分派圖片選單選擇（按鈕與右鍵選單共用）：複製 / 儲存 / 重抓。
  void _onImageMenuSelected(String value, _GalleryChipEntry current) {
    switch (value) {
      case 'copy':
        unawaited(_copyImage(current));
      case 'save':
        unawaited(_saveImage(current));
      case 'refetch':
        _refetchEntry(current);
    }
  }

  /// 圖片區右上角的溢出選單按鈕：複製圖片 / 儲存圖片 / --- / 重抓圖片。
  /// 沿用 lightbox X 鈕的半透明黑底圓鈕視覺；僅在圖片 ready 時疊在圖上顯示。
  Widget _buildImageMenu(BuildContext context, _GalleryChipEntry current) {
    final l = AppLocalizations.of(context)!;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.black.withValues(alpha: 0.4),
        shape: const CircleBorder(),
        child: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          tooltip: '',
          onSelected: (value) => _onImageMenuSelected(value, current),
          itemBuilder: (_) => _imageMenuItems(l),
        ),
      ),
    );
  }

  /// 右鍵在圖片上叫出與右上角按鈕相同的選單，位置跟著游標。
  Future<void> _showImageContextMenu(
    BuildContext context,
    Offset globalPosition,
    _GalleryChipEntry current,
  ) async {
    final l = AppLocalizations.of(context)!;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: _imageMenuItems(l),
    );
    if (selected == null || !mounted) return;
    _onImageMenuSelected(selected, current);
  }

  /// 把 record 名稱與 chip 標籤組成存檔建議檔名（不含副檔名），並去掉非法字元。
  /// 副檔名由 [saveImageFile] 依實際格式（gif／png）補上。
  String _suggestedBaseName(_GalleryChipEntry e) {
    final raw = '${widget.record.name}_${e.label}';
    // Windows 檔名非法字元（< > : " / \ | ? *）一律換 _，避免存檔對話框拒絕。
    return raw.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }

  /// 複製目前圖片到剪貼簿（GIF 保留原始、其餘轉 PNG），結果以 toast 回報。
  Future<void> _copyImage(_GalleryChipEntry e) async {
    final l = AppLocalizations.of(context)!;
    final ok = await copyImageFileToClipboard(e.file);
    if (!mounted) return;
    _showSnack(ok ? l.imageCopied : l.imageCopyFailed);
  }

  /// 儲存目前圖片（GIF 存成 .gif 保留動畫、其餘轉 PNG）→ 系統存檔對話框，
  /// 結果以 toast 回報。使用者取消不提示；準備／寫檔失敗提示失敗。
  Future<void> _saveImage(_GalleryChipEntry e) async {
    final l = AppLocalizations.of(context)!;
    try {
      final savedPath = await saveImageFile(
        e.file,
        suggestedBaseName: _suggestedBaseName(e),
      );
      if (!mounted || savedPath == null) return;
      _showSnack(l.imageSavedTo(savedPath));
    } catch (_) {
      if (!mounted) return;
      _showSnack(l.imageSaveFailed);
    }
  }

  /// 以 toast 顯示 [message]。用 [showDialogToast]（疊在 dialog 之上的 overlay）
  /// 而非 SnackBar — SnackBar 由 app 層級 Scaffold 繪製，會被 dialog 的 modal
  /// barrier 蓋住。
  void _showSnack(String message) {
    if (!mounted) return;
    showDialogToast(context, message);
  }

  /// 依當前 chip 的 [_GalleryLoadState] 顯示對應內容：
  ///   - Ready → Image.file（可點開縮放）
  ///   - Loading → CircularProgressIndicator
  ///   - Failed → Icon + 重試按鈕
  Widget _buildCurrentImageArea(
    BuildContext context,
    _GalleryChipEntry current,
  ) {
    final theme = Theme.of(context);
    final tokens = theme.gacha;
    final l = AppLocalizations.of(context)!;
    final state = _loadStates[current.file.path] ?? const _GalleryLoading();
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: switch (state) {
        _GalleryReady(:final file) => Stack(
          children: [
            Positioned.fill(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    _log.info('open zoom path=${sanitizeFsPath(file.path)}');
                    showZoomableImageOverlay(
                      context,
                      imageFile: file,
                      suggestedBaseName: _suggestedBaseName(current),
                    );
                  },
                  onSecondaryTapDown: (details) => unawaited(
                    _showImageContextMenu(
                      context,
                      details.globalPosition,
                      current,
                    ),
                  ),
                  child: Image.file(
                    file,
                    key: ValueKey(file.path),
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                    // 切 chip / 同圖重 build 時保留前一張 frame，等新 frame
                    // 解碼完才換；配合 precacheImage 消除「閃一下」。
                    gaplessPlayback: true,
                    errorBuilder: (_, e, st) {
                      _log.warning(
                        'gallery image errorBuilder '
                        'path=${sanitizeFsPath(file.path)}',
                        e,
                        st,
                      );
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
            ),
            Positioned(
              top: AppSpacing.s,
              right: AppSpacing.s,
              child: _buildImageMenu(context, current),
            ),
          ],
        ),
        _GalleryLoading() => Center(
          child: SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: tokens.textSecondary,
            ),
          ),
        ),
        _GalleryFailed() => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.broken_image_outlined,
                size: 48,
                color: tokens.textMuted,
              ),
              const SizedBox(height: AppSpacing.s),
              Text(
                l.galleryLazyLoadFailed,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.s),
              TextButton.icon(
                onPressed: () => _refetchEntry(current),
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(l.actionRetry),
              ),
            ],
          ),
        ),
      },
    );
  }

  /// 從 cache 檔路徑反推 hoyowiki id（僅用於 retry log 標籤，失敗回 null）。
  /// 路徑樣式：`.../<id>_gallery_<hash>.<ext>` 或 `.../<id>_icon.<ext>`。
  String? _extractIdFromPath(String path) {
    final base = path.split(Platform.pathSeparator).last;
    final underscoreIdx = base.indexOf('_');
    if (underscoreIdx <= 0) return null;
    return base.substring(0, underscoreIdx);
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

    // chip 順序：gallery list → pic 卡片 → Icon。Icon chip 永遠最後一個。
    final chipEntries = <_GalleryChipEntry>[];
    if (id != null) {
      if (gallery != null) {
        for (final it in gallery.list) {
          if (it.imgUrl.isEmpty) continue;
          final f = hoyowikiGalleryCacheFile(
            baseDir: cacheDir,
            id: id,
            url: it.imgUrl,
          );
          chipEntries.add(
            _GalleryChipEntry(
              label: it.key,
              url: it.imgUrl,
              file: f,
              descHtml: it.imgDescHtml,
              kind: _ChipKind.galleryList,
            ),
          );
        }
        if (gallery.picUrl.isNotEmpty) {
          final f = hoyowikiGalleryCacheFile(
            baseDir: cacheDir,
            id: id,
            url: gallery.picUrl,
          );
          chipEntries.add(
            _GalleryChipEntry(
              label: l.galleryCardLabel,
              url: gallery.picUrl,
              file: f,
              descHtml: '',
              kind: _ChipKind.galleryPic,
            ),
          );
        }
      }
      if (iconFile != null) {
        chipEntries.add(
          _GalleryChipEntry(
            label: l.galleryIconLabel,
            url: entry?.iconUrl ?? '',
            file: iconFile,
            descHtml: '',
            kind: _ChipKind.icon,
          ),
        );
      }
    }

    // 同步 _loadStates：首次出現的 gallery chip 若本地已有檔 → _GalleryReady；
    // 否則 → _GalleryLoading 並觸發背景下載。Icon chip 永遠 _GalleryReady。
    for (final ce in chipEntries) {
      if (_loadStates.containsKey(ce.file.path)) continue;
      switch (ce.kind) {
        case _ChipKind.icon:
          _loadStates[ce.file.path] = _GalleryReady(ce.file);
        case _ChipKind.galleryList:
        case _ChipKind.galleryPic:
          if (ce.file.existsSync()) {
            _loadStates[ce.file.path] = _GalleryReady(ce.file);
          } else {
            _loadStates[ce.file.path] = const _GalleryLoading();
            final theId = id!;
            final theUrl = ce.url;
            final theFile = ce.file;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              unawaited(_fetchAndCache(id: theId, url: theUrl, file: theFile));
            });
          }
      }
    }

    final clampedIndex = chipEntries.isEmpty
        ? -1
        : _selectedIndex.clamp(0, chipEntries.length - 1);
    final current = clampedIndex >= 0 ? chipEntries[clampedIndex] : null;

    // 排程所有已就緒 chip 圖預載；post-frame 是避開 build 內直接 schedule async 的 lint。
    // 以 _precacheScheduled flag 確保每個 frame 最多只排一次，避免每次 setState 累積 callback。
    if (chipEntries.isNotEmpty && !_precacheScheduled) {
      _precacheScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _precacheScheduled = false;
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
      // 物品 dialog 含大圖預覽，需要更高空間；AppDialog 仍會 fit 小視窗。
      maxHeight: 880,
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
                  _log.warning('icon errorBuilder id=$id', e, st);
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
                if (desc.trim().isNotEmpty) ...[
                  // 名稱與說明之間的固定間距，讓單行/多行說明都有一致的呼吸空間。
                  // 用 2px 微距（小於最小 token AppSpacing.xs=4），名稱與說明貼得更近。
                  const SizedBox(height: 2),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 120),
                    child: SingleChildScrollView(
                      // 壓低環境 DefaultTextStyle 的行高：flutter_html 以繼承的環境
                      // 行高當作區塊最小高度，dialog title 的環境行高偏高（約 31px），
                      // 使「單行說明」被在偏高行框內垂直置中、首行比「多行說明」下移
                      // 約 6px。壓成 1.0 後區塊最小高度＝文字行高，單行/多行首行對齊。
                      child: DefaultTextStyle.merge(
                        style: const TextStyle(height: 1.0),
                        child: AppHtml(
                          data: desc,
                          style: {
                            'body': Style(
                              fontSize: FontSize(
                                theme.textTheme.bodyMedium?.fontSize ?? 14,
                              ),
                              lineHeight: LineHeight.number(1.2),
                              color: tokens.textSecondary,
                              margin: Margins.zero,
                              padding: HtmlPaddings.zero,
                            ),
                            'p': Style(margin: Margins.zero),
                          },
                        ),
                      ),
                    ),
                  ),
                ],
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
      // hasImage 為 true 時 Column 撐到 parent 給的 maxHeight，配合
      // Expanded(image) 吸收剩餘空間 → 切 chip 時即使 imgDesc 區 0px ↔ 105px
      // 變動，dialog 整體高度仍固定（只有 image 區大小被重新分配）。
      content: Column(
        mainAxisSize: current != null ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (chipEntries.length > 1) ...[
            GalleryChipBar(
              labels: [for (final e in chipEntries) e.label],
              selectedIndex: clampedIndex,
              onSelected: (i) => setState(() => _selectedIndex = i),
            ),
            const SizedBox(height: 12),
          ],
          if (current != null) ...[
            Expanded(child: _buildCurrentImageArea(context, current)),
          ],
          if (current != null && current.descHtml.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            // 顯式收緊段落 margin：flutter_html 預設 `<p>` 上下 1em margin，
            // 在 imgDescHtml 「<p>標題</p><p>內文</p>」結構下會有 ~25-30px
            // 空白；官方頁面只有 ~6-8px。body margin/padding 歸零避免額外間距。
            AppHtml(
              data: current.descHtml,
              style: {
                'body': Style(margin: Margins.zero, padding: HtmlPaddings.zero),
                'p': Style(margin: Margins.symmetric(vertical: 4)),
              },
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
                  _log.info('open wiki id=$id lang=${record.lang}');
                  openExternalUrl(
                    buildHoYoWikiEntryUrl(id: id, lang: record.lang),
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

/// chip 類別 — icon 永遠 ready（已由 hasHoYoWikiContent 把關），gallery 走 lazy。
enum _ChipKind {
  /// gallery list[i].imgUrl。
  galleryList,

  /// gallery picUrl。
  galleryPic,

  /// entry.iconUrl（已預下載，永遠 ready）。
  icon,
}

/// 內部：單一 chip 條目。
class _GalleryChipEntry {
  /// 建立 [_GalleryChipEntry]。
  const _GalleryChipEntry({
    required this.label,
    required this.url,
    required this.file,
    required this.descHtml,
    required this.kind,
  });

  /// chip 顯示文字。
  final String label;

  /// 該 chip 對應的遠端 URL（icon chip 為 entry.iconUrl，gallery chip 為對應 gallery URL）。
  final String url;

  /// 該 chip 對應的本地 cache 檔（可能尚未存在，由 [_GachaItemDetailDialogState._loadStates] 追蹤狀態）。
  final File file;

  /// 描述 HTML；trim 後為空則不繪描述區。
  final String descHtml;

  /// chip 類別 — icon 永遠 ready（已由 hasHoYoWikiContent 把關），gallery 走 lazy。
  final _ChipKind kind;
}

/// 組出 HoYoWiki 詞條頁網址，帶上 [lang] 讓落地頁語言對齊 Dialog 顯示的資料語言。
Uri buildHoYoWikiEntryUrl({required String id, required String lang}) =>
    Uri.parse(
      'https://wiki.hoyolab.com/pc/genshin/entry/$id',
    ).replace(queryParameters: {'lang': lang});

/// 顯示 [GachaItemDetailDialog]。
Future<void> showGachaItemDetailDialog(
  BuildContext context,
  GachaRecord record,
) {
  _log.info(
    'open name=${record.name} lang=${record.lang} rank=${record.rankType}',
  );
  return showDialog<void>(
    context: context,
    builder: (_) => GachaItemDetailDialog(record: record),
  );
}

/// module-level logger，供 [showGachaItemDetailDialog] 使用。
final _log = Logger('gacha.hoyowiki.detail');

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

/// gallery 圖檔的下載／載入狀態，由 [_GachaItemDetailDialogState._loadStates] 管理。
sealed class _GalleryLoadState {
  /// 建立 [_GalleryLoadState]。
  const _GalleryLoadState();
}

/// 下載中（initState 觸發後尚未完成，或使用者按下重試後）。
class _GalleryLoading extends _GalleryLoadState {
  /// 建立 [_GalleryLoading]。
  const _GalleryLoading();
}

/// 本地已有 cache 檔，可直接 `Image.file` 顯示。
class _GalleryReady extends _GalleryLoadState {
  /// 建立 [_GalleryReady]。
  const _GalleryReady(this.file);

  /// 對應的本地 cache 檔（已保證 existsSync）。
  final File file;
}

/// 下載失敗，UI 顯示 placeholder + 重試按鈕。
class _GalleryFailed extends _GalleryLoadState {
  /// 建立 [_GalleryFailed]。
  const _GalleryFailed(this.error);

  /// 失敗原因，用於 log；UI 不顯示。
  final Object error;
}
