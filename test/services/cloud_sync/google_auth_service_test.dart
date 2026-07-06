import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_sync_config.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/google_auth_service.dart';

void main() {
  group('isInvalidGrant', () {
    test('訊息含 invalid_grant → true', () {
      expect(
        isInvalidGrant(Exception('Refresh failed: invalid_grant')),
        isTrue,
      );
    });

    test('一般網路錯誤 → false', () {
      expect(isInvalidGrant(Exception('Connection refused')), isFalse);
    });
  });

  group('isInsufficientScope', () {
    test('insufficient_scope → true', () {
      expect(isInsufficientScope(Exception('401 insufficient_scope')), isTrue);
    });

    test('insufficient authentication scopes → true', () {
      expect(
        isInsufficientScope(
          Exception('Request had insufficient authentication scopes.'),
        ),
        isTrue,
      );
    });

    test('一般網路錯誤 → false', () {
      expect(isInsufficientScope(Exception('Connection refused')), isFalse);
    });
  });

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
