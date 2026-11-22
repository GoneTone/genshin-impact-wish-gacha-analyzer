import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/android/app_prefs_platform.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/settings_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/localization_metadata.dart';

void main() {
  const configPath = 'android/app/src/main/res/xml/locales_config.xml';

  // 系統設定「應用程式語言」的清單是寫死的 XML，App 內則是翻譯釋出後才開放；
  // 新語言釋出（或下架）時這裡會失敗，照訊息更新 XML。
  test('Android locales_config.xml lists exactly the released locales', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final expected = [
      for (final locale in container.read(releasedLocalesProvider))
        systemLocaleTagOf(LocaleLanguage(locale.toLanguageTag())),
    ]..sort();

    final xml = File(configPath).readAsStringSync();
    final actual = [
      for (final m in RegExp(r'android:name="([^"]+)"').allMatches(xml))
        m.group(1)!,
    ]..sort();

    expect(
      actual,
      expected,
      reason:
          'Update $configPath to:\n'
          '${expected.map((t) => '    <locale android:name="$t" />').join('\n')}',
    );
  });

  // 啟動器名稱與配對通知走 Android 原生字串，不在 ARB 裡；少了某語言就會顯示英文。
  test('every listed locale has Android strings with the same names', () {
    const res = 'android/app/src/main/res';
    String stringsOf(String dir) =>
        File('$res/$dir/strings.xml').readAsStringSync();
    Set<String> namesIn(String dir) => {
      for (final m in RegExp(
        r'<string name="([^"]+)"',
      ).allMatches(stringsOf(dir)))
        m.group(1)!,
    };
    final expected = namesIn('values');
    final xml = File(configPath).readAsStringSync();
    for (final m in RegExp(r'android:name="([^"]+)"').allMatches(xml)) {
      final dir = switch (m.group(1)!) {
        'en' => 'values',
        'zh-Hant' => 'values-zh-rTW',
        'zh-Hans' => 'values-zh-rCN',
        'pt-BR' => 'values-pt-rBR',
        // Android 比對資源時會把語言代碼轉成舊式（he → iw），values-he 對不到。
        'he' => 'values-iw',
        final tag => 'values-$tag',
      };
      expect(
        File('$res/$dir/strings.xml').existsSync(),
        isTrue,
        reason: 'missing $res/$dir/strings.xml',
      );
      expect(namesIn(dir), expected, reason: dir);
      // aapt2 不接受未跳脫的引號；字串內容裡的 ' 與 " 前面都要有 \。
      for (final s in RegExp(
        r'<string name="[^"]+">(.*?)</string>',
      ).allMatches(stringsOf(dir))) {
        expect(
          RegExp(r"""(?<!\\)['"]""").hasMatch(s.group(1)!),
          isFalse,
          reason: '$dir has an unescaped quote: ${s.group(1)}',
        );
      }
    }
  });
}
