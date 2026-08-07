// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_dna/src/util/dna_config.dart';
import 'package:gg_dna/src/util/dna_fs.dart';
import 'package:gg_dna/src/util/layer_graph.dart';
import 'package:test/test.dart';

void main() {
  const root = '/t';

  /// A DNA package installed under node_modules with optional parents.
  Map<String, String> npmDna(
    String name,
    String version, {
    List<String> deps = const [],
  }) {
    final depsJson = deps.map((d) => '"$d": "^1.0.0"').join(', ');
    return {
      '$root/node_modules/$name/package.json':
          '{"name": "$name", "version": "$version", '
              '"dependencies": {$depsJson}}',
      '$root/node_modules/$name/dna/doc/$name.md': '# $name',
    };
  }

  group('expandLayerGraph', () {
    test('resolves default order from devDependencies and recurses', () {
      final host = MemoryDnaHost(
        files: {
          '$root/package.json': '{"devDependencies": '
              '{"dna-dart": "^2.0.0", "not-dna": "1.0.0"}}',
          ...npmDna('dna-dart', '2.1.0', deps: ['base-dna']),
          ...npmDna('base-dna', '1.2.0'),
          '$root/node_modules/not-dna/package.json':
              '{"name": "not-dna", "version": "1.0.0"}',
          '$root/node_modules/not-dna/index.js': '',
        },
      );
      final r = expandLayerGraph(
        host: host,
        targetRoot: root,
        config: const DnaConfig(),
      );
      expect(r.layers.map((l) => l.name).toList(), ['base-dna', 'dna-dart']);
      expect(r.layers.first.via, 'dna-dart');
      expect(r.layers.first.version, '1.2.0');
      expect(r.layers.last.via, isNull);
      expect(r.layers.last.root, '$root/node_modules/dna-dart');
    });

    test('deduplicates diamonds — first topological position wins', () {
      final host = MemoryDnaHost(
        files: {
          '$root/package.json': '{"devDependencies": '
              '{"ds-dna-dart": "^1.0.0"}}',
          ...npmDna('ds-dna-dart', '1.0.0', deps: ['dna-dart', 'ds-dna']),
          ...npmDna('dna-dart', '2.0.0', deps: ['base-dna']),
          ...npmDna('ds-dna', '1.0.0', deps: ['base-dna']),
          ...npmDna('base-dna', '1.0.0'),
        },
      );
      final r = expandLayerGraph(
        host: host,
        targetRoot: root,
        config: const DnaConfig(),
      );
      expect(r.layers.map((l) => l.name).toList(), [
        'base-dna',
        'dna-dart',
        'ds-dna',
        'ds-dna-dart',
      ]);
      expect(
        r.layers.firstWhere((l) => l.name == 'base-dna').via,
        'dna-dart',
      );
    });

    test('explicit order in the config overrides the default', () {
      final host = MemoryDnaHost(
        files: {
          '$root/package.json': '{"devDependencies": '
              '{"a-dna": "1", "b-dna": "1"}}',
          ...npmDna('a-dna', '1.0.0'),
          ...npmDna('b-dna', '1.0.0'),
        },
      );
      final r = expandLayerGraph(
        host: host,
        targetRoot: root,
        config: const DnaConfig(order: ['b-dna']),
      );
      expect(r.layers.map((l) => l.name).toList(), ['b-dna']);
    });

    test('resolves pub packages via package_config.json, snake names', () {
      final host = MemoryDnaHost(
        files: {
          '$root/pubspec.yaml': 'name: consumer\n'
              'dev_dependencies:\n  dna_dart: ^2.0.0\n  test: ^1.0.0\n',
          '$root/.dart_tool/package_config.json': '{"configVersion": 2, '
              '"packages": [ '
              '{"name": "dna_dart", "rootUri": "../../cache/dna_dart"}, '
              '{"name": "test", "rootUri": "../../cache/test"}]}',
          '/cache/dna_dart/pubspec.yaml': 'name: dna_dart\nversion: 2.1.0\n',
          '/cache/dna_dart/dna/doc/x.md': '# x',
          '/cache/test/pubspec.yaml': 'name: test\nversion: 1.0.0\n',
        },
      );
      final r = expandLayerGraph(
        host: host,
        targetRoot: root,
        config: const DnaConfig(),
      );
      expect(r.layers.single.name, 'dna-dart');
      expect(r.layers.single.package, 'dna_dart');
      expect(r.layers.single.root, '/cache/dna_dart');
      expect(r.layers.single.version, '2.1.0');
    });

    test('path overrides win over installed packages at any depth', () {
      final host = MemoryDnaHost(
        files: {
          '$root/package.json': '{"devDependencies": {"dna-dart": "^2.0.0"}}',
          ...npmDna('dna-dart', '2.1.0', deps: ['base-dna']),
          ...npmDna('base-dna', '1.0.0'),
          '$root/../base-dna/dna/doc/local.md': '# local',
        },
      );
      final r = expandLayerGraph(
        host: host,
        targetRoot: root,
        config: const DnaConfig(
          pathOverrides: {'base-dna': '../base-dna'},
        ),
      );
      final base = r.layers.firstWhere((l) => l.name == 'base-dna');
      expect(base.path, '../base-dna');
      expect(base.package, isNull);
      expect(base.root, '$root/../base-dna');
    });

    test('a layer with dna/src fails with the migration error', () {
      final host = MemoryDnaHost(
        files: {
          '$root/package.json': '{"devDependencies": {"old-dna": "1"}}',
          '$root/node_modules/old-dna/package.json':
              '{"name": "old-dna", "version": "1.0.0"}',
          '$root/node_modules/old-dna/dna/src/doc/x.md': '# x',
        },
      );
      expect(
        () => expandLayerGraph(
          host: host,
          targetRoot: root,
          config: const DnaConfig(order: ['old-dna']),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('dna/src'),
          ),
        ),
      );
    });

    test('cycles are detected', () {
      final host = MemoryDnaHost(
        files: {
          '$root/package.json': '{"devDependencies": {"a-dna": "1"}}',
          ...npmDna('a-dna', '1.0.0', deps: ['b-dna']),
          ...npmDna('b-dna', '1.0.0', deps: ['a-dna']),
        },
      );
      expect(
        () => expandLayerGraph(
          host: host,
          targetRoot: root,
          config: const DnaConfig(),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('cycle'),
          ),
        ),
      );
    });

    test('unresolvable explicit layers fail with install hint', () {
      final host = MemoryDnaHost(
        files: {'$root/package.json': '{}'},
      );
      expect(
        () => expandLayerGraph(
          host: host,
          targetRoot: root,
          config: const DnaConfig(order: ['missing-dna']),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('dev-dependency'),
          ),
        ),
      );
    });

    test('explicit layer without dna/ folder fails', () {
      final host = MemoryDnaHost(
        files: {
          '$root/node_modules/plain/package.json':
              '{"name": "plain", "version": "1.0.0"}',
          '$root/node_modules/plain/index.js': '',
        },
      );
      expect(
        () => expandLayerGraph(
          host: host,
          targetRoot: root,
          config: const DnaConfig(order: ['plain']),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('no dna/ folder'),
          ),
        ),
      );
    });

    test('dev-dependencies of a layer do not contribute parents', () {
      final host = MemoryDnaHost(
        files: {
          '$root/package.json': '{"devDependencies": {"child-dna": "1"}}',
          '$root/node_modules/child-dna/package.json':
              '{"name": "child-dna", "version": "1.0.0", '
                  '"devDependencies": {"tool-dna": "^1.0.0"}}',
          '$root/node_modules/child-dna/dna/doc/x.md': '# x',
          ...npmDna('tool-dna', '1.0.0'),
        },
      );
      final r = expandLayerGraph(
        host: host,
        targetRoot: root,
        config: const DnaConfig(),
      );
      expect(r.layers.map((l) => l.name).toList(), ['child-dna']);
    });

    test('the engine package gg_dna never counts as a DNA layer', () {
      final host = MemoryDnaHost(
        files: {
          '$root/pubspec.yaml':
              'dev_dependencies:\n  gg_dna: ^5.0.0\n  dna_dart: ^1.0.0\n',
          '$root/.dart_tool/package_config.json': '{"packages": [ '
              '{"name": "gg_dna", "rootUri": "../../cache/gg_dna"}, '
              '{"name": "dna_dart", "rootUri": "../../cache/dna_dart"}]}',
          '/cache/gg_dna/pubspec.yaml': 'name: gg_dna\nversion: 5.0.0\n',
          '/cache/gg_dna/dna/doc/base.md': '# base',
          '/cache/dna_dart/pubspec.yaml': 'name: dna_dart\nversion: 1.0.0\n',
          '/cache/dna_dart/dna/doc/x.md': '# x',
        },
      );
      final r = expandLayerGraph(
        host: host,
        targetRoot: root,
        config: const DnaConfig(),
      );
      expect(r.layers.map((l) => l.name).toList(), ['dna-dart']);

      expect(
        () => expandLayerGraph(
          host: host,
          targetRoot: root,
          config: const DnaConfig(order: ['gg_dna']),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('layer 0'),
          ),
        ),
      );
    });

    test('layer order inside a DNA package comes from its .gg/dna.json', () {
      final host = MemoryDnaHost(
        files: {
          '$root/package.json': '{"devDependencies": {"child-dna": "1"}}',
          ...npmDna('child-dna', '1.0.0', deps: ['a-dna', 'b-dna']),
          '$root/node_modules/child-dna/.gg/dna.json':
              '{"role": "dna", "order": ["b-dna", "a-dna"]}',
          ...npmDna('a-dna', '1.0.0'),
          ...npmDna('b-dna', '1.0.0'),
        },
      );
      final r = expandLayerGraph(
        host: host,
        targetRoot: root,
        config: const DnaConfig(),
      );
      expect(r.layers.map((l) => l.name).toList(), [
        'b-dna',
        'a-dna',
        'child-dna',
      ]);
    });

    test('a tree deeper than the limit fails', () {
      final files = <String, String>{
        '$root/package.json': '{"devDependencies": {"dna-0": "1"}}',
      };
      for (var i = 0; i <= maxLayerDepth + 1; i++) {
        files.addAll(
          npmDna('dna-$i', '1.0.0', deps: ['dna-${i + 1}']),
        );
      }
      expect(
        () => expandLayerGraph(
          host: MemoryDnaHost(files: files),
          targetRoot: root,
          config: const DnaConfig(),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('deeper than $maxLayerDepth'),
          ),
        ),
      );
    });

    test('absolute path overrides are used as given', () {
      final host = MemoryDnaHost(
        files: {
          '$root/package.json': '{}',
          '/elsewhere/base-dna/dna/doc/x.md': '# x',
        },
      );
      final r = expandLayerGraph(
        host: host,
        targetRoot: root,
        config: const DnaConfig(
          order: ['base-dna'],
          pathOverrides: {'base-dna': '/elsewhere/base-dna'},
        ),
      );
      expect(r.layers.single.root, '/elsewhere/base-dna');
    });

    test('resolves file:// and trailing-slash rootUris', () {
      final host = MemoryDnaHost(
        files: {
          '$root/pubspec.yaml': 'dev_dependencies:\n  a_dna: ^1.0.0\n'
              '  b_dna: ^1.0.0\n',
          '$root/.dart_tool/package_config.json': '{"packages": [ '
              '{"name": "a_dna", "rootUri": "file:///abs/a_dna"}, '
              '{"name": "b_dna", "rootUri": "../../rel/b_dna/"}]}',
          '/abs/a_dna/dna/doc/x.md': '# x',
          '/rel/b_dna/dna/doc/x.md': '# x',
        },
      );
      final r = expandLayerGraph(
        host: host,
        targetRoot: root,
        config: const DnaConfig(),
      );
      expect(r.layers.map((l) => l.root).toList(), [
        '/abs/a_dna',
        '/rel/b_dna',
      ]);
    });

    test('packages without rootUri are skipped', () {
      final host = MemoryDnaHost(
        files: {
          '$root/.dart_tool/package_config.json':
              '{"packages": ["not a map", {"name": "a_dna"}]}',
        },
      );
      expect(
        () => expandLayerGraph(
          host: host,
          targetRoot: root,
          config: const DnaConfig(order: ['a-dna']),
        ),
        throwsFormatException,
      );
    });

    test('an unreadable package_config.json resolves no packages', () {
      final host = MemoryDnaHost(
        files: {'$root/.dart_tool/package_config.json': '{broken'},
      );
      expect(
        () => expandLayerGraph(
          host: host,
          targetRoot: root,
          config: const DnaConfig(order: ['a-dna']),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('cannot be resolved'),
          ),
        ),
      );
    });

    test('unreadable manifests are ignored, not fatal', () {
      final host = MemoryDnaHost(
        files: {
          // Broken manifests at the target …
          '$root/package.json': '{broken',
          '$root/pubspec.yaml': '*undefined-anchor',
          '$root/.dart_tool/package_config.json': '{broken',
        },
      );
      final r = expandLayerGraph(
        host: host,
        targetRoot: root,
        config: const DnaConfig(),
      );
      expect(r.layers, isEmpty);
    });

    test('a layer version falls back over broken manifests', () {
      final host = MemoryDnaHost(
        files: {
          '$root/package.json': '{"devDependencies": {"a-dna": "1"}}',
          // Broken package.json, version comes from the pubspec …
          '$root/node_modules/a-dna/package.json': '{broken',
          '$root/node_modules/a-dna/pubspec.yaml':
              'name: a_dna\nversion: 3.2.1\n',
          '$root/node_modules/a-dna/dna/doc/x.md': '# x',
          // … and no version at all when both are unusable.
          '$root/node_modules/b-dna/package.json': '{"name": "b-dna"}',
          '$root/node_modules/b-dna/pubspec.yaml': '*undefined-anchor',
          '$root/node_modules/b-dna/dna/doc/x.md': '# x',
        },
      );
      final r = expandLayerGraph(
        host: host,
        targetRoot: root,
        config: const DnaConfig(order: ['a-dna', 'b-dna']),
      );
      expect(r.layers.first.version, '3.2.1');
      expect(r.layers.last.version, isNull);
    });
  });

  group('canonicalLayerName', () {
    test('folds snake to kebab, lowercases', () {
      expect(canonicalLayerName('base_dna'), 'base-dna');
      expect(canonicalLayerName('Base-DNA'), 'base-dna');
    });
  });

  group('defaultDnaOrder', () {
    test('combines package.json and pubspec.yaml, dedups by identity', () {
      final host = MemoryDnaHost(
        files: {
          '$root/package.json': '{"devDependencies": {"base-dna": "^1.0.0"}}',
          '$root/pubspec.yaml':
              'dev_dependencies:\n  base_dna: ^1.0.0\n  dna_dart: ^1.0.0\n',
          ...npmDna('base-dna', '1.0.0'),
          '$root/.dart_tool/package_config.json': '{"packages": [ '
              '{"name": "dna_dart", "rootUri": "../../cache/dna_dart"}]}',
          '/cache/dna_dart/pubspec.yaml': 'name: dna_dart\nversion: 1.0.0\n',
          '/cache/dna_dart/dna/doc/x.md': '# x',
        },
      );
      final names = defaultDnaOrder(
        host,
        root,
        manifestRoot: root,
        config: const DnaConfig(),
      );
      expect(names, ['base-dna', 'dna_dart']);
    });
  });
}
