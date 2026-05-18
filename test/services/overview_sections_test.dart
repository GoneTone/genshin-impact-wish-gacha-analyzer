import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/overview_sections.dart';

GachaRecord _r(String gt, int rank, String name, DateTime t) => GachaRecord(
  id: '${name}_${t.microsecondsSinceEpoch}',
  uid: '123456789',
  gachaType: gt,
  name: name,
  itemType: rank == 5 ? '角色' : '武器',
  rankType: rank,
  time: t,
  lang: 'zh-tw',
);

void main() {
  test('buildOverviewSections 切出祈願與頌願兩段、統計正確', () {
    final t = DateTime(2026, 5, 1);
    final activeBanners = <String, List<GachaRecord>>{
      '301': [_r('301', 5, '那維萊特', t), _r('301', 3, '冷刃', t)],
      '2000': [_r('2000', 5, '某五星', t)],
    };

    final sections = buildOverviewSections(activeBanners);

    expect(sections.gacha.stats.total, 2);
    expect(sections.gacha.stats.fiveStarCount, 1);
    expect(sections.gacha.timeline.length, 1);
    expect(sections.odes.stats.total, 1);
    expect(sections.odes.eventFiveCount, 1);
  });

  test('buildOverviewSections 空輸入不拋例外、各欄位回傳零值', () {
    final sections = buildOverviewSections(const <String, List<GachaRecord>>{});

    expect(sections.gacha.stats.total, 0);
    expect(sections.odes.stats.total, 0);
    expect(sections.gacha.fiveStarAvg, isNull);
    expect(sections.odes.eventFiveCount, 0);
    expect(sections.odes.standardFourCount, 0);
    expect(sections.gacha.timeline, isEmpty);
    expect(sections.odes.timeline, isEmpty);
  });

  test('buildOverviewSections 僅頌願輸入：祈願 total=0，odes eventFiveCount=1', () {
    final t = DateTime(2026, 5, 1);
    final activeBanners = <String, List<GachaRecord>>{
      '2000': [_r('2000', 5, '某頌願五星', t)],
    };

    final sections = buildOverviewSections(activeBanners);

    expect(sections.gacha.stats.total, 0);
    expect(sections.odes.eventFiveCount, 1);
  });
}
