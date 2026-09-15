// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:typed_data';

import 'package:helix/src/util/dna_includes.dart';
import 'package:test/test.dart';

void main() {
  Map<String, Uint8List> mergedOf(Map<String, String> texts) => {
    for (final entry in texts.entries)
      entry.key: Uint8List.fromList(utf8.encode(entry.value)),
  };

  group('resolveIncludes', () {
    test('splices the referenced file in place of the marker', () {
      final merged = mergedOf({'doc/guide.md': '# Guide\n\nDetails.\n'});
      final result = resolveIncludes(
        '# Host\n\n<!-- helix:include:doc/guide.md -->\n',
        merged,
        selfLabel: 'host.md',
      );
      expect(result, '# Host\n\n# Guide\n\nDetails.\n\n');
    });

    test('tolerates extra whitespace inside the marker', () {
      final merged = mergedOf({'doc/guide.md': 'Details.'});
      final result = resolveIncludes(
        '<!--   helix:include:doc/guide.md   -->',
        merged,
        selfLabel: 'host.md',
      );
      expect(result, 'Details.');
    });

    test('leaves lines without a marker untouched', () {
      final merged = mergedOf({});
      final result = resolveIncludes(
        '# Host\n\nNo marker here.\n',
        merged,
        selfLabel: 'host.md',
      );
      expect(result, '# Host\n\nNo marker here.\n');
    });

    test('throws when the referenced file is missing', () {
      final merged = mergedOf({});
      expect(
        () => resolveIncludes(
          '<!-- helix:include:doc/missing.md -->',
          merged,
          selfLabel: 'host.md',
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('host.md'), contains('doc/missing.md')),
          ),
        ),
      );
    });

    test('ignores a lone @import line by default', () {
      final merged = mergedOf({'doc/guide.md': 'Details.'});
      final result = resolveIncludes(
        '@doc/guide.md',
        merged,
        selfLabel: 'host.md',
      );
      expect(result, '@doc/guide.md');
    });

    test('inlines a lone @import line when inlineAtImports is set', () {
      final merged = mergedOf({'doc/guide.md': 'Details.'});
      final result = resolveIncludes(
        '@doc/guide.md',
        merged,
        selfLabel: 'host.md',
        inlineAtImports: true,
      );
      expect(result, 'Details.');
    });

    test('ignores a bare @tag such as an @license header line', () {
      final merged = mergedOf({});
      final result = resolveIncludes(
        '@license',
        merged,
        selfLabel: 'host.md',
        inlineAtImports: true,
      );
      expect(result, '@license');
    });

    test('does not treat an @-word inside a longer line as an import', () {
      final merged = mergedOf({});
      final result = resolveIncludes(
        'Contact us @doc/guide.md for details.',
        merged,
        selfLabel: 'host.md',
        inlineAtImports: true,
      );
      expect(result, 'Contact us @doc/guide.md for details.');
    });

    test('throws when an inlined @import is missing', () {
      final merged = mergedOf({});
      expect(
        () => resolveIncludes(
          '@doc/missing.md',
          merged,
          selfLabel: 'host.md',
          inlineAtImports: true,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
