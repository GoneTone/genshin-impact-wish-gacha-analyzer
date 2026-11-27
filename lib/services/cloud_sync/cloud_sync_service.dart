import 'dart:convert';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/alias_merge.dart';
import 'package:genshin_impact_wish_gacha_analyzer/models/accounts_bundle.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/accounts_import.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_sync_remote.dart';

/// Logger 實例（同步編排）。
final _log = Logger('cloudsync.sync');

/// 計算 bundle JSON 的同步指紋：去除 `exported_at` 後的 SHA-256。
///
/// 用於「本機資料變動」觸發的跳過判斷——內容沒變（只有匯出時間戳會變）就不再跑一輪。
String syncFingerprint(String bundleJson) {
  final map = Map<String, dynamic>.from(
    jsonDecode(bundleJson) as Map<String, dynamic>,
  )..remove('exported_at');
  return sha256.convert(utf8.encode(jsonEncode(map))).toString();
}

/// 在背景 isolate 算 [syncFingerprint]：同步檔有數 MB，在主 isolate 算會卡住畫面。
Future<String> syncFingerprintInBackground(String bundleJson) =>
    Isolate.run(() => syncFingerprint(bundleJson));

/// 在背景 isolate 解析雲端 bundle 並算其 [syncFingerprint]（例外原樣傳回呼叫端）。
Future<(AccountsBundle, String)> _importInBackground(String json) =>
    Isolate.run(() => (importAccounts(json), syncFingerprint(json)));

/// 一輪同步的結果。
sealed class CloudSyncOutcome {
  /// 建立 [CloudSyncOutcome]。
  const CloudSyncOutcome();
}

/// 同步成功：雲端已與本機內容一致（已上傳，或內容相同而跳過上傳）。
class CloudSyncSuccess extends CloudSyncOutcome {
  /// 建立 [CloudSyncSuccess]。
  const CloudSyncSuccess({required this.uploadedFingerprint});

  /// 雲端目前內容（即本機內容）的 [syncFingerprint]，供後續變動觸發的跳過判斷。
  final String uploadedFingerprint;
}

/// 雲端檔 schema 比本機支援的新，整輪跳過（不合併、不上傳），提示使用者更新 App。
class CloudSyncSkippedSchemaTooNew extends CloudSyncOutcome {
  /// 建立 [CloudSyncSkippedSchemaTooNew]。
  const CloudSyncSkippedSchemaTooNew();
}

/// 執行一輪「下載 → 合併 → 上傳」同步。
///
/// - [pendingRemovals] 內的 UID 會先從下載的雲端 bundle 剔除（防止剛刪的帳號
///   被合併復活），上傳成功後經 [clearPendingRemovals] 清除。
/// - 雲端檔損毀（非 JSON／外來檔）視為不存在，直接以本機內容上傳自癒。
/// - [applyRemote] 拋出的例外（如更新進行中）原樣往外傳，由呼叫端重排。
/// - 合併前本機已與雲端相同就整輪跳過合併與上傳；合併後才相同則只省上傳。
Future<CloudSyncOutcome> runSyncRound({
  required CloudSyncRemote remote,
  required List<String> pendingRemovals,
  required Future<void> Function(AccountsBundle bundle) applyRemote,
  required Future<String> Function() exportLocal,
  required Future<void> Function(List<String> uids) clearPendingRemovals,
}) async {
  final sw = Stopwatch()..start();
  final remoteJson = await remote.download();
  String? remoteFingerprint;

  if (remoteJson != null) {
    AccountsBundle? bundle;
    try {
      (bundle, remoteFingerprint) = await _importInBackground(remoteJson);
    } on UnsupportedSchemaVersionException catch (e) {
      _log.warning('skip round: remote schema v${e.version} too new');
      return const CloudSyncSkippedSchemaTooNew();
    } on FormatException catch (e) {
      _log.severe('remote file corrupt (treated as absent): ${e.message}');
    } on ForeignBundleException {
      _log.severe('remote file foreign (treated as absent)');
    }
    if (bundle != null) {
      final filtered = _withoutUids(bundle, pendingRemovals.toSet());
      if (filtered.accounts.isNotEmpty) {
        // 雲端與本機已一致（同一台裝置重開 App 最常見）：合併與上傳都不必做，
        // 省下主 isolate 上的逐筆比對；指紋在背景算。
        final localBefore = await exportLocal();
        final before = await syncFingerprintInBackground(localBefore);
        if (before == remoteFingerprint) {
          await clearPendingRemovals(pendingRemovals);
          _log.info(
            'round done in ${sw.elapsedMilliseconds}ms, '
            'remote=${remoteJson.length}B already in sync (merge and upload skipped)',
          );
          return CloudSyncSuccess(uploadedFingerprint: before);
        }
        // 跨裝置時常只差「目前選中的帳號」等設定，記錄完全相同；這些帳號合併不會有任何
        // 變化，先在背景挑掉（也就不會進入資料語言轉換），省下主 isolate 上的逐筆比對。
        final same = await _identicalAccountsInBackground(
          remoteJson,
          localBefore,
        );
        final toMerge = _withoutUids(filtered, same);
        if (toMerge.accounts.isNotEmpty) {
          await applyRemote(toMerge);
        } else {
          _log.info('merge skipped: all ${same.length} remote accounts match');
        }
      } else {
        _log.info('merge skipped: remote has no applicable accounts');
      }
    }
  }

  final localJson = await exportLocal();
  final localFingerprint = await syncFingerprintInBackground(localJson);
  final unchanged = localFingerprint == remoteFingerprint;
  if (!unchanged) await remote.upload(localJson);
  await clearPendingRemovals(pendingRemovals);
  _log.info(
    'round done in ${sw.elapsedMilliseconds}ms, '
    'remote=${remoteJson?.length ?? 0}B '
    "uploaded=${unchanged ? 'skipped (unchanged)' : '${localJson.length}B'} "
    'pendingRemovalsCleared=${pendingRemovals.length}',
  );
  return CloudSyncSuccess(uploadedFingerprint: localFingerprint);
}

/// 在背景比對兩份 bundle JSON，回傳可跳過合併的帳號 UID：內容（不看別名與其修改時間）相同，且依 [incomingAliasWins] 雲端別名不會勝出。
Future<Set<String>> _identicalAccountsInBackground(
  String remoteJson,
  String localJson,
) => Isolate.run(() {
  Map<String, Map<String, dynamic>> byUid(String json) => {
    for (final a
        in (jsonDecode(json) as Map<String, dynamic>)['accounts']
            as List<dynamic>)
      (a as Map<String, dynamic>)['uid'] as String: a,
  };
  String content(Map<String, dynamic> a) => jsonEncode(
    Map<String, dynamic>.from(a)
      ..remove('alias')
      ..remove('alias_updated_at'),
  );
  bool remoteAliasWins(Map<String, dynamic> l, Map<String, dynamic> r) =>
      incomingAliasWins(
        localAlias: l['alias'] as String?,
        localUpdatedAt: parseAliasUpdatedAt(l['alias_updated_at']),
        incomingAlias: r['alias'] as String?,
        incomingUpdatedAt: parseAliasUpdatedAt(r['alias_updated_at']),
      );
  final remote = byUid(remoteJson);
  final local = byUid(localJson);
  return {
    for (final MapEntry(:key, :value) in remote.entries)
      // 別名規則同 _runImport：雲端別名（含較新的清空）會勝出時，要靠合併帶進來。
      if (local[key] case final l?
          when content(l) == content(value) && !remoteAliasWins(l, value))
        key,
  };
});

/// 回傳剔除 [uids] 帳號後的新 bundle（其餘欄位不變）。
AccountsBundle _withoutUids(AccountsBundle bundle, Set<String> uids) {
  if (uids.isEmpty) return bundle;
  return AccountsBundle(
    exportedAt: bundle.exportedAt,
    appVersion: bundle.appVersion,
    lastActiveUid: bundle.lastActiveUid,
    accounts: bundle.accounts
        .where((a) => !uids.contains(a.data.uid))
        .toList(growable: false),
  );
}
