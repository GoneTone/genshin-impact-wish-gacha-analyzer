// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get localeNativeName => 'English';

  @override
  String get localeTranslator => 'Zanah_68, pan93412, Lemon7777';

  @override
  String get appName => 'Genshin Wish Analyzer';

  @override
  String get actionUpdate => 'Update';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionClose => 'Close';

  @override
  String get actionPrevPage => 'Previous';

  @override
  String get actionNextPage => 'Next';

  @override
  String get navOverview => 'Overview';

  @override
  String get navCharacter => 'Character';

  @override
  String get navWeapon => 'Weapon';

  @override
  String get navChronicled => 'Chronicled';

  @override
  String get navStandard => 'Standard';

  @override
  String get navBeginner => 'Beginner';

  @override
  String get navSettings => 'Settings';

  @override
  String get navContributors => 'Contribution';

  @override
  String get gachaTypeCharacter => 'Character Event Wish';

  @override
  String get gachaTypeWeapon => 'Weapon Event Wish';

  @override
  String get gachaTypeChronicled => 'Chronicled Wish';

  @override
  String get gachaTypeStandard => 'Standard Wish';

  @override
  String get gachaTypeBeginner => 'Beginners\' Wish';

  @override
  String get gachaTypeOdesEvent => 'Event Odes';

  @override
  String get gachaTypeOdesStandard => 'Standard Odes';

  @override
  String get navOdesEvent => 'Event Odes';

  @override
  String get navOdesStandard => 'Standard Odes';

  @override
  String get navSectionWish => 'Wish';

  @override
  String get navSectionOdes => 'Odes';

  @override
  String get footerNotSynced => 'Not synced';

  @override
  String footerLastUpdated(String time) {
    return 'Last updated: $time';
  }

  @override
  String get relativeNow => 'Just now';

  @override
  String relativeSecondsAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seconds ago',
      one: '1 second ago',
    );
    return '$_temp0';
  }

  @override
  String relativeMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes ago',
      one: '1 minute ago',
    );
    return '$_temp0';
  }

  @override
  String relativeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours ago',
      one: '1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String relativeDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String relativeMonthsAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count months ago',
      one: '1 month ago',
    );
    return '$_temp0';
  }

  @override
  String relativeYearsAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count years ago',
      one: '1 year ago',
    );
    return '$_temp0';
  }

  @override
  String get uidSwitchTooltip => 'Switch account';

  @override
  String get uidNotSynced => 'Not synced';

  @override
  String get uidActiveSuffix => ' (active)';

  @override
  String get uidRecapture => 'Add account';

  @override
  String get emptyNoSyncTitle => 'No data synced yet';

  @override
  String get emptyNoSyncMessage => 'Click \"Update\" in the top right to start';

  @override
  String get emptyNoRecords => 'No records for this banner';

  @override
  String get emptyNoFiltered => 'No records match the current filter';

  @override
  String get emptyNoOdesRecords => 'No Odes records yet';

  @override
  String get statsTotal => 'Total pulls';

  @override
  String get statsFiveStarCount => '5★ Count';

  @override
  String get statsFourStarCount => '4★ Count';

  @override
  String statsShareOfTotal(String rate) {
    return '$rate% of total';
  }

  @override
  String get statsRarityDistribution => 'Rarity Distribution';

  @override
  String get statsItemTypeDistribution => 'Type Distribution';

  @override
  String get statsNoData => 'No data';

  @override
  String get statsThreeStarCount => '3★ Count';

  @override
  String get statsTwoStarCount => '2★ Count';

  @override
  String get kindUnknown => 'Unknown';

  @override
  String get tableTime => 'Time';

  @override
  String get tableName => 'Name';

  @override
  String get tableKind => 'Type';

  @override
  String get tableRarity => 'Rarity';

  @override
  String get tableTotalIndex => 'Total';

  @override
  String get tableMainPity => 'Pity';

  @override
  String tableMainPityTooltip(int rank) {
    return 'Pulls since the last $rank★';
  }

  @override
  String get sortDirectionDesc => 'Descending';

  @override
  String get sortDirectionAsc => 'Ascending';

  @override
  String get sortDirectionNone => 'Click to sort';

  @override
  String get progressPreparing => 'Preparing…';

  @override
  String get progressPreparingHint => 'Preparing data source…';

  @override
  String get progressWaiting => 'Waiting for capture…';

  @override
  String get progressFetching => 'Fetching…';

  @override
  String get progressDone => 'Update complete';

  @override
  String get progressFailed => 'Failed';

  @override
  String get progressOpenGameHint => 'Open Genshin → Wishes → History';

  @override
  String get progressFallbackHint =>
      '(Previous auth expired, re-capture needed)';

  @override
  String progressFetchingBanner(String name) {
    return 'Fetching: $name';
  }

  @override
  String progressPageStatus(int page, int count) {
    return 'Page $page, $count new records so far';
  }

  @override
  String progressDoneSummary(int count) {
    return 'Added $count new records';
  }

  @override
  String progressPartialFailed(String names) {
    return '⚠ Partial failure: $names';
  }

  @override
  String get errorAuthExpired =>
      'Auth keeps expiring; please log in to the game again';

  @override
  String get errorRateLimited => 'Too many requests; please retry later';

  @override
  String errorServer(String message) {
    return 'Server error: $message';
  }

  @override
  String get errorNoRecords => 'This account has no wish records yet';

  @override
  String get pageOverviewTitle => 'Overview (all banners)';

  @override
  String get pageOverviewWishSection => 'Wish Overview';

  @override
  String get pageOverviewOdesSection => 'Odes Overview';

  @override
  String get pageBannerRecordList => 'Record list';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeSystem => 'Follow system';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLocaleSystem => 'Follow system';

  @override
  String get settingsDataManagement => 'Data management';

  @override
  String get settingsAccountManagement => 'Account management';

  @override
  String get settingsAbout => 'About';

  @override
  String settingsAboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String get settingsPlaceholderPhase2 => '(Coming soon)';

  @override
  String get contributorsTitle => 'Contributors';

  @override
  String get contributorsSubtitle =>
      'Special thanks to the following partners who have contributed to the development of this software!';

  @override
  String get contributorsProjectLeader => 'Project moderator';

  @override
  String get contributorsTesters => 'Testers';

  @override
  String get contributorsGithubContributors => 'GitHub Contributors';

  @override
  String get contributorsTranslationReviewer => 'Translation proofreaders';

  @override
  String get contributorsTranslatedLanguages => 'Available languages';

  @override
  String get contributorsHelpTranslate =>
      'Unavailable in your preferred languages? Help us translate it!';

  @override
  String get contributorsProjectLicense => 'Project License';

  @override
  String get pityFiveStar => '5★ pity';

  @override
  String get pityFourStar => '4★ pity';

  @override
  String get pityThreeStar => '3★ pity';

  @override
  String pityCurrent(int current, int threshold) {
    return '$current / $threshold';
  }

  @override
  String pityDistance(int n) {
    return '$n pulls until guaranteed';
  }

  @override
  String pityClose(int n) {
    return 'Close to guaranteed! $n pulls left';
  }

  @override
  String get pityGuaranteed => 'Guaranteed soon';

  @override
  String pityNoMainRarity(int rank) {
    return 'No $rank★ yet';
  }

  @override
  String get pityBeginnerEnded => 'Ended';

  @override
  String timelineNoRecordsForRank(int rank) {
    return 'No $rank★ records';
  }

  @override
  String timelineSinceLast(int n) {
    return '$n pulls';
  }

  @override
  String get timelineNowLabel => 'Now';

  @override
  String timelineNowPulls(int n) {
    return '$n pulls';
  }

  @override
  String timelineNowSinceLast(int rank, int n) {
    return '$n pulls since last $rank★';
  }

  @override
  String timelineNowSinceCrossPool(int rank, int n) {
    return '$n pulls since last $rank★ across banners';
  }

  @override
  String timelineMonthLabel(String year, String month) {
    return '$month / $year';
  }

  @override
  String get timelineScrollLeft => 'Scroll left';

  @override
  String get timelineScrollRight => 'Scroll right';

  @override
  String get filterRarityAll => 'All rarities';

  @override
  String get filterRarityFiveStar => '5★ only';

  @override
  String get filterRarityFourStar => '4★ only';

  @override
  String get filterKindAll => 'All kinds';

  @override
  String get filterSearchHint => 'Search name…';

  @override
  String get filterClear => 'Clear filters';

  @override
  String get pagerFirst => 'First';

  @override
  String get pagerLast => 'Last';

  @override
  String get settingsClearActive => 'Clear current account data';

  @override
  String get settingsClearAll => 'Clear all data';

  @override
  String get settingsExportAccounts => 'Export data';

  @override
  String get settingsImportAccounts => 'Import data';

  @override
  String settingsExportSuccess(String path) {
    return 'Exported to $path';
  }

  @override
  String get settingsImportConfirmTitle => 'Import confirmation';

  @override
  String settingsImportConfirmIntro(int accounts, int records) {
    return 'About to import $accounts accounts ($records records total):';
  }

  @override
  String get settingsImportConfirmOverwriteHeader =>
      'The following UIDs already have data and will be overwritten:';

  @override
  String get settingsImportConfirmNoConflict => 'No data conflicts.';

  @override
  String settingsImportConfirmPreserveFooter(String uids) {
    return 'Other existing accounts ($uids) will be preserved.';
  }

  @override
  String get settingsImportConfirmWarning =>
      'This action cannot be undone. Type IMPORT to confirm.';

  @override
  String settingsImportSuccess(int accounts, int records) {
    return 'Successfully imported $accounts accounts ($records records)';
  }

  @override
  String settingsImportPartial(int success, int total, String failedUids) {
    return 'Imported $success/$total accounts; failed: $failedUids';
  }

  @override
  String settingsImportFailed(String reason) {
    return 'Import failed: $reason';
  }

  @override
  String get settingsExportSelectTitle => 'Select accounts to export';

  @override
  String get settingsImportSelectTitle => 'Select accounts to import';

  @override
  String get settingsImportOverwriteBadge => 'Overwrite';

  @override
  String get accountsPickerSelectAll => 'Select all';

  @override
  String accountRecordCount(int n) {
    return '$n records';
  }

  @override
  String get confirmTitle => 'Confirm';

  @override
  String confirmClearActiveBody(String uid) {
    return 'This will permanently delete all wish records for UID $uid. Type the UID to confirm:';
  }

  @override
  String get confirmClearAllBody =>
      'This will permanently delete every account\'s wish records. Type DELETE to confirm:';

  @override
  String get confirmTypeMismatch => 'Input did not match. Operation cancelled.';

  @override
  String get confirmCancel => 'Cancel';

  @override
  String get confirmDelete => 'Delete';

  @override
  String get confirmImport => 'Import';

  @override
  String get confirmExport => 'Export';

  @override
  String get confirmContinue => 'Continue';

  @override
  String get accountListEmpty => 'No accounts yet';

  @override
  String accountLastUpdated(String time) {
    return 'Last updated $time';
  }

  @override
  String get accountActiveTag => 'Active';

  @override
  String get accountSetActive => 'Set active';

  @override
  String get accountRemove => 'Remove';

  @override
  String get accountRecapture => 'Add account';

  @override
  String get accountAliasLabel => 'Alias';

  @override
  String get accountAliasHint => 'A friendly name for this account';

  @override
  String get accountDragHandleTooltip => 'Drag to reorder';

  @override
  String get loadingBootstrap => 'Loading…';

  @override
  String timelineCountTopRarity(int rank, int n) {
    return '$rank★ Timeline ($n)';
  }

  @override
  String get bannerTopRarityCountTitle => 'Highest rarity count per banner';

  @override
  String bannerTopRarityPullsSinceLast(int rank, int n) {
    return '$n pulls since last $rank★';
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
