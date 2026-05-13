// lib/data/team_info.dart
//
// 團隊資訊與社群連結常數。對齊舊版 (master) `src/store/index.js` 中的
// configs.team / configs.app.githubUrl，從環境變數搬到 dart 常數。

class TeamInfo {
  const TeamInfo._();

  static const String name = '原神資訊站 Genshin Impact Info';
  static const String websiteUrl = 'https://genshininfo.reh.tw/';
  static const String facebookUrl = 'https://genshininfo.reh.tw/facebook';
  static const String discordUrl = 'https://genshininfo.reh.tw/discord';
  static const String lineUrl = 'https://genshininfo.reh.tw/line';
}

/// 專案 GitHub repo。對齊 master `configs.app.githubUrl`（屬於 app 而非 team）。
const String appGithubUrl =
    'https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer';
