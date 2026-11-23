import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// 從單一主檔產生 app icon 的各尺寸 UI 資產、Windows 多解析度 `.ico`、Android 各密度 mipmap（含自適應圖示前景層）、Android 11 以下的啟動畫面圖示與 Play 商店圖示。
///
/// 用法：`dart run tool/generate_app_icons.dart`
/// 來源：`tool/app_icon_source.png`（滿版正方形、不含圓角與透明，建議 1024×1024，避免放大失真）。
/// 換 icon 時只要替換主檔再執行本腳本，即可一次重產所有輸出；
/// 自適應圖示的背景色在 `android/app/src/main/res/values/ic_launcher_background.xml`，換圖時一併確認。
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

  // Android 8+ 自適應圖示前景層：108dp 畫布，整張主檔縮成中央 72dp 可見區，
  // 四周用邊緣像素延伸補滿，啟動器做視差位移時也不會露出接縫。
  const adaptiveForegrounds = <String, int>{
    'mdpi': 108,
    'hdpi': 162,
    'xhdpi': 216,
    'xxhdpi': 324,
    'xxxhdpi': 432,
  };
  for (final entry in adaptiveForegrounds.entries) {
    final path =
        'android/app/src/main/res/mipmap-${entry.key}/ic_launcher_foreground.png';
    File(path)
      ..createSync(recursive: true)
      ..writeAsBytesSync(
        img.encodePng(_adaptiveForeground(source, entry.value)),
      );
    stdout.writeln('✓ $path  ${entry.value}x${entry.value}');
  }

  // Android 12 以下的啟動畫面中央圖示（12 以上由系統拿啟動器圖示畫成圓形，不讀這張）。
  // 裁成圓形與 12 以上一致；flutter_native_splash 以 4x 解讀，640px＝160dp。
  // 換圖後要再跑 `dart run flutter_native_splash:create`。
  const splashIconPath = 'assets/splash/icon.png';
  File(splashIconPath)
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(_circle(_resize(source, 640))));
  stdout.writeln('✓ $splashIconPath  640x640');

  // Play 商店圖示（Play 會自己套圓角遮罩，所以維持滿版）；Play 要求 32 位元 PNG（含 alpha）。
  const playIconPath = 'docs/images/play-store/icon-512.png';
  File(playIconPath)
    ..createSync(recursive: true)
    ..writeAsBytesSync(
      img.encodePng(_resize(source, 512).convert(numChannels: 4)),
    );
  stdout.writeln('✓ $playIconPath  512x512');
}

/// 產生 `canvas`×`canvas` 的自適應圖示前景層：主檔縮到畫布中央 2/3（72dp／108dp），外圍以邊緣像素延伸。
img.Image _adaptiveForeground(img.Image source, int canvas) {
  final inner = canvas * 2 ~/ 3;
  final offset = (canvas - inner) ~/ 2;
  final scaled = _resize(source, inner);
  final out = img.Image(width: canvas, height: canvas, numChannels: 4);
  for (var y = 0; y < canvas; y++) {
    final sy = (y - offset).clamp(0, inner - 1);
    for (var x = 0; x < canvas; x++) {
      final sx = (x - offset).clamp(0, inner - 1);
      final p = scaled.getPixel(sx, sy);
      out.setPixelRgba(x, y, p.r, p.g, p.b, 255);
    }
  }
  return out;
}

/// 把正方形 [square] 裁成內切圓，圓外透明，邊緣 1px 反鋸齒。
img.Image _circle(img.Image square) {
  final size = square.width;
  final r = size / 2;
  final out = img.Image(width: size, height: size, numChannels: 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final dx = x + 0.5 - r;
      final dy = y + 0.5 - r;
      final alpha = (r - math.sqrt(dx * dx + dy * dy)).clamp(0.0, 1.0);
      final p = square.getPixel(x, y);
      out.setPixelRgba(x, y, p.r, p.g, p.b, (alpha * 255).round());
    }
  }
  return out;
}

/// 將來源縮放成 `size`×`size` 正方形，使用 average 內插取得較佳的縮小品質。
img.Image _resize(img.Image source, int size) => img.copyResize(
  source,
  width: size,
  height: size,
  interpolation: img.Interpolation.average,
);
