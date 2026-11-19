import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/theme/layout.dart';

void main() {
  for (final (platform, size, want) in [
    (TargetPlatform.android, const Size(360, 800), true),
    (TargetPlatform.android, const Size(800, 360), true),
    (TargetPlatform.android, const Size(1280, 800), false),
    (TargetPlatform.android, const Size(600, 1000), false),
    (TargetPlatform.windows, const Size(1093, 560), false),
    (TargetPlatform.windows, const Size(500, 900), true),
    (TargetPlatform.windows, const Size(600, 450), false),
    (TargetPlatform.windows, const Size(1280, 800), false),
  ]) {
    testWidgets(
      'isCompactLayout ${platform.name} ${size.width}x${size.height} is $want',
      (tester) async {
        late bool got;
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(size: size),
            child: Builder(
              builder: (c) {
                got = isCompactLayout(c);
                return const SizedBox();
              },
            ),
          ),
        );
        expect(got, want);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  testWidgets('touching outside a text field drops its focus on phones', (
    tester,
  ) async {
    // 手機上 Flutter 預設點外部不收焦點：按返回收起鍵盤後欄位仍有焦點，
    // 之後關掉任何對話框焦點回到欄位，鍵盤又跳出來；別名欄位也因不失焦而不提交。
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        actions: appActions,
        home: Scaffold(
          body: Column(
            children: [
              TextField(focusNode: focus),
              const SizedBox(height: 300, child: Text('outside')),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focus.hasFocus, isTrue);

    await tester.tap(find.text('outside'));
    await tester.pump();
    expect(focus.hasFocus, isFalse);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
