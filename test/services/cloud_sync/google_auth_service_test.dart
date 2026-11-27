import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_sync_config.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/google_auth_service.dart';

import '../../helpers/cloud_sync_fakes.dart';

void main() {
  test(
    'signOut deletes the stored token without any network request',
    () async {
      var requests = 0;
      final store = InMemoryTokenStore()..token = 'refresh-1';
      final svc = GoogleAuthService(
        tokenStore: store,
        baseClientFactory: () => MockClient((_) async {
          requests++;
          return http.Response('', 200);
        }),
      );
      await svc.unlink();
      expect(store.token, isNull);
      expect(requests, 0);
    },
  );

  group('hasRequiredCloudScopes', () {
    test('含 drive.appdata → true', () {
      expect(
        hasRequiredCloudScopes([
          'https://www.googleapis.com/auth/drive.appdata',
          'email',
        ]),
        isTrue,
      );
    });

    test('漏勾 drive.appdata → false', () {
      expect(hasRequiredCloudScopes(['email']), isFalse);
    });
  });

  group('buildResumeCredentials', () {
    test('產出已過期的 UTC Bearer 種子憑證並保留 refresh token', () {
      final c = buildResumeCredentials('refresh-abc');
      expect(c.refreshToken, 'refresh-abc');
      expect(c.accessToken.type, 'Bearer');
      expect(c.accessToken.expiry.isUtc, isTrue);
      expect(c.accessToken.expiry.isBefore(DateTime.now().toUtc()), isTrue);
      expect(c.scopes, cloudSyncScopes);
    });
  });
}
