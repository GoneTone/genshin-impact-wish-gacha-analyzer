import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/android_version_code.dart';

void main() {
  test('release tags', () {
    expect(androidVersionCodeForTag('v1.8.1'), 1080199);
    expect(androidVersionCodeForTag('v1.9.0'), 1090099);
  });
  test('rc tags sort below the release', () {
    expect(androidVersionCodeForTag('v1.9.0-rc.2'), 1090002);
    expect(
      androidVersionCodeForTag('v1.9.0-rc.2'),
      lessThan(androidVersionCodeForTag('v1.9.0')),
    );
  });
  test('invalid tags throw', () {
    for (final t in [
      '1.9.0',
      'v1.9',
      'v1.9.0-beta.1',
      'v1.9.0-rc.0',
      'v1.9.0-rc.99',
      'v1.100.0',
      'v1.0.100',
      'v0.9.0',
      'v01.9.0',
      'v1.09.0',
      'v1.9.00',
      'v1.9.0-rc.02',
      'v2100.0.0',
      'v99999999999999999999999.0.0',
    ]) {
      expect(
        () => androidVersionCodeForTag(t),
        throwsFormatException,
        reason: t,
      );
    }
  });
  test("largest major still fits Play's versionCode limit", () {
    expect(androidVersionCodeForTag('v2099.99.99'), 2099999999);
  });
  test('overflowing digits give a clear message', () {
    expect(
      () => androidVersionCodeForTag('v99999999999999999999999.0.0'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          'Release tag out of range',
        ),
      ),
    );
  });
  test('reverse mapping', () {
    expect(tagForAndroidVersionCode(1080199), 'v1.8.1');
    expect(tagForAndroidVersionCode(1090002), 'v1.9.0-rc.2');
    expect(tagForAndroidVersionCode(17), isNull);
    expect(tagForAndroidVersionCode(1080100), isNull);
  });
  test('round trip', () {
    for (final t in [
      'v1.0.0',
      'v1.9.0',
      'v12.99.99',
      'v1.9.0-rc.1',
      'v2.3.4-rc.98',
    ]) {
      expect(tagForAndroidVersionCode(androidVersionCodeForTag(t)), t);
    }
  });
}
