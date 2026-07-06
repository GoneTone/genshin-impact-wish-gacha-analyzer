import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_sync_remote.dart';

/// 回傳 JSON 200 回應。
http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('download：雲端無檔 → null', () async {
    final client = MockClient((req) async {
      expect(req.url.path, '/drive/v3/files');
      return _json({'files': <Object>[]});
    });
    final remote = DriveSyncRemote(client);
    expect(await remote.download(), isNull);
  });

  test('download：有檔 → 回傳內容', () async {
    final client = MockClient((req) async {
      if (req.url.queryParameters['alt'] == 'media') {
        return http.Response(
          '{"hello":1}',
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return _json({
        'files': [
          {'id': 'file-1'},
        ],
      });
    });
    final remote = DriveSyncRemote(client);
    expect(await remote.download(), '{"hello":1}');
  });

  test('upload：雲端無檔 → 走 create（POST /upload）', () async {
    final calls = <String>[];
    final client = MockClient((req) async {
      calls.add('${req.method} ${req.url.path}');
      if (req.url.path == '/drive/v3/files') {
        return _json({'files': <Object>[]});
      }
      return _json({'id': 'new-file'});
    });
    final remote = DriveSyncRemote(client);
    await remote.upload('{"a":1}');
    expect(
      calls.any((c) => c.startsWith('POST /upload/drive/v3/files')),
      isTrue,
    );
  });

  test('upload：雲端已有檔 → 走 update（PATCH /upload/.../file-1）', () async {
    final calls = <String>[];
    final client = MockClient((req) async {
      calls.add('${req.method} ${req.url.path}');
      if (req.url.path == '/drive/v3/files') {
        return _json({
          'files': [
            {'id': 'file-1'},
          ],
        });
      }
      return _json({'id': 'file-1'});
    });
    final remote = DriveSyncRemote(client);
    await remote.upload('{"a":1}');
    expect(
      calls.any((c) => c.startsWith('PATCH /upload/drive/v3/files/file-1')),
      isTrue,
    );
  });
}
