import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 目前是否在 Android 上執行；測試以 override 切換平台分支。
final isAndroidProvider = Provider<bool>((ref) => Platform.isAndroid);
