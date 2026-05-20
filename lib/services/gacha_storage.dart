import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/log_sanitize.dart';

/// 負責祈願資料與已擷取 URL 的本地 JSON 讀寫。
class GachaStorage {
  GachaStorage(this.baseDir);

  /// Logger 實例（gacha 儲存）。
  static final _log = Logger('gacha.storage');

  /// `<applicationSupportDirectory>/gacha_data/`，main.dart 創建後傳入
  final Directory baseDir;

  /// 回傳 [uid] 對應的資料檔路徑。
  File _dataFile(String uid) => File('${baseDir.path}/$uid.json');

  /// 回傳 [uid] 對應的已擷取 URL 檔路徑。
  File _urlFile(String uid) => File('${baseDir.path}/$uid.url.json');

  /// 讀取 [uid] 的祈願資料；檔案不存在時回傳 null。
  Future<BannerStorage?> load(String uid) async {
    final f = _dataFile(uid);
    if (!await f.exists()) return null;
    try {
      final text = await f.readAsString();
      final json = jsonDecode(text) as Map<String, dynamic>;
      return BannerStorage.fromJson(json);
    } catch (e, st) {
      _log.severe('load failed for uid=${sanitizeUid(uid)}', e, st);
      rethrow;
    }
  }

  /// 將 [data] 寫回磁碟。
  Future<void> save(BannerStorage data) async {
    try {
      await _atomicWrite(_dataFile(data.uid), jsonEncode(data.toJson()));
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
      uids.add(name.substring(0, name.length - '.json'.length));
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
    await _atomicWrite(_urlFile(uid), jsonEncode(json));
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
    final f = _dataFile(uid);
    if (await f.exists()) await f.delete();
    await deleteCapturedUrl(uid);
    _log.info('delete uid=${sanitizeUid(uid)}');
  }

  /// 清除 [baseDir] 內所有 `.json` 檔案。
  Future<void> clearAll() async {
    if (!await baseDir.exists()) return;
    final entries = await baseDir.list().toList();
    for (final e in entries) {
      if (e is File && e.path.endsWith('.json')) {
        await e.delete();
      }
    }
    _log.info('clear all gacha data');
  }

  /// 先寫入 `.tmp` 再 rename，確保寫入的原子性。
  Future<void> _atomicWrite(File target, String content) async {
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(content);
    await tmp.rename(target.path); // atomic on same volume
  }
}
