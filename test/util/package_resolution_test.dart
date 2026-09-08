// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:helix/src/util/dna_fs.dart';
import 'package:helix/src/util/package_resolution.dart';
import 'package:test/test.dart';

void main() {
  const root = '/t';

  PackageResolution read(Map<String, String> files) =>
      PackageResolution.read(MemoryDnaHost(files: files), root);

  group('canonicalPackageName', () {
    test('folds snake to kebab, lowercases, drops the npm scope', () {
      expect(canonicalPackageName('dna_guides'), 'dna-guides');
      expect(canonicalPackageName('Dna-Guides'), 'dna-guides');
      expect(canonicalPackageName('@ggdna/dna-guides'), 'dna-guides');
      expect(canonicalPackageName('@carat-ds/ds_dna'), 'ds-dna');
    });

    test('a bare @ without a slash is not a scope', () {
      expect(canonicalPackageName('@weird'), '@weird');
    });
  });

  group('locate — node', () {
    test('finds the package under node_modules', () {
      final r = read({
        '$root/node_modules/dna-guides/package.json':
            '{"name": "dna-guides", "version": "1.2.3"}',
      });
      final p = r.locate('dna-guides')!;
      expect(p.ecosystem, PackageEcosystem.node);
      expect(p.root, '$root/node_modules/dna-guides');
      expect(p.version, '1.2.3');
      expect(p.source, PackageSource.registry);
    });

    test('the lock file maps an identity to the installed scoped name', () {
      // Declared as `dna_guides`, installed as `@ggdna/dna-guides` — only
      // the lock file can bridge the two.
      final r = read({
        '$root/pnpm-lock.yaml': '''
lockfileVersion: '9.0'
importers:
  .:
    dependencies:
      '@ggdna/dna-guides':
        specifier: 1.0.0
        version: 1.0.0
packages:
  '@ggdna/dna-guides@1.0.0':
    resolution: {integrity: sha512-x}
''',
        '$root/node_modules/@ggdna/dna-guides/package.json':
            '{"name": "@ggdna/dna-guides", "version": "1.0.0"}',
      });
      expect(r.locate('dna_guides')!.packageName, '@ggdna/dna-guides');
    });

    test('a link: entry is a path source', () {
      final r = read({
        '$root/pnpm-lock.yaml': '''
lockfileVersion: '9.0'
importers:
  .:
    dependencies:
      dna-guides:
        specifier: 1.0.0
        version: link:../dna-guides
''',
        '$root/node_modules/dna-guides/package.json':
            '{"name": "dna-guides", "version": "1.0.0"}',
      });
      expect(r.locate('dna-guides')!.source, PackageSource.path);
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
  '@ggdna/dna-guides@1.0.0':
    resolution: {integrity: sha512-y}
''',
        '$root/node_modules/@ggdna/dna-guides/package.json':
            '{"name": "@ggdna/dna-guides"}',
      });
      final p = r.locate('dna_guides')!;
      expect(p.packageName, '@ggdna/dna-guides');
      expect(p.version, '1.0.0');
    });

    test('a broken manifest leaves the version unknown', () {
      final r = read({'$root/node_modules/a-dna/package.json': '{broken'});
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

    test('a peer-suffixed packages: key is trimmed', () {
      // pnpm appends the peer context to the key of a transitive package.
      // The identity index has to strip it, otherwise neither the name nor
      // the version can be read from it.
      final r = read({
        '$root/pnpm-lock.yaml': '''
lockfileVersion: '9.0'
packages:
  'a-dna@4.1.10(vitest@4.1.10)':
    resolution: {integrity: sha512-z}
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

  group('locate — a layer\'s own parents', () {
    // pnpm installs a package as a symlink into its store and puts the
    // package's dependencies next to it there. A layer resolving its own
    // parents therefore starts at a link path, and the consumer's
    // node_modules holds none of them.
    const store =
        '/t/node_modules/.pnpm/@tssuite+dna-tssuite@0.1.1/node_modules';
    const link = '/t/node_modules/@tssuite/dna-tssuite';
    const manifest =
        '{"name": "@tssuite/dna-tssuite", '
        '"dependencies": {"@ggdna/dna-readme": "^0.1.0"}}';

    PackageResolution readLayer() => PackageResolution.read(
      MemoryDnaHost(
        files: {
          // The real file system reads both paths through the link.
          '$link/package.json': manifest,
          '$store/@tssuite/dna-tssuite/package.json': manifest,
          '$store/@ggdna/dna-readme/package.json':
              '{"name": "@ggdna/dna-readme", "version": "0.1.0"}',
        },
        links: {link: '$store/@tssuite/dna-tssuite'},
      ),
      link,
    );

    test('follows the link into the store and searches its node_modules', () {
      final p = readLayer().locate('dna_readme')!;
      expect(p.packageName, '@ggdna/dna-readme');
      expect(p.root, '$store/@ggdna/dna-readme');
      expect(p.version, '0.1.0');
    });

    test('package.json supplies the installed spelling', () {
      // The layer ships no lock file, so `dna_readme` — the name
      // dna/_dna.json uses — can only be mapped to `@ggdna/dna-readme`
      // through the manifest.
      final r = read({
        '$root/package.json':
            '{"name": "x", '
            '"devDependencies": {"@ggdna/dna-readme": "^0.1.0"}}',
        '$root/node_modules/@ggdna/dna-readme/package.json':
            '{"name": "@ggdna/dna-readme", "version": "0.1.0"}',
      });
      expect(r.locate('dna_readme')!.packageName, '@ggdna/dna-readme');
    });

    test('pubspec.yaml supplies it on the pub side', () {
      final r = read({
        '$root/pubspec.yaml':
            'name: x\ndev_dependencies:\n  dna_readme: ^0.1\n',
        '$root/.dart_tool/package_config.json':
            '{"packages": [ '
            '{"name": "dna_readme", "rootUri": "file:///abs/dna_readme"}]}',
        '/abs/dna_readme/pubspec.yaml': 'name: dna_readme\nversion: 0.1.0\n',
      });
      expect(r.locate('@ggdna/dna-readme')!.root, '/abs/dna_readme');
    });

    test('unreadable manifests contribute no names', () {
      // Neither a broken nor a non-map manifest is ours to validate.
      for (final files in [
        {'$root/package.json': '{broken', '$root/pubspec.yaml': '*undefined'},
        {'$root/package.json': '"text"', '$root/pubspec.yaml': 'text'},
      ]) {
        final r = read({
          ...files,
          '$root/node_modules/@ggdna/dna-readme/package.json':
              '{"name": "@ggdna/dna-readme"}',
        });
        expect(r.locate('dna_readme'), isNull);
      }
    });

    test('describeFailure names the node_modules folders it searched', () {
      final r = read({'$root/node_modules/other/package.json': '{}'});
      expect(
        r.describeFailure('dna_readme'),
        contains('in $root/node_modules'),
      );
    });
  });

  group('resolveRootUri', () {
    test('resolves absolute file:// URIs and relative rootUris', () {
      // Relative rootUris are relative to the .dart_tool folder, and a
      // trailing slash must not survive into the recorded root.
      expect(resolveRootUri('file:///abs/dna_guides', '/t'), '/abs/dna_guides');
      expect(
        resolveRootUri('../../cache/dna_guides', '/t'),
        '/cache/dna_guides',
      );
      expect(
        resolveRootUri('../../cache/dna_guides/', '/t'),
        '/cache/dna_guides',
      );
    });

    test('drops the leading slash a windows drive decodes to', () {
      // pub writes an absolute file:// URI for every hosted package. On
      // Windows it decodes to "/C:/…", and that leading slash makes the
      // path invalid for dart:io — every hosted layer failed to resolve.
      expect(
        resolveRootUri('file:///C:/Users/x/Pub/Cache/dna_guides-0.3.1', '/t'),
        'C:/Users/x/Pub/Cache/dna_guides-0.3.1',
      );
      expect(resolveRootUri('file:///d:/x', '/t'), 'd:/x');
      // A posix path keeps its leading slash, and a folder that merely
      // looks like a drive letter is left alone.
      expect(resolveRootUri('file:///abs/dna_guides', '/t'), '/abs/dna_guides');
      expect(resolveRootUri('file:///CC:/x', '/t'), '/CC:/x');
    });
  });

  group('normalizePosix', () {
    test('collapses . and .. segments', () {
      expect(normalizePosix('/t/../dna_guides'), '/dna_guides');
      expect(normalizePosix('/t/./a/b/../c'), '/t/a/c');
      expect(normalizePosix('a/../../b'), '../b');
    });
  });

  group('locate — pub', () {
    test('finds the package through a file:// rootUri', () {
      final r = read({
        '$root/.dart_tool/package_config.json':
            '{"packages": [ '
            '{"name": "dna_guides", "rootUri": "file:///abs/dna_guides"}]}',
        '/abs/dna_guides/pubspec.yaml': 'name: dna_guides\nversion: 1.0.0\n',
        '/abs/dna_guides/dna/LICENSE': 'MIT\n',
      });
      expect(r.locate('dna_guides')!.root, '/abs/dna_guides');
    });

    test('finds the package through package_config.json', () {
      final r = read({
        '$root/.dart_tool/package_config.json':
            '{"packages": [ '
            '{"name": "dna_guides", "rootUri": "../../cache/dna_guides"}]}',
        '/cache/dna_guides/pubspec.yaml': 'name: dna_guides\nversion: 1.0.1\n',
      });
      final p = r.locate('dna-guides')!;
      expect(p.ecosystem, PackageEcosystem.pub);
      expect(p.root, '/cache/dna_guides');
      expect(p.version, '1.0.1');
    });

    test('never reads the other ecosystem\'s manifest', () {
      // A pub tarball ships both manifests. Reading package.json here
      // reported the npm version — the 1.0.0-instead-of-1.0.1 bug.
      final r = read({
        '$root/.dart_tool/package_config.json':
            '{"packages": [ '
            '{"name": "dna_guides", "rootUri": "../../cache/dna_guides"}]}',
        '/cache/dna_guides/pubspec.yaml': 'name: dna_guides\nversion: 1.0.1\n',
        '/cache/dna_guides/package.json':
            '{"name": "@ggdna/dna-guides", "version": "1.0.0"}',
      });
      expect(r.locate('dna_guides')!.version, '1.0.1');
    });

    test('a broken pubspec leaves the version unknown', () {
      final r = read({
        '$root/.dart_tool/package_config.json':
            '{"packages": [ '
            '{"name": "dna_guides", "rootUri": "../../cache/dna_guides"}]}',
        '/cache/dna_guides/pubspec.yaml': '*undefined-anchor',
        '/cache/dna_guides/dna/LICENSE': 'MIT\n',
      });
      expect(r.locate('dna_guides')!.version, isNull);
    });

    test('the lock file wins for a registry package', () {
      final r = read({
        '$root/pubspec.lock': '''
packages:
  dna_guides:
    dependency: "direct main"
    description:
      name: dna_guides
      url: "https://pub.dev"
    source: hosted
    version: "1.0.1"
''',
        '$root/.dart_tool/package_config.json':
            '{"packages": [ '
            '{"name": "dna_guides", "rootUri": "../../cache/dna_guides"}]}',
        '/cache/dna_guides/pubspec.yaml': 'name: dna_guides\nversion: 9.9.9\n',
      });
      expect(r.locate('dna_guides')!.version, '1.0.1');
      // The installed package disagrees with the pin — worth saying.
      expect(r.warnings.single, contains('run pnpm install / dart pub get'));
    });

    test('a localized sibling takes its version from disk', () {
      // gg_localize_refs writes a path override; the sibling can bump
      // its version without a re-resolve, so the lock goes stale.
      final r = read({
        '$root/pubspec.lock': '''
packages:
  dna_guides:
    dependency: "direct main"
    description:
      path: "../dna_guides"
      relative: true
    source: path
    version: "1.0.0"
''',
        '$root/.dart_tool/package_config.json':
            '{"packages": [ '
            '{"name": "dna_guides", "rootUri": "../../dna_guides"}]}',
        '/dna_guides/pubspec.yaml': 'name: dna_guides\nversion: 1.1.0\n',
      });
      final p = r.locate('dna_guides')!;
      expect(p.version, '1.1.0');
      expect(p.source, PackageSource.path);
    });
  });

  group('fallbacks and failures', () {
    test('a lock path entry resolves when nothing is installed yet', () {
      final r = read({
        '$root/pubspec.lock': '''
packages:
  dna_guides:
    dependency: "direct main"
    description:
      path: "../dna_guides"
      relative: true
    source: path
    version: "1.0.0"
''',
        '/dna_guides/pubspec.yaml': 'name: dna_guides\nversion: 1.0.0\n',
      });
      expect(r.locate('dna_guides')!.root, '/dna_guides');
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
  dna_guides:
    dependency: "direct main"
    description:
      name: dna_guides
      url: "https://pub.dev"
    source: hosted
    version: "1.0.1"
''',
      });
      final message = r.describeFailure('dna_guides');
      expect(message, contains('identity:            dna-guides'));
      expect(message, contains('node_modules/'));
      expect(message, contains('pubspec.lock knows dna_guides 1.0.1'));
      expect(message, contains('declared but not installed'));
    });

    test('describeFailure reports the pnpm side too', () {
      final r = read({
        '$root/pnpm-lock.yaml': '''
lockfileVersion: '9.0'
importers:
  .:
    dependencies:
      '@ggdna/dna-guides':
        specifier: 1.0.0
        version: 1.0.0
''',
      });
      expect(
        r.describeFailure('dna_guides'),
        allOf(
          contains('pnpm-lock.yaml knows @ggdna/dna-guides 1.0.0'),
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
      '@ggdna/dna-guides':
        specifier: 1.0.0
        version: 1.0.0
''',
        '$root/node_modules/@ggdna/dna-guides/package.json':
            '{"name": "@ggdna/dna-guides", "version": "1.0.0"}',
        '$root/.dart_tool/package_config.json':
            '{"packages": [ '
            '{"name": "dna_guides", "rootUri": "../../cache/dna_guides"}]}',
        '/cache/dna_guides/pubspec.yaml': 'name: dna_guides\nversion: 1.0.1\n',
      });
      final all = r.locateAll('dna_guides');
      expect(all.map((p) => p.ecosystem).toList(), [
        PackageEcosystem.node,
        PackageEcosystem.pub,
      ]);
      expect(all.every((p) => p.identity == 'dna-guides'), isTrue);
    });
  });
}
