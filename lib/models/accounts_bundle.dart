import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';

/// 匯入檔的 schema 版本高於目前 App 支援版本時拋出，供 UI 給出「請更新 App」指引。
class UnsupportedSchemaVersionException implements Exception {
  /// 建立 [UnsupportedSchemaVersionException]。
  const UnsupportedSchemaVersionException(this.version);

  /// 匯入檔宣告的 schema 版本（高於 [AccountsBundle.currentSchemaVersion]）。
  final int version;

  @override
  String toString() => 'UnsupportedSchemaVersionException(version: $version)';
}

/// 單一匯出帳號：包含祈願資料與選填別名。
class ExportedAccount {
  /// 建立 [ExportedAccount]。
  const ExportedAccount({required this.data, this.alias});

  /// 帳號的祈願存檔資料。
  final BannerStorage data;

  /// 使用者自定義別名（選填）。
  final String? alias;

  /// 序列化為 JSON，alias 為空時省略該欄位。
  Map<String, dynamic> toJson() {
    final a = alias;
    return {...data.toJson(), if (a != null && a.isNotEmpty) 'alias': a};
  }

  /// 從 JSON 還原 [ExportedAccount]，alias 空白視同無別名。
  factory ExportedAccount.fromJson(Map<String, dynamic> json) {
    final rawAlias = json['alias'];
    final alias = (rawAlias is String && rawAlias.trim().isNotEmpty)
        ? rawAlias.trim()
        : null;
    return ExportedAccount(data: BannerStorage.fromJson(json), alias: alias);
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

  /// 目前支援的 schema 版本號，反序列化時用於相容性檢查。
  static const int currentSchemaVersion = 1;

  /// 此包的 schema 版本，固定回傳 [currentSchemaVersion]。
  int get schemaVersion => currentSchemaVersion;

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
    if (version > currentSchemaVersion) {
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
        throw FormatException('Duplicate UID in accounts: ${account.data.uid}');
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
