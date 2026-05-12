// lib/data/contributors.dart

class Contributor {
  const Contributor({required this.name, this.url});
  final String name;
  final String? url;
}

const projectLeaders = <Contributor>[
  Contributor(name: 'GoneTone', url: 'https://github.com/GoneTone'),
];

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

const translationReviewers = <Contributor>[
  Contributor(
    name: '世界へいわ',
    url: 'https://home.gamer.com.tw/homeindex.php?owner=XMoiswnX',
  ),
  Contributor(name: 'pan93412'),
  Contributor(name: 'Lemon7777'),
];

const githubContributorsUrl =
    'https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/graphs/contributors';
const translationCrowdinUrl =
    'https://crowdin.com/project/genshin-impact-wish-gacha-analyzer';
const licenseUrl =
    'https://github.com/GoneTone/genshin-impact-wish-gacha-analyzer/blob/master/LICENSE';
