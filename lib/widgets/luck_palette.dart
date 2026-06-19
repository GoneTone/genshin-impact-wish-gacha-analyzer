import 'package:flutter/material.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/tokens.dart';

/// 歐非分級：依「抽到該筆所花抽數 / 該池保底門檻」的比例分三階。
enum LuckTier {
  /// 歐：半個保底內出貨。
  lucky,

  /// 普通。
  average,

  /// 非：進入軟保底區（接近硬保底）。
  unlucky,
}

/// 歐（綠）上界比例：抽數在保底的一半以內視為歐。
const double _luckyMaxRatio = 0.5;

/// 普通（金）上界比例：超過此比例即進入軟保底區，視為非。
const double _averageMaxRatio = 0.8;

/// 依 [pulls] 相對 [pityThreshold] 的比例回傳分級。
/// `ratio <= 0.5` 歐；`<= 0.8` 普通；其餘（含 ratio > 1）非。
/// [pityThreshold] <= 0 時防呆視為非（避免除以零；正常資料不會發生）。
LuckTier luckTierFor(int pulls, int pityThreshold) {
  if (pityThreshold <= 0) return LuckTier.unlucky;
  final ratio = pulls / pityThreshold;
  if (ratio <= _luckyMaxRatio) return LuckTier.lucky;
  if (ratio <= _averageMaxRatio) return LuckTier.average;
  return LuckTier.unlucky;
}

/// 將分級映射到既有語意色（綠 / 金 / 紅），不新增 token。
Color luckColorFor(LuckTier tier, GachaTokens t) => switch (tier) {
  LuckTier.lucky => t.stateSuccess,
  LuckTier.average => t.stateWarning,
  LuckTier.unlucky => t.stateDanger,
};
