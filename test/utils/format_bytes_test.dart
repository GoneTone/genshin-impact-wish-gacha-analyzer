import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/utils/format_bytes.dart';

void main() {
  group('formatBytes', () {
    test('0 bytes → 0.0 KB', () {
      expect(formatBytes(0), '0.0 KB');
    });

    test('1023 bytes 仍顯示 KB（1024 為 1 KB 閾值）', () {
      expect(formatBytes(1023), '1.0 KB');
    });

    test('1024 bytes → 1.0 KB', () {
      expect(formatBytes(1024), '1.0 KB');
    });

    test('1 MB - 1 byte → 1024.0 KB（未跨進 MB）', () {
      expect(formatBytes(1024 * 1024 - 1), '1024.0 KB');
    });

    test('1 MB → 1.0 MB', () {
      expect(formatBytes(1024 * 1024), '1.0 MB');
    });

    test('123.4 MB（驗 1 位小數四捨五入）', () {
      expect(formatBytes((123.4 * 1024 * 1024).round()), '123.4 MB');
    });

    test('1 GB - 1 byte 仍顯示 MB', () {
      expect(formatBytes(1024 * 1024 * 1024 - 1), '1024.0 MB');
    });

    test('1 GB → 1.0 GB', () {
      expect(formatBytes(1024 * 1024 * 1024), '1.0 GB');
    });

    test('2.5 GB', () {
      expect(formatBytes((2.5 * 1024 * 1024 * 1024).round()), '2.5 GB');
    });
  });
}
