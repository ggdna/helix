// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:helix/src/util/jsonc.dart';
import 'package:test/test.dart';

void main() {
  group('parseJsonc', () {
    test('parses plain JSON', () {
      expect(parseJsonc('{"a": 1}'), {'a': 1});
    });

    test('strips line comments', () {
      const src = '''
{
  // comment
  "a": 1 // trailing
}''';
      expect(parseJsonc(src), {'a': 1});
    });

    test('strips block comments', () {
      const src = '{ /* multi\nline */ "a": /* inline */ 1 }';
      expect(parseJsonc(src), {'a': 1});
    });

    test('keeps comment-like content inside strings', () {
      expect(parseJsonc('{"url": "http://x/*y*/z"}'), {
        'url': 'http://x/*y*/z',
      });
      expect(parseJsonc(r'{"a": "with \" // quote"}'), {
        'a': 'with " // quote',
      });
    });

    test('tolerates trailing commas in objects and arrays', () {
      expect(parseJsonc('{"a": 1,}'), {'a': 1});
      expect(parseJsonc('[1, 2,]'), [1, 2]);
      expect(
        parseJsonc('''
{
  "a": [1, 2, // comment after comma
  ],
}'''),
        {
          'a': [1, 2],
        },
      );
    });

    test('keeps non-trailing commas', () {
      expect(parseJsonc('[1, 2, 3]'), [1, 2, 3]);
    });

    test('detects trailing commas behind block comments', () {
      expect(parseJsonc('[1, /* why */ ]'), [1]);
      expect(parseJsonc('[1, /* multi\nline */ ]'), [1]);
      expect(parseJsonc('{"a": 1, /* c */ /* d */ }'), {'a': 1});
    });

    test('a comma followed by a comment and more data stays', () {
      expect(parseJsonc('[1, /* c */ 2]'), [1, 2]);
      expect(parseJsonc('[1, // c\n2]'), [1, 2]);
    });

    test('throws FormatException with source label', () {
      expect(
        () => parseJsonc('{invalid', sourceLabel: 'x.json'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('x.json'),
          ),
        ),
      );
    });
  });

  group('stripJsonComments', () {
    test('preserves offsets by blanking with spaces', () {
      const src = '{"a": /*x*/ 1}';
      final out = stripJsonComments(src);
      expect(out.length, src.length);
      expect(out, '{"a":       1}');
    });

    test('keeps newlines inside block comments', () {
      final out = stripJsonComments('{/*a\nb*/"a":1}');
      expect(out.contains('\n'), isTrue);
    });
  });
}
