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

    testWidgets('無 alias:只渲染 UID 主標(沒有副標)', (tester) async {
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
}
