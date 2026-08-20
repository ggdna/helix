// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:helix/src/engine/base_dna.dart';
import 'package:helix/src/util/dna_fs.dart';
import 'package:helix/src/util/dna_layout.dart';
import 'package:helix/src/util/dna_tree_hash.dart';
import 'package:helix/src/util/dna_vars.dart';
import 'package:test/test.dart';

void main() {
  group('baseDnaFiles', () {
    test('matches the dna folder this package ships', () {
      // GENERATED, like test/helix_version_test.dart: drift is repaired
      // here rather than reported — the map is the source, `dna/` is what
      // consumers get. Nothing else writes these files, so this test is
      // their single owner.
      baseDnaFiles.forEach((rel, content) {
        final file = File('$dnaDirname/$rel');
        if (!file.existsSync() || file.readAsStringSync() != content) {
          file.parent.createSync(recursive: true);
          file.writeAsStringSync(content);
        }
        expect(file.readAsStringSync(), content, reason: rel);
      });
    });

    test('carries no file the engine excludes from a layer', () {
      // `_generated.json` is the engine's own bookkeeping. Embedding it
      // would ship a stale hash to every consumer — and `isDnaContent`
      // keeps it out of the hash anyway.
      expect(baseDnaFiles.keys, isNot(contains(dnaGeneratedFilename)));
      expect(
        baseDnaFiles.keys.where(isDnaContent).toList()..sort(),
        [dnaVarsFilename, baseDnaHelloWorldPath]..sort(),
      );
    });

    test('declares no parent layer — it is the bottom of every tree', () {
      expect(baseDnaConfig, contains('"layers": []'));
      expect(baseDnaConfig, contains('"version": $dnaFormatVersion'));
    });

    test('is reachable under the path init places it at', () {
      expect(helloWorldDnaPath, '$dnaDirname/$baseDnaHelloWorldPath');
      expect(baseDnaFiles[baseDnaHelloWorldPath], helloWorldDoc);
    });
  });

  group('materializeBaseDna', () {
    test('writes every base file below dna/ of a fresh folder', () {
      final host = MemoryDnaHost();
      final root = materializeBaseDna(host);

      expect(host.existsDir('$root/$dnaDirname'), isTrue);
      baseDnaFiles.forEach((rel, content) {
        expect(host.readString('$root/$dnaDirname/$rel'), content, reason: rel);
      });
      expect(
        host.listFilesRecursive('$root/$dnaDirname')..sort(),
        baseDnaFiles.keys.toList()..sort(),
      );
    });

    test('hands out a new folder every time, so runs cannot collide', () {
      final host = MemoryDnaHost();
      expect(materializeBaseDna(host), isNot(materializeBaseDna(host)));
    });
  });
}
