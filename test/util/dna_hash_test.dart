// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_dna/src/util/dna_hash.dart';
import 'package:test/test.dart';

void main() {
  group('hashDnaDirectory', () {
    test('returns null when the directory does not exist', () {
      final dir = Directory(
        '${Directory.systemTemp.path}/gg_dna_hash_missing',
      );
      expect(hashDnaDirectory(dir), isNull);
    });

    test('returns a stable hex hash for the same content', () {
      final tmp = Directory.systemTemp.createTempSync('gg_dna_hash_');
      try {
        File('${tmp.path}/a.txt').writeAsStringSync('hello');
        File('${tmp.path}/b.txt').writeAsStringSync('world');
        final h1 = hashDnaDirectory(tmp);
        final h2 = hashDnaDirectory(tmp);
        expect(h1, isNotNull);
        expect(h1, startsWith('0x'));
        expect(h1, equals(h2));
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('ignores the manifest file', () {
      final tmp = Directory.systemTemp.createTempSync('gg_dna_hash_');
      try {
        File('${tmp.path}/a.txt').writeAsStringSync('hello');
        final before = hashDnaDirectory(tmp);
        File('${tmp.path}/$dnaManifestFilename').writeAsStringSync('{}');
        final after = hashDnaDirectory(tmp);
        expect(after, equals(before));
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('ignores a root .git folder', () {
      final tmp = Directory.systemTemp.createTempSync('gg_dna_hash_');
      try {
        File('${tmp.path}/a.txt').writeAsStringSync('hello');
        final before = hashDnaDirectory(tmp);
        final git = Directory('${tmp.path}/.git')..createSync();
        File('${git.path}/index').writeAsStringSync('git state');
        expect(hashDnaDirectory(tmp), equals(before));
        File('${git.path}/index').writeAsStringSync('changed git state');
        expect(hashDnaDirectory(tmp), equals(before));
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });

    test('is line-ending agnostic', () {
      final lfDir = Directory.systemTemp.createTempSync('gg_dna_hash_');
      final crlfDir = Directory.systemTemp.createTempSync('gg_dna_hash_');
      try {
        File('${lfDir.path}/a.md').writeAsStringSync('line1\nline2\n');
        File('${crlfDir.path}/a.md').writeAsStringSync('line1\r\nline2\r\n');
        expect(hashDnaDirectory(lfDir), equals(hashDnaDirectory(crlfDir)));

        // Real content differences still change the hash.
        File('${crlfDir.path}/a.md').writeAsStringSync('line1\r\nother\r\n');
        expect(
          hashDnaDirectory(lfDir),
          isNot(equals(hashDnaDirectory(crlfDir))),
        );
      } finally {
        lfDir.deleteSync(recursive: true);
        crlfDir.deleteSync(recursive: true);
      }
    });
  });
}
