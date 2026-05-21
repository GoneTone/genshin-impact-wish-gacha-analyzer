/// 團隊資訊與社群連結常數。
///
/// 對齊舊版 (master) `src/store/index.js` 中的
/// configs.team / configs.app.githubUrl，從環境變數搬到 dart 常數。
class TeamInfo {
  /// 防止外部實例化。
  const TeamInfo._();

  /// 團隊顯示名稱。
  static const String name = '原神資訊站 Genshin Impact Info';

  /// 官方網站 URL。
  static const String websiteUrl = 'https://genshininfo.reh.tw/';

  /// Facebook 粉絲頁 URL。
  static const String facebookUrl = 'https://genshininfo.reh.tw/facebook';

  /// Discord 伺服器 URL。
  static const String discordUrl = 'https://genshininfo.reh.tw/discord';

  /// LINE 社群 URL。
  static const String lineUrl = 'https://genshininfo.reh.tw/line';
}
