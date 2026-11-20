import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:genshin_impact_wish_gacha_analyzer/services/cloud_sync/google_authorization_gateway.dart';

void main() {
  group('isUserCancellation', () {
    test('canceled code → true', () {
      expect(
        isUserCancellation(
          const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
        ),
        isTrue,
      );
    });

    test('unknownError with Play services status 16 → true', () {
      expect(
        isUserCancellation(
          const GoogleSignInException(
            code: GoogleSignInExceptionCode.unknownError,
            description:
                'SDK reported an exception: 16: [16] Cancelled by user.',
          ),
        ),
        isTrue,
      );
    });

    test('unknownError with another status → false', () {
      expect(
        isUserCancellation(
          const GoogleSignInException(
            code: GoogleSignInExceptionCode.unknownError,
            description: 'SDK reported an exception: 10: DEVELOPER_ERROR',
          ),
        ),
        isFalse,
      );
    });

    test('unknownError without description → false', () {
      expect(
        isUserCancellation(
          const GoogleSignInException(
            code: GoogleSignInExceptionCode.unknownError,
          ),
        ),
        isFalse,
      );
    });

    test('other codes → false', () {
      expect(
        isUserCancellation(
          const GoogleSignInException(
            code: GoogleSignInExceptionCode.clientConfigurationError,
            description: 'SDK reported an exception: 16: x',
          ),
        ),
        isFalse,
      );
    });
  });
}
