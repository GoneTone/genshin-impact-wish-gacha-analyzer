import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:logging/logging.dart';

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

/// 一輪同步的結果。
sealed class CloudSyncOutcome {
  /// 建立 [CloudSyncOutcome]。
  const CloudSyncOutcome();
}

/// 同步成功：已上傳本機資料。
class CloudSyncSuccess extends CloudSyncOutcome {
  /// 建立 [CloudSyncSuccess]。
  const CloudSyncSuccess({required this.uploadedFingerprint});

  /// 已上傳內容的 [syncFingerprint]，供後續變動觸發的跳過判斷。
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
Future<CloudSyncOutcome> runSyncRound({
  required CloudSyncRemote remote,
  required List<String> pendingRemovals,
  required Future<void> Function(AccountsBundle bundle) applyRemote,
  required String Function() exportLocal,
  required Future<void> Function(List<String> uids) clearPendingRemovals,
}) async {
  final sw = Stopwatch()..start();
  final remoteJson = await remote.download();

  if (remoteJson != null) {
    AccountsBundle? bundle;
    try {
      bundle = importAccounts(remoteJson);
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
        await applyRemote(filtered);
      } else {
        _log.info('merge skipped: remote has no applicable accounts');
      }
    }
  }

  final localJson = exportLocal();
  await remote.upload(localJson);
  await clearPendingRemovals(pendingRemovals);
  _log.info(
    'round done in ${sw.elapsedMilliseconds}ms, '
    'remote=${remoteJson?.length ?? 0}B uploaded=${localJson.length}B '
    'pendingRemovalsCleared=${pendingRemovals.length}',
  );
  return CloudSyncSuccess(uploadedFingerprint: syncFingerprint(localJson));
}

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
