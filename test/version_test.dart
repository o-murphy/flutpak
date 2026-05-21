import 'dart:io';
import 'package:flutpak/src/version.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('packageVersion matches pubspec.yaml version', () {
    final pubspec = File('pubspec.yaml');
    expect(pubspec.existsSync(), isTrue, reason: 'pubspec.yaml not found');

    final yaml = loadYaml(pubspec.readAsStringSync()) as YamlMap;
    final pubspecVersion = yaml['version']?.toString();

    expect(
      packageVersion,
      equals(pubspecVersion),
      reason:
          'lib/src/version.dart is out of sync with pubspec.yaml.\n'
          'Run: dart run tool/update_version.dart',
    );
  });
}
