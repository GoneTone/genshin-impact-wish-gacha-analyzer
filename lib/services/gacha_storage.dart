import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';

/// 負責祈願資料與已擷取 URL 的本地 JSON 讀寫。
class GachaStorage {
  /// 建立 [GachaStorage]，需指定資料根目錄 [baseDir]。
  GachaStorage(this.baseDir);

  /// Logger 實例（gacha 儲存）。
  static final _log = Logger('gacha.storage');

  /// Genshin UID 模式：純數字。
  static final _uidPattern = RegExp(r'^\d+$');

  /// `<applicationSupportDirectory>/gacha_data/`，main.dart 創建後傳入
  final Directory baseDir;

  /// 回傳 [uid] 對應的資料檔路徑（雲端同步匯出會在背景 isolate 直接讀它）。
  File recordsFile(String uid) => File('${baseDir.path}/$uid.json');

  /// 回傳 [uid] 對應的已擷取 URL 檔路徑。
  File _urlFile(String uid) => File('${baseDir.path}/$uid.url.json');

  /// 讀取 [uid] 的祈願資料；檔案不存在時回傳 null。
  Future<BannerStorage?> load(String uid) async {
    final f = recordsFile(uid);
    if (!await f.exists()) return null;
    try {
      return await Isolate.run(() => readRecordsFileSync(f.path));
    } catch (e, st) {
      _log.severe('load failed for uid=${sanitizeUid(uid)}', e, st);
      rethrow;
    }
  }

  /// 將 [data] 寫回磁碟。
  Future<void> save(BannerStorage data) async {
    try {
      await _atomicWrite(
        recordsFile(data.uid),
        await _encodeInBackground(data),
        data.uid,
      );
      final total = data.banners.values.fold<int>(0, (a, b) => a + b.length);
      _log.fine('saved uid=${sanitizeUid(data.uid)} records=$total');
    } catch (e, st) {
      _log.severe('save failed for uid=${sanitizeUid(data.uid)}', e, st);
      rethrow;
    }
  }

  /// 回傳 [baseDir] 中所有已有資料的 UID 列表。
  Future<List<String>> listKnownUids() async {
    if (!await baseDir.exists()) return const [];
    final entries = await baseDir.list().toList();
    final uids = <String>[];
    for (final e in entries) {
      if (e is! File) continue;
      final name = e.uri.pathSegments.last;
      // 必須是 <uid>.json，但不是 <uid>.url.json
      if (name.endsWith('.url.json')) continue;
      if (!name.endsWith('.json')) continue;
      final uid = name.substring(0, name.length - '.json'.length);
      // UID 一律全數字（Genshin server-generated）；非數字檔名忽略，
      // 避免把 hoyowiki_index.json 之類的 metadata 誤當成 UID 載入。
      if (!_uidPattern.hasMatch(uid)) continue;
      uids.add(uid);
    }
    return uids;
  }

  /// 讀取 [uid] 的已擷取 URL；不存在時回傳 null。
  Future<String?> loadCapturedUrl(String uid) async {
    final f = _urlFile(uid);
    if (!await f.exists()) return null;
    final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    return json['url'] as String?;
  }

  /// 將 [url] 寫入 [uid] 的 URL 檔。
  Future<void> saveCapturedUrl(String uid, String url) async {
    final json = {
      'uid': uid,
      'url': url,
      'captured_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _atomicWrite(_urlFile(uid), jsonEncode(json), uid);
    _log.fine('saved captured url for uid=${sanitizeUid(uid)}');
  }

  /// 刪除 [uid] 的 URL 檔（若存在）。
  Future<void> deleteCapturedUrl(String uid) async {
    final f = _urlFile(uid);
    if (await f.exists()) {
      await f.delete();
      _log.fine('deleted captured url for uid=${sanitizeUid(uid)}');
    }
  }

  /// 刪除 [uid] 的所有本地資料（資料檔 + URL 檔）。
  Future<void> delete(String uid) async {
    final f = recordsFile(uid);
    if (await f.exists()) await _retryWhileHeld(f.delete, uid);
    await deleteCapturedUrl(uid);
    _log.info('delete uid=${sanitizeUid(uid)}');
  }

  /// 清除 [baseDir] 內所有 `.json` 檔案。
  Future<void> clearAll() async {
    if (!await baseDir.exists()) return;
    final entries = await baseDir.list().toList();
    for (final e in entries) {
      if (e is File && e.path.endsWith('.json')) {
        await _retryWhileHeld(e.delete, e.uri.pathSegments.last);
      }
    }
    _log.info('clear all gacha data');
  }

  /// 先寫入 `.tmp` 再 rename，確保寫入的原子性。
  Future<void> _atomicWrite(File target, String content, String uid) async {
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(content);
    await _retryWhileHeld(
      () => tmp.rename(target.path), // atomic on same volume
      uid,
    );
  }

  /// 執行 [op]；Windows 上背景 isolate 讀檔會暫時占住檔案，遇 [PathAccessException] 時短暫退避重試。
  Future<void> _retryWhileHeld(
    Future<Object?> Function() op,
    String uid,
  ) async {
    // Dart 開檔不帶 FILE_SHARE_DELETE，讀檔期間 rename／delete 會被擋；讀檔只持續毫秒級，不需要鎖。
    var delay = const Duration(milliseconds: 20);
    for (var attempt = 1; ; attempt++) {
      try {
        await op();
        if (attempt > 1) {
          _log.info(
            'file op succeeded after retry uid=${sanitizeUid(uid)} '
            'retries=${attempt - 1}',
          );
        }
        return;
      } on PathAccessException {
        if (attempt == _maxAttempts) rethrow;
        await Future<void>.delayed(delay);
        delay *= 2;
      }
    }
  }

  /// [_retryWhileHeld] 的最多嘗試次數（等待 20、40、80、160 ms，合計約 300 ms）。
  static const _maxAttempts = 5;
}

/// 在背景 isolate 把 [data] 編成 JSON：大帳號的 jsonEncode 在主 isolate 實機量到數十毫秒。
///
/// 送過去的物件複製仍在主 isolate，但比整份編碼便宜得多；寫成 top-level 讓閉包只抓參數。
Future<String> _encodeInBackground(BannerStorage data) =>
    Isolate.run(() => jsonEncode(data.toJson()));

/// 同步讀取並解析 [path] 的記錄檔；只在背景 isolate 呼叫（匯出與 [GachaStorage.load] 共用）。
BannerStorage readRecordsFileSync(String path) => BannerStorage.fromJson(
  jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>,
);
