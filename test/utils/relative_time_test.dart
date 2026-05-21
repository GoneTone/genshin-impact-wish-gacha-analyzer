import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';
import 'package:genshin_impact_wish_gacha_analyzer/utils/relative_time.dart';

Future<AppLocalizations> _loadL10n() async {
  // 用 Locale.fromSubtags 設 scriptCode，避免 'Hant' 被當成 countryCode。
  return AppLocalizations.delegate.load(
    const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  );
}

void main() {
  late AppLocalizations l;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    l = await _loadL10n();
  });

  final now = DateTime(2026, 5, 13, 14, 0, 0);

  String rt(DateTime t) => relativeTime(t, l, now: now);

  group('relativeTime', () {
    test('未來時間視為現在', () {
      expect(rt(now.add(const Duration(minutes: 5))), '現在');
    });

    test('差距小於 5 秒回傳「現在」', () {
      expect(rt(now), '現在');
      expect(rt(now.subtract(const Duration(seconds: 4))), '現在');
    });

    test('5~59 秒回傳「X 秒前」', () {
      expect(rt(now.subtract(const Duration(seconds: 5))), '5 秒前');
      expect(rt(now.subtract(const Duration(seconds: 30))), '30 秒前');
      expect(rt(now.subtract(const Duration(seconds: 59))), '59 秒前');
    });

    test('60 秒~59 分回傳「X 分鐘前」', () {
      expect(rt(now.subtract(const Duration(seconds: 60))), '1 分鐘前');
      expect(rt(now.subtract(const Duration(minutes: 30))), '30 分鐘前');
      expect(rt(now.subtract(const Duration(minutes: 59))), '59 分鐘前');
    });

    test('60 分~23 小時 59 分回傳「X 小時前」', () {
      expect(rt(now.subtract(const Duration(minutes: 60))), '1 小時前');
      expect(rt(now.subtract(const Duration(hours: 12))), '12 小時前');
      expect(
        rt(now.subtract(const Duration(hours: 23, minutes: 59))),
        '23 小時前',
      );
    });

    test('24 小時~29 天回傳「X 天前」', () {
      expect(rt(now.subtract(const Duration(days: 1))), '1 天前');
      expect(rt(now.subtract(const Duration(days: 15))), '15 天前');
      expect(rt(now.subtract(const Duration(days: 29))), '29 天前');
    });

    test('30 天~359 天回傳「X 個月前」(以 30 天/月)', () {
      expect(rt(now.subtract(const Duration(days: 30))), '1 個月前');
      expect(rt(now.subtract(const Duration(days: 90))), '3 個月前');
      expect(rt(now.subtract(const Duration(days: 359))), '11 個月前');
    });

    test('360 天以上回傳「X 年前」(以 360 天/年)', () {
      expect(rt(now.subtract(const Duration(days: 360))), '1 年前');
      expect(rt(now.subtract(const Duration(days: 364))), '1 年前');
      expect(rt(now.subtract(const Duration(days: 365))), '1 年前');
      expect(rt(now.subtract(const Duration(days: 720))), '2 年前');
      expect(rt(now.subtract(const Duration(days: 360 * 5))), '5 年前');
    });
  });

  group('formatAbsoluteDateTime / formatAbsoluteDate', () {
    test('formatAbsoluteDateTime 用 yyyy-MM-dd HH:mm', () {
      expect(
        formatAbsoluteDateTime(DateTime(2026, 5, 13, 14, 30)),
        '2026-05-13 14:30',
      );
    });

    test('formatAbsoluteDate 用 yyyy-MM-dd', () {
      expect(formatAbsoluteDate(DateTime(2026, 5, 13, 14, 30)), '2026-05-13');
    });
  });
}
