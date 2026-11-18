import 'dart:io';

import 'package:image/image.dart' as img;

/// 從單一主檔產生 app icon 的各尺寸 UI 資產、Windows 多解析度 `.ico` 與 Android 各密度 mipmap。
///
/// 用法：`dart run tool/generate_app_icons.dart`
/// 來源：`tool/app_icon_source.png`（白底滿版方圖，建議 512×512 以上，避免放大失真）。
/// 換 icon 時只要替換主檔再執行本腳本，即可一次重產所有輸出。
void main() {
  const sourcePath = 'tool/app_icon_source.png';
  final sourceFile = File(sourcePath);
  if (!sourceFile.existsSync()) {
    stderr.writeln('找不到主檔：$sourcePath');
    exitCode = 1;
    return;
  }

  final source = img.decodePng(sourceFile.readAsBytesSync());
  if (source == null) {
    stderr.writeln('無法解析 PNG：$sourcePath');
    exitCode = 1;
    return;
  }

  // assets/icons/ 的 1.0x / 2.0x / 3.0x UI 變體（AppBar 標題列、分享圖 header 用）。
  const uiVariants = <String, int>{
    'assets/icons/app_icon.png': 64,
    'assets/icons/2.0x/app_icon.png': 128,
    'assets/icons/3.0x/app_icon.png': 256,
  };
  for (final entry in uiVariants.entries) {
    final resized = _resize(source, entry.value);
    File(entry.key)
      ..createSync(recursive: true)
      ..writeAsBytesSync(img.encodePng(resized));
    stdout.writeln('✓ ${entry.key}  ${entry.value}x${entry.value}');
  }

  // Windows exe / 工作列 / Alt+Tab / 安裝檔用的多解析度 .ico。
  const icoSizes = <int>[16, 24, 32, 48, 64, 128, 256];
  final icoImages = [for (final size in icoSizes) _resize(source, size)];
  const icoPath = 'windows/runner/resources/app_icon.ico';
  File(icoPath).writeAsBytesSync(img.IcoEncoder().encodeImages(icoImages));
  stdout.writeln('✓ $icoPath  ${icoSizes.join('/')}');

  // Android 啟動器圖示（各密度 mipmap）。
  const androidMipmaps = <String, int>{
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  };
  for (final entry in androidMipmaps.entries) {
    final path = 'android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png';
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(img.encodePng(_resize(source, entry.value)));
    stdout.writeln('✓ $path  ${entry.value}x${entry.value}');
  }
}

/// 將來源縮放成 `size`×`size` 正方形，使用 average 內插取得較佳的縮小品質。
img.Image _resize(img.Image source, int size) => img.copyResize(
  source,
  width: size,
  height: size,
  interpolation: img.Interpolation.average,
);
