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
  String get navContributors => '貢獻者';

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
  String get gachaTypeOdesEvent => '活動頌願';

  @override
  String get gachaTypeOdesStandard => '常駐頌願';

  @override
  String get navOdesEvent => '活動頌願';

  @override
  String get navOdesStandard => '常駐頌願';

  @override
  String get navSectionWish => '祈願';

  @override
  String get navSectionOdes => '頌願';

  @override
  String get footerNotSynced => '尚未同步';

  @override
  String footerLastUpdated(String time) {
    return '最後更新：$time';
  }

  @override
  String get relativeNow => 'Agora';

  @override
  String relativeSecondsAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Há $count segundos',
      one: 'Há 1 segundo',
    );
    return '$_temp0';
  }

  @override
  String relativeMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Há $count minutos',
      one: 'Há 1 minuto',
    );
    return '$_temp0';
  }

  @override
  String relativeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Há $count horas',
      one: 'Há 1 hora',
    );
    return '$_temp0';
  }

  @override
  String relativeDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Há $count dias',
      one: 'Há 1 dia',
    );
    return '$_temp0';
  }

  @override
  String relativeMonthsAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Há $count meses',
      one: 'Há 1 mês',
    );
    return '$_temp0';
  }

  @override
  String relativeYearsAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Há $count anos',
      one: 'Há 1 ano',
    );
    return '$_temp0';
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
  String get emptyNoOdesRecords => '尚無頌願記錄';

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
  String get statsThreeStarCount => '3★ 件數';

  @override
  String get statsTwoStarCount => '2★ 件數';

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
  String get tableMainPity => '保底內';

  @override
  String tableMainPityTooltip(int rank) {
    return '距上一次 $rank★ 的抽數';
  }

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
  String get pageOverviewWishSection => '祈願綜合';

  @override
  String get pageOverviewOdesSection => '頌願綜合';

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
  String get contributorsTitle => '貢獻名單';

  @override
  String get contributorsSubtitle => '感謝以下為此軟體貢獻的夥伴！';

  @override
  String get contributorsProjectLeader => 'O líder do projeto';

  @override
  String get contributorsTesters => 'Os testadores';

  @override
  String get contributorsGithubContributors => 'Os contribuintes de Github';

  @override
  String get contributorsTranslationReviewer => '翻譯審稿人';

  @override
  String get contributorsTranslatedLanguages => '已翻譯語言';

  @override
  String get contributorsHelpTranslate => '沒有您的語言嗎？協助我們翻譯！';

  @override
  String get contributorsProjectLicense => '專案授權';

  @override
  String get pityFiveStar => '5★ 保底';

  @override
  String get pityFourStar => '4★ 保底';

  @override
  String get pityThreeStar => '3★ 保底';

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
  String pityNoMainRarity(int rank) {
    return '暫無 $rank★';
  }

  @override
  String get pityBeginnerEnded => '已結束';

  @override
  String timelineNoRecordsForRank(int rank) {
    return '暫無 $rank★ 紀錄';
  }

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
  String timelineNowSinceLast(int rank, int n) {
    return '距上次 $rank★ $n 抽';
  }

  @override
  String timelineNowSinceCrossPool(int rank, int n) {
    return '從上次 $rank★ 至今 $n 抽';
  }

  @override
  String timelineMonthLabel(String year, String month) {
    return '$year / $month';
  }

  @override
  String get timelineScrollLeft => '往左捲動';

  @override
  String get timelineScrollRight => '往右捲動';

  @override
  String get filterRarityAll => '全部稀有度';

  @override
  String get filterRarityFiveStar => '只看 5★';

  @override
  String get filterRarityFourStar => '只看 4★';

  @override
  String get filterKindAll => '全部類型';

  @override
  String get filterSearchHint => '搜尋名稱…';

  @override
  String get filterClear => '清除篩選';

  @override
  String get pagerFirst => '首頁';

  @override
  String get pagerLast => '末頁';

  @override
  String get settingsClearActive => '清除目前帳號資料';

  @override
  String get settingsClearAll => '清除所有資料';

  @override
  String get settingsExportAccounts => '匯出資料';

  @override
  String get settingsImportAccounts => '匯入資料';

  @override
  String settingsExportSuccess(String path) {
    return '已匯出至 $path';
  }

  @override
  String get settingsImportConfirmTitle => '匯入確認';

  @override
  String settingsImportConfirmIntro(int accounts, int records) {
    return '即將匯入 $accounts 個帳號（共 $records 筆紀錄）：';
  }

  @override
  String get settingsImportConfirmOverwriteHeader => '下列 UID 已有資料，將被覆蓋：';

  @override
  String get settingsImportConfirmNoConflict => '無資料衝突。';

  @override
  String settingsImportConfirmPreserveFooter(String uids) {
    return '其他現有帳號（$uids）將保留。';
  }

  @override
  String get settingsImportConfirmWarning => '此操作無法復原。請輸入 IMPORT 以確認。';

  @override
  String settingsImportSuccess(int accounts, int records) {
    return '已成功匯入 $accounts 個帳號（$records 筆紀錄）';
  }

  @override
  String settingsImportPartial(int success, int total, String failedUids) {
    return '已匯入 $success/$total 個帳號；失敗：$failedUids';
  }

  @override
  String settingsImportFailed(String reason) {
    return '匯入失敗：$reason';
  }

  @override
  String get settingsExportSelectTitle => '選擇要匯出的帳號';

  @override
  String get settingsImportSelectTitle => '選擇要匯入的帳號';

  @override
  String get settingsImportOverwriteBadge => '覆蓋';

  @override
  String get accountsPickerSelectAll => '全選';

  @override
  String accountRecordCount(int n) {
    return '$n 筆紀錄';
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
  String get confirmImport => '匯入';

  @override
  String get confirmExport => '匯出';

  @override
  String get confirmContinue => '繼續';

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
  String timelineCountTopRarity(int rank, int n) {
    return '$rank★ 時間軸 ($n)';
  }

  @override
  String get bannerTopRarityCountTitle => '各卡池最高稀有度件數';

  @override
  String bannerTopRarityPullsSinceLast(int rank, int n) {
    return '距上次 $rank★ $n 抽';
  }

  @override
  String updateTitle(String version) {
    return '有新版本 $version 可用';
  }

  @override
  String updateReleasedAt(String date) {
    return '發布於 $date';
  }

  @override
  String get updateButtonDownload => '前往下載';

  @override
  String get updateButtonSkip => '跳過此版本';

  @override
  String get updateButtonLater => '稍後再說';

  @override
  String get updateCheckButton => '檢查更新';

  @override
  String get updateChecking => '檢查中…';

  @override
  String get updateAlreadyLatest => '已是最新版本';

  @override
  String updateCheckFailed(String reason) {
    return '檢查更新失敗：$reason';
  }

  @override
  String get updateErrorNetwork => '無法連線，請檢查網路';

  @override
  String get updateErrorTimeout => '請求逾時';

  @override
  String get updateErrorRateLimited => 'GitHub API 配額用盡，請稍後再試';

  @override
  String updateErrorServer(String status) {
    return '伺服器錯誤 (HTTP $status)';
  }

  @override
  String get updateErrorFormat => '回應格式異常';
}
