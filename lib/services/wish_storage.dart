import 'dart:convert';
import 'dart:io';

import 'package:genshin_impact_wish_gacha_analyzer/models/banner_storage.dart';

class WishStorage {
  WishStorage(this.baseDir);

  /// `<applicationSupportDirectory>/wish_data/`，main.dart 創建後傳入
  final Directory baseDir;

  File _dataFile(String uid) => File('${baseDir.path}/$uid.json');
  File _urlFile(String uid) => File('${baseDir.path}/$uid.url.json');

  Future<BannerStorage?> load(String uid) async {
    final f = _dataFile(uid);
    if (!await f.exists()) return null;
    final text = await f.readAsString();
    final json = jsonDecode(text) as Map<String, dynamic>;
    return BannerStorage.fromJson(json);
  }

  Future<void> save(BannerStorage data) async {
    await _atomicWrite(_dataFile(data.uid), jsonEncode(data.toJson()));
  }

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

  Future<String?> loadCapturedUrl(String uid) async {
    final f = _urlFile(uid);
    if (!await f.exists()) return null;
    final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    return json['url'] as String?;
  }

  Future<void> saveCapturedUrl(String uid, String url) async {
    final json = {
      'uid': uid,
      'url': url,
      'captured_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _atomicWrite(_urlFile(uid), jsonEncode(json));
  }

  Future<void> deleteCapturedUrl(String uid) async {
    final f = _urlFile(uid);
    if (await f.exists()) await f.delete();
  }

  Future<void> delete(String uid) async {
    final f = _dataFile(uid);
    if (await f.exists()) await f.delete();
    await deleteCapturedUrl(uid);
  }

  Future<void> clearAll() async {
    if (!await baseDir.exists()) return;
    final entries = await baseDir.list().toList();
    for (final e in entries) {
      if (e is File && e.path.endsWith('.json')) {
        await e.delete();
      }
    }
  }

  Future<void> _atomicWrite(File target, String content) async {
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(content);
    await tmp.rename(target.path); // atomic on same volume
  }
}
