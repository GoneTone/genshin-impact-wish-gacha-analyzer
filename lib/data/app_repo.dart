/// 專案 GitHub repo 座標。集中於此檔，未來 fork 修改成其他遊戲使用時，
/// 只需改 [owner] / [repo] 兩行常數即可全專案套用。
class AppRepo {
  /// 防止外部實例化。
  const AppRepo._();

  /// GitHub 組織或個人名稱。
  static const String owner = 'GoneTone';

  /// GitHub repo 名稱。
  static const String repo = 'genshin-impact-wish-gacha-analyzer';

  /// 專案 GitHub 頁面 URL。
  static const String githubUrl = 'https://github.com/$owner/$repo';

  /// GitHub REST API base URL。
  static const String apiBase = 'https://api.github.com/repos/$owner/$repo';
}
