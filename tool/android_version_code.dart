import 'dart:io';

import 'package:genshin_impact_wish_gacha_analyzer/services/android_version_code.dart';

/// 由 release tag 印出 Android 建置用的 `VERSION_CODE` 與 `BUILD_NAME`，供 CI 寫入 `GITHUB_ENV`。
///
/// 用法：`dart run tool/android_version_code.dart v1.9.0-rc.2`
void main(List<String> args) {
  exitCode = runVersionCodeCli(args, stdout, stderr);
}

/// CLI 本體：結果寫入 [out]、錯誤寫入 [err]，回傳 exit code（成功 0、格式錯誤 1、參數數量錯誤 64）。
int runVersionCodeCli(List<String> args, StringSink out, StringSink err) {
  if (args.length != 1) {
    err.writeln('Usage: dart run tool/android_version_code.dart <tag>');
    return 64;
  }
  try {
    final code = androidVersionCodeForTag(args[0]);
    out.writeln('VERSION_CODE=$code');
    out.writeln('BUILD_NAME=${args[0].substring(1)}');
    return 0;
  } on FormatException catch (e) {
    err.writeln('${e.message}: ${e.source}');
    return 1;
  }
}
