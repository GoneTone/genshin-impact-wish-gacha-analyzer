import 'package:flutter_test/flutter_test.dart';
import 'package:genshin_impact_wish_gacha_analyzer/state/gacha_capture.dart';
import 'package:logging/logging.dart';

void main() {
  test('Rust bridge 未初始化時，RustGachaCapture.start 不會直接拋出例外', () async {
    final session = RustGachaCapture().start();

    await expectLater(session.result, throwsA(isA<StateError>()));
  });

  test('capture error 的 log 只帶型別，不帶 error 物件', () async {
    final records = <LogRecord>[];
    Logger.root.level = Level.ALL;
    final sub = Logger.root.onRecord.listen(records.add);
    addTearDown(sub.cancel);

    final session = RustGachaCapture().start();
    await expectLater(session.result, throwsA(isA<StateError>()));

    final rec = records.firstWhere(
      (r) => r.message.startsWith('capture error'),
    );
    expect(rec.message, contains('error=StateError'));
    expect(rec.error, isNull);
  });
}
