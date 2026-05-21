import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

void main() {
  group('AppLocalizations.rarityStar', () {
    test('zh / en / zh_Hans 為 {rank}★ 順序', () async {
      final zh = await AppLocalizations.delegate.load(const Locale('zh'));
      expect(zh.rarityStar(5), '5★');
      expect(zh.rarityStar(2), '2★');

      final en = await AppLocalizations.delegate.load(const Locale('en'));
      expect(en.rarityStar(4), '4★');

      final hans = await AppLocalizations.delegate.load(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      );
      expect(hans.rarityStar(3), '3★');
    });

    test('ja 為 ★{rank} 順序', () async {
      final ja = await AppLocalizations.delegate.load(const Locale('ja'));
      expect(ja.rarityStar(5), '★5');
      expect(ja.rarityStar(4), '★4');
      expect(ja.rarityStar(3), '★3');
      expect(ja.rarityStar(2), '★2');
    });
  });
}
