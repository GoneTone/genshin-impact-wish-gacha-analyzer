import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/l10n/generated/app_localizations.dart';

/// 帶「數量 + 名詞」的字串，以同一個數量 [n] 呼叫（多參數的字串全部填 [n]）。
final Map<String, String Function(AppLocalizations l, int n)> _probes = {
  'relativeDaysAgo': (l, n) => l.relativeDaysAgo(n),
  'progressDoneSummary': (l, n) => l.progressDoneSummary(n),
  'pityDistance': (l, n) => l.pityDistance(n),
  'timelineSinceLast': (l, n) => l.timelineSinceLast(n),
  'accountRecordCount': (l, n) => l.accountRecordCount(n),
  'importTargetAccountRecordCount': (l, n) =>
      l.importTargetAccountRecordCount(n),
  'settingsImportConfirmIntro': (l, n) => l.settingsImportConfirmIntro(n, n),
  'pagerJumpCurrent': (l, n) => l.pagerJumpCurrent(7, n),
};

/// 把數字遮掉，只比較數字以外的詞形。
String _shape(String s, int n) => s.replaceAll('$n', '#');

/// 取得 [locale] 的字串實例。
AppLocalizations _l(String locale) {
  final parts = locale.split('_');
  return lookupAppLocalizations(
    Locale(parts[0], parts.length > 1 ? parts[1] : null),
  );
}

void main() {
  /// 單複數有不同詞形的語言（`=1` 與 `other`）。
  const pluralLocales = ['en', 'es', 'pt_BR', 'fr'];

  /// 沒有單複數之分的語言：1 和 2 的詞形必須相同。
  const invariantLocales = ['zh', 'zh_Hans', 'ja', 'th', 'vi'];

  for (final locale in pluralLocales) {
    for (final entry in _probes.entries) {
      test('$locale ${entry.key}: 1 與 2 詞形不同', () {
        final l = _l(locale);
        expect(
          _shape(entry.value(l, 1), 1),
          isNot(_shape(entry.value(l, 2), 2)),
        );
      });
    }
  }

  for (final locale in invariantLocales) {
    for (final entry in _probes.entries) {
      test('$locale ${entry.key}: 1 與 2 詞形相同', () {
        final l = _l(locale);
        expect(_shape(entry.value(l, 1), 1), _shape(entry.value(l, 2), 2));
      });
    }
  }

  test('en 單數不出現複數名詞', () {
    final l = _l('en');
    expect(l.pityDistance(1), '1 pull until guaranteed');
    expect(l.timelineSinceLast(1), '1 pull');
    expect(l.relativeDaysAgo(1), '1 day ago');
    expect(l.accountRecordCount(1), '1 record');
    expect(
      l.settingsImportConfirmIntro(1, 1),
      'About to import 1 account (1 record total):',
    );
    expect(l.pityDistance(2), '2 pulls until guaranteed');
    expect(l.relativeDaysAgo(2), '2 days ago');
  });

  test('fr 0 與 1 都用單數', () {
    final l = _l('fr');
    for (final entry in _probes.entries) {
      expect(
        _shape(entry.value(l, 0), 0),
        _shape(entry.value(l, 1), 1),
        reason: entry.key,
      );
    }
    expect(l.accountRecordCount(0), '0 enregistrement');
    expect(l.accountRecordCount(2), '2 enregistrements');
  });

  test('pt、pt_BR 的 0 落在 one 分支，仍要顯示 0 而不是字面 1', () {
    for (final locale in ['pt', 'pt_BR']) {
      final l = _l(locale);
      expect(l.accountRecordCount(0), startsWith('0 '), reason: locale);
      expect(l.progressDoneSummary(0), contains('0'), reason: locale);
      expect(l.progressDoneSummary(0), isNot(contains('1')), reason: locale);
      expect(l.timelineSinceLast(0), startsWith('0 '), reason: locale);
    }
  });

  test('ru 依 one／few／many 變化：21 與 1 同形，2 與 5 不同形', () {
    final l = _l('ru');
    for (final entry in _probes.entries) {
      String shape(int n) => _shape(entry.value(l, n), n);
      expect(shape(21), shape(1), reason: '${entry.key} 21 同 one');
    }
    // 部分字串兩個數量用同一個詞形（如「аккаунтов — #」），所以只要求至少一個字串能分辨。
    bool someProbeDiffers(int a, int b) => _probes.values.any(
      (probe) => _shape(probe(l, a), a) != _shape(probe(l, b), b),
    );
    expect(someProbeDiffers(2, 1), isTrue);
    expect(someProbeDiffers(5, 2), isTrue);
    expect(l.accountRecordCount(1), '1 запись');
    expect(l.accountRecordCount(2), '2 записи');
    expect(l.accountRecordCount(5), '5 записей');
    expect(l.accountRecordCount(21), '21 запись');
  });

  test('ar 在 2 時用 two 詞形，與 1、3 都不同', () {
    final l = _l('ar');
    for (final entry in _probes.entries) {
      String shape(int n) => _shape(entry.value(l, n), n);
      expect(shape(2), isNot(shape(1)), reason: '${entry.key} two 異於 one');
      expect(shape(2), isNot(shape(3)), reason: '${entry.key} two 異於 few');
    }
    expect(l.accountRecordCount(2), 'سجلان');
  });

  test('de 在 1 時用單數，與 2 不同', () {
    final l = _l('de');
    expect(l.accountRecordCount(1), '1 Eintrag');
    expect(l.accountRecordCount(2), '2 Einträge');
    expect(l.pityDistance(1), 'Noch 1 Ziehung bis zur Garantie');
    expect(l.pityDistance(2), 'Noch 2 Ziehungen bis zur Garantie');
  });
}
