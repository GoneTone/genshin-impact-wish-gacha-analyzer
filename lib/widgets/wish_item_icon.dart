import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/hoyowiki_index.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/preloaded_hoyowiki_images.dart';

/// 頌願卡池（odes） gachaType 集合 — 不顯示 icon 也不顯示 placeholder。
const _odesGachaTypes = {'2000', '1000'};

/// 顯示一筆祈願物品的 icon；cache 未到 / 缺資料時顯示 [_Placeholder]。
class WishItemIcon extends ConsumerWidget {
  /// 建立 [WishItemIcon]。
  const WishItemIcon({super.key, required this.record, required this.size});

  /// 祈願記錄；用其 name / lang / rankType / gachaType。
  final GachaRecord record;

  /// icon 邊長（px，依使用情境調整：表格 28 / 時間軸 32）。
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (_odesGachaTypes.contains(record.gachaType)) {
      return const SizedBox.shrink();
    }

    final index = ref.watch(hoyowikiIndexProvider);
    final cacheDir = ref.watch(hoyowikiCacheDirProvider);
    final tokens = Theme.of(context).gacha;

    final preloaded = PreloadedHoyoWikiImages.maybeOf(context);
    final id = index.lookupId(name: record.name, lang: record.lang);
    final entry = id == null ? null : index.lookupEntry(id);
    final iconUrl = entry?.iconUrl;

    if (id != null && iconUrl != null && iconUrl.isNotEmpty) {
      final preloadedImage = preloaded?.images[id];
      if (preloadedImage != null) {
        return SizedBox(
          width: size,
          height: size,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: RawImage(image: preloadedImage, fit: BoxFit.cover),
          ),
        );
      }

      final file = hoyowikiCacheFile(
        baseDir: cacheDir,
        id: id,
        kind: HoyoWikiImageKind.icon,
        url: iconUrl,
      );
      if (file.existsSync()) {
        return SizedBox(
          width: size,
          height: size,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.file(file, fit: BoxFit.cover),
          ),
        );
      }
    }

    return _Placeholder(rankType: record.rankType, size: size, tokens: tokens);
  }
}

/// 缺 icon 時的固定尺寸方塊；底色依 rank 上色。
class _Placeholder extends StatelessWidget {
  /// 建立 [_Placeholder]。
  const _Placeholder({
    required this.rankType,
    required this.size,
    required this.tokens,
  });

  /// 星級（3 / 4 / 5）；決定強調色。
  final int rankType;

  /// 方塊邊長（px）。
  final double size;

  /// 主題 token；提供稀有度顏色。
  final GachaTokens tokens;

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
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
