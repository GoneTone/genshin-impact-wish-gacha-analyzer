import 'package:flutter/material.dart';

abstract class GachaColors {
  static const fiveStar = Color(0xFFB8860B);   // 金
  static const fourStar = Color(0xFF8E44AD);   // 紫
  static const threeStar = Color(0xFF3498DB);  // 藍
  static const character = Color(0xFF2E7D32);  // 深綠
  static const weapon = Color(0xFFC62828);     // 深紅
  static const unknown = Color(0xFF9E9E9E);    // 灰
}

ThemeData buildAppTheme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      useMaterial3: true,
    );
