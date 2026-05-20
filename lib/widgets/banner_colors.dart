import 'package:flutter/material.dart';

/// 卡池配色表，給 Timeline 系列 widget 共用。
///
/// 配色刻意跟稀有度 token（5★ 金、4★ 紫、3★ 藍、2★ 灰）保持距離，避免使用者
/// 看到時間軸節點的顏色誤判為稀有度。每個 banner 一個獨特色相，dark / light
/// 各一組對應飽和度。
@immutable
class BannerColors {
  /// 建立 [BannerColors]。
  const BannerColors({
    required this.character,
    required this.weapon,
    required this.chronicled,
    required this.standard,
    required this.beginner,
    required this.odesEvent,
    required this.odesStandard,
    required this.fallback,
  });

  /// 依當前 [Brightness] 取得 dark / light palette。
  factory BannerColors.of(Brightness brightness) =>
      brightness == Brightness.dark ? _dark : _light;

  /// Dark mode palette。
  static const _dark = BannerColors(
    character: Color(0xFF46B07A), // 森林綠
    weapon: Color(0xFFE6736B), // 珊瑚紅
    chronicled: Color(0xFFFF9F40), // 鮮橘
    standard: Color(0xFF26A69A), // 青綠
    beginner: Color(0xFF7A8AAD), // 灰藍
    odesEvent: Color(0xFFEC4899), // 桃紅
    odesStandard: Color(0xFFB59574), // 棕褐
    fallback: Color(0xFF8A92A6), // 中性
  );

  /// Light mode palette。
  static const _light = BannerColors(
    character: Color(0xFF2E7D32),
    weapon: Color(0xFFC62828),
    chronicled: Color(0xFFE07B22),
    standard: Color(0xFF00897B),
    beginner: Color(0xFF5A6680),
    odesEvent: Color(0xFFC2185B),
    odesStandard: Color(0xFF7A5F40),
    fallback: Color(0xFF6A7080),
  );

  /// 角色活動祈願配色。
  final Color character;

  /// 武器活動祈願配色。
  final Color weapon;

  /// 集錄祈願配色。
  final Color chronicled;

  /// 常駐祈願配色。
  final Color standard;

  /// 新手祈願配色。
  final Color beginner;

  /// 歐差事件祈願配色。
  final Color odesEvent;

  /// 歐差常駐祈願配色。
  final Color odesStandard;

  /// 未知 gachaType 的備用配色。
  final Color fallback;

  /// 依 [gachaType] 字串（如 `'301'`）回傳對應色；未知 type 回傳 [fallback]。
  Color colorFor(String gachaType) => switch (gachaType) {
    '301' => character,
    '302' => weapon,
    '500' => chronicled,
    '200' => standard,
    '100' => beginner,
    '2000' => odesEvent,
    '1000' => odesStandard,
    _ => fallback,
  };
}
