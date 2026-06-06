import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/data/related_projects.dart';

void main() {
  test(
    'wutheringWavesAnalyzer points to the WW convene gacha analyzer repo',
    () {
      expect(
        RelatedProjects.wutheringWavesAnalyzer,
        'https://github.com/GoneTone/wuthering-waves-convene-gacha-analyzer',
      );
    },
  );
}
