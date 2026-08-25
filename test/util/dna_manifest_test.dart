// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:helix/src/util/dna_config.dart';
import 'package:helix/src/util/dna_fs.dart';
import 'package:helix/src/util/dna_layout.dart';
import 'package:helix/src/util/dna_manifest.dart';
import 'package:gg_json/gg_json.dart';
import 'package:test/test.dart';

void main() {
  const root = '/repo';

  const manifest = DnaManifest(
    layers: [
      DnaManifestLayer(
        name: 'dna-base',
        package: '@tssuite/dna-base',
        ecosystem: 'node',
        resolvedVersion: '1.0.0',
        via: 'dna-dart',
        hash: '0x1',
      ),
      DnaManifestLayer(name: 'self', hash: '0x2'),
    ],
    instances: [
      DnaManifestInstance(path: '.vscode/settings.json', hash: '0x3'),
      DnaManifestInstance(path: 'LICENSE', hash: '0x4'),
    ],
    claude: DnaManifestClaude(claudeMdInclude: ['doc/conventions']),
    baseVersion: '4.0.0',
    baseHash: '0x5',
  );

  MemoryDnaHost hostWithGenerated(String content) =>
      MemoryDnaHost(files: {'$root/$dnaGeneratedPath': content});

  group('DnaManifest', () {
    test('round-trips through the file the engine writes', () {
      // The engine writes `encodeJsonPretty(toJson())` inline, so that is
      // what the round-trip has to exercise.
      final host = hostWithGenerated(encodeJsonPretty(manifest.toJson()));

      final read = DnaManifest.read(host, root)!;
      expect(read.layers, hasLength(2));
      expect(read.layers.first.name, 'dna-base');
      expect(read.layers.first.package, '@tssuite/dna-base');
      expect(read.layers.first.ecosystem, 'node');
      expect(read.layers.first.via, 'dna-dart');
      expect(read.layers.first.resolvedVersion, '1.0.0');
      expect(read.layers.last.name, 'self');
      expect(read.instances, hasLength(2));
      expect(read.instances.first.path, '.vscode/settings.json');
      expect(read.claude.claudeMdInclude, ['doc/conventions']);
      expect(read.baseVersion, '4.0.0');
      expect(read.baseHash, '0x5');
    });

    test('layers and instances share one file, vars stay out', () {
      expect(manifest.toJson()['instances'], hasLength(2));
      expect(manifest.toJson().containsKey('vars'), isFalse);
    });

    test('toJson carries the format version', () {
      expect(manifest.toJson()['version'], dnaFormatVersion);
    });

    test('read returns null only when the file is absent', () {
      expect(DnaManifest.read(MemoryDnaHost(), root), isNull);
    });

    test('a file that exists but is unusable throws', () {
      // null would mean "never instantiated", which makes every instance
      // count as unowned — and unowned instances get overwritten.
      for (final broken in ['{broken', '[1]', '{"version": 5}']) {
        expect(
          () => DnaManifest.read(hostWithGenerated(broken), root),
          throwsFormatException,
          reason: broken,
        );
      }
    });

    test('read tolerates missing optional fields', () {
      final read = DnaManifest.read(
        hostWithGenerated('{"version": $dnaFormatVersion}'),
        root,
      )!;
      expect(read.layers, isEmpty);
      expect(read.instances, isEmpty);
      expect(read.claude.claudeMdInclude, isNull);
      expect(read.baseVersion, 'unknown');
    });

    test('the config file is not the manifest', () {
      final host = MemoryDnaHost(
        files: {'$root/$dnaConfigPath': '{"version": $dnaFormatVersion}'},
      );
      expect(DnaManifest.read(host, root), isNull);
    });
  });
}
