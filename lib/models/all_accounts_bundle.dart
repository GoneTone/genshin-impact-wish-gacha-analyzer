import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';

class ExportedAccount {
  const ExportedAccount({required this.data, this.alias});

  final BannerStorage data;
  final String? alias;

  Map<String, dynamic> toJson() {
    final base = data.toJson();
    if (alias != null && alias!.isNotEmpty) {
      base['alias'] = alias;
    }
    return base;
  }

  factory ExportedAccount.fromJson(Map<String, dynamic> json) {
    final rawAlias = json['alias'];
    final alias = (rawAlias is String && rawAlias.trim().isNotEmpty)
        ? rawAlias.trim()
        : null;
    return ExportedAccount(data: BannerStorage.fromJson(json), alias: alias);
  }
}

class AllAccountsBundle {
  const AllAccountsBundle({
    required this.schemaVersion,
    required this.exportedAt,
    required this.appVersion,
    required this.lastActiveUid,
    required this.accounts,
  });

  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final DateTime exportedAt;
  final String appVersion;
  final String? lastActiveUid;
  final List<ExportedAccount> accounts;

  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'exported_at': exportedAt.toUtc().toIso8601String(),
    'app_version': appVersion,
    'last_active_uid': lastActiveUid,
    'accounts': accounts.map((a) => a.toJson()).toList(growable: false),
  };

  factory AllAccountsBundle.fromJson(Map<String, dynamic> json) {
    final version = json['schema_version'];
    if (version is! int) {
      throw const FormatException('Missing or invalid "schema_version"');
    }
    if (version > currentSchemaVersion) {
      throw FormatException(
        'Unsupported schema version: $version. Please update the app.',
      );
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
        parsedExportedAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      }
    } else {
      parsedExportedAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }

    final rawAppVersion = json['app_version'];
    final appVersion = rawAppVersion is String ? rawAppVersion : '';

    final rawLastActive = json['last_active_uid'];
    final lastActiveUid = rawLastActive is String ? rawLastActive : null;

    return AllAccountsBundle(
      schemaVersion: version,
      exportedAt: parsedExportedAt,
      appVersion: appVersion,
      lastActiveUid: lastActiveUid,
      accounts: accounts,
    );
  }
}
