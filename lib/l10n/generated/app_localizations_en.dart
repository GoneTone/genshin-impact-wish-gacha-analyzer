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
  String get statsFiveStarRate => '5★ Rate';

  @override
  String get statsFourStarRate => '4★ Rate';

  @override
  String get statsThreeStarRate => '3★ Rate';

  @override
  String get statsCharacterRate => 'Character Rate';

  @override
  String get statsWeaponRate => 'Weapon Rate';

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
}
