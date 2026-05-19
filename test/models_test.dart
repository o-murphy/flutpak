import 'package:flutpak/flutpak.dart';
import 'package:test/test.dart';

void main() {
  group('ArchiveSource', () {
    test('toJson minimal', () {
      final s = ArchiveSource(
        url: 'https://example.com/pkg-1.0.tar.gz',
        sha256: 'abc123',
        dest: '.pub-cache/hosted/pub.dev/pkg-1.0',
      );
      expect(s.toJson(), {
        'type': 'archive',
        'url': 'https://example.com/pkg-1.0.tar.gz',
        'sha256': 'abc123',
        'dest': '.pub-cache/hosted/pub.dev/pkg-1.0',
        'strip-components': 1,
      });
    });

    test('toJson with only-arches', () {
      final s = ArchiveSource(
        url: 'https://example.com/x64.zip',
        sha256: 'def456',
        dest: 'flutter/bin/cache',
        stripComponents: 0,
        onlyArches: ['x86_64'],
      );
      final json = s.toJson();
      expect(json['only-arches'], ['x86_64']);
      expect(json['strip-components'], 0);
    });

    test('toJson omits only-arches when null', () {
      final s = ArchiveSource(
        url: 'https://example.com/all.zip',
        sha256: 'ff',
        dest: 'some/dest',
        stripComponents: 0,
      );
      expect(s.toJson().containsKey('only-arches'), isFalse);
    });
  });

  group('GitSource', () {
    test('toJson with all fields', () {
      final s = GitSource(
        url: 'https://github.com/flutter/flutter.git',
        tag: '3.41.9',
        commit: 'abc123def456',
        dest: 'flutter',
        disableSubmodules: true,
      );
      expect(s.toJson(), {
        'type': 'git',
        'url': 'https://github.com/flutter/flutter.git',
        'tag': '3.41.9',
        'commit': 'abc123def456',
        'dest': 'flutter',
        'disable-submodules': true,
      });
    });

    test('toJson omits optional nulls', () {
      final s = GitSource(url: 'https://github.com/example/repo.git');
      final json = s.toJson();
      expect(json.containsKey('tag'), isFalse);
      expect(json.containsKey('commit'), isFalse);
      expect(json.containsKey('dest'), isFalse);
    });
  });

  group('FileSource', () {
    test('toJson', () {
      final s = FileSource(
        url: 'https://storage.googleapis.com/flutter/engine_stamp.json',
        sha256: 'deadbeef',
        dest: 'flutter/bin/cache',
      );
      expect(s.toJson(), {
        'type': 'file',
        'url': 'https://storage.googleapis.com/flutter/engine_stamp.json',
        'sha256': 'deadbeef',
        'dest': 'flutter/bin/cache',
      });
    });
  });

  group('ScriptSource', () {
    test('toJson', () {
      final s = ScriptSource(
        commands: ['flutter pub get --offline \$@'],
        dest: 'flutter/bin',
        destFilename: 'setup-flutter.sh',
      );
      expect(s.toJson(), {
        'type': 'script',
        'commands': ['flutter pub get --offline \$@'],
        'dest': 'flutter/bin',
        'dest-filename': 'setup-flutter.sh',
      });
    });
  });

  group('PatchSource', () {
    test('toJson with dest', () {
      final s = PatchSource(
        path: 'patches/objectbox/CMakeLists.txt.patch',
        dest: '.pub-cache/hosted/pub.dev/objectbox_flutter_libs-5.3.1',
      );
      expect(s.toJson(), {
        'type': 'patch',
        'path': 'patches/objectbox/CMakeLists.txt.patch',
        'dest': '.pub-cache/hosted/pub.dev/objectbox_flutter_libs-5.3.1',
      });
    });

    test('toJson without dest', () {
      final s = PatchSource(path: 'patches/flutter/shared.sh.patch');
      expect(s.toJson().containsKey('dest'), isFalse);
    });
  });
}
