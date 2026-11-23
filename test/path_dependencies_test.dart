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
        appDir: appDir,
        repoRoot: fixtureRepo,
      );
      expect(results, hasLength(1));
      expect(results.single.location, PathDepLocation.insideRepo);
    });

    test('fails clearly for a path outside the repo', () {
      expect(
        () => validatePathDependencies(
          lockFilePaths: [p.join(locksDir, 'outside.lock')],
          appDir: appDir,
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
          appDir: appDir,
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
}
