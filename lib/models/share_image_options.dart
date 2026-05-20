import 'package:flutter/material.dart';

/// 生成分享圖前由使用者在 dialog 選定的選項。
class ShareImageOptions {
  /// 建立 [ShareImageOptions]，預設暗色主題且不顯示完整 UID。
  const ShareImageOptions({
    this.brightness = Brightness.dark,
    this.showFullUid = false,
  });

  /// 分享圖主題（與 App 當前 themeMode 解耦）。
  final Brightness brightness;

  /// true = 圖上顯示完整 UID；false = 經 maskUidForShare 遮罩。
  final bool showFullUid;
}
