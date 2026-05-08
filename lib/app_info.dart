import 'package:flutter_riverpod/flutter_riverpod.dart';

const appName = '原神祈願卡池分析';

/// 由 main.dart 透過 `PackageInfo.fromPlatform()` 取得 pubspec.yaml `version:` 並 override。
/// Windows 從 .exe 的 FileVersion 讀（CMake 內建從 pubspec 同步寫入 Runner.rc）。
final appVersionProvider = Provider<String>((ref) {
  throw UnimplementedError('appVersionProvider must be overridden in main()');
});
