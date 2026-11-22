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
}
