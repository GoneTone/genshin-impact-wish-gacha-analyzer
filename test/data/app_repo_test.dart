// test/data/app_repo_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/data/app_repo.dart';

void main() {
  group('AppRepo', () {
    test('owner 與 repo 非空', () {
      expect(AppRepo.owner, isNotEmpty);
      expect(AppRepo.repo, isNotEmpty);
    });

    test('githubUrl 由 owner / repo 組成且指向 github.com', () {
      final uri = Uri.parse(AppRepo.githubUrl);
      expect(uri.scheme, 'https');
      expect(uri.host, 'github.com');
      expect(AppRepo.githubUrl, contains('/${AppRepo.owner}/${AppRepo.repo}'));
    });

    test('apiBase 指向 api.github.com 並含 repos path', () {
      final uri = Uri.parse(AppRepo.apiBase);
      expect(uri.scheme, 'https');
      expect(uri.host, 'api.github.com');
      expect(
        AppRepo.apiBase,
        contains('/repos/${AppRepo.owner}/${AppRepo.repo}'),
      );
    });
  });
}
