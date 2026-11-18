import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_capture.dart';

void main() {
  test(
    'RustGachaCapture.start does not throw when the Rust bridge is uninitialized',
    () async {
      final session = RustGachaCapture().start();

      await expectLater(session.result, throwsA(isA<StateError>()));
    },
  );
}
