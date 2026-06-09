import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/gacha_record.dart';

GachaRecord _r(String id, {String lang = 'zh-tw'}) => GachaRecord(
  id: id,
  uid: '100000001',
  gachaType: '301',
  name: 'x',
  itemType: '武器',
  rankType: 3,
  time: DateTime.utc(2025, 1, 1),
  lang: lang,
);

BannerStorage _s(
  Map<String, List<GachaRecord>> banners, {
  DateTime? lastUpdated,
}) => BannerStorage(
  uid: '100000001',
  lastUpdated: lastUpdated ?? DateTime.utc(2026, 1, 1),
  banners: banners,
);

void main() {
  test('union by id, dedup, sorted desc', () {
    final local = _s({
      '301': [_r('3'), _r('1')],
    });
    final incoming = _s({
      '301': [_r('2'), _r('1')],
    });
    final merged = local.mergeWith(incoming);
    expect(merged.banners['301']!.map((r) => r.id).toList(), ['3', '2', '1']);
  });

  test('banner keys are unioned', () {
    final local = _s({
      '301': [_r('1')],
    });
    final incoming = _s({
      '302': [_r('2')],
    });
    final merged = local.mergeWith(incoming);
    expect(merged.banners.keys.toSet(), {'301', '302'});
    expect(merged.banners['301']!.single.id, '1');
    expect(merged.banners['302']!.single.id, '2');
  });

  test('lastUpdated takes the newer of the two', () {
    final local = _s({'301': []}, lastUpdated: DateTime.utc(2026, 1, 1));
    final incoming = _s({'301': []}, lastUpdated: DateTime.utc(2026, 5, 12));
    expect(local.mergeWith(incoming).lastUpdated, DateTime.utc(2026, 5, 12));
    expect(incoming.mergeWith(local).lastUpdated, DateTime.utc(2026, 5, 12));
  });

  test('same id: keep local, but backfill empty local lang from incoming', () {
    final local = _s({
      '301': [_r('1', lang: '')],
    });
    final incoming = _s({
      '301': [_r('1', lang: 'en-us')],
    });
    final merged = local.mergeWith(incoming);
    expect(merged.banners['301']!.single.lang, 'en-us');
  });

  test('same id: non-empty local lang is NOT overwritten by incoming', () {
    final local = _s({
      '301': [_r('1', lang: 'zh-tw')],
    });
    final incoming = _s({
      '301': [_r('1', lang: 'en-us')],
    });
    final merged = local.mergeWith(incoming);
    expect(merged.banners['301']!.single.lang, 'zh-tw');
  });

  test('empty local merges to incoming content', () {
    final local = _s({});
    final incoming = _s({
      '301': [_r('2'), _r('1')],
    });
    final merged = local.mergeWith(incoming);
    expect(merged.banners['301']!.map((r) => r.id).toList(), ['2', '1']);
  });
}
