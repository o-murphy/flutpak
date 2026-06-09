import 'package:flutpak/src/version.dart';
import 'package:test/test.dart';

void main() {
  test('packageVersion is a non-empty string', () {
    expect(packageVersion, isNotEmpty);
  });

  test('packageVersion defaults to "dev" when not injected at compile time',
      () {
    // When running under `dart test` (no --define=version=...), the value is 'dev'.
    // In release builds the Makefile/CI passes --define=version=<tag>.
    expect(
      packageVersion,
      anyOf(equals('dev'), matches(r'^\d+\.\d+\.\d+')),
      reason: 'packageVersion must be "dev" or a semver string',
    );
  });
}
