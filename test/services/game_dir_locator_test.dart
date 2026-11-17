import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/game_dir_locator.dart';

void main() {
  late Directory tmp;

  /// 在 [dir] 下建立假的有效遊戲資料夾（含空的 GenshinImpact_Data）。
  String makeGameDir(String dir) {
    Directory('$dir\\GenshinImpact_Data').createSync(recursive: true);
    return dir;
  }

  setUp(() => tmp = Directory.systemTemp.createTempSync('gdl_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('gameDirFromOutputLog', () {
    const game = r'D:\Program Files\Genshin Impact\games\Genshin Impact game';

    test('extracts the game dir from a mixed-slash log line', () {
      const log =
          '[2026-11-17 15:35:55.781] DeserializeBinary '
          '(D:/Program Files/Genshin Impact/games/Genshin Impact game/'
          r'GenshinImpact_Data/Persistent\AssetBundles/x)';
      expect(GameDirLocator.gameDirFromOutputLog(log), game);
    });

    test('takes the first match', () {
      const log = 'a E:/A/GenshinImpact_Data/x\nb F:/B/GenshinImpact_Data/y';
      expect(GameDirLocator.gameDirFromOutputLog(log), r'E:\A');
    });

    test('returns null when nothing matches', () {
      expect(GameDirLocator.gameDirFromOutputLog('nothing here'), isNull);
    });
  });

  test('webCachesPath appends the webCaches folder', () {
    expect(
      GameDirLocator.webCachesPath(r'D:\G'),
      r'D:\G\GenshinImpact_Data\webCaches',
    );
  });

  group('normalize', () {
    test('valid game dir returns itself', () async {
      final game = makeGameDir('${tmp.path}\\Game');
      expect(await GameDirLocator().normalize(game), game);
    });

    test('install root is corrected to games\\Genshin Impact game', () async {
      final root = '${tmp.path}\\Genshin Impact';
      final game = makeGameDir('$root\\games\\Genshin Impact game');
      expect(await GameDirLocator().normalize(root), game);
    });

    test('<root>\\Genshin Impact game is accepted', () async {
      final root = '${tmp.path}\\R';
      final game = makeGameDir('$root\\Genshin Impact game');
      expect(await GameDirLocator().normalize(root), game);
    });

    test('picking GenshinImpact_Data itself goes up one level', () async {
      final game = makeGameDir('${tmp.path}\\Game');
      expect(
        await GameDirLocator().normalize('$game\\GenshinImpact_Data'),
        game,
      );
    });

    test('empty dir returns null', () async {
      expect(await GameDirLocator().normalize(tmp.path), isNull);
    });
  });

  group('locate', () {
    GameDirLocator build({
      Future<List<String>> Function()? registry,
      Future<String?> Function()? log,
      List<String> common = const [],
    }) => GameDirLocator(
      readInstallPaths: registry ?? () async => [],
      readOutputLog: log ?? () async => null,
      commonDirs: common,
    );

    test('valid setting wins', () async {
      final game = makeGameDir('${tmp.path}\\S');
      final r = await build().locate(settingDir: game);
      expect(r?.path, game);
      expect(r?.source, GameDirSource.setting);
    });

    test('invalid setting falls back to output log', () async {
      final game = makeGameDir('${tmp.path}\\L');
      final r = await build(
        log: () async => 'x ${game.replaceAll('\\', '/')}/GenshinImpact_Data/y',
      ).locate(settingDir: '${tmp.path}\\nope');
      expect(r?.path, game);
      expect(r?.source, GameDirSource.outputLog);
    });

    test('registry install root falls back after output log', () async {
      final root = '${tmp.path}\\Root';
      final game = makeGameDir('$root\\games\\Genshin Impact game');
      final r = await build(registry: () async => [root]).locate();
      expect(r?.path, game);
      expect(r?.source, GameDirSource.registry);
    });

    test('falls back to first valid common dir', () async {
      final game = makeGameDir('${tmp.path}\\C2');
      final r = await build(common: ['${tmp.path}\\C1', game]).locate();
      expect(r?.path, game);
      expect(r?.source, GameDirSource.common);
    });

    test('nothing valid returns null', () async {
      expect(await build(common: ['${tmp.path}\\x']).locate(), isNull);
    });

    test('reader exceptions do not propagate', () async {
      final game = makeGameDir('${tmp.path}\\C');
      final r = await build(
        registry: () async => throw Exception('boom'),
        log: () async => throw Exception('boom'),
        common: [game],
      ).locate();
      expect(r?.source, GameDirSource.common);
    });
  });
}
