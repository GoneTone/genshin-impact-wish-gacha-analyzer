import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/app_release.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/play_update_download.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/platform.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/new_version_dialog.dart';

import '../../helpers/fake_url_launcher.dart';

/// 記錄 start 呼叫的下載替身。
class _Download extends PlayUpdateDownloadNotifier {
  /// start 被呼叫的次數。
  int starts = 0;

  /// install 被呼叫的次數。
  int installs = 0;

  /// 建立替身；[initial] 為初始階段。
  _Download([this.initial = PlayDownloadPhase.idle]);

  /// 初始階段。
  final PlayDownloadPhase initial;

  @override
  PlayDownloadPhase build() => initial;

  @override
  Future<void> start() async => starts++;

  @override
  Future<void> install() async => installs++;
}

/// 建立測試用 release。
AppRelease _release(String tag) => AppRelease(
  tagName: tag,
  version: tag.substring(1),
  name: tag,
  body: '## Notes $tag',
  htmlUrl: 'https://github.com/o/r/releases/tag/$tag',
  publishedAt: DateTime.utc(2026, 5, 27),
);

/// 以 [android] 平台、[releases] 與 [playTag] 在 320 寬視窗開啟對話框，回傳下載替身。
Future<_Download> _pump(
  WidgetTester tester, {
  required bool android,
  required List<AppRelease> releases,
  String? playTag,
  PlayDownloadPhase phase = PlayDownloadPhase.idle,
}) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final download = _Download(phase);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isAndroidProvider.overrideWithValue(android),
        playUpdateDownloadProvider.overrideWith(() => download),
      ],
      child: MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) =>
                  NewVersionDialog(releases: releases, playTag: playTag),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return download;
}

void main() {
  testWidgets('android: primary button is Update and starts the download', (
    tester,
  ) async {
    final d = await _pump(
      tester,
      android: true,
      releases: [_release('v1.2.0')],
      playTag: 'v1.2.0',
    );
    expect(find.text('Download'), findsNothing);
    expect(find.textContaining('Release notes are unavailable'), findsNothing);
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    expect(d.starts, 1);
    expect(find.byType(NewVersionDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('android: empty releases shows the notes-unavailable text and '
      'the play tag in the title', (tester) async {
    await _pump(tester, android: true, releases: [], playTag: 'v1.3.0');
    expect(find.textContaining('v1.3.0'), findsOneWidget);
    expect(find.textContaining('Release notes are unavailable'), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('android: play version without notes shows the hint above the '
      'older notes', (tester) async {
    await _pump(
      tester,
      android: true,
      releases: [_release('v1.2.0')],
      playTag: 'v1.3.0',
    );
    final hint = find.textContaining('Release notes are unavailable');
    expect(hint, findsOne);
    expect(
      tester.getTopLeft(hint).dy,
      lessThan(tester.getTopLeft(find.textContaining('Notes v1.2.0')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('android: already downloaded + Update installs instead', (
    tester,
  ) async {
    final d = await _pump(
      tester,
      android: true,
      releases: [_release('v1.2.0')],
      playTag: 'v1.2.0',
      phase: PlayDownloadPhase.downloaded,
    );
    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();
    expect(d.installs, 1);
    expect(d.starts, 0);
    expect(find.byType(NewVersionDialog), findsNothing);
  });

  testWidgets('windows: primary button still opens the GitHub page', (
    tester,
  ) async {
    final launcher = installFakeUrlLauncher();
    final d = await _pump(
      tester,
      android: false,
      releases: [_release('v1.2.0')],
    );
    expect(find.text('Update'), findsNothing);
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(d.starts, 0);
    expect(launcher.launched, ['https://github.com/o/r/releases/tag/v1.2.0']);
    expect(tester.takeException(), isNull);
  });
}
