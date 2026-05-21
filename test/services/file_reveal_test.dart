import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/file_reveal.dart';

void main() {
  // 記錄 fake 收到的呼叫
  String? capturedExe;
  List<String>? capturedArgs;
  Uri? capturedUri;

  setUp(() {
    capturedExe = null;
    capturedArgs = null;
    capturedUri = null;
  });

  tearDown(resetFileRevealSeams);

  Future<File> makeTempFile() => File(
    '${Directory.systemTemp.path}/__gwga_reveal_${DateTime.now().microsecondsSinceEpoch}.tmp',
  ).create();

  group('revealInFileManager', () {
    test('non-existent file returns false without touching seams', () async {
      revealProcessRunner = (exe, args) async {
        capturedExe = exe;
        capturedArgs = args;
        return ProcessResult(0, 0, '', '');
      };
      revealUrlLauncher = (uri) async {
        capturedUri = uri;
        return true;
      };

      final fakePath =
          '${Directory.systemTemp.path}/__gwga_missing_${DateTime.now().microsecondsSinceEpoch}.tmp';
      final ok = await revealInFileManager(fakePath);

      expect(ok, isFalse);
      expect(capturedExe, isNull);
      expect(capturedArgs, isNull);
      expect(capturedUri, isNull);
    });

    test('windows branch calls explorer /select,<path>', () async {
      revealPlatform = () => RevealPlatform.windows;
      revealProcessRunner = (exe, args) async {
        capturedExe = exe;
        capturedArgs = args;
        return ProcessResult(0, 1, '', ''); // explorer 常回非 0
      };

      final f = await makeTempFile();
      try {
        final ok = await revealInFileManager(f.path);
        expect(ok, isTrue);
        expect(capturedExe, 'explorer');
        expect(capturedArgs, ['/select,${f.path}']);
      } finally {
        if (await f.exists()) await f.delete();
      }
    });

    test('macos branch with exit 0 returns true', () async {
      revealPlatform = () => RevealPlatform.macos;
      revealProcessRunner = (exe, args) async {
        capturedExe = exe;
        capturedArgs = args;
        return ProcessResult(0, 0, '', '');
      };

      final f = await makeTempFile();
      try {
        final ok = await revealInFileManager(f.path);
        expect(ok, isTrue);
        expect(capturedExe, 'open');
        expect(capturedArgs, ['-R', f.path]);
      } finally {
        if (await f.exists()) await f.delete();
      }
    });

    test('macos branch with non-zero exit returns false', () async {
      revealPlatform = () => RevealPlatform.macos;
      revealProcessRunner = (exe, args) async => ProcessResult(0, 1, '', '');

      final f = await makeTempFile();
      try {
        final ok = await revealInFileManager(f.path);
        expect(ok, isFalse);
      } finally {
        if (await f.exists()) await f.delete();
      }
    });

    test('other platform falls back to openFolder via launcher', () async {
      revealPlatform = () => RevealPlatform.other;
      revealProcessRunner = (exe, args) async {
        capturedExe = exe;
        return ProcessResult(0, 0, '', '');
      };
      revealUrlLauncher = (uri) async {
        capturedUri = uri;
        return true;
      };

      final f = await makeTempFile();
      try {
        final ok = await revealInFileManager(f.path);
        expect(ok, isTrue);
        expect(capturedExe, isNull); // runner 未被呼叫
        expect(capturedUri, Uri.file(f.parent.path));
      } finally {
        if (await f.exists()) await f.delete();
      }
    });
  });

  group('openFolder', () {
    test('calls launcher with Uri.file(dir) and returns its result', () async {
      revealUrlLauncher = (uri) async {
        capturedUri = uri;
        return true;
      };
      final dir = await Directory(
        '${Directory.systemTemp.path}/__gwga_open_${DateTime.now().microsecondsSinceEpoch}',
      ).create();
      try {
        final ok = await openFolder(dir.path);
        expect(ok, isTrue);
        expect(capturedUri, Uri.file(dir.path));
      } finally {
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    });

    test('launcher returning false yields false', () async {
      revealUrlLauncher = (uri) async => false;
      final ok = await openFolder(Directory.systemTemp.path);
      expect(ok, isFalse);
    });

    test('launcher throwing yields false without throwing', () async {
      revealUrlLauncher = (uri) async => throw Exception('boom');
      final ok = await openFolder(Directory.systemTemp.path);
      expect(ok, isFalse);
    });
  });
}
