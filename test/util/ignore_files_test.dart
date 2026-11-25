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
      for (final path in [
        'dot-pubignore',
        'dot-gitignore',
        'dot-prettierignore',
        '.npmignore',
        'example/dot-pubignore',
      ]) {
        expect(isIgnoreFile(path), isTrue, reason: path);
      }
    });

    test('rejects other files', () {
      for (final path in [
        'dot-ignore',
        'pubignore',
        'doc/ignore',
        'dot-pubignore.md',
        'dot-pubignore/file',
        'doc/guides/ignore-guide.md',
      ]) {
        expect(isIgnoreFile(path), isFalse, reason: path);
      }
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

    test('keeps a repetition that follows a negation', () {
      final merged = mergeIgnoreSections([
        (name: 'a', text: 'doc/\n'),
        (name: 'b', text: '!doc/api/\n'),
        (name: 'c', text: 'doc/\n!doc/api/\n'),
      ]);
      expect(merged, '# a\ndoc/\n\n# b\n!doc/api/\n\n# c\ndoc/\n!doc/api/\n');
    });

    test('leading and escaped trailing spaces belong to the pattern', () {
      final merged = mergeIgnoreSections([
        (name: 'a', text: 'foo\nbar\\ \n'),
        (name: 'b', text: ' foo\nfoo  \nbar\\ \nbar\n'),
      ]);
      expect(merged, '# a\nfoo\nbar\\ \n\n# b\n foo\nbar\n');
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
