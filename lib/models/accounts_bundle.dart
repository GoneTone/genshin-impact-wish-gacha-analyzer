import 'package:genshin_impact_wish_gacha_analyzer/models/alias_merge.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/record_merge.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';

/// 本軟體的匯出識別字串，寫入備份檔的 `app` 欄位供匯入端辨識來源。
///
/// 值對齊 pubspec 套件名；姐妹專案（鳴潮）為 `wuthering_waves_convene_gacha_analyzer`，天生相異。
const String accountsBundleAppId = 'genshin_impact_wish_gacha_analyzer';

/// 匯入檔的 schema 版本高於目前 App 支援版本時拋出，供 UI 給出「請更新 App」指引。
class UnsupportedSchemaVersionException implements Exception {
  /// 建立 [UnsupportedSchemaVersionException]。
  const UnsupportedSchemaVersionException(this.version);

  /// 匯入檔宣告的 schema 版本（高於 [AccountsBundle.maxReadableSchemaVersion]）。
  final int version;

  @override
  String toString() => 'UnsupportedSchemaVersionException(version: $version)';
}

/// 單一匯出帳號：包含祈願資料、選填別名與別名修改時間。
class ExportedAccount {
  /// 建立 [ExportedAccount]。
  const ExportedAccount({required this.data, this.alias, this.aliasUpdatedAt});

  /// 帳號的祈願存檔資料。
  final BannerStorage data;

  /// 使用者自定義別名（選填）。
  final String? alias;

  /// 別名最後修改（含清空）的時間（UTC）；null 代表沒有記錄（舊版留下的資料）。
  final DateTime? aliasUpdatedAt;

  /// 序列化為 JSON：alias 為空時省略；有修改時間就寫，沒有別名時代表已清空。
  Map<String, dynamic> toJson() {
    final a = alias;
    final t = aliasUpdatedAt;
    return {
      ...data.toJson(),
      if (a != null && a.isNotEmpty) 'alias': a,
      if (t != null) 'alias_updated_at': t.toUtc().toIso8601String(),
    };
  }

  /// 從 JSON 還原 [ExportedAccount]，alias 空白視同無別名。
  factory ExportedAccount.fromJson(Map<String, dynamic> json) {
    final rawAlias = json['alias'];
    final alias = (rawAlias is String && rawAlias.trim().isNotEmpty)
        ? rawAlias.trim()
        : null;
    return ExportedAccount(
      data: BannerStorage.fromJson(json),
      alias: alias,
      aliasUpdatedAt: parseAliasUpdatedAt(json['alias_updated_at']),
    );
  }
}

/// 多帳號匯出包，含 schema 版本、匯出時間與帳號列表。
class AccountsBundle {
  /// 建立 [AccountsBundle]。
  const AccountsBundle({
    required this.exportedAt,
    required this.appVersion,
    required this.lastActiveUid,
    required this.accounts,
  });

  /// 目前讀取端能理解的最高 schema 版本，反序列化時用於相容性檢查。
  static const int maxReadableSchemaVersion = 2;

  /// 此包寫出的 schema 版本：讀取端要能理解這份內容所需的最低版本。
  ///
  /// - 版本 1：既有格式，不含替代記錄。
  /// - 版本 2：含替代記錄（任一筆記錄 id 以 '0' 開頭，見 [isSubstituteId]）。
  ///
  /// 之後新增的版本，同樣取所有成立條件中的最大值；舊版 App 讀到較高版本會被擋下並提示更新。
  int get schemaVersion =>
      accounts.any(
        (a) => a.data.banners.values.any(
          (rs) => rs.any((r) => isSubstituteId(r.id)),
        ),
      )
      ? 2
      : 1;

  /// 匯出時間（UTC）。
  final DateTime exportedAt;

  /// 匯出時的 app 版本字串。
  final String appVersion;

  /// 匯出時的作用中 UID（選填）。
  final String? lastActiveUid;

  /// 匯出的帳號列表。
  final List<ExportedAccount> accounts;

  /// 序列化為 JSON。
  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'app': accountsBundleAppId,
    'exported_at': exportedAt.toUtc().toIso8601String(),
    'app_version': appVersion,
    'last_active_uid': lastActiveUid,
    'accounts': accounts.map((a) => a.toJson()).toList(growable: false),
  };

  /// 從 JSON 還原 [AccountsBundle]。
  ///
  /// schema 版本高於支援版本時丟 [UnsupportedSchemaVersionException]；其餘格式錯誤丟 [FormatException]。
  factory AccountsBundle.fromJson(Map<String, dynamic> json) {
    final version = json['schema_version'];
    if (version is! int) {
      throw const FormatException('Missing or invalid "schema_version"');
    }
    if (version > maxReadableSchemaVersion) {
      throw UnsupportedSchemaVersionException(version);
    }

    final rawAccounts = json['accounts'];
    if (rawAccounts is! List) {
      throw const FormatException('Missing or invalid "accounts" array');
    }

    final accounts = <ExportedAccount>[];
    final seen = <String>{};
    for (var i = 0; i < rawAccounts.length; i++) {
      final entry = rawAccounts[i];
      if (entry is! Map<String, dynamic>) {
        throw FormatException('accounts[$i] must be an object');
      }
      ExportedAccount account;
      try {
        account = ExportedAccount.fromJson(entry);
      } catch (e) {
        throw FormatException('accounts[$i]: $e');
      }
      if (!seen.add(account.data.uid)) {
        throw FormatException(
          'Duplicate UID in accounts: ${sanitizeUid(account.data.uid)}',
        );
      }
      accounts.add(account);
    }

    DateTime parsedExportedAt;
    final rawExportedAt = json['exported_at'];
    if (rawExportedAt is String) {
      try {
        parsedExportedAt = DateTime.parse(rawExportedAt);
      } catch (_) {
        parsedExportedAt = DateTime.now().toUtc();
      }
    } else {
      parsedExportedAt = DateTime.now().toUtc();
    }

    final rawAppVersion = json['app_version'];
    final appVersion = rawAppVersion is String ? rawAppVersion : '';

    final rawLastActive = json['last_active_uid'];
    final lastActiveUid = rawLastActive is String ? rawLastActive : null;

    return AccountsBundle(
      exportedAt: parsedExportedAt,
      appVersion: appVersion,
      lastActiveUid: lastActiveUid,
      accounts: accounts,
    );
  }
}
