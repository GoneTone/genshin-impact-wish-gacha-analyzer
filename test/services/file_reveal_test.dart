import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/file_reveal.dart';

void main() {
  group('revealInFileManager', () {
    test('returns false for non-existent file', () async {
      final fakePath =
          '${Directory.systemTemp.path}/__gwga_does_not_exist_${DateTime.now().microsecondsSinceEpoch}.tmp';
      final ok = await revealInFileManager(fakePath);
      expect(ok, isFalse);
    });

    test('does not throw when file exists (smoke)', () async {
      // 故意不 assert 結果 true/false：在 test 環境
      // launchUrl 通常因為 platform plugin 不存在而失敗回傳 false，
      // 但呼叫本身不應丟例外。
      final f = await File(
        '${Directory.systemTemp.path}/__gwga_reveal_smoke_${DateTime.now().microsecondsSinceEpoch}.tmp',
      ).create();
      try {
        await revealInFileManager(f.path);
      } finally {
        if (await f.exists()) await f.delete();
      }
    });
  });

  group('openFolder', () {
    test('does not throw when dir exists (smoke)', () async {
      final dir = await Directory(
        '${Directory.systemTemp.path}/__gwga_open_smoke_${DateTime.now().microsecondsSinceEpoch}',
      ).create();
      try {
        await openFolder(dir.path);
      } finally {
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    });
  });
}
