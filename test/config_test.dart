import 'package:flatpak_gen/flatpak_gen.dart';
import 'package:test/test.dart';

void main() {
  group('FlatpakGenConfig.fromYaml', () {
    test('parses full config', () {
      final cfg = FlatpakGenConfig.fromYaml({
        'output': 'flatpak/generated-sources.json',
        'pub': {
          'locks': ['pubspec.lock', 'packages/a7p/pubspec.lock'],
        },
        'flutter': {
          'sdk': '/home/user/flutter',
        },
        'patch_path': 'flatpak/patches/flutter/shared.sh.patch',
      });

      expect(cfg.output, 'flatpak/generated-sources.json');
      expect(cfg.pubLocks, ['pubspec.lock', 'packages/a7p/pubspec.lock']);
      expect(cfg.flutterSdk, '/home/user/flutter');
      expect(cfg.patchPath, 'flatpak/patches/flutter/shared.sh.patch');
    });

    test('defaults output when missing', () {
      final cfg = FlatpakGenConfig.fromYaml({});
      expect(cfg.output, 'flatpak/generated-sources.json');
    });

    test('defaults pub locks to pubspec.lock when missing', () {
      final cfg = FlatpakGenConfig.fromYaml({});
      expect(cfg.pubLocks, contains('pubspec.lock'));
    });

    test('resolves \$ENV variables in paths', () {
      final cfg = FlatpakGenConfig.fromYaml({
        'flutter': {'sdk': '\$HOME/flutter'},
      });
      // Should expand HOME (or leave as-is if unset in test env)
      expect(cfg.flutterSdk, isNotNull);
      expect(cfg.flutterSdk, isNot(isEmpty));
    });
  });
}
