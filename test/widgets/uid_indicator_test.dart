import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/uid_indicator.dart';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('zh', 'Hant'),
  theme: buildDarkTheme(),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('AccountMenuLabel', () {
    testWidgets('有 alias:渲染 alias 主標 + UID 副標', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AccountMenuLabel(
            uid: '123456789',
            alias: 'MainAcc',
            isActive: false,
          ),
        ),
      );
      expect(find.text('MainAcc'), findsOneWidget);
      expect(find.text('123456789'), findsOneWidget);
    });

    testWidgets('無 alias:只渲染 UID(findsOneWidget 隱含無副標)', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AccountMenuLabel(
            uid: '987654321',
            alias: null,
            isActive: false,
          ),
        ),
      );
      expect(find.text('987654321'), findsOneWidget);
    });

    testWidgets('isActive=true:接「（活躍）」suffix', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AccountMenuLabel(
            uid: '123456789',
            alias: 'MainAcc',
            isActive: true,
          ),
        ),
      );
      expect(find.text('（活躍）'), findsOneWidget);
    });

    testWidgets('alias 主標 Text:overflow=ellipsis、maxLines=1', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AccountMenuLabel(
            uid: '123456789',
            alias: 'VeryLongAliasName',
            isActive: false,
          ),
        ),
      );
      final aliasText = tester.widget<Text>(find.text('VeryLongAliasName'));
      expect(aliasText.overflow, TextOverflow.ellipsis);
      expect(aliasText.maxLines, 1);
    });
  });

  group('AccountTriggerButton', () {
    testWidgets('渲染 OutlinedButton 且形狀為 StadiumBorder（橢圓）', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AccountTriggerButton(
            tooltip: 'switch',
            onPressed: () {},
            child: const AccountTriggerLabel(
              activeUid: '123456789',
              alias: null,
            ),
          ),
        ),
      );

      final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      final shape = button.style!.shape!.resolve(<WidgetState>{});
      expect(shape, isA<StadiumBorder>());
    });

    testWidgets('點擊觸發 onPressed', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(
          AccountTriggerButton(
            tooltip: 'switch',
            onPressed: () => tapped = true,
            child: const AccountTriggerLabel(
              activeUid: '123456789',
              alias: null,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(OutlinedButton));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('內含傳入的 child 內容（UID 文字）', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AccountTriggerButton(
            tooltip: 'switch',
            onPressed: () {},
            child: const AccountTriggerLabel(
              activeUid: '987654321',
              alias: null,
            ),
          ),
        ),
      );
      expect(find.text('987654321'), findsOneWidget);
    });
  });

  group('AccountTriggerLabel', () {
    testWidgets('activeUid=null:顯示「未同步」', (tester) async {
      await tester.pumpWidget(
        _wrap(const AccountTriggerLabel(activeUid: null, alias: null)),
      );
      expect(find.text('未同步'), findsOneWidget);
    });

    testWidgets('有 alias:顯示 alias + 完整 UID', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AccountTriggerLabel(activeUid: '123456789', alias: 'MainAcc'),
        ),
      );
      expect(find.text('MainAcc'), findsOneWidget);
      // UID 用 " (123456789)" 形式接在 alias 後
      expect(find.text(' (123456789)'), findsOneWidget);
    });

    testWidgets('無 alias:只顯示 UID', (tester) async {
      await tester.pumpWidget(
        _wrap(const AccountTriggerLabel(activeUid: '987654321', alias: null)),
      );
      expect(find.text('987654321'), findsOneWidget);
    });

    testWidgets('alias Text:overflow=ellipsis、maxLines=1', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AccountTriggerLabel(
            activeUid: '123456789',
            alias: 'VeryLongAliasName',
          ),
        ),
      );
      final aliasText = tester.widget<Text>(find.text('VeryLongAliasName'));
      expect(aliasText.overflow, TextOverflow.ellipsis);
      expect(aliasText.maxLines, 1);
    });
  });

  group('AccountTriggerLabel: maskUid', () {
    testWidgets('displays full uid when maskUid=false', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AccountTriggerLabel(activeUid: '123456789', maskUid: false),
        ),
      );
      expect(find.text('123456789'), findsOneWidget);
    });

    testWidgets('displays masked uid when maskUid=true', (tester) async {
      await tester.pumpWidget(
        _wrap(const AccountTriggerLabel(activeUid: '123456789', maskUid: true)),
      );
      expect(find.text('123xxxxxx'), findsOneWidget);
      expect(find.text('123456789'), findsNothing);
    });

    testWidgets('with alias: still masks the (uid) suffix', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AccountTriggerLabel(
            activeUid: '123456789',
            alias: '主帳',
            maskUid: true,
          ),
        ),
      );
      expect(find.text('主帳'), findsOneWidget);
      expect(find.text(' (123xxxxxx)'), findsOneWidget);
      expect(find.text(' (123456789)'), findsNothing);
    });

    testWidgets('with alias: maskUid=false shows full', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AccountTriggerLabel(
            activeUid: '123456789',
            alias: '主帳',
            maskUid: false,
          ),
        ),
      );
      expect(find.text(' (123456789)'), findsOneWidget);
    });
  });

  group('AccountMenuLabel: maskUid', () {
    testWidgets('without alias shows masked uid as primary', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AccountMenuLabel(
            uid: '123456789',
            isActive: false,
            maskUid: true,
          ),
        ),
      );
      expect(find.text('123xxxxxx'), findsOneWidget);
    });

    testWidgets('with alias: alias primary, masked uid as subtitle', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const AccountMenuLabel(
            uid: '123456789',
            alias: '主帳',
            isActive: false,
            maskUid: true,
          ),
        ),
      );
      expect(find.text('主帳'), findsOneWidget);
      expect(find.text('123xxxxxx'), findsOneWidget);
      expect(find.text('123456789'), findsNothing);
    });
  });
}
