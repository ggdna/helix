// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_dna/src/util/dna_fs.dart';
import 'package:gg_dna/src/util/dna_manifest.dart';
import 'package:test/test.dart';

void main() {
  const root = '/repo';

  const manifest = DnaManifest(
    layers: [
      DnaManifestLayer(
        name: 'base-dna',
        package: 'base-dna',
        resolvedVersion: '1.0.0',
        via: 'dna-dart',
        hash: '0x1',
      ),
      DnaManifestLayer(name: 'local', path: '../local', hash: '0x2'),
    ],
    instances: [
      DnaManifestInstance(path: '.vscode/settings.json', hash: '0x3'),
      DnaManifestInstance(path: 'LICENSE', hash: '0x4'),
    ],
    claude: DnaManifestClaude(claudeMdInclude: ['doc/conventions']),
    baseVersion: '5.0.0',
    baseHash: '0x5',
    hash: '0x6',
  );

  group('DnaManifest', () {
    test('round-trips through write and read', () {
      final host = MemoryDnaHost();
      manifest.write(host, root);
      expect(host.existsFile('$root/dna/_dna.json'), isTrue);

      final read = DnaManifest.read(host, root)!;
      expect(read.layers, hasLength(2));
      expect(read.layers.first.name, 'base-dna');
      expect(read.layers.first.via, 'dna-dart');
      expect(read.layers.first.resolvedVersion, '1.0.0');
      expect(read.layers.last.path, '../local');
      expect(read.instances, hasLength(2));
      expect(read.instances.first.path, '.vscode/settings.json');
      expect(read.claude.claudeMdInclude, ['doc/conventions']);
      // Instances live in their own file, layers in the manifest.
      expect(host.existsFile('$root/dna/_instances.json'), isTrue);
      expect(manifest.toJson().containsKey('instances'), isFalse);
      expect(manifest.toJson().containsKey('vars'), isFalse);
      expect(manifest.instancesToJson()['instances'], hasLength(2));
      expect(read.baseVersion, '5.0.0');
      expect(read.baseHash, '0x5');
      expect(read.hash, '0x6');
    });

    test('toJson carries the format version', () {
      expect(manifest.toJson()['version'], dnaManifestFormatVersion);
    });

    test('read returns null for missing, invalid or outdated manifests', () {
      expect(DnaManifest.read(MemoryDnaHost(), root), isNull);
      expect(
        DnaManifest.read(
          MemoryDnaHost(files: {'$root/dna/_dna.json': '{broken'}),
          root,
        ),
        isNull,
      );
      expect(
        DnaManifest.read(
          MemoryDnaHost(files: {'$root/dna/_dna.json': '{"version": 4}'}),
          root,
        ),
        isNull,
      );
      expect(
        DnaManifest.read(
          MemoryDnaHost(files: {'$root/dna/_dna.json': '[1]'}),
          root,
        ),
        isNull,
      );
    });

    test('an unusable instances file falls back to the manifest', () {
      for (final broken in ['{broken', '[1]', '{"version": 4}']) {
        final host = MemoryDnaHost(
          files: {
            '$root/dna/_dna.json': '{"version": 5, "instances": [ '
                '{"path": "a.md", "hash": "0x1"}]}',
            '$root/dna/_instances.json': broken,
          },
        );
        final read = DnaManifest.read(host, root)!;
        expect(read.instances.single.path, 'a.md', reason: broken);
      }
    });

    test('read tolerates missing optional fields', () {
      final host = MemoryDnaHost(
        files: {'$root/dna/_dna.json': '{"version": 5}'},
      );
      final read = DnaManifest.read(host, root)!;
      expect(read.layers, isEmpty);
      expect(read.instances, isEmpty);
      expect(read.claude.claudeMdInclude, isNull);
      expect(read.baseVersion, 'unknown');
    });
  });
}
