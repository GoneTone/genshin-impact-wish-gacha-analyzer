import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/app_release_checker.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/current_release.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/current_release_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/release_notes_content.dart';

AppRelease _release({String tag = 'v1.1.0', String body = '## Hi'}) =>
    AppRelease(
      tagName: tag,
      version: tag.startsWith('v') ? tag.substring(1) : tag,
      name: tag,
      body: body,
      htmlUrl: 'https://github.com/o/r/releases/tag/$tag',
      publishedAt: DateTime.utc(2026, 5, 27),
    );

/// Pump a Riverpod-scoped app that opens [CurrentReleaseDialog] with the
/// given fake fetcher and waits for the open animation to start. Caller is
/// responsible for `pumpAndSettle()` when ready.
Future<void> _pumpDialog(
  WidgetTester tester, {
  required Future<AppRelease> Function(Ref ref) fetcher,
  String version = '1.1.0',
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [currentReleaseProvider(version).overrideWith(fetcher)],
      child: MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: ctx,
                  builder: (_) => CurrentReleaseDialog(version: version),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
}

void main() {
  testWidgets(
    'data state → renders ReleaseNotesContent + [View on GitHub] [Close]',
    (tester) async {
      final release = _release();
      await _pumpDialog(tester, fetcher: (ref) async => release);
      await tester.pumpAndSettle();

      expect(find.byType(ReleaseNotesContent), findsOneWidget);
      expect(find.text('View on GitHub'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    },
  );

  testWidgets('loading state → no ReleaseNotesContent yet, only [Close]', (
    tester,
  ) async {
    final completer = Completer<AppRelease>();
    await _pumpDialog(tester, fetcher: (ref) => completer.future);

    expect(find.byType(ReleaseNotesContent), findsNothing);
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('View on GitHub'), findsNothing);

    completer.complete(_release());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'ReleaseCheckNotFound → renders not-found message + [Go to Releases page] [Close]',
    (tester) async {
      await _pumpDialog(
        tester,
        fetcher: (ref) => Future.error(const ReleaseCheckNotFound('v1.1.0')),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Release notes not found for 1.1.0'),
        findsOneWidget,
      );
      expect(find.text('Go to GitHub Releases page'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    },
  );

  testWidgets('ReleaseCheckRateLimited → [Go to Releases page] [Close]', (
    tester,
  ) async {
    await _pumpDialog(
      tester,
      fetcher: (ref) => Future.error(const ReleaseCheckRateLimited()),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('quota'), findsOneWidget);
    expect(find.text('Go to GitHub Releases page'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('ReleaseCheckNetwork → [Retry] [Close]', (tester) async {
    await _pumpDialog(
      tester,
      fetcher: (ref) => Future.error(const ReleaseCheckNetwork()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Go to GitHub Releases page'), findsNothing);
  });

  testWidgets(
    'ReleaseCheckServer(503) → [Retry] [Close] with status code visible',
    (tester) async {
      await _pumpDialog(
        tester,
        fetcher: (ref) => Future.error(const ReleaseCheckServer(503)),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('503'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    },
  );

  testWidgets('Retry → ref.invalidate triggers refetch', (tester) async {
    var fetches = 0;
    await _pumpDialog(
      tester,
      fetcher: (ref) {
        fetches++;
        if (fetches == 1) {
          return Future.error(const ReleaseCheckNetwork());
        }
        return Future.value(_release());
      },
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(fetches, greaterThanOrEqualTo(2));
    expect(find.byType(ReleaseNotesContent), findsOneWidget);
  });

  testWidgets('Close → dialog dismissed', (tester) async {
    await _pumpDialog(tester, fetcher: (ref) async => _release());
    await tester.pumpAndSettle();
    expect(find.byType(CurrentReleaseDialog), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.byType(CurrentReleaseDialog), findsNothing);
  });
}
