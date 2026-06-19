import 'package:flutter/material.dart';

/// 卡池配色表，給 Timeline 系列 widget 共用。
///
/// 配色刻意避開歐非語意色（綠 stateSuccess / 金 stateWarning / 紅 stateDanger），因為
/// 時間軸節點已改由歐非色標示運氣等級。卡池色僅用於 meta 列的卡池名稱與分佈圖。
/// 每個 banner 一個獨特色相，dark / light 各一組對應飽和度。
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
    character: Color(0xFF35BFD0), // 青藍
    weapon: Color(0xFF4FA3E8), // 天藍
    chronicled: Color(0xFF6E8BE6), // 矢車菊藍
    standard: Color(0xFF8A7CE0), // 靛藍
    beginner: Color(0xFFA86FD9), // 紫羅蘭
    odesEvent: Color(0xFFC56FD0), // 蘭紫
    odesStandard: Color(0xFFD96BA8), // 桃紅
    fallback: Color(0xFF8A92A6), // 中性
  );

  /// Light mode palette。
  static const _light = BannerColors(
    character: Color(0xFF1B92A8),
    weapon: Color(0xFF2E6FC0),
    chronicled: Color(0xFF4F5FC0),
    standard: Color(0xFF6A4FC0),
    beginner: Color(0xFF8A3FB0),
    odesEvent: Color(0xFFA63FA8),
    odesStandard: Color(0xFFB23A7E),
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
