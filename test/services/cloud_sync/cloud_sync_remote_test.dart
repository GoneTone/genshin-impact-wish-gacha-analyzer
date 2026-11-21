import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart'
    show AccessDeniedException;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_auth.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_sync_remote.dart';

void main() {
  group('fetchDriveMedia', () {
    test('downloads the given file with the token and decodes UTF-8', () async {
      late http.Request seen;
      final client = MockClient((req) async {
        seen = req;
        return http.Response.bytes(utf8.encode('{"名稱":"值"}'), 200);
      });
      final result = await fetchDriveMedia(client, 'file-1', 'tok');
      expect(result.text, '{"名稱":"值"}');
      expect(result.bytes, utf8.encode('{"名稱":"值"}').length);
      expect(seen.url.path, '/drive/v3/files/file-1');
      expect(seen.url.queryParameters['alt'], 'media');
      expect(seen.headers['Authorization'], 'Bearer tok');
    });

    test(
      'www-authenticate response → AccessDeniedException the existing check recognises',
      () async {
        final client = MockClient(
          (_) async => http.Response(
            '',
            401,
            headers: {'www-authenticate': 'Bearer error="invalid_token"'},
          ),
        );
        final error = await fetchDriveMedia(
          client,
          'f',
          't',
        ).then<Object?>((_) => null, onError: (Object e) => e);
        expect(error, isA<AccessDeniedException>());
        expect(isInvalidToken(error!), isTrue);
      },
    );

    test(
      'insufficient scope (no www-authenticate) → DetailedApiRequestError',
      () async {
        final client = MockClient(
          (_) async => http.Response(
            '{"error":{"message":"Request had insufficient authentication scopes."}}',
            403,
          ),
        );
        final error = await fetchDriveMedia(
          client,
          'f',
          't',
        ).then<Object?>((_) => null, onError: (Object e) => e);
        expect(error, isA<drive.DetailedApiRequestError>());
        expect((error! as drive.DetailedApiRequestError).status, 403);
        expect(isInsufficientScope(error), isTrue);
      },
    );
  });

  group('putDriveMedia', () {
    test('PATCHes raw UTF-8 bytes with uploadType=media (no base64)', () async {
      late http.Request seen;
      final client = MockClient((req) async {
        seen = req;
        return http.Response('{}', 200);
      });
      const content = '{"名稱":"值"}';
      final sent = await putDriveMedia(client, 'file-1', 'tok', content);
      expect(sent, utf8.encode(content).length);
      expect(seen.method, 'PATCH');
      expect(seen.url.path, '/upload/drive/v3/files/file-1');
      expect(seen.url.queryParameters['uploadType'], 'media');
      expect(seen.headers['Authorization'], 'Bearer tok');
      expect(seen.bodyBytes, utf8.encode(content));
    });

    test(
      'www-authenticate response → AccessDeniedException the existing check recognises',
      () async {
        final client = MockClient(
          (_) async => http.Response(
            '',
            401,
            headers: {'www-authenticate': 'Bearer error="invalid_token"'},
          ),
        );
        final error = await putDriveMedia(
          client,
          'f',
          't',
          '{}',
        ).then<Object?>((_) => null, onError: (Object e) => e);
        expect(error, isA<AccessDeniedException>());
        expect(isInvalidToken(error!), isTrue);
      },
    );

    test(
      'non-2xx without www-authenticate → DetailedApiRequestError',
      () async {
        final client = MockClient((_) async => http.Response('boom', 500));
        final error = await putDriveMedia(
          client,
          'f',
          't',
          '{}',
        ).then<Object?>((_) => null, onError: (Object e) => e);
        expect(error, isA<drive.DetailedApiRequestError>());
        expect((error! as drive.DetailedApiRequestError).status, 500);
        expect(
          (error as drive.DetailedApiRequestError).message,
          contains('Drive upload failed'),
        );
      },
    );
  });
}
