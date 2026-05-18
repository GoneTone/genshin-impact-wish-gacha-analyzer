import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/share_image_options.dart';
import 'package:genshin_impact_wish_gacha_analyzer/theme/app_theme.dart';
import 'package:genshin_impact_wish_gacha_analyzer/widgets/share/share_card.dart';

Future<ui.Image> _img() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 4, 4),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  return recorder.endRecording().toImage(4, 4);
}

GachaRecord _r(String gt, int rank, String name) => GachaRecord(
  id: '$name$rank${gt}_${DateTime.now().microsecondsSinceEpoch}',
  uid: '800123456',
  gachaType: gt,
  name: name,
  itemType: rank == 5 ? '角色' : '武器',
  rankType: rank,
  time: DateTime(2026, 5, 10, 12),
  lang: 'zh-tw',
);

Future<void> _pump(WidgetTester t, Widget card) async {
  await t.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(
        body: SingleChildScrollView(child: SizedBox(width: 1200, child: card)),
      ),
    ),
  );
  await t.pump();
}

void main() {
  testWidgets('卡池模式渲染且無 overflow（遮罩 UID）', (t) async {
    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    final card = ShareCard.banner(
      l: l,
      appVersion: '1.0.0',
      appIcon: await _img(),
      options: const ShareImageOptions(),
      uid: '800123456',
      updatedAt: DateTime(2026, 5, 18, 14, 30),
      title: '角色活動祈願',
      records: [_r('301', 5, '那維萊特'), _r('301', 4, '菲謝爾'), _r('301', 3, '冷刃')],
      targetRank: 5,
    );
    await _pump(t, card);
    expect(t.takeException(), isNull);
    expect(find.textContaining('800xxxxxx'), findsOneWidget);
    expect(find.textContaining('800123456'), findsNothing);
  });

  testWidgets('頂部 stat 為水平橫排（三張同一橫列）', (t) async {
    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    final card = ShareCard.banner(
      l: l,
      appVersion: '1.0.0',
      appIcon: await _img(),
      options: const ShareImageOptions(),
      uid: '800123456',
      updatedAt: DateTime(2026, 5, 18, 14, 30),
      title: '角色活動祈願',
      records: [_r('301', 5, '那維萊特'), _r('301', 4, '菲謝爾'), _r('301', 3, '冷刃')],
      targetRank: 5,
    );
    await _pump(t, card);
    expect(t.takeException(), isNull);

    // 結構斷言：stat 橫排 Row 帶 Key('shareStatRow')。
    final statRow = find.byKey(const Key('shareStatRow'));
    expect(statRow, findsOneWidget);

    // 版面斷言：三個 stat label（總計 / 5★ / 4★）位於同一橫列，
    // y 座標相近（同列），且 x 座標遞增（左→右排列）。
    final labels = <Finder>[
      find.text(l.statsTotal),
      find.text(l.statsRankCount(l.rarityStar(5))),
      find.text(l.statsRankCount(l.rarityStar(4))),
    ];
    final tops = labels
        .map((f) => t.getTopLeft(f.first).dy)
        .toList(growable: false);
    final lefts = labels
        .map((f) => t.getTopLeft(f.first).dx)
        .toList(growable: false);
    expect((tops[0] - tops[1]).abs(), lessThan(2));
    expect((tops[1] - tops[2]).abs(), lessThan(2));
    expect(lefts[0], lessThan(lefts[1]));
    expect(lefts[1], lessThan(lefts[2]));
  });

  testWidgets('綜合模式：祈願 + 頌願兩段，showFullUid', (t) async {
    final l = await AppLocalizations.delegate.load(const Locale('zh'));
    final card = ShareCard.overview(
      l: l,
      appVersion: '1.0.0',
      appIcon: await _img(),
      options: const ShareImageOptions(showFullUid: true),
      uid: '800123456',
      updatedAt: DateTime(2026, 5, 18, 14, 30),
      banners: {
        '301': [_r('301', 5, '那維萊特'), _r('301', 3, '冷刃')],
        '2000': [_r('2000', 5, '某五星')],
      },
    );
    await _pump(t, card);
    expect(t.takeException(), isNull);
    expect(find.textContaining('800123456'), findsOneWidget);
  });
}
