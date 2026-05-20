import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/team_info.dart';

void main() {
  group('TeamInfo constants', () {
    test('name 非空', () {
      expect(TeamInfo.name, isNotEmpty);
    });

    test('websiteUrl 是 https URL', () {
      final uri = Uri.parse(TeamInfo.websiteUrl);
      expect(uri.scheme, 'https');
      expect(uri.host, isNotEmpty);
    });

    test('facebookUrl 是 https URL', () {
      final uri = Uri.parse(TeamInfo.facebookUrl);
      expect(uri.scheme, 'https');
      expect(uri.host, isNotEmpty);
    });

    test('discordUrl 是 https URL', () {
      final uri = Uri.parse(TeamInfo.discordUrl);
      expect(uri.scheme, 'https');
      expect(uri.host, isNotEmpty);
    });

    test('lineUrl 是 https URL', () {
      final uri = Uri.parse(TeamInfo.lineUrl);
      expect(uri.scheme, 'https');
      expect(uri.host, isNotEmpty);
    });
  });
}
