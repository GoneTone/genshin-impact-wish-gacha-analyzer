import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/contributors.dart';

void main() {
  group('Contributor lists', () {
    test('projectLeaders 名單非空且 URL 可解析', () {
      expect(projectLeaders, isNotEmpty);
      for (final c in projectLeaders) {
        expect(c.name, isNotEmpty);
        if (c.url != null) {
          final uri = Uri.tryParse(c.url!);
          expect(uri, isNotNull, reason: '${c.name} URL 無法解析');
          expect(uri!.scheme, anyOf('http', 'https'));
        }
      }
    });

    test('testers 名單非空且 URL 可解析', () {
      expect(testers, isNotEmpty);
      for (final c in testers) {
        expect(c.name, isNotEmpty);
        if (c.url != null) {
          final uri = Uri.tryParse(c.url!);
          expect(uri, isNotNull);
          expect(uri!.scheme, anyOf('http', 'https'));
        }
      }
    });

    test('translationReviewers 名單非空且 URL 可解析', () {
      expect(translationReviewers, isNotEmpty);
      for (final c in translationReviewers) {
        expect(c.name, isNotEmpty);
        if (c.url != null) {
          final uri = Uri.tryParse(c.url!);
          expect(uri, isNotNull);
          expect(uri!.scheme, anyOf('http', 'https'));
        }
      }
    });
  });

  group('External URLs', () {
    test('githubContributorsUrl 是 https URL', () {
      final uri = Uri.parse(githubContributorsUrl);
      expect(uri.scheme, 'https');
      expect(uri.host, contains('github.com'));
    });

    test('translationCrowdinUrl 是 https URL', () {
      final uri = Uri.parse(translationCrowdinUrl);
      expect(uri.scheme, 'https');
      expect(uri.host, contains('crowdin.com'));
    });

    test('licenseUrl 是 https URL', () {
      final uri = Uri.parse(licenseUrl);
      expect(uri.scheme, 'https');
      expect(uri.host, contains('github.com'));
    });
  });
}
