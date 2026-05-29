import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/preloaded_hoyowiki_images.dart';

/// 頌願卡池（odes） gachaType 集合 — 不顯示 icon 也不顯示 placeholder。
const _odesGachaTypes = {'2000', '1000'};

/// 顯示一筆卡池物品的 icon；cache 未到 / 缺資料時顯示 [_Placeholder]。
class GachaItemIcon extends ConsumerWidget {
  /// 建立 [GachaItemIcon]。
  const GachaItemIcon({
    super.key,
    required this.record,
    required this.size,
    this.circular = false,
  });

  /// 卡池記錄；用其 name / lang / rankType / gachaType。
  final GachaRecord record;

  /// icon 邊長（px，依使用情境調整：所有宿主一律 32）。
  final double size;

  /// true 時以圓形裁切／圓形 placeholder 呈現（五星一覽用）。
  final bool circular;

  /// 依 [circular] 將 icon 圖片裁成圓形或 4px 圓角方塊。
  Widget _clipIcon(Widget child) => circular
      ? ClipOval(child: child)
      : ClipRRect(borderRadius: BorderRadius.circular(4), child: child);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (_odesGachaTypes.contains(record.gachaType)) {
      return const SizedBox.shrink();
    }

    final index = ref.watch(hoyowikiIndexProvider);
    final cacheDir = ref.watch(hoyowikiCacheDirProvider);
    final tokens = Theme.of(context).gacha;

    final preloaded = PreloadedHoYoWikiImages.maybeOf(context);
    final id = index.lookupId(name: record.name, lang: record.lang);
    final entry = id == null ? null : index.lookupEntry(id);
    final iconUrl = entry?.iconUrl;

    if (id != null && iconUrl != null && iconUrl.isNotEmpty) {
      final preloadedImage = preloaded?.images[id];
      if (preloadedImage != null) {
        return SizedBox(
          width: size,
          height: size,
          child: _clipIcon(RawImage(image: preloadedImage, fit: BoxFit.cover)),
        );
      }

      final file = hoyowikiIconCacheFile(
        baseDir: cacheDir,
        id: id,
        url: iconUrl,
      );
      if (file.existsSync()) {
        return SizedBox(
          width: size,
          height: size,
          child: _clipIcon(Image.file(file, fit: BoxFit.cover)),
        );
      }
    }

    return _Placeholder(
      rankType: record.rankType,
      size: size,
      tokens: tokens,
      circular: circular,
    );
  }
}

/// 缺 icon 時的固定尺寸方塊；底色依 rank 上色，中央疊一個 `?` icon。
class _Placeholder extends StatelessWidget {
  /// 建立 [_Placeholder]。
  const _Placeholder({
    required this.rankType,
    required this.size,
    required this.tokens,
    this.circular = false,
  });

  /// 星級（3 / 4 / 5）；決定強調色。
  final int rankType;

  /// 方塊邊長（px）。
  final double size;

  /// 主題 token；提供稀有度顏色。
  final GachaTokens tokens;

  /// true 時以圓形呈現。
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final accent = switch (rankType) {
      5 => tokens.fiveStar,
      4 => tokens.fourStar,
      _ => tokens.textMuted,
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.18),
        border: Border.all(color: accent.withValues(alpha: 0.40)),
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circular ? null : BorderRadius.circular(4),
      ),
      child: Center(
        child: Icon(Icons.question_mark, size: size * 0.55, color: accent),
      ),
    );
  }
}
