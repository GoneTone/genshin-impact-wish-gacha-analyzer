import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/accounts_picker_dialog.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/dialogs/import_target_account_dialog.dart';

/// 對話框回傳的 UID。
String? _result;

/// 對話框是否已關閉。
bool _completed = false;

/// 兩個本機帳號，第二個有長別名。
final _accounts = [
  AccountPickerEntry(
    uid: '800000001',
    lastUpdated: DateTime(2026, 11, 1),
    recordCount: 1155,
  ),
  AccountPickerEntry(
    uid: '800000002',
    alias: List.filled(6, '很長的別名').join(),
    lastUpdated: DateTime(2026, 11, 2),
    recordCount: 1,
  ),
];

/// 開啟選帳號對話框；[accounts] 為本機帳號，[maskUidInUi] 為介面隱私設定。
Future<void> _open(
  WidgetTester tester,
  List<AccountPickerEntry> accounts, {
  bool maskUidInUi = false,
}) async {
  _result = null;
  _completed = false;
  SharedPreferences.setMockInitialValues({'pref.maskUidInUi': maskUidInUi});
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh', 'Hant'),
        theme: buildDarkTheme(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  _result = await showImportTargetAccountDialog(
                    context: ctx,
                    accounts: accounts,
                  );
                  _completed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// 「繼續」按鈕。
final _continue = find.widgetWithText(FilledButton, '繼續');

/// 「繼續」目前是否可按。
bool _continueEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(_continue).onPressed != null;

void main() {
  testWidgets('preselects the first local account and returns it', (
    tester,
  ) async {
    await _open(tester, _accounts);
    expect(find.text('匯入到哪個帳號？'), findsOneWidget);
    expect(find.text('800000001'), findsOneWidget);
    expect(find.text('本機已有 1155 筆記錄'), findsOneWidget);
    expect(_continueEnabled(tester), isTrue);

    await tester.tap(_continue);
    await tester.pumpAndSettle();

    expect(_completed, isTrue);
    expect(_result, '800000001');
  });

  testWidgets('shows the alias with the UID', (tester) async {
    await _open(tester, _accounts);
    expect(
      find.text('${List.filled(6, '很長的別名').join()} (800000002)'),
      findsOneWidget,
    );
  });

  testWidgets('masks the UID when maskUidInUi is on', (tester) async {
    await _open(tester, _accounts, maskUidInUi: true);
    expect(find.text('800••••••'), findsOneWidget);
    expect(
      find.text('${List.filled(6, '很長的別名').join()} (800••••••)'),
      findsOneWidget,
    );
    expect(find.textContaining('80000000'), findsNothing);
  });

  testWidgets('other UID needs 9 to 10 digits before continuing', (
    tester,
  ) async {
    await _open(tester, _accounts);
    await tester.tap(find.text('其他 UID'));
    await tester.pump();
    expect(_continueEnabled(tester), isFalse);

    await tester.enterText(find.byType(TextField), '1234567');
    await tester.pump();
    expect(_continueEnabled(tester), isFalse);

    await tester.enterText(find.byType(TextField), '123456789');
    await tester.pump();
    expect(_continueEnabled(tester), isTrue);

    await tester.tap(_continue);
    await tester.pumpAndSettle();
    expect(_result, '123456789');
  });

  testWidgets('typing in the field selects other UID', (tester) async {
    await _open(tester, _accounts);
    await tester.enterText(find.byType(TextField), '1234567');
    await tester.pump();
    expect(_continueEnabled(tester), isFalse);
  });

  testWidgets('without local accounts only the UID field is shown', (
    tester,
  ) async {
    await _open(tester, const []);
    expect(find.byType(RadioListTile<String>), findsNothing);
    expect(find.text('其他 UID'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(_continueEnabled(tester), isFalse);

    await tester.enterText(find.byType(TextField), '1234567890');
    await tester.pump();
    await tester.tap(_continue);
    await tester.pumpAndSettle();
    expect(_result, '1234567890');
  });

  testWidgets('cancel returns null', (tester) async {
    await _open(tester, _accounts);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(_completed, isTrue);
    expect(_result, isNull);
  });

  for (final size in const [Size(360, 640), Size(640, 360), Size(1280, 800)]) {
    testWidgets('fits without overflow at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _open(tester, _accounts);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('其他 UID'));
      await tester.enterText(find.byType(TextField), '123456789');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(_continue);
      await tester.pumpAndSettle();
      expect(_continueEnabled(tester), isTrue);
    });
  }

  testWidgets('phone width puts the record count below the UID', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _open(tester, _accounts);

    final uid = tester.getRect(find.text('800000001'));
    final count = tester.getRect(find.text('本機已有 1155 筆記錄'));
    expect(count.top, greaterThanOrEqualTo(uid.bottom));
  });

  testWidgets('desktop width keeps the UID and record count on one line', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _open(tester, _accounts);

    final uid = tester.getRect(find.text('800000001'));
    final count = tester.getRect(find.text('本機已有 1155 筆記錄'));
    expect(count.left, greaterThan(uid.right));
    expect(count.center.dy, closeTo(uid.center.dy, 2));
  });
}
