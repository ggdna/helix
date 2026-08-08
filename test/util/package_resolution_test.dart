// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_dna/src/util/dna_fs.dart';
import 'package:gg_dna/src/util/package_resolution.dart';
import 'package:test/test.dart';

void main() {
  const root = '/t';

  PackageResolution read(Map<String, String> files) =>
      PackageResolution.read(MemoryDnaHost(files: files), root);

  group('canonicalPackageName', () {
    test('folds snake to kebab, lowercases, drops the npm scope', () {
      expect(canonicalPackageName('base_dna'), 'base-dna');
      expect(canonicalPackageName('Base-DNA'), 'base-dna');
      expect(canonicalPackageName('@tssuite/base-dna'), 'base-dna');
      expect(canonicalPackageName('@carat-ds/ds_dna'), 'ds-dna');
    });

    test('a bare @ without a slash is not a scope', () {
      expect(canonicalPackageName('@weird'), '@weird');
    });
  });

  group('locate — node', () {
    test('finds the package under node_modules', () {
      final r = read({
        '$root/node_modules/base-dna/package.json':
            '{"name": "base-dna", "version": "1.2.3"}',
      });
      final p = r.locate('base-dna')!;
      expect(p.ecosystem, PackageEcosystem.node);
      expect(p.root, '$root/node_modules/base-dna');
      expect(p.version, '1.2.3');
      expect(p.source, PackageSource.registry);
    });

    test('the lock file maps an identity to the installed scoped name', () {
      // Declared as `base_dna`, installed as `@tssuite/base-dna` — only
      // the lock file can bridge the two.
      final r = read({
        '$root/pnpm-lock.yaml': '''
lockfileVersion: '9.0'
importers:
  .:
    dependencies:
      '@tssuite/base-dna':
        specifier: 1.0.0
        version: 1.0.0
packages:
  '@tssuite/base-dna@1.0.0':
    resolution: {integrity: sha512-x}
''',
        '$root/node_modules/@tssuite/base-dna/package.json':
            '{"name": "@tssuite/base-dna", "version": "1.0.0"}',
      });
      expect(r.locate('base_dna')!.packageName, '@tssuite/base-dna');
    });

    test('a link: entry is a path source', () {
      final r = read({
        '$root/pnpm-lock.yaml': '''
lockfileVersion: '9.0'
importers:
  .:
    dependencies:
      base-dna:
        specifier: 1.0.0
        version: link:../base-dna
''',
        '$root/node_modules/base-dna/package.json':
            '{"name": "base-dna", "version": "1.0.0"}',
      });
      expect(r.locate('base-dna')!.source, PackageSource.path);
    });

    test('a transitive package is known from packages: alone', () {
      // Only direct dependencies appear under `importers`. A DNA pulled
      // in by another DNA shows up in `packages:` only — and that is
      // exactly the entry the identity index needs to find it.
      final r = read({
        '$root/pnpm-lock.yaml': '''
lockfileVersion: '9.0'
importers:
  .:
    dependencies:
      '@tssuite/dna-dart':
        specifier: 2.0.0
        version: 2.0.0
packages:
  '@tssuite/dna-dart@2.0.0':
    resolution: {integrity: sha512-x}
  '@tssuite/base-dna@1.0.0':
    resolution: {integrity: sha512-y}
''',
        '$root/node_modules/@tssuite/base-dna/package.json':
            '{"name": "@tssuite/base-dna"}',
      });
      final p = r.locate('base_dna')!;
      expect(p.packageName, '@tssuite/base-dna');
      expect(p.version, '1.0.0');
    });

    test('a broken manifest leaves the version unknown', () {
      final r = read({
        '$root/node_modules/a-dna/package.json': '{broken',
      });
      expect(r.locate('a-dna')!.version, isNull);
    });

    test('a peer-suffixed version is trimmed', () {
      final r = read({
        '$root/pnpm-lock.yaml': '''
lockfileVersion: '9.0'
importers:
  .:
    devDependencies:
      a-dna:
        specifier: ^4.1.0
        version: 4.1.10(vitest@4.1.10)
''',
        '$root/node_modules/a-dna/package.json': '{"name": "a-dna"}',
      });
      expect(r.locate('a-dna')!.version, '4.1.10');
    });

    test('package-lock.json without pnpm-lock.yaml warns', () {
      final r = read({'$root/package-lock.json': '{"lockfileVersion": 3}'});
      expect(
        r.warnings.single,
        allOf(contains('package-lock.json'), contains('pnpm')),
      );
    });
  });

  group('resolveRootUri', () {
    test('resolves absolute file:// URIs and relative rootUris', () {
      // Relative rootUris are relative to the .dart_tool folder, and a
      // trailing slash must not survive into the recorded root.
      expect(resolveRootUri('file:///abs/base_dna', '/t'), '/abs/base_dna');
      expect(resolveRootUri('../../cache/base_dna', '/t'), '/cache/base_dna');
      expect(resolveRootUri('../../cache/base_dna/', '/t'), '/cache/base_dna');
    });
  });

  group('normalizePosix', () {
    test('collapses . and .. segments', () {
      expect(normalizePosix('/t/../base_dna'), '/base_dna');
      expect(normalizePosix('/t/./a/b/../c'), '/t/a/c');
      expect(normalizePosix('a/../../b'), '../b');
    });
  });

  group('locate — pub', () {
    test('finds the package through a file:// rootUri', () {
      final r = read({
        '$root/.dart_tool/package_config.json': '{"packages": [ '
            '{"name": "base_dna", "rootUri": "file:///abs/base_dna"}]}',
        '/abs/base_dna/pubspec.yaml': 'name: base_dna\nversion: 1.0.0\n',
        '/abs/base_dna/dna/LICENSE': 'MIT\n',
      });
      expect(r.locate('base_dna')!.root, '/abs/base_dna');
    });

    test('finds the package through package_config.json', () {
      final r = read({
        '$root/.dart_tool/package_config.json': '{"packages": [ '
            '{"name": "base_dna", "rootUri": "../../cache/base_dna"}]}',
        '/cache/base_dna/pubspec.yaml': 'name: base_dna\nversion: 1.0.1\n',
      });
      final p = r.locate('base-dna')!;
      expect(p.ecosystem, PackageEcosystem.pub);
      expect(p.root, '/cache/base_dna');
      expect(p.version, '1.0.1');
    });

    test('never reads the other ecosystem\'s manifest', () {
      // A pub tarball ships both manifests. Reading package.json here
      // reported the npm version — the 1.0.0-instead-of-1.0.1 bug.
      final r = read({
        '$root/.dart_tool/package_config.json': '{"packages": [ '
            '{"name": "base_dna", "rootUri": "../../cache/base_dna"}]}',
        '/cache/base_dna/pubspec.yaml': 'name: base_dna\nversion: 1.0.1\n',
        '/cache/base_dna/package.json':
            '{"name": "@tssuite/base-dna", "version": "1.0.0"}',
      });
      expect(r.locate('base_dna')!.version, '1.0.1');
    });

    test('a broken pubspec leaves the version unknown', () {
      final r = read({
        '$root/.dart_tool/package_config.json': '{"packages": [ '
            '{"name": "base_dna", "rootUri": "../../cache/base_dna"}]}',
        '/cache/base_dna/pubspec.yaml': '*undefined-anchor',
        '/cache/base_dna/dna/LICENSE': 'MIT\n',
      });
      expect(r.locate('base_dna')!.version, isNull);
    });

    test('the lock file wins for a registry package', () {
      final r = read({
        '$root/pubspec.lock': '''
packages:
  base_dna:
    dependency: "direct main"
    description:
      name: base_dna
      url: "https://pub.dev"
    source: hosted
    version: "1.0.1"
''',
        '$root/.dart_tool/package_config.json': '{"packages": [ '
            '{"name": "base_dna", "rootUri": "../../cache/base_dna"}]}',
        '/cache/base_dna/pubspec.yaml': 'name: base_dna\nversion: 9.9.9\n',
      });
      expect(r.locate('base_dna')!.version, '1.0.1');
      // The installed package disagrees with the pin — worth saying.
      expect(r.warnings.single, contains('run pnpm install / dart pub get'));
    });

    test('a localized sibling takes its version from disk', () {
      // gg_localize_refs writes a path override; the sibling can bump
      // its version without a re-resolve, so the lock goes stale.
      final r = read({
        '$root/pubspec.lock': '''
packages:
  base_dna:
    dependency: "direct main"
    description:
      path: "../base_dna"
      relative: true
    source: path
    version: "1.0.0"
''',
        '$root/.dart_tool/package_config.json': '{"packages": [ '
            '{"name": "base_dna", "rootUri": "../../base_dna"}]}',
        '/base_dna/pubspec.yaml': 'name: base_dna\nversion: 1.1.0\n',
      });
      final p = r.locate('base_dna')!;
      expect(p.version, '1.1.0');
      expect(p.source, PackageSource.path);
    });
  });

  group('fallbacks and failures', () {
    test('a lock path entry resolves when nothing is installed yet', () {
      final r = read({
        '$root/pubspec.lock': '''
packages:
  base_dna:
    dependency: "direct main"
    description:
      path: "../base_dna"
      relative: true
    source: path
    version: "1.0.0"
''',
        '/base_dna/pubspec.yaml': 'name: base_dna\nversion: 1.0.0\n',
      });
      expect(r.locate('base_dna')!.root, '/base_dna');
    });

    test('unknown packages yield null', () {
      expect(read({}).locate('nope'), isNull);
    });

    test('broken lock files warn but never fail', () {
      final r = read({
        '$root/pnpm-lock.yaml': '*undefined-anchor',
        '$root/pubspec.lock': '*undefined-anchor',
        '$root/.dart_tool/package_config.json': '{broken',
      });
      expect(r.warnings, hasLength(3));
      expect(r.locate('anything'), isNull);
    });

    test('describeFailure names what was tried and what the lock knows', () {
      final r = read({
        '$root/pubspec.lock': '''
packages:
  base_dna:
    dependency: "direct main"
    description:
      name: base_dna
      url: "https://pub.dev"
    source: hosted
    version: "1.0.1"
''',
      });
      final message = r.describeFailure('base_dna');
      expect(message, contains('identity:            base-dna'));
      expect(message, contains('node_modules/'));
      expect(message, contains('pubspec.lock knows base_dna 1.0.1'));
      expect(message, contains('declared but not installed'));
    });

    test('describeFailure reports the pnpm side too', () {
      final r = read({
        '$root/pnpm-lock.yaml': '''
lockfileVersion: '9.0'
importers:
  .:
    dependencies:
      '@tssuite/base-dna':
        specifier: 1.0.0
        version: 1.0.0
''',
      });
      expect(
        r.describeFailure('base_dna'),
        allOf(
          contains('pnpm-lock.yaml knows @tssuite/base-dna 1.0.0'),
          contains('declared but not installed'),
        ),
      );
    });
  });

  group('locateAll', () {
    test('reports both ecosystem copies, node first', () {
      final r = read({
        '$root/pnpm-lock.yaml': '''
lockfileVersion: '9.0'
importers:
  .:
    dependencies:
      '@tssuite/base-dna':
        specifier: 1.0.0
        version: 1.0.0
''',
        '$root/node_modules/@tssuite/base-dna/package.json':
            '{"name": "@tssuite/base-dna", "version": "1.0.0"}',
        '$root/.dart_tool/package_config.json': '{"packages": [ '
            '{"name": "base_dna", "rootUri": "../../cache/base_dna"}]}',
        '/cache/base_dna/pubspec.yaml': 'name: base_dna\nversion: 1.0.1\n',
      });
      final all = r.locateAll('base_dna');
      expect(all.map((p) => p.ecosystem).toList(), [
        PackageEcosystem.node,
        PackageEcosystem.pub,
      ]);
      expect(all.every((p) => p.identity == 'base-dna'), isTrue);
    });
  });
}
