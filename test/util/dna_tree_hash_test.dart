// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import 'package:gg_dna/src/util/dna_fs.dart';
import 'package:gg_dna/src/util/dna_layout.dart';
import 'package:gg_dna/src/util/dna_tree_hash.dart';
import 'package:test/test.dart';

void main() {
  group('isDnaContent', () {
    test('excludes both manifests and git internals', () {
      expect(isDnaContent('doc/develop.md'), isTrue);
      expect(isDnaContent(dnaConfigFilename), isFalse);
      expect(isDnaContent(dnaGeneratedFilename), isFalse);
      expect(isDnaContent('.git'), isFalse);
      expect(isDnaContent('.git/config'), isFalse);
      // Only at the root — deeper down they are ordinary content.
      expect(isDnaContent('sub/$dnaConfigFilename'), isTrue);
    });
  });

  group('hashTree', () {
    test('is stable, EOL-agnostic and excludes both manifests', () {
      final a = MemoryDnaHost(
        files: {
          '/r/dna/doc/x.md': 'line1\nline2\n',
          '/r/dna/_dna.json': '{"version": 1}',
          '/r/dna/_generated.json': '{"version": 1}',
        },
      );
      final b = MemoryDnaHost(
        files: {
          '/r/dna/doc/x.md': 'line1\r\nline2\r\n',
          '/r/dna/_dna.json': '{"different": true}',
          '/r/dna/_generated.json': '{"also": "different"}',
        },
      );
      expect(hashTree(a, '/r/dna'), hashTree(b, '/r/dna'));
    });

    test('returns null for a missing folder', () {
      expect(hashTree(MemoryDnaHost(), '/r/missing'), isNull);
    });

    test('changes when content or paths change', () {
      final a = MemoryDnaHost(files: {'/r/dna/x.md': 'a'});
      final b = MemoryDnaHost(files: {'/r/dna/x.md': 'b'});
      final c = MemoryDnaHost(files: {'/r/dna/y.md': 'a'});
      expect(hashTree(a, '/r/dna'), isNot(hashTree(b, '/r/dna')));
      expect(hashTree(a, '/r/dna'), isNot(hashTree(c, '/r/dna')));
    });
  });

  group('hashFileBytes', () {
    test('normalizes CRLF to LF', () {
      expect(hashFileBytes(_bytes('a\r\nb')), hashFileBytes(_bytes('a\nb')));
    });

    test('differs for different content', () {
      expect(hashFileBytes(_bytes('a')), isNot(hashFileBytes(_bytes('b'))));
    });
  });

  group('normalizeEol', () {
    test('keeps content without carriage returns untouched', () {
      final bytes = _bytes('plain');
      expect(identical(normalizeEol(bytes), bytes), isTrue);
    });

    test('drops only the CR of a CRLF pair', () {
      expect(normalizeEol(_bytes('a\r\nb\rc')), _bytes('a\nb\rc'));
    });
  });

  group('toHex64', () {
    test('renders unsigned 64 bit hex, never signed', () {
      expect(toHex64(0), '0x0000000000000000');
      expect(toHex64(255), '0x00000000000000ff');
      expect(toHex64(-1), '0xffffffffffffffff');
    });
  });
}

// .............................................................................
Uint8List _bytes(String s) => Uint8List.fromList(s.codeUnits);
