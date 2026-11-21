import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart'
    show AccessDeniedException, AuthClient;
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_sync_config.dart';

/// 在背景 isolate 覆寫雲端檔（編碼與送出都不經主 isolate）；寫成 top-level 讓閉包只抓參數。
Future<int> _putInBackground(String fileId, String accessToken, String text) =>
    Isolate.run(() async {
      final client = http.Client();
      try {
        return await putDriveMedia(client, fileId, accessToken, text);
      } finally {
        client.close();
      }
    });

/// 在背景 isolate 做 UTF-8 解碼：數 MB 的同步檔在主 isolate 實機量到約 30ms（掉好幾格）。
///
/// 寫成 top-level 讓閉包只抓參數，不會把 Drive client 等無法跨 isolate 的物件帶進去。
Future<String> _decodeInBackground(Uint8List bytes) =>
    Isolate.run(() => utf8.decode(bytes));

/// 在背景 isolate 做 UTF-8 編碼（理由同 [_decodeInBackground]）。
Future<Uint8List> _encodeInBackground(String text) =>
    Isolate.run(() => utf8.encode(text));

/// 以 [accessToken] 透過 [client] 下載 Drive 檔 [fileId] 的內容並以 UTF-8 解碼。
///
/// 錯誤表面見 [_throwIfDriveError]。
@visibleForTesting
Future<({String text, int bytes})> fetchDriveMedia(
  http.Client client,
  String fileId,
  String accessToken,
) async {
  final resp = await client.get(
    Uri.https('www.googleapis.com', '/drive/v3/files/$fileId', {
      'alt': 'media',
    }),
    headers: {'Authorization': 'Bearer $accessToken'},
  );
  _throwIfDriveError(resp, 'download');
  return (text: utf8.decode(resp.bodyBytes), bytes: resp.bodyBytes.length);
}

/// 以 [accessToken] 透過 [client] 直接覆寫 Drive 檔 [fileId] 的內容（`uploadType=media`）。
///
/// googleapis 預設的 multipart 上傳會把整份內容做 Base64（多約三分之一流量），
/// 而且編碼在呼叫端 isolate 上跑，實機量到每次約 32～47ms（見 docs/superpowers/specs/2026-11-21-ui-stall-fixes-design.md 附錄 B）；這裡直接送原始位元組。
/// 錯誤表面同 [fetchDriveMedia]。回傳送出的位元組數。
@visibleForTesting
Future<int> putDriveMedia(
  http.Client client,
  String fileId,
  String accessToken,
  String content,
) async {
  final bytes = utf8.encode(content);
  final resp = await client.patch(
    Uri.https('www.googleapis.com', '/upload/drive/v3/files/$fileId', {
      'uploadType': 'media',
    }),
    headers: {
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json; charset=utf-8',
    },
    body: bytes,
  );
  _throwIfDriveError(resp, 'upload');
  return bytes.length;
}

/// 依 googleapis／googleapis_auth 的錯誤表面丟例外，讓呼叫端既有的授權失效判斷照常運作：
/// 回應帶 `www-authenticate` 時拋 [AccessDeniedException]（訊息格式同 googleapis_auth），
/// 其他非 2xx 拋 [drive.DetailedApiRequestError]（訊息含回應內容）。
void _throwIfDriveError(http.Response resp, String action) {
  final wwwAuthenticate = resp.headers['www-authenticate'];
  if (wwwAuthenticate != null) {
    throw AccessDeniedException(
      'Access was denied (www-authenticate header was: $wwwAuthenticate).',
    );
  }
  if (resp.statusCode < 200 || resp.statusCode >= 300) {
    throw drive.DetailedApiRequestError(
      resp.statusCode,
      'Drive $action failed: ${resp.body}',
    );
  }
}

/// 在背景 isolate 下載並解碼同步檔：連 HTTP 解析都不經主 isolate（實機約 11ms）。
///
/// 寫成 top-level 讓閉包只抓參數；背景 isolate 自建 client，用完即關。
Future<({String text, int bytes})> _downloadInBackground(
  String fileId,
  String accessToken,
) => Isolate.run(() async {
  final client = http.Client();
  try {
    return await fetchDriveMedia(client, fileId, accessToken);
  } finally {
    client.close();
  }
});

/// 雲端同步檔的遠端存取介面；抽象化以便測試注入 fake。
abstract class CloudSyncRemote {
  /// 下載同步檔內容；檔案不存在回 null。
  Future<String?> download();

  /// 上傳（覆蓋）同步檔內容。
  Future<void> upload(String json);
}

/// 以 Google Drive v3 appDataFolder 實作的 [CloudSyncRemote]，單一檔案
/// [cloudSyncFileName]。
class DriveSyncRemote implements CloudSyncRemote {
  /// 建立 [DriveSyncRemote]，[client] 需為已授權的 HTTP client。
  DriveSyncRemote(http.Client client)
    : _client = client,
      _api = drive.DriveApi(client);

  /// 已授權的 client；為 [AuthClient] 時取其 access token 交給背景 isolate 下載。
  final http.Client _client;

  /// Drive v3 API 入口。
  final drive.DriveApi _api;

  /// Logger 實例（同步遠端存取）。
  static final _log = Logger('cloudsync.sync');

  /// 查找 appDataFolder 內同步檔的 file id；不存在回 null。
  ///
  /// orderBy 讓兩台電腦首次同步同時建檔時，後續各 client 穩定挑到同一個
  /// （最新的）檔案收斂，避免各自讀寫不同孤兒檔。
  Future<String?> _findFileId() async {
    final list = await _api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$cloudSyncFileName'",
      orderBy: 'modifiedTime desc',
      $fields: 'files(id)',
    );
    final files = list.files;
    if (files == null || files.isEmpty) return null;
    return files.first.id;
  }

  /// 下載 appDataFolder 內的同步檔內容；檔案不存在回 null。
  @override
  Future<String?> download() async {
    final id = await _findFileId();
    if (id == null) {
      _log.info('download: no remote file');
      return null;
    }
    // _findFileId 剛用同一個 client 打過 API，自動續期的 token 此時是有效的。
    final client = _client;
    if (client is AuthClient) {
      final result = await _downloadInBackground(
        id,
        client.credentials.accessToken.data,
      );
      _log.info('download: ${result.bytes} bytes (background)');
      return result.text;
    }
    final media =
        await _api.files.get(
              id,
              downloadOptions: drive.DownloadOptions.fullMedia,
            )
            as drive.Media;
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in media.stream) {
      bytes.add(chunk);
    }
    _log.info('download: ${bytes.length} bytes');
    return _decodeInBackground(bytes.takeBytes());
  }

  /// 上傳（覆蓋）appDataFolder 內的同步檔；無檔時建立、有檔時更新。
  @override
  Future<void> upload(String json) async {
    final id = await _findFileId();
    // _findFileId 剛用同一個 client 打過 API，自動續期的 token 此時是有效的。
    final client = _client;
    if (id != null && client is AuthClient) {
      final sent = await _putInBackground(
        id,
        client.credentials.accessToken.data,
        json,
      );
      _log.info('upload: updated, $sent bytes (background)');
      return;
    }
    final data = await _encodeInBackground(json);
    final media = drive.Media(Stream.value(data), data.length);
    if (id == null) {
      await _api.files.create(
        drive.File()
          ..name = cloudSyncFileName
          ..parents = ['appDataFolder'],
        uploadMedia: media,
      );
      _log.info('upload: created, ${data.length} bytes');
    } else {
      await _api.files.update(drive.File(), id, uploadMedia: media);
      _log.info('upload: updated, ${data.length} bytes');
    }
  }
}
