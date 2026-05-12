import 'dart:convert';

import 'package:genshin_impact_wish_gacha_analyzer/models/all_accounts_bundle.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/uid_ordering.dart';

/// 把目前狀態打包成 [AllAccountsBundle] 並序列化成 pretty-printed JSON 字串。
///
/// 帳號順序套用 [mergeUidOrder]，與設定頁顯示順序一致。
String exportAllAccounts({
  required Map<String, BannerStorage> byUid,
  required List<String> uidOrder,
  required Map<String, String> uidAliases,
  required String? lastActiveUid,
  required String appVersion,
  required DateTime now,
}) {
  final ordered = mergeUidOrder(
    knownUids: byUid.keys,
    customOrder: uidOrder,
    lastUpdatedOf: (u) => byUid[u]!.lastUpdated,
  );

  final accounts = [
    for (final uid in ordered)
      ExportedAccount(data: byUid[uid]!, alias: uidAliases[uid]),
  ];

  final bundle = AllAccountsBundle(
    exportedAt: now.toUtc(),
    appVersion: appVersion,
    lastActiveUid: lastActiveUid,
    accounts: accounts,
  );

  return const JsonEncoder.withIndent('  ').convert(bundle.toJson());
}
