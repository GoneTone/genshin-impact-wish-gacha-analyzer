import 'dart:typed_data';

/// 執行一條 shell 指令並回傳 stdout 原始位元組。
typedef ShellExec = Future<Uint8List> Function(String command);
