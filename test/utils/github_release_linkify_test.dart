import 'package:flutter_test/flutter_test.dart';

import 'package:genshin_impact_wish_gacha_analyzer/utils/github_release_linkify.dart';

void main() {
  const base = 'https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer';

  group('linkifyGithubReferences — 網址型', () {
    test('PR 連結轉成 #N', () {
      expect(linkifyGithubReferences('$base/pull/70'), '[#70]($base/pull/70)');
    });

    test('Issue 連結轉成 #N', () {
      expect(
        linkifyGithubReferences('$base/issues/123'),
        '[#123]($base/issues/123)',
      );
    });

    test('compare 連結轉成比較區間', () {
      expect(
        linkifyGithubReferences('$base/compare/v1.0.0...v1.1.0'),
        '[v1.0.0...v1.1.0]($base/compare/v1.0.0...v1.1.0)',
      );
    });

    test('commit 連結轉成前 7 碼短 SHA', () {
      const sha = '0123456789abcdef0123456789abcdef01234567';
      expect(
        linkifyGithubReferences('$base/commit/$sha'),
        '[0123456]($base/commit/$sha)',
      );
    });
  });

  group('linkifyGithubReferences — @提及', () {
    test('一般使用者轉成個人頁連結', () {
      expect(
        linkifyGithubReferences('@GoneTone'),
        '[@GoneTone](https://github.com/GoneTone)',
      );
    });

    test('[bot] 後綴轉成 app 連結並保留 [bot] 顯示', () {
      expect(
        linkifyGithubReferences('@dependabot[bot]'),
        '[@dependabot[bot]](https://github.com/apps/dependabot)',
      );
    });

    test('email 樣式不被誤判為提及', () {
      expect(
        linkifyGithubReferences('contact foo@example.com please'),
        'contact foo@example.com please',
      );
    });
  });

  group('linkifyGithubReferences — 不該動的情況', () {
    test('非 GitHub 網址維持原樣', () {
      expect(
        linkifyGithubReferences('https://genshininfo.reh.tw/archives/97'),
        'https://genshininfo.reh.tw/archives/97',
      );
    });

    test('已是 markdown 連結的網址不再被包一層', () {
      expect(
        linkifyGithubReferences('[#70]($base/pull/70)'),
        '[#70]($base/pull/70)',
      );
    });

    test('autolink <url> 形式不被改寫', () {
      expect(linkifyGithubReferences('<$base/pull/70>'), '<$base/pull/70>');
    });
  });

  group('linkifyGithubReferences — 組合', () {
    test('同一行的提及與 PR 連結皆正確轉換', () {
      expect(
        linkifyGithubReferences('* feat by @GoneTone in $base/pull/70'),
        '* feat by [@GoneTone](https://github.com/GoneTone) '
        'in [#70]($base/pull/70)',
      );
    });
  });
}
