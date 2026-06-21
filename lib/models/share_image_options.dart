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

/// 分享圖輸出動作：複製到剪貼簿或存檔。
enum ShareImageAction {
  /// 複製分享圖到系統剪貼簿。
  copy,

  /// 將分享圖存檔到使用者選擇的位置。
  save,
}
