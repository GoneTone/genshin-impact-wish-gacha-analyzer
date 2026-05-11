// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

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
  String get footerNotSynced => 'Not synced';

  @override
  String footerLastUpdated(String time) {
    return 'Last updated: $time';
  }

  @override
  String get uidSwitchTooltip => 'Switch account';

  @override
  String get uidNotSynced => 'Not synced';

  @override
  String get uidActiveSuffix => ' (active)';

  @override
  String get uidRecapture => 'Re-capture / switch account';

  @override
  String get emptyNoSyncTitle => 'No data synced yet';

  @override
  String get emptyNoSyncMessage => 'Click \"Update\" in the top right to start';

  @override
  String get emptyNoRecords => 'No records for this banner';

  @override
  String get emptyNoFiltered => 'No records match the current filter';

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
  String get kindCharacter => 'Character';

  @override
  String get kindWeapon => 'Weapon';

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
  String get tableFiveStarPity => 'Pity';

  @override
  String get tableFiveStarPityTooltip => 'Pulls since the last 5★';

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
  String get settingsLocaleZhHant => '繁體中文';

  @override
  String get settingsLocaleZhHans => '简体中文';

  @override
  String get settingsLocaleEn => 'English';

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
  String get pityFiveStar => '5★ pity';

  @override
  String get pityFourStar => '4★ pity';

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
  String get pityNoFiveStar => 'No 5★ yet';

  @override
  String get pityBeginnerEnded => 'Ended';

  @override
  String get timelineNoRecords => 'No 5★ records';

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
  String timelineNowSinceLast(int n) {
    return '$n pulls since last 5★';
  }

  @override
  String timelineNowSinceCrossPool(int n) {
    return '$n pulls since last 5★ across banners';
  }

  @override
  String timelineMonthLabel(String year, String month) {
    return '$month / $year';
  }

  @override
  String get filterRarityAll => 'All rarities';

  @override
  String get filterRarityFiveStar => '5★ only';

  @override
  String get filterRarityFourStar => '4★ only';

  @override
  String get filterKindAll => 'All kinds';

  @override
  String get filterKindCharacter => 'Characters only';

  @override
  String get filterKindWeapon => 'Weapons only';

  @override
  String get filterSearchHint => 'Search name…';

  @override
  String get filterClear => 'Clear filters';

  @override
  String get pagerFirst => 'First';

  @override
  String get pagerLast => 'Last';

  @override
  String get settingsExportJson => 'Export JSON';

  @override
  String get settingsExportCsv => 'Export CSV';

  @override
  String get settingsImportJson => 'Import JSON';

  @override
  String get settingsClearActive => 'Clear current account data';

  @override
  String get settingsClearAll => 'Clear all data';

  @override
  String settingsExportSuccess(String path) {
    return 'Exported to $path';
  }

  @override
  String settingsImportSuccess(String uid, int count) {
    return 'Imported $count records for UID $uid';
  }

  @override
  String settingsImportFailed(String reason) {
    return 'Import failed: $reason';
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
  String get accountRecapture => 'Re-capture / add account';

  @override
  String get loadingBootstrap => 'Loading…';

  @override
  String timelineCountFiveStar(int n) {
    return '5★ Timeline ($n)';
  }

  @override
  String get bannerFiveStarCountTitle => '5★ count per banner';

  @override
  String bannerFiveStarPullsSinceLast(int n) {
    return '$n pulls since last 5★';
  }
}
