// lib/data/app_repo.dart
//
// 專案 GitHub repo 座標。集中於此檔，未來 fork 修改成其他遊戲使用時，
// 只需改 owner / repo 兩行常數即可全專案套用。

class AppRepo {
  const AppRepo._();

  static const String owner = 'GoneTone';
  static const String repo = 'genshin-impact-wish-gacha-analyzer';
  static const String githubUrl = 'https://github.com/$owner/$repo';
  static const String apiBase = 'https://api.github.com/repos/$owner/$repo';
}
