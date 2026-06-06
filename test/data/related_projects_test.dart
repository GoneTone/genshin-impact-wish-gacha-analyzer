import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/related_projects.dart';

void main() {
  group('RelatedProjects', () {
    test('wutheringWavesAnalyzer is a well-formed HTTPS GitHub URL', () {
      final uri = Uri.parse(RelatedProjects.wutheringWavesAnalyzer);
      expect(uri.scheme, 'https');
      expect(uri.host, 'github.com');
      expect(uri.pathSegments, isNotEmpty);
    });

    test('wutheringWavesAnalyzer points to the GoneTone WW analyzer repo', () {
      expect(
        RelatedProjects.wutheringWavesAnalyzer,
        contains('/GoneTone/wuthering-waves-convene-gacha-analyzer'),
      );
    });
  });
}
