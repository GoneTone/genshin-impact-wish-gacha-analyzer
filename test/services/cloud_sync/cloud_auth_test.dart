import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/oauth2/v2.dart' show DetailedApiRequestError;
import 'package:googleapis_auth/googleapis_auth.dart'
    show AccessDeniedException;
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/cloud_auth.dart';

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

    test(
      'Drive 403 insufficient_scope 訊息（www-authenticate header 路徑）→ true',
      () {
        expect(
          isInsufficientScope(
            Exception(
              'Access was denied (www-authenticate header was: '
              'Bearer realm="https://accounts.google.com/", '
              'error="insufficient_scope", scope="...").',
            ),
          ),
          isTrue,
        );
      },
    );

    test('DetailedApiRequestError 的 JSON message 路徑 → true', () {
      expect(
        isInsufficientScope(
          Exception(
            'DetailedApiRequestError(status: 403, message: '
            'Request had insufficient authentication scopes.)',
          ),
        ),
        isTrue,
      );
    });

    test('結構化 reason ACCESS_TOKEN_SCOPE_INSUFFICIENT → true', () {
      expect(
        isInsufficientScope(
          Exception('reason: ACCESS_TOKEN_SCOPE_INSUFFICIENT'),
        ),
        isTrue,
      );
    });

    test('一般網路錯誤 → false', () {
      expect(isInsufficientScope(Exception('Connection refused')), isFalse);
    });
  });

  group('isInvalidToken', () {
    test('DetailedApiRequestError 401 → true', () {
      expect(isInvalidToken(DetailedApiRequestError(401, 'x')), isTrue);
    });

    test('AccessDeniedException 帶 invalid_token → true', () {
      expect(
        isInvalidToken(
          AccessDeniedException(
            'Access was denied (www-authenticate header was: '
            'Bearer realm="https://accounts.google.com/", '
            'error="invalid_token").',
          ),
        ),
        isTrue,
      );
    });

    test('insufficient_scope 的 AccessDeniedException → false', () {
      expect(
        isInvalidToken(
          AccessDeniedException(
            'Access was denied (www-authenticate header was: '
            'Bearer error="insufficient_scope").',
          ),
        ),
        isFalse,
      );
    });

    test('DetailedApiRequestError 403 → false', () {
      expect(isInvalidToken(DetailedApiRequestError(403, 'x')), isFalse);
    });

    test('一般網路錯誤 → false', () {
      expect(isInvalidToken(Exception('Connection refused')), isFalse);
    });
  });
}
