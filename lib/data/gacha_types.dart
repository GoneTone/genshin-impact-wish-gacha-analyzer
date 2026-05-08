class GachaType {
  const GachaType({required this.gachaType, required this.name});

  /// 對應 getGachaLog API 的 query string `gacha_type=...`，String 型別跟 query 對齊。
  final String gachaType;

  /// UI 顯示用中文名稱。
  final String name;
}

// TODO: name 欄位後續 i18n 改用 translation key；目前 hardcode 中文。
const gachaTypes = <GachaType>[
  GachaType(gachaType: '301', name: '角色活動祈願'),
  GachaType(gachaType: '302', name: '武器活動祈願'),
  GachaType(gachaType: '500', name: '集錄祈願'),
  GachaType(gachaType: '200', name: '常駐祈願'),
  GachaType(gachaType: '100', name: '新手祈願'),
];
