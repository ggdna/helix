// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:helix/src/util/dna_config.dart';
import 'package:helix/src/util/dna_fs.dart';
import 'package:helix/src/util/dna_layout.dart';
import 'package:helix/src/util/layer_graph.dart';
import 'package:helix/src/util/package_resolution.dart';
import 'package:test/test.dart';

void main() {
  const root = '/t';

  String dnaConfig(List<String> layers) {
    final list = layers.map((l) => '"$l"').join(', ');
    return '{"version": $dnaFormatVersion, "role": "dna", '
        '"layers": [$list]}';
  }

  /// A DNA package installed under node_modules, with its own parents.
  Map<String, String> npmDna(
    String name,
    String version, {
    List<String> layers = const [],
  }) => {
    '$root/node_modules/$name/package.json':
        '{"name": "$name", "version": "$version"}',
    '$root/node_modules/$name/$dnaConfigPath': dnaConfig(layers),
    '$root/node_modules/$name/dna/doc/$name.md': '# $name',
  };

  /// A DNA package installed by pub at [at], plus its package_config entry.
  Map<String, String> pubDna(
    String name,
    String version, {
    List<String> layers = const [],
    String? at,
  }) {
    final dir = at ?? '/cache/$name';
    return {
      '$dir/pubspec.yaml': 'name: $name\nversion: $version\n',
      '$dir/$dnaConfigPath': dnaConfig(layers),
      '$dir/dna/doc/$name.md': '# $name',
    };
  }

  String packageConfig(Map<String, String> nameToRootUri) {
    final entries = nameToRootUri.entries
        .map((e) => '{"name": "${e.key}", "rootUri": "${e.value}"}')
        .join(', ');
    return '{"configVersion": 2, "packages": [$entries]}';
  }

  ({List<ResolvedLayer> layers, List<String> warnings}) expand(
    MemoryDnaHost host,
    List<String> layers,
  ) => expandLayerGraph(
    host: host,
    targetRoot: root,
    config: DnaConfig(layers: layers),
    resolution: PackageResolution.read(host, root),
  );

  group('expandLayerGraph', () {
    test('recurses through each layer\'s own dna/_dna.json', () {
      final host = MemoryDnaHost(
        files: {
          '$root/package.json': '{"dependencies": {"dna-dart": "^2.0.0"}}',
          ...npmDna('dna-dart', '2.1.0', layers: ['dna-base']),
          ...npmDna('dna-base', '1.2.0'),
        },
      );
      final r = expand(host, ['dna-dart']);
      expect(r.layers.map((l) => l.name).toList(), ['dna-base', 'dna-dart']);
      expect(r.layers.first.via, 'dna-dart');
      expect(r.layers.first.version, '1.2.0');
      expect(r.layers.first.ecosystem, PackageEcosystem.node);
      expect(r.layers.last.via, isNull);
      expect(r.layers.last.root, '$root/node_modules/dna-dart');
    });

    test('layers apply in the listed order', () {
      final host = MemoryDnaHost(
        files: {...npmDna('a-dna', '1.0.0'), ...npmDna('b-dna', '1.0.0')},
      );
      expect(
        expand(host, ['b-dna', 'a-dna']).layers.map((l) => l.name).toList(),
        ['b-dna', 'a-dna'],
      );
    });

    test('a dependency that is not listed is not a layer', () {
      final host = MemoryDnaHost(
        files: {
          '$root/package.json':
              '{"dependencies": '
              '{"a-dna": "1", "b-dna": "1"}}',
          ...npmDna('a-dna', '1.0.0'),
          ...npmDna('b-dna', '1.0.0'),
        },
      );
      expect(expand(host, ['a-dna']).layers.map((l) => l.name).toList(), [
        'a-dna',
      ]);
    });

    test('deduplicates diamonds — first topological position wins', () {
      final host = MemoryDnaHost(
        files: {
          ...npmDna('ds-dna-dart', '1.0.0', layers: ['dna-dart', 'ds-dna']),
          ...npmDna('dna-dart', '2.0.0', layers: ['dna-base']),
          ...npmDna('ds-dna', '1.0.0', layers: ['dna-base']),
          ...npmDna('dna-base', '1.0.0'),
        },
      );
      final r = expand(host, ['ds-dna-dart']);
      expect(r.layers.map((l) => l.name).toList(), [
        'dna-base',
        'dna-dart',
        'ds-dna',
        'ds-dna-dart',
      ]);
      expect(r.layers.firstWhere((l) => l.name == 'dna-base').via, 'dna-dart');
    });

    test('resolves pub packages via package_config.json, snake names', () {
      final host = MemoryDnaHost(
        files: {
          '$root/.dart_tool/package_config.json': packageConfig({
            'dna_dart': '../../cache/dna_dart',
          }),
          ...pubDna('dna_dart', '2.1.0'),
        },
      );
      final r = expand(host, ['dna-dart']);
      expect(r.layers.single.name, 'dna-dart');
      expect(r.layers.single.package, 'dna_dart');
      expect(r.layers.single.root, '/cache/dna_dart');
      expect(r.layers.single.version, '2.1.0');
      expect(r.layers.single.ecosystem, PackageEcosystem.pub);
    });

    test('a parent is found in the layer\'s own node_modules', () {
      // pnpm exposes only direct dependencies at the top level, so a DNA
      // pulled in by another DNA sits under *that* package — never under
      // the consumer's. Looking only at the target would lose the whole
      // upper half of the tree.
      final host = MemoryDnaHost(
        files: {
          '$root/node_modules/dna-ts/package.json':
              '{"name": "dna-ts", "version": "1.0.0"}',
          '$root/node_modules/dna-ts/$dnaConfigPath': dnaConfig(['dna-base']),
          '$root/node_modules/dna-ts/dna/doc/ts.md': '# ts',
          // The parent lives below the layer, not below the target.
          '$root/node_modules/dna-ts/node_modules/dna-base/package.json':
              '{"name": "dna-base", "version": "1.2.0"}',
          '$root/node_modules/dna-ts/node_modules/dna-base/$dnaConfigPath':
              dnaConfig([]),
          '$root/node_modules/dna-ts/node_modules/dna-base/dna/LICENSE':
              'MIT\n',
        },
      );
      final r = expand(host, ['dna-ts']);
      expect(r.layers.map((l) => l.name).toList(), ['dna-base', 'dna-ts']);
      expect(
        r.layers.first.root,
        '$root/node_modules/dna-ts/node_modules/dna-base',
      );
      expect(r.layers.first.via, 'dna-ts');
    });

    test('the target still resolves parents pub flattened', () {
      // pub puts everything into the target's package_config.json, and a
      // package in the cache has no resolution of its own — so the
      // fallback to the target has to keep working.
      final host = MemoryDnaHost(
        files: {
          '$root/.dart_tool/package_config.json': packageConfig({
            'dna_dart': '../../cache/dna_dart',
            'dna_base': '../../cache/dna_base',
          }),
          ...pubDna('dna_dart', '1.0.0', layers: ['dna_base']),
          ...pubDna('dna_base', '1.0.1'),
        },
      );
      final r = expand(host, ['dna_dart']);
      expect(r.layers.map((l) => l.name).toList(), ['dna-base', 'dna-dart']);
      expect(r.layers.first.root, '/cache/dna_base');
    });

    test('resolves file:// and trailing-slash rootUris', () {
      final host = MemoryDnaHost(
        files: {
          '$root/.dart_tool/package_config.json': packageConfig({
            'a_dna': 'file:///abs/a_dna',
            'b_dna': '../../rel/b_dna/',
          }),
          ...pubDna('a_dna', '1.0.0', at: '/abs/a_dna'),
          ...pubDna('b_dna', '1.0.0', at: '/rel/b_dna'),
        },
      );
      expect(expand(host, ['a_dna', 'b_dna']).layers.map((l) => l.root), [
        '/abs/a_dna',
        '/rel/b_dna',
      ]);
    });
  });

  group('any package with a config can be a layer', () {
    test('a dna/ folder without a config is not one', () {
      final host = MemoryDnaHost(
        files: {
          '$root/node_modules/plain/package.json':
              '{"name": "plain", "version": "1.0.0"}',
          '$root/node_modules/plain/dna/doc/x.md': '# x',
        },
      );
      expect(
        () => expand(host, ['plain']),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('ships no DNA'), contains(dnaConfigPath)),
          ),
        ),
      );
    });

    test('no flag is needed — a config is enough', () {
      final host = MemoryDnaHost(
        files: {
          '$root/node_modules/consumer/package.json':
              '{"name": "consumer", "version": "1.0.0"}',
          '$root/node_modules/consumer/$dnaConfigPath':
              '{"version": $dnaFormatVersion}',
          '$root/node_modules/consumer/dna/doc/x.md': '# x',
        },
      );
      final r = expand(host, ['consumer']);
      expect(r.layers.single.name, 'consumer');
      expect(r.warnings, isEmpty);
    });

    test('a retired role is ignored without warning in a layer', () {
      final host = MemoryDnaHost(
        files: {
          '$root/node_modules/consumer/package.json':
              '{"name": "consumer", "version": "1.0.0"}',
          '$root/node_modules/consumer/$dnaConfigPath':
              '{"version": $dnaFormatVersion, "role": "project"}',
          '$root/node_modules/consumer/dna/doc/x.md': '# x',
        },
      );
      final r = expand(host, ['consumer']);
      expect(r.layers.single.name, 'consumer');
      expect(r.warnings, isEmpty);
    });
  });

  group('dual publication', () {
    test('the npm and pub copies fold into one layer', () {
      final host = MemoryDnaHost(
        files: {
          // The consumer declares the same DNA in both manifests.
          '$root/package.json':
              '{"dependencies": {"@tssuite/dna-base": "1.0.0"}}',
          '$root/pubspec.yaml': 'name: c\ndependencies:\n  dna_base: ^1.0.0\n',
          '$root/pnpm-lock.yaml': '''
lockfileVersion: '9.0'
importers:
  .:
    dependencies:
      '@tssuite/dna-base':
        specifier: 1.0.0
        version: 1.0.0
packages:
  '@tssuite/dna-base@1.0.0':
    resolution: {integrity: sha512-x}
''',
          '$root/node_modules/@tssuite/dna-base/package.json':
              '{"name": "@tssuite/dna-base", "version": "1.0.0"}',
          '$root/node_modules/@tssuite/dna-base/$dnaConfigPath': dnaConfig([]),
          '$root/node_modules/@tssuite/dna-base/dna/doc/x.md': '# x',
          '$root/.dart_tool/package_config.json': packageConfig({
            'dna_base': '../../cache/dna_base',
          }),
          ...pubDna('dna_base', '1.0.1'),
          '/cache/dna_base/dna/doc/x.md': '# x',
        },
      );
      // The pub copy carries the same tree — remove the file pubDna added
      // under its own name so both sides are identical.
      host.deleteFile('/cache/dna_base/dna/doc/dna_base.md');

      final r = expand(host, ['dna_base']);
      expect(r.layers, hasLength(1));
      expect(r.layers.single.name, 'dna-base');
      expect(r.layers.single.package, '@tssuite/dna-base');
      expect(r.warnings, isEmpty);
    });

    test('drifted copies warn, the npm one is used', () {
      final host = MemoryDnaHost(
        files: {
          '$root/pnpm-lock.yaml': '''
lockfileVersion: '9.0'
importers:
  .:
    dependencies:
      '@tssuite/dna-base':
        specifier: 1.0.0
        version: 1.0.0
''',
          '$root/node_modules/@tssuite/dna-base/package.json':
              '{"name": "@tssuite/dna-base", "version": "1.0.0"}',
          '$root/node_modules/@tssuite/dna-base/$dnaConfigPath': dnaConfig([]),
          '$root/node_modules/@tssuite/dna-base/dna/doc/x.md': '# npm',
          '$root/.dart_tool/package_config.json': packageConfig({
            'dna_base': '../../cache/dna_base',
          }),
          '/cache/dna_base/pubspec.yaml': 'name: dna_base\nversion: 1.0.1\n',
          '/cache/dna_base/$dnaConfigPath': dnaConfig([]),
          '/cache/dna_base/dna/doc/x.md': '# pub — stale',
        },
      );
      final r = expand(host, ['dna_base']);
      expect(r.layers.single.package, '@tssuite/dna-base');
      expect(
        r.warnings.single,
        allOf(contains('dna-base'), contains('the two copies differ')),
      );
    });
  });

  group('failures', () {
    test('cycles are detected', () {
      final host = MemoryDnaHost(
        files: {
          ...npmDna('a-dna', '1.0.0', layers: ['b-dna']),
          ...npmDna('b-dna', '1.0.0', layers: ['a-dna']),
        },
      );
      expect(
        () => expand(host, ['a-dna']),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('cycle'),
          ),
        ),
      );
    });

    test('an unresolvable layer reports what was tried', () {
      final host = MemoryDnaHost(files: {'$root/package.json': '{}'});
      expect(
        () => expand(host, ['missing-dna']),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('cannot be resolved'),
              contains('node_modules/'),
              contains('not declared anywhere'),
              contains('gg_localize_refs'),
            ),
          ),
        ),
      );
    });

    test('a layer in the lock but not installed says so', () {
      final host = MemoryDnaHost(
        files: {
          '$root/pubspec.lock': '''
packages:
  dna_base:
    dependency: "direct main"
    description:
      name: dna_base
      url: "https://pub.dev"
    source: hosted
    version: "1.0.1"
''',
        },
      );
      expect(
        () => expand(host, ['dna_base']),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('pubspec.lock knows dna_base 1.0.1'),
              contains('declared but not installed'),
            ),
          ),
        ),
      );
    });

    test('the engine and its bridge never count as DNA layers', () {
      final host = MemoryDnaHost(files: {'$root/package.json': '{}'});
      for (final name in ['helix', '@tssuite/helix-js']) {
        expect(
          () => expand(host, [name]),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('layer 0'),
            ),
          ),
          reason: name,
        );
      }
    });

    test('a tree deeper than the limit fails', () {
      final files = <String, String>{};
      for (var i = 0; i <= maxLayerDepth + 1; i++) {
        files.addAll(npmDna('dna-$i', '1.0.0', layers: ['dna-${i + 1}']));
      }
      expect(
        () => expand(MemoryDnaHost(files: files), ['dna-0']),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('deeper than $maxLayerDepth'),
          ),
        ),
      );
    });

    test('an unreadable package_config.json resolves no packages', () {
      final host = MemoryDnaHost(
        files: {'$root/.dart_tool/package_config.json': '{broken'},
      );
      expect(
        () => expand(host, ['a-dna']),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('cannot be resolved'),
          ),
        ),
      );
    });
  });

  group('suggestDnaLayers', () {
    test('combines both manifests and dedups by identity', () {
      final host = MemoryDnaHost(
        files: {
          '$root/package.json': '{"dependencies": {"dna-base": "^1.0.0"}}',
          '$root/pubspec.yaml':
              'dependencies:\n  dna_base: ^1.0.0\n  dna_dart: ^1.0.0\n',
          ...npmDna('dna-base', '1.0.0'),
          '$root/.dart_tool/package_config.json': packageConfig({
            'dna_dart': '../../cache/dna_dart',
          }),
          ...pubDna('dna_dart', '1.0.0'),
        },
      );
      expect(suggestDnaLayers(host, root, PackageResolution.read(host, root)), [
        'dna-base',
        'dna_dart',
      ]);
    });

    test('skips packages that are not DNA and survives broken manifests', () {
      final host = MemoryDnaHost(
        files: {
          '$root/package.json': '{broken',
          '$root/pubspec.yaml': '*undefined-anchor',
        },
      );
      expect(
        suggestDnaLayers(host, root, PackageResolution.read(host, root)),
        isEmpty,
      );
    });

    test('never suggests a package the engine would reject', () {
      final host = MemoryDnaHost(
        files: {
          '$root/package.json':
              '{"dependencies": '
              '{"plain": "1", "real-dna": "1"}}',
          '$root/node_modules/plain/package.json':
              '{"name": "plain", "version": "1.0.0"}',
          '$root/node_modules/plain/dna/doc/x.md': '# x',
          ...npmDna('real-dna', '1.0.0'),
        },
      );
      expect(suggestDnaLayers(host, root, PackageResolution.read(host, root)), [
        'real-dna',
      ]);
    });
  });
}
