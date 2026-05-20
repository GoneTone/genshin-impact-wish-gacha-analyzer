/// 貢獻者資料（姓名與選填連結）。
class Contributor {
  /// 建立 [Contributor]。
  const Contributor({required this.name, this.url});

  /// 顯示名稱。
  final String name;

  /// 個人頁面 URL（選填）。
  final String? url;
}

/// 專案負責人清單。
const projectLeaders = <Contributor>[
  Contributor(name: 'GoneTone', url: 'https://github.com/GoneTone'),
];

/// 測試人員清單。
const testers = <Contributor>[
  Contributor(
    name: '世界へいわ',
    url: 'https://home.gamer.com.tw/homeindex.php?owner=XMoiswnX',
  ),
  Contributor(
    name: 'Zhi',
    url: 'https://www.hoyolab.com/genshin/accountCenter/gameRecord?id=8094152',
  ),
];

/// 翻譯審核人員清單。
const translationReviewers = <Contributor>[
  Contributor(
    name: '世界へいわ',
    url: 'https://home.gamer.com.tw/homeindex.php?owner=XMoiswnX',
  ),
  Contributor(name: 'pan93412'),
  Contributor(name: 'Lemon7777'),
];

/// GitHub 貢獻者圖表頁面 URL。
const githubContributorsUrl =
    'https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/graphs/contributors';

/// Crowdin 翻譯專案 URL。
const translationCrowdinUrl =
    'https://crowdin.com/project/genshin-impact-wish-gacha-analyzer';

/// 授權條款 URL。
const licenseUrl =
    'https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/blob/master/LICENSE';
