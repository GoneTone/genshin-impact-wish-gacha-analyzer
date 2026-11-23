import 'package:flutter_test/flutter_test.dart';

import '../../tool/android_version_code.dart';

void main() {
  test('valid tag prints VERSION_CODE and BUILD_NAME, exit 0', () {
    final out = StringBuffer();
    final err = StringBuffer();
    expect(runVersionCodeCli(['v1.9.0-rc.2'], out, err), 0);
    expect(out.toString(), 'VERSION_CODE=1090002\nBUILD_NAME=1.9.0-rc.2\n');
    expect(err.toString(), isEmpty);
  });

  test('invalid tag prints the error to stderr, non-zero exit', () {
    final out = StringBuffer();
    final err = StringBuffer();
    expect(runVersionCodeCli(['v01.9.0'], out, err), isNot(0));
    expect(out.toString(), isEmpty);
    expect(err.toString(), contains('v01.9.0'));
  });

  test('wrong argument count prints usage, exit 64', () {
    for (final args in [
      <String>[],
      ['v1.9.0', 'extra'],
    ]) {
      final out = StringBuffer();
      final err = StringBuffer();
      expect(runVersionCodeCli(args, out, err), 64);
      expect(out.toString(), isEmpty);
      expect(err.toString(), startsWith('Usage:'));
    }
  });
}
