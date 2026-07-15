// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_dna/src/util/dna_config.dart';
import 'package:gg_dna/src/util/dna_manifest.dart';
import 'package:test/test.dart';

void main() {
  group('DnaManifest', () {
    test('read returns null when the manifest file is missing', () {
      final tmp = Directory.systemTemp.createTempSync('gg_dna_manifest_');
      try {
        expect(DnaManifest.read(tmp), isNull);
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('write and read round-trip preserves all fields', () {
      final tmp = Directory.systemTemp.createTempSync('gg_dna_manifest_');
      try {
        const original = DnaManifest(
          layers: [
            DnaManifestLayer(
              name: 'dna_company',
              git: 'https://example.com/dna_company.git',
              versionConstraint: '^1.4.0',
              resolvedVersion: '1.5.0',
              resolvedTag: 'v1.5.0',
              commit: 'abc123',
              hash: '0xdeadbeef',
            ),
            DnaManifestLayer(
              name: 'dna_repo',
              path: 'dna/_override',
              hash: '0xfeedface',
            ),
          ],
          baseVersion: '1.2.3',
          baseHash: '0xcafef00d',
          hash: '0x0000000000000001',
        );
        original.write(tmp);
        final loaded = DnaManifest.read(tmp);
        expect(loaded, isNotNull);
        expect(loaded!.toJson(), equals(original.toJson()));
        expect(loaded.layers, hasLength(2));
        expect(loaded.layers.first.resolvedTag, 'v1.5.0');
        expect(loaded.layers.last.path, 'dna/_override');
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('writes the format version', () {
      final tmp = Directory.systemTemp.createTempSync('gg_dna_manifest_');
      try {
        const DnaManifest().write(tmp);
        final data = jsonDecode(
          File('${tmp.path}/.dna.json').readAsStringSync(),
        ) as Map<String, dynamic>;
        expect(data['version'], DnaManifest.formatVersion);
        expect(data['layers'], isEmpty);
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('read returns null on invalid JSON', () {
      final tmp = Directory.systemTemp.createTempSync('gg_dna_manifest_');
      try {
        File('${tmp.path}/.dna.json').writeAsStringSync('not json');
        expect(DnaManifest.read(tmp), isNull);
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('read returns null on pre-2.0 manifests', () {
      final tmp = Directory.systemTemp.createTempSync('gg_dna_manifest_');
      try {
        // A gg_dna 1.x manifest has no version field.
        File('${tmp.path}/.dna.json').writeAsStringSync(
          '{"overlay": "gg_foo", "hash": "0x01"}',
        );
        expect(DnaManifest.read(tmp), isNull);
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('read tolerates a missing layers list and layer names', () {
      final tmp = Directory.systemTemp.createTempSync('gg_dna_manifest_');
      try {
        File('${tmp.path}/.dna.json').writeAsStringSync(
          '{"version": 2, "hash": "0x01"}',
        );
        final manifest = DnaManifest.read(tmp);
        expect(manifest!.layers, isEmpty);
        expect(manifest.hash, '0x01');

        File('${tmp.path}/.dna.json').writeAsStringSync(
          '{"version": 2, "layers": [{}]}',
        );
        expect(DnaManifest.read(tmp)!.layers.single.name, '');
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('read returns null on structurally malformed manifests', () {
      final tmp = Directory.systemTemp.createTempSync('gg_dna_manifest_');
      try {
        final file = File('${tmp.path}/.dna.json');

        // Valid JSON, but not an object.
        file.writeAsStringSync('[1, 2, 3]');
        expect(DnaManifest.read(tmp), isNull);

        // A layers element that is not an object.
        file.writeAsStringSync('{"version": 2, "layers": [42]}');
        expect(DnaManifest.read(tmp), isNull);

        // A non-list layers value is treated as absent.
        file.writeAsStringSync('{"version": 2, "layers": "nope"}');
        expect(DnaManifest.read(tmp)!.layers, isEmpty);

        // Non-string fields are treated as absent.
        file.writeAsStringSync(
          '{"version": 2, "hash": 42, "layers": [{"name": 7, "git": []}]}',
        );
        final manifest = DnaManifest.read(tmp);
        expect(manifest!.hash, isNull);
        expect(manifest.layers.single.name, '');
        expect(manifest.layers.single.git, isNull);
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });
  });

  group('DnaManifestLayer', () {
    const config = DnaLayerConfig(
      name: 'company',
      git: 'gg_dna_company',
      rawVersionConstraint: '^1.4.0',
    );

    test('fromConfig copies the raw config values', () {
      final layer = DnaManifestLayer.fromConfig(
        config,
        resolvedVersion: '1.5.0',
        resolvedTag: 'v1.5.0',
        commit: 'abc',
        hash: '0x01',
      );
      expect(layer.name, 'company');
      expect(layer.git, 'gg_dna_company');
      expect(layer.path, isNull);
      expect(layer.versionConstraint, '^1.4.0');
      expect(layer.resolvedTag, 'v1.5.0');
    });

    test('matchesConfig detects drift in any config field', () {
      final layer = DnaManifestLayer.fromConfig(config);
      expect(layer.matchesConfig(config), isTrue);
      expect(
        layer.matchesConfig(const DnaLayerConfig(name: 'x', git: 'g')),
        isFalse,
      );
      expect(
        layer.matchesConfig(const DnaLayerConfig(name: 'company', git: 'g')),
        isFalse,
      );
      expect(
        layer.matchesConfig(
          const DnaLayerConfig(name: 'company', path: 'dna/_override'),
        ),
        isFalse,
      );
      expect(
        layer.matchesConfig(
          const DnaLayerConfig(
            name: 'company',
            git: 'gg_dna_company',
            rawVersionConstraint: '^2.0.0',
          ),
        ),
        isFalse,
      );
    });
  });

  group('readPackageVersion', () {
    test('returns null when pubspec.yaml is missing', () {
      final tmp = Directory.systemTemp.createTempSync('gg_dna_version_');
      try {
        expect(readPackageVersion(tmp.path), isNull);
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('returns the version field from pubspec.yaml', () {
      final tmp = Directory.systemTemp.createTempSync('gg_dna_version_');
      try {
        File('${tmp.path}/pubspec.yaml').writeAsStringSync(
          'name: foo\nversion: 4.5.6\n',
        );
        expect(readPackageVersion(tmp.path), equals('4.5.6'));
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });
  });
}
