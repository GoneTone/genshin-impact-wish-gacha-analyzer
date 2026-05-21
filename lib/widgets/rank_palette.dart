import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

/// 依稀有度 rank 取對應主色 token。
Color accentForRank(int rank, GachaTokens t) => switch (rank) {
  5 => t.fiveStar,
  4 => t.fourStar,
  3 => t.threeStar,
  2 => t.twoStar,
  _ => t.textMuted,
};
