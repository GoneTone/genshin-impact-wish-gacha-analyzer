import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_pt.dart';
import 'app_localizations_th.dart';
import 'app_localizations_vi.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('ja'),
    Locale('pt'),
    Locale('pt', 'BR'),
    Locale('th'),
    Locale('vi'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ];

  /// Native name of this locale, shown in language picker.
  ///
  /// In zh_Hant, this message translates to:
  /// **'繁體中文'**
  String get localeNativeName;

  /// Comma-separated list of translators for this locale. Empty = original language (no credit row shown).
  ///
  /// In zh_Hant, this message translates to:
  /// **''**
  String get localeTranslator;

  /// No description provided for @appName.
  ///
  /// In zh_Hant, this message translates to:
  /// **'原神祈願卡池分析'**
  String get appName;

  /// No description provided for @actionUpdate.
  ///
  /// In zh_Hant, this message translates to:
  /// **'更新資料'**
  String get actionUpdate;

  /// No description provided for @actionCancel.
  ///
  /// In zh_Hant, this message translates to:
  /// **'取消'**
  String get actionCancel;

  /// No description provided for @actionClose.
  ///
  /// In zh_Hant, this message translates to:
  /// **'關閉'**
  String get actionClose;

  /// No description provided for @actionPrevPage.
  ///
  /// In zh_Hant, this message translates to:
  /// **'上一頁'**
  String get actionPrevPage;

  /// No description provided for @actionNextPage.
  ///
  /// In zh_Hant, this message translates to:
  /// **'下一頁'**
  String get actionNextPage;

  /// No description provided for @navOverview.
  ///
  /// In zh_Hant, this message translates to:
  /// **'綜合'**
  String get navOverview;

  /// No description provided for @navCharacter.
  ///
  /// In zh_Hant, this message translates to:
  /// **'角色'**
  String get navCharacter;

  /// No description provided for @navWeapon.
  ///
  /// In zh_Hant, this message translates to:
  /// **'武器'**
  String get navWeapon;

  /// No description provided for @navChronicled.
  ///
  /// In zh_Hant, this message translates to:
  /// **'集錄'**
  String get navChronicled;

  /// No description provided for @navStandard.
  ///
  /// In zh_Hant, this message translates to:
  /// **'常駐'**
  String get navStandard;

  /// No description provided for @navBeginner.
  ///
  /// In zh_Hant, this message translates to:
  /// **'新手'**
  String get navBeginner;

  /// No description provided for @navSettings.
  ///
  /// In zh_Hant, this message translates to:
  /// **'設定'**
  String get navSettings;

  /// No description provided for @gachaTypeCharacter.
  ///
  /// In zh_Hant, this message translates to:
  /// **'角色活動祈願'**
  String get gachaTypeCharacter;

  /// No description provided for @gachaTypeWeapon.
  ///
  /// In zh_Hant, this message translates to:
  /// **'武器活動祈願'**
  String get gachaTypeWeapon;

  /// No description provided for @gachaTypeChronicled.
  ///
  /// In zh_Hant, this message translates to:
  /// **'集錄祈願'**
  String get gachaTypeChronicled;

  /// No description provided for @gachaTypeStandard.
  ///
  /// In zh_Hant, this message translates to:
  /// **'常駐祈願'**
  String get gachaTypeStandard;

  /// No description provided for @gachaTypeBeginner.
  ///
  /// In zh_Hant, this message translates to:
  /// **'新手祈願'**
  String get gachaTypeBeginner;

  /// No description provided for @footerNotSynced.
  ///
  /// In zh_Hant, this message translates to:
  /// **'尚未同步'**
  String get footerNotSynced;

  /// No description provided for @footerLastUpdated.
  ///
  /// In zh_Hant, this message translates to:
  /// **'最後更新：{time}'**
  String footerLastUpdated(String time);

  /// No description provided for @uidSwitchTooltip.
  ///
  /// In zh_Hant, this message translates to:
  /// **'切換帳號'**
  String get uidSwitchTooltip;

  /// No description provided for @uidNotSynced.
  ///
  /// In zh_Hant, this message translates to:
  /// **'未同步'**
  String get uidNotSynced;

  /// No description provided for @uidActiveSuffix.
  ///
  /// In zh_Hant, this message translates to:
  /// **'（活躍）'**
  String get uidActiveSuffix;

  /// No description provided for @uidRecapture.
  ///
  /// In zh_Hant, this message translates to:
  /// **'重新攔截 / 切換帳號'**
  String get uidRecapture;

  /// No description provided for @emptyNoSyncTitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'尚未同步任何資料'**
  String get emptyNoSyncTitle;

  /// No description provided for @emptyNoSyncMessage.
  ///
  /// In zh_Hant, this message translates to:
  /// **'點右上「更新資料」開始'**
  String get emptyNoSyncMessage;

  /// No description provided for @emptyNoRecords.
  ///
  /// In zh_Hant, this message translates to:
  /// **'此卡池無紀錄'**
  String get emptyNoRecords;

  /// No description provided for @emptyNoFiltered.
  ///
  /// In zh_Hant, this message translates to:
  /// **'沒有符合條件的紀錄'**
  String get emptyNoFiltered;

  /// No description provided for @statsTotal.
  ///
  /// In zh_Hant, this message translates to:
  /// **'總抽數'**
  String get statsTotal;

  /// No description provided for @statsFiveStarCount.
  ///
  /// In zh_Hant, this message translates to:
  /// **'5★ 件數'**
  String get statsFiveStarCount;

  /// No description provided for @statsFourStarCount.
  ///
  /// In zh_Hant, this message translates to:
  /// **'4★ 件數'**
  String get statsFourStarCount;

  /// No description provided for @statsShareOfTotal.
  ///
  /// In zh_Hant, this message translates to:
  /// **'佔總抽 {rate}%'**
  String statsShareOfTotal(String rate);

  /// No description provided for @statsRarityDistribution.
  ///
  /// In zh_Hant, this message translates to:
  /// **'稀有度分布'**
  String get statsRarityDistribution;

  /// No description provided for @statsItemTypeDistribution.
  ///
  /// In zh_Hant, this message translates to:
  /// **'類型分布'**
  String get statsItemTypeDistribution;

  /// No description provided for @statsNoData.
  ///
  /// In zh_Hant, this message translates to:
  /// **'無資料'**
  String get statsNoData;

  /// No description provided for @kindCharacter.
  ///
  /// In zh_Hant, this message translates to:
  /// **'角色'**
  String get kindCharacter;

  /// No description provided for @kindWeapon.
  ///
  /// In zh_Hant, this message translates to:
  /// **'武器'**
  String get kindWeapon;

  /// No description provided for @kindUnknown.
  ///
  /// In zh_Hant, this message translates to:
  /// **'未知'**
  String get kindUnknown;

  /// No description provided for @tableTime.
  ///
  /// In zh_Hant, this message translates to:
  /// **'時間'**
  String get tableTime;

  /// No description provided for @tableName.
  ///
  /// In zh_Hant, this message translates to:
  /// **'名稱'**
  String get tableName;

  /// No description provided for @tableKind.
  ///
  /// In zh_Hant, this message translates to:
  /// **'類型'**
  String get tableKind;

  /// No description provided for @tableRarity.
  ///
  /// In zh_Hant, this message translates to:
  /// **'稀有度'**
  String get tableRarity;

  /// No description provided for @tableTotalIndex.
  ///
  /// In zh_Hant, this message translates to:
  /// **'總抽數'**
  String get tableTotalIndex;

  /// No description provided for @tableFiveStarPity.
  ///
  /// In zh_Hant, this message translates to:
  /// **'保底內'**
  String get tableFiveStarPity;

  /// No description provided for @tableFiveStarPityTooltip.
  ///
  /// In zh_Hant, this message translates to:
  /// **'距上一次 5★ 的抽數'**
  String get tableFiveStarPityTooltip;

  /// No description provided for @sortDirectionDesc.
  ///
  /// In zh_Hant, this message translates to:
  /// **'降序'**
  String get sortDirectionDesc;

  /// No description provided for @sortDirectionAsc.
  ///
  /// In zh_Hant, this message translates to:
  /// **'升序'**
  String get sortDirectionAsc;

  /// No description provided for @sortDirectionNone.
  ///
  /// In zh_Hant, this message translates to:
  /// **'點擊排序'**
  String get sortDirectionNone;

  /// No description provided for @progressPreparing.
  ///
  /// In zh_Hant, this message translates to:
  /// **'準備中…'**
  String get progressPreparing;

  /// No description provided for @progressPreparingHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'正在準備資料來源…'**
  String get progressPreparingHint;

  /// No description provided for @progressWaiting.
  ///
  /// In zh_Hant, this message translates to:
  /// **'等待攔截…'**
  String get progressWaiting;

  /// No description provided for @progressFetching.
  ///
  /// In zh_Hant, this message translates to:
  /// **'抓取中…'**
  String get progressFetching;

  /// No description provided for @progressDone.
  ///
  /// In zh_Hant, this message translates to:
  /// **'更新完成'**
  String get progressDone;

  /// No description provided for @progressFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'失敗'**
  String get progressFailed;

  /// No description provided for @progressOpenGameHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'請開啟原神 → 卡池 → 歷史紀錄'**
  String get progressOpenGameHint;

  /// No description provided for @progressFallbackHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'（先前的認證已失效，需重新攔截）'**
  String get progressFallbackHint;

  /// No description provided for @progressFetchingBanner.
  ///
  /// In zh_Hant, this message translates to:
  /// **'正在抓取：{name}'**
  String progressFetchingBanner(String name);

  /// No description provided for @progressPageStatus.
  ///
  /// In zh_Hant, this message translates to:
  /// **'第 {page} 頁，已新增 {count} 筆'**
  String progressPageStatus(int page, int count);

  /// No description provided for @progressDoneSummary.
  ///
  /// In zh_Hant, this message translates to:
  /// **'新增 {count} 筆紀錄'**
  String progressDoneSummary(int count);

  /// No description provided for @progressPartialFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'⚠ 部分失敗：{names}'**
  String progressPartialFailed(String names);

  /// No description provided for @errorAuthExpired.
  ///
  /// In zh_Hant, this message translates to:
  /// **'認證持續失效，請重新登入遊戲'**
  String get errorAuthExpired;

  /// No description provided for @errorRateLimited.
  ///
  /// In zh_Hant, this message translates to:
  /// **'請求過於頻繁，請稍後再試'**
  String get errorRateLimited;

  /// No description provided for @errorServer.
  ///
  /// In zh_Hant, this message translates to:
  /// **'伺服器錯誤：{message}'**
  String errorServer(String message);

  /// No description provided for @errorNoRecords.
  ///
  /// In zh_Hant, this message translates to:
  /// **'此帳號尚無任何卡池紀錄'**
  String get errorNoRecords;

  /// No description provided for @pageOverviewTitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'綜合數據（全卡池合計）'**
  String get pageOverviewTitle;

  /// No description provided for @pageBannerRecordList.
  ///
  /// In zh_Hant, this message translates to:
  /// **'紀錄列表'**
  String get pageBannerRecordList;

  /// No description provided for @settingsTitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'設定'**
  String get settingsTitle;

  /// No description provided for @settingsAppearance.
  ///
  /// In zh_Hant, this message translates to:
  /// **'外觀'**
  String get settingsAppearance;

  /// No description provided for @settingsTheme.
  ///
  /// In zh_Hant, this message translates to:
  /// **'主題'**
  String get settingsTheme;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In zh_Hant, this message translates to:
  /// **'跟隨系統'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeDark.
  ///
  /// In zh_Hant, this message translates to:
  /// **'深色'**
  String get settingsThemeDark;

  /// No description provided for @settingsThemeLight.
  ///
  /// In zh_Hant, this message translates to:
  /// **'淺色'**
  String get settingsThemeLight;

  /// No description provided for @settingsLanguage.
  ///
  /// In zh_Hant, this message translates to:
  /// **'語言'**
  String get settingsLanguage;

  /// No description provided for @settingsLocaleSystem.
  ///
  /// In zh_Hant, this message translates to:
  /// **'跟隨系統'**
  String get settingsLocaleSystem;

  /// No description provided for @settingsDataManagement.
  ///
  /// In zh_Hant, this message translates to:
  /// **'資料管理'**
  String get settingsDataManagement;

  /// No description provided for @settingsAccountManagement.
  ///
  /// In zh_Hant, this message translates to:
  /// **'帳號管理'**
  String get settingsAccountManagement;

  /// No description provided for @settingsAbout.
  ///
  /// In zh_Hant, this message translates to:
  /// **'關於'**
  String get settingsAbout;

  /// No description provided for @settingsAboutVersion.
  ///
  /// In zh_Hant, this message translates to:
  /// **'版本 {version}'**
  String settingsAboutVersion(String version);

  /// No description provided for @settingsPlaceholderPhase2.
  ///
  /// In zh_Hant, this message translates to:
  /// **'（即將推出）'**
  String get settingsPlaceholderPhase2;

  /// No description provided for @pityFiveStar.
  ///
  /// In zh_Hant, this message translates to:
  /// **'5★ 保底'**
  String get pityFiveStar;

  /// No description provided for @pityFourStar.
  ///
  /// In zh_Hant, this message translates to:
  /// **'4★ 保底'**
  String get pityFourStar;

  /// No description provided for @pityCurrent.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{current} / {threshold}'**
  String pityCurrent(int current, int threshold);

  /// No description provided for @pityDistance.
  ///
  /// In zh_Hant, this message translates to:
  /// **'距下次保底 {n} 抽'**
  String pityDistance(int n);

  /// No description provided for @pityClose.
  ///
  /// In zh_Hant, this message translates to:
  /// **'快保底了！剩餘 {n} 抽'**
  String pityClose(int n);

  /// No description provided for @pityGuaranteed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'保底中'**
  String get pityGuaranteed;

  /// No description provided for @pityNoFiveStar.
  ///
  /// In zh_Hant, this message translates to:
  /// **'暫無 5★'**
  String get pityNoFiveStar;

  /// No description provided for @pityBeginnerEnded.
  ///
  /// In zh_Hant, this message translates to:
  /// **'已結束'**
  String get pityBeginnerEnded;

  /// No description provided for @timelineNoRecords.
  ///
  /// In zh_Hant, this message translates to:
  /// **'暫無 5★ 紀錄'**
  String get timelineNoRecords;

  /// No description provided for @timelineSinceLast.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{n} 抽'**
  String timelineSinceLast(int n);

  /// No description provided for @timelineNowLabel.
  ///
  /// In zh_Hant, this message translates to:
  /// **'現在'**
  String get timelineNowLabel;

  /// No description provided for @timelineNowPulls.
  ///
  /// In zh_Hant, this message translates to:
  /// **'已 {n} 抽'**
  String timelineNowPulls(int n);

  /// No description provided for @timelineNowSinceLast.
  ///
  /// In zh_Hant, this message translates to:
  /// **'距上次 5★ {n} 抽'**
  String timelineNowSinceLast(int n);

  /// No description provided for @timelineNowSinceCrossPool.
  ///
  /// In zh_Hant, this message translates to:
  /// **'從上次 5★ 至今 {n} 抽'**
  String timelineNowSinceCrossPool(int n);

  /// No description provided for @timelineMonthLabel.
  ///
  /// In zh_Hant, this message translates to:
  /// **'{year} / {month}'**
  String timelineMonthLabel(String year, String month);

  /// No description provided for @filterRarityAll.
  ///
  /// In zh_Hant, this message translates to:
  /// **'全部稀有度'**
  String get filterRarityAll;

  /// No description provided for @filterRarityFiveStar.
  ///
  /// In zh_Hant, this message translates to:
  /// **'只看 5★'**
  String get filterRarityFiveStar;

  /// No description provided for @filterRarityFourStar.
  ///
  /// In zh_Hant, this message translates to:
  /// **'只看 4★'**
  String get filterRarityFourStar;

  /// No description provided for @filterKindAll.
  ///
  /// In zh_Hant, this message translates to:
  /// **'全部類型'**
  String get filterKindAll;

  /// No description provided for @filterKindCharacter.
  ///
  /// In zh_Hant, this message translates to:
  /// **'只看角色'**
  String get filterKindCharacter;

  /// No description provided for @filterKindWeapon.
  ///
  /// In zh_Hant, this message translates to:
  /// **'只看武器'**
  String get filterKindWeapon;

  /// No description provided for @filterSearchHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'搜尋名稱…'**
  String get filterSearchHint;

  /// No description provided for @filterClear.
  ///
  /// In zh_Hant, this message translates to:
  /// **'清除篩選'**
  String get filterClear;

  /// No description provided for @pagerFirst.
  ///
  /// In zh_Hant, this message translates to:
  /// **'首頁'**
  String get pagerFirst;

  /// No description provided for @pagerLast.
  ///
  /// In zh_Hant, this message translates to:
  /// **'末頁'**
  String get pagerLast;

  /// No description provided for @settingsExportJson.
  ///
  /// In zh_Hant, this message translates to:
  /// **'匯出 JSON'**
  String get settingsExportJson;

  /// No description provided for @settingsExportCsv.
  ///
  /// In zh_Hant, this message translates to:
  /// **'匯出 CSV'**
  String get settingsExportCsv;

  /// No description provided for @settingsImportJson.
  ///
  /// In zh_Hant, this message translates to:
  /// **'匯入 JSON'**
  String get settingsImportJson;

  /// No description provided for @settingsClearActive.
  ///
  /// In zh_Hant, this message translates to:
  /// **'清除目前帳號資料'**
  String get settingsClearActive;

  /// No description provided for @settingsClearAll.
  ///
  /// In zh_Hant, this message translates to:
  /// **'清除所有資料'**
  String get settingsClearAll;

  /// No description provided for @settingsExportSuccess.
  ///
  /// In zh_Hant, this message translates to:
  /// **'已匯出至 {path}'**
  String settingsExportSuccess(String path);

  /// No description provided for @settingsImportSuccess.
  ///
  /// In zh_Hant, this message translates to:
  /// **'成功匯入 UID {uid} 的 {count} 筆紀錄'**
  String settingsImportSuccess(String uid, int count);

  /// No description provided for @settingsImportFailed.
  ///
  /// In zh_Hant, this message translates to:
  /// **'匯入失敗：{reason}'**
  String settingsImportFailed(String reason);

  /// No description provided for @confirmTitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'確認操作'**
  String get confirmTitle;

  /// No description provided for @confirmClearActiveBody.
  ///
  /// In zh_Hant, this message translates to:
  /// **'這會永久刪除 UID {uid} 的所有祈願紀錄。輸入 UID 確認：'**
  String confirmClearActiveBody(String uid);

  /// No description provided for @confirmClearAllBody.
  ///
  /// In zh_Hant, this message translates to:
  /// **'這會永久刪除所有帳號的祈願紀錄。輸入 DELETE 確認：'**
  String get confirmClearAllBody;

  /// No description provided for @confirmTypeMismatch.
  ///
  /// In zh_Hant, this message translates to:
  /// **'輸入不符，操作已取消'**
  String get confirmTypeMismatch;

  /// No description provided for @confirmCancel.
  ///
  /// In zh_Hant, this message translates to:
  /// **'取消'**
  String get confirmCancel;

  /// No description provided for @confirmDelete.
  ///
  /// In zh_Hant, this message translates to:
  /// **'刪除'**
  String get confirmDelete;

  /// No description provided for @accountListEmpty.
  ///
  /// In zh_Hant, this message translates to:
  /// **'目前沒有任何帳號'**
  String get accountListEmpty;

  /// No description provided for @accountLastUpdated.
  ///
  /// In zh_Hant, this message translates to:
  /// **'最後更新 {time}'**
  String accountLastUpdated(String time);

  /// No description provided for @accountActiveTag.
  ///
  /// In zh_Hant, this message translates to:
  /// **'活躍'**
  String get accountActiveTag;

  /// No description provided for @accountSetActive.
  ///
  /// In zh_Hant, this message translates to:
  /// **'設為活躍'**
  String get accountSetActive;

  /// No description provided for @accountRemove.
  ///
  /// In zh_Hant, this message translates to:
  /// **'移除'**
  String get accountRemove;

  /// No description provided for @accountRecapture.
  ///
  /// In zh_Hant, this message translates to:
  /// **'重新攔截 / 新增帳號'**
  String get accountRecapture;

  /// No description provided for @accountAliasLabel.
  ///
  /// In zh_Hant, this message translates to:
  /// **'別名'**
  String get accountAliasLabel;

  /// No description provided for @accountAliasHint.
  ///
  /// In zh_Hant, this message translates to:
  /// **'為此帳號取一個好記的名稱'**
  String get accountAliasHint;

  /// No description provided for @accountDragHandleTooltip.
  ///
  /// In zh_Hant, this message translates to:
  /// **'拖曳排序'**
  String get accountDragHandleTooltip;

  /// No description provided for @loadingBootstrap.
  ///
  /// In zh_Hant, this message translates to:
  /// **'載入中…'**
  String get loadingBootstrap;

  /// No description provided for @timelineCountFiveStar.
  ///
  /// In zh_Hant, this message translates to:
  /// **'5★ 時間軸 ({n})'**
  String timelineCountFiveStar(int n);

  /// No description provided for @bannerFiveStarCountTitle.
  ///
  /// In zh_Hant, this message translates to:
  /// **'各卡池 5★ 件數'**
  String get bannerFiveStarCountTitle;

  /// No description provided for @bannerFiveStarPullsSinceLast.
  ///
  /// In zh_Hant, this message translates to:
  /// **'距上次 5★ {n} 抽'**
  String bannerFiveStarPullsSinceLast(int n);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'en',
    'es',
    'fr',
    'ja',
    'pt',
    'th',
    'vi',
    'zh',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.scriptCode) {
          case 'Hans':
            return AppLocalizationsZhHans();
          case 'Hant':
            return AppLocalizationsZhHant();
        }
        break;
      }
  }

  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'pt':
      {
        switch (locale.countryCode) {
          case 'BR':
            return AppLocalizationsPtBr();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'ja':
      return AppLocalizationsJa();
    case 'pt':
      return AppLocalizationsPt();
    case 'th':
      return AppLocalizationsTh();
    case 'vi':
      return AppLocalizationsVi();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
