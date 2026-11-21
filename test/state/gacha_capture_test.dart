import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_capture.dart';

void main() {
  test('Rust bridge 未初始化時，RustGachaCapture.start 不會直接拋出例外', () async {
    final session = RustGachaCapture().start();

    await expectLater(session.result, throwsA(isA<StateError>()));
  });
}
