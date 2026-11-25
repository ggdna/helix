// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:helix/src/util/ignore_files.dart';
import 'package:test/test.dart';

void main() {
  group('isIgnoreFile', () {
    test('accepts escaped and literal ignore files at any depth', () {
      expect(isIgnoreFile('dot-pubignore'), isTrue);
      expect(isIgnoreFile('dot-gitignore'), isTrue);
      expect(isIgnoreFile('dot-prettierignore'), isTrue);
      expect(isIgnoreFile('.npmignore'), isTrue);
      expect(isIgnoreFile('example/dot-pubignore'), isTrue);
    });

    test('rejects other files', () {
      expect(isIgnoreFile('dot-ignore'), isFalse);
      expect(isIgnoreFile('pubignore'), isFalse);
      expect(isIgnoreFile('doc/ignore'), isFalse);
      expect(isIgnoreFile('dot-pubignore.md'), isFalse);
      expect(isIgnoreFile('dot-pubignore/file'), isFalse);
      expect(isIgnoreFile('doc/guides/ignore-guide.md'), isFalse);
    });
  });

  group('mergeIgnoreSections', () {
    test('joins the sections in order, each under its name', () {
      final merged = mergeIgnoreSections([
        (name: 'a', text: '/doc/guides/\n'),
        (name: 'b', text: '/scripts/\n'),
      ]);
      expect(merged, '# a\n/doc/guides/\n\n# b\n/scripts/\n');
    });

    test('keeps a pattern in the first section that names it', () {
      final merged = mergeIgnoreSections([
        (name: 'a', text: '/doc/guides/\n/doc/templates/\n'),
        (name: 'b', text: '/doc/guides/\n  /scripts/  \n'),
        (name: 'c', text: '/doc/templates/\n'),
      ]);
      expect(
        merged,
        '# a\n/doc/guides/\n/doc/templates/\n\n# b\n  /scripts/  \n',
      );
    });

    test('keeps comments, negations and inner blank lines', () {
      final merged = mergeIgnoreSections([
        (name: 'a', text: '\n\n# built\nbuild/\n\n!build/keep.md\n\n'),
      ]);
      expect(merged, '# a\n# built\nbuild/\n\n!build/keep.md\n');
    });

    test('drops a section without a pattern of its own', () {
      final merged = mergeIgnoreSections([
        (name: 'a', text: '/doc/guides/\n'),
        (name: 'b', text: '# only a comment\n/doc/guides/\n'),
        (name: 'c', text: ''),
      ]);
      expect(merged, '# a\n/doc/guides/\n');
    });

    test('is empty without any pattern', () {
      expect(mergeIgnoreSections([]), '');
      expect(mergeIgnoreSections([(name: 'a', text: '# x\n\n')]), '');
    });

    test('reads CRLF line endings', () {
      final merged = mergeIgnoreSections([
        (name: 'a', text: '/a\r\n/b\r\n'),
        (name: 'b', text: '/b\r\n'),
      ]);
      expect(merged, '# a\n/a\n/b\n');
    });
  });
}
