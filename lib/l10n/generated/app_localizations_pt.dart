// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get localeNativeName => 'Português';

  @override
  String get localeTranslator => 'Mirusausiliq & Boemio';

  @override
  String get appName => 'O analisador de gacha de Genshin Impact';

  @override
  String get actionUpdate => '更新資料';

  @override
  String get actionCancel => '取消';

  @override
  String get actionClose => '關閉';

  @override
  String get actionPrevPage => 'A página anterior';

  @override
  String get actionNextPage => 'A próxima página';

  @override
  String get navOverview => '綜合';

  @override
  String get navCharacter => 'O personangem';

  @override
  String get navWeapon => 'A arma';

  @override
  String get navChronicled => '集錄';

  @override
  String get navStandard => '常駐';

  @override
  String get navBeginner => '新手';

  @override
  String get navSettings => '設定';

  @override
  String get gachaTypeCharacter => '角色活動祈願';

  @override
  String get gachaTypeWeapon => '武器活動祈願';

  @override
  String get gachaTypeChronicled => '集錄祈願';

  @override
  String get gachaTypeStandard => '常駐祈願';

  @override
  String get gachaTypeBeginner => '新手祈願';

  @override
  String get footerNotSynced => '尚未同步';

  @override
  String footerLastUpdated(String time) {
    return '最後更新：$time';
  }

  @override
  String get uidSwitchTooltip => '切換帳號';

  @override
  String get uidNotSynced => '未同步';

  @override
  String get uidActiveSuffix => '（活躍）';

  @override
  String get uidRecapture => '新增帳號';

  @override
  String get emptyNoSyncTitle => '尚未同步任何資料';

  @override
  String get emptyNoSyncMessage => '點右上「更新資料」開始';

  @override
  String get emptyNoRecords => '此卡池無紀錄';

  @override
  String get emptyNoFiltered => '沒有符合條件的紀錄';

  @override
  String get statsTotal => '總抽數';

  @override
  String get statsFiveStarCount => 'O número de ganhar um 5 estrelas';

  @override
  String get statsFourStarCount => 'A quantidade ganha de um 4 estrelas';

  @override
  String statsShareOfTotal(String rate) {
    return '佔總抽 $rate%';
  }

  @override
  String get statsRarityDistribution => '稀有度分布';

  @override
  String get statsItemTypeDistribution => '類型分布';

  @override
  String get statsNoData => '無資料';

  @override
  String get kindCharacter => 'O personangem';

  @override
  String get kindWeapon => 'A arma';

  @override
  String get kindUnknown => '未知';

  @override
  String get tableTime => '時間';

  @override
  String get tableName => 'O nome';

  @override
  String get tableKind => 'tipo';

  @override
  String get tableRarity => '稀有度';

  @override
  String get tableTotalIndex => '總抽數';

  @override
  String get tableFiveStarPity => '保底內';

  @override
  String get tableFiveStarPityTooltip => '距上一次 5★ 的抽數';

  @override
  String get sortDirectionDesc => '降序';

  @override
  String get sortDirectionAsc => '升序';

  @override
  String get sortDirectionNone => '點擊排序';

  @override
  String get progressPreparing => '準備中…';

  @override
  String get progressPreparingHint => '正在準備資料來源…';

  @override
  String get progressWaiting => '等待攔截…';

  @override
  String get progressFetching => '抓取中…';

  @override
  String get progressDone => '更新完成';

  @override
  String get progressFailed => '失敗';

  @override
  String get progressOpenGameHint => '請開啟原神 → 卡池 → 歷史紀錄';

  @override
  String get progressFallbackHint => '（先前的認證已失效，需重新攔截）';

  @override
  String progressFetchingBanner(String name) {
    return '正在抓取：$name';
  }

  @override
  String progressPageStatus(int page, int count) {
    return '第 $page 頁，已新增 $count 筆';
  }

  @override
  String progressDoneSummary(int count) {
    return '新增 $count 筆紀錄';
  }

  @override
  String progressPartialFailed(String names) {
    return '⚠ 部分失敗：$names';
  }

  @override
  String get errorAuthExpired => '認證持續失效，請重新登入遊戲';

  @override
  String get errorRateLimited => '請求過於頻繁，請稍後再試';

  @override
  String errorServer(String message) {
    return '伺服器錯誤：$message';
  }

  @override
  String get errorNoRecords => '此帳號尚無任何卡池紀錄';

  @override
  String get pageOverviewTitle => '綜合數據（全卡池合計）';

  @override
  String get pageBannerRecordList => '紀錄列表';

  @override
  String get settingsTitle => '設定';

  @override
  String get settingsAppearance => '外觀';

  @override
  String get settingsTheme => '主題';

  @override
  String get settingsThemeSystem => '跟隨系統';

  @override
  String get settingsThemeDark => '深色';

  @override
  String get settingsThemeLight => '淺色';

  @override
  String get settingsLanguage => '語言';

  @override
  String get settingsLocaleSystem => '跟隨系統';

  @override
  String get settingsDataManagement => '資料管理';

  @override
  String get settingsAccountManagement => '帳號管理';

  @override
  String get settingsAbout => 'Cerca de';

  @override
  String settingsAboutVersion(String version) {
    return '版本 $version';
  }

  @override
  String get settingsPlaceholderPhase2 => '（即將推出）';

  @override
  String get pityFiveStar => '5★ 保底';

  @override
  String get pityFourStar => '4★ 保底';

  @override
  String pityCurrent(int current, int threshold) {
    return '$current / $threshold';
  }

  @override
  String pityDistance(int n) {
    return '距下次保底 $n 抽';
  }

  @override
  String pityClose(int n) {
    return '快保底了！剩餘 $n 抽';
  }

  @override
  String get pityGuaranteed => '保底中';

  @override
  String get pityNoFiveStar => '暫無 5★';

  @override
  String get pityBeginnerEnded => '已結束';

  @override
  String get timelineNoRecords => '暫無 5★ 紀錄';

  @override
  String timelineSinceLast(int n) {
    return '$n 抽';
  }

  @override
  String get timelineNowLabel => '現在';

  @override
  String timelineNowPulls(int n) {
    return '已 $n 抽';
  }

  @override
  String timelineNowSinceLast(int n) {
    return '距上次 5★ $n 抽';
  }

  @override
  String timelineNowSinceCrossPool(int n) {
    return '從上次 5★ 至今 $n 抽';
  }

  @override
  String timelineMonthLabel(String year, String month) {
    return '$year / $month';
  }

  @override
  String get filterRarityAll => '全部稀有度';

  @override
  String get filterRarityFiveStar => '只看 5★';

  @override
  String get filterRarityFourStar => '只看 4★';

  @override
  String get filterKindAll => '全部類型';

  @override
  String get filterKindCharacter => '只看角色';

  @override
  String get filterKindWeapon => '只看武器';

  @override
  String get filterSearchHint => '搜尋名稱…';

  @override
  String get filterClear => '清除篩選';

  @override
  String get pagerFirst => '首頁';

  @override
  String get pagerLast => '末頁';

  @override
  String get settingsExportJson => '匯出 JSON';

  @override
  String get settingsExportCsv => '匯出 CSV';

  @override
  String get settingsImportJson => '匯入 JSON';

  @override
  String get settingsClearActive => '清除目前帳號資料';

  @override
  String get settingsClearAll => '清除所有資料';

  @override
  String settingsExportSuccess(String path) {
    return '已匯出至 $path';
  }

  @override
  String settingsImportSuccess(String uid, int count) {
    return '成功匯入 UID $uid 的 $count 筆紀錄';
  }

  @override
  String settingsImportFailed(String reason) {
    return '匯入失敗：$reason';
  }

  @override
  String get confirmTitle => '確認操作';

  @override
  String confirmClearActiveBody(String uid) {
    return '這會永久刪除 UID $uid 的所有祈願紀錄。輸入 UID 確認：';
  }

  @override
  String get confirmClearAllBody => '這會永久刪除所有帳號的祈願紀錄。輸入 DELETE 確認：';

  @override
  String get confirmTypeMismatch => '輸入不符，操作已取消';

  @override
  String get confirmCancel => '取消';

  @override
  String get confirmDelete => '刪除';

  @override
  String get accountListEmpty => '目前沒有任何帳號';

  @override
  String accountLastUpdated(String time) {
    return '最後更新 $time';
  }

  @override
  String get accountActiveTag => '活躍';

  @override
  String get accountSetActive => '設為活躍';

  @override
  String get accountRemove => '移除';

  @override
  String get accountRecapture => '新增帳號';

  @override
  String get accountAliasLabel => '別名';

  @override
  String get accountAliasHint => '為此帳號取一個好記的名稱';

  @override
  String get accountDragHandleTooltip => '拖曳排序';

  @override
  String get loadingBootstrap => '載入中…';

  @override
  String timelineCountFiveStar(int n) {
    return '5★ 時間軸 ($n)';
  }

  @override
  String get bannerFiveStarCountTitle => '各卡池 5★ 件數';

  @override
  String bannerFiveStarPullsSinceLast(int n) {
    return '距上次 5★ $n 抽';
  }
}
