import 'dart:io';

import 'package:flutpak/flutpak.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final fixtureRepo =
      p.join(Directory.current.path, 'test', 'fixtures', 'path_deps');
  final appDir = p.join(fixtureRepo, 'app');
  final insideLock = p.join(appDir, 'pubspec.lock');
  final locksDir =
      p.join(Directory.current.path, 'test', 'fixtures', 'path_deps_locks');

  group('parsePathPackagesFromLock', () {
    test('reads source:path entries and ignores hosted packages', () {
      final pkgs = parsePathPackagesFromLock(insideLock);
      expect(pkgs, hasLength(1));
      expect(pkgs.single.name, 'shared');
      expect(pkgs.single.path, '../packages/shared');
      expect(pkgs.single.relative, isTrue);
    });

    test('returns empty for a missing lock file', () {
      expect(parsePathPackagesFromLock('no-such.lock'), isEmpty);
    });
  });

  group('classifyPathDependency', () {
    test('classifies a monorepo ../packages path as inside the repo', () {
      final pkg = parsePathPackagesFromLock(insideLock).single;
      final classified = classifyPathDependency(
        package: pkg,
        appDir: appDir,
        repoRoot: fixtureRepo,
      );
      expect(classified.location, PathDepLocation.insideRepo);
      expect(
        p.equals(classified.resolvedPath!,
            p.join(fixtureRepo, 'packages', 'shared')),
        isTrue,
      );
    });

    test('classifies a relative path outside the repo as outsideRepo', () {
      final pkg =
          parsePathPackagesFromLock(p.join(locksDir, 'outside.lock')).single;
      final classified = classifyPathDependency(
        package: pkg,
        appDir: appDir,
        repoRoot: fixtureRepo,
      );
      expect(classified.location, PathDepLocation.outsideRepo);
    });

    test('classifies an absolute path as absolute', () {
      final pkg =
          parsePathPackagesFromLock(p.join(locksDir, 'absolute.lock')).single;
      final classified = classifyPathDependency(
        package: pkg,
        appDir: appDir,
        repoRoot: fixtureRepo,
      );
      expect(classified.location, PathDepLocation.absolute);
    });
  });

  group('validatePathDependencies', () {
    test('accepts an in-repo path package', () {
      final results = validatePathDependencies(
        lockFilePaths: [insideLock],
        repoRoot: fixtureRepo,
      );
      expect(results, hasLength(1));
      expect(results.single.location, PathDepLocation.insideRepo);
    });

    test('fails clearly for a path outside the repo', () {
      expect(
        () => validatePathDependencies(
          lockFilePaths: [p.join(locksDir, 'outside.lock')],
          repoRoot: fixtureRepo,
        ),
        throwsA(isA<PathDependencyException>().having(
          (e) => e.message,
          'message',
          contains('outside the repository'),
        )),
      );
    });

    test('fails clearly for an absolute path', () {
      expect(
        () => validatePathDependencies(
          lockFilePaths: [p.join(locksDir, 'absolute.lock')],
          repoRoot: fixtureRepo,
        ),
        throwsA(isA<PathDependencyException>().having(
          (e) => e.message,
          'message',
          contains('absolute path'),
        )),
      );
    });
  });

  group('GenerateCommand path validation with subdir:', () {
    late Directory tmp;
    late String mono;
    late String appDir;
    late String sharedDir;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('flutpak-path-subdir-');
      mono = p.join(tmp.path, 'mono');
      appDir = p.join(mono, 'app');
      sharedDir = p.join(mono, 'packages', 'shared');
      Directory(sharedDir).createSync(recursive: true);
      Directory(appDir).createSync(recursive: true);
      File(p.join(sharedDir, 'pubspec.yaml')).writeAsStringSync(
        'name: shared\n'
        'publish_to: none\n'
        'environment:\n'
        '  sdk: ">=3.3.0 <4.0.0"\n',
      );
      File(p.join(appDir, 'pubspec.yaml')).writeAsStringSync(
        'name: path_deps_app\n'
        'publish_to: none\n'
        'environment:\n'
        '  sdk: ">=3.3.0 <4.0.0"\n'
        'dependencies:\n'
        '  shared:\n'
        '    path: ../packages/shared\n',
      );
      File(p.join(appDir, 'flutpak.yaml')).writeAsStringSync(
        'app-id: org.example.PathDeps\n'
        'command: PathDeps\n'
        'subdir: app\n',
      );
      final git = Process.runSync('git', ['init'], workingDirectory: mono);
      expect(git.exitCode, 0, reason: git.stderr.toString());
    });

    tearDown(() {
      tmp.deleteSync(recursive: true);
    });

    void writeLock(String pathValue) {
      File(p.join(appDir, 'pubspec.lock')).writeAsStringSync(
        'packages:\n'
        '  shared:\n'
        '    dependency: "direct main"\n'
        '    description:\n'
        '      path: "$pathValue"\n'
        '      relative: true\n'
        '    source: path\n'
        '    version: "0.0.0"\n'
        'sdks:\n'
        '  dart: ">=3.3.0 <4.0.0"\n',
      );
    }

    test('resolves ../packages/shared from the lock dir, not configDir/subdir',
        () {
      writeLock('../packages/shared');
      final cfg = FlatpakGenConfig.load(p.join(appDir, 'flutpak.yaml'), appDir);
      expect(cfg.manifest!.subdir, 'app');

      final results = validateGeneratePathDependencies(
        pubLocks: cfg.pubLocks,
        baseDir: appDir,
      );

      expect(results, hasLength(1));
      expect(results.single.location, PathDepLocation.insideRepo);
      expect(
        p.equals(
            results.single.resolvedPath!, p.join(mono, 'packages', 'shared')),
        isTrue,
      );
      // The previous join(baseDir, subdir) derivation produced this wrong path.
      expect(
        p.equals(
            results.single.resolvedPath!, p.join(appDir, 'packages', 'shared')),
        isFalse,
      );
    });

    test('rejects an out-of-repo ../../ path when subdir is set', () {
      writeLock('../../outside_pkg');
      final cfg = FlatpakGenConfig.load(p.join(appDir, 'flutpak.yaml'), appDir);
      expect(cfg.manifest!.subdir, 'app');

      final expected = p.normalize(p.join(p.dirname(mono), 'outside_pkg'));
      // join(baseDir, subdir) plus ../../outside_pkg would land inside the repo.
      final buggy = p.normalize(p.join(appDir, 'app', '../../outside_pkg'));
      expect(p.isWithin(mono, buggy) || p.equals(buggy, mono), isTrue);

      expect(
        () => validateGeneratePathDependencies(
          pubLocks: cfg.pubLocks,
          baseDir: appDir,
        ),
        throwsA(isA<PathDependencyException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('outside the repository'),
            contains(expected),
          ),
        )),
      );
    });
  });
}
