// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:helix/src/commands/init.dart';
import 'package:helix/src/util/dna_config.dart';
import 'package:helix/src/util/dna_config_edit.dart';
import 'package:helix/src/util/dna_fs.dart';
import 'package:test/test.dart';

void main() {
  group('addDnaLayer', () {
    test('fills an empty array', () {
      expect(
        addDnaLayer('{"layers": []}', 'dna_base'),
        '{"layers": ["dna_base"]}',
      );
    });

    test('appends inline in a one-line array', () {
      expect(
        addDnaLayer('{"layers": ["dna_base"]}', 'dna_dart'),
        '{"layers": ["dna_base", "dna_dart"]}',
      );
    });

    test('respects an existing trailing comma', () {
      expect(
        addDnaLayer('{"layers": ["dna_base",]}', 'dna_dart'),
        '{"layers": ["dna_base", "dna_dart"]}',
      );
    });

    test('keeps the indentation of a multi-line array', () {
      const text = '''
{
  "layers": [
    "dna_base"
  ]
}
''';
      expect(addDnaLayer(text, 'dna_dart'), '''
{
  "layers": [
    "dna_base",
    "dna_dart"
  ]
}
''');
    });

    test('appends after a trailing comma in a multi-line array', () {
      const text = '{\n  "layers": [\n    "a",\n  ]\n}';
      expect(
        addDnaLayer(text, 'b'),
        '{\n  "layers": '
        '[\n    "a",\n    "b"\n  ]\n}',
      );
    });

    test('keeps comments — the config is hand-authored', () {
      const text = '''
{
  // The layers, in application order.
  "layers": ["dna_base"] // last one wins
}
''';
      final result = addDnaLayer(text, 'dna_dart');
      expect(result, contains('// The layers, in application order.'));
      expect(result, contains('"layers": ["dna_base", "dna_dart"]'));
      expect(result, contains('// last one wins'));
    });

    test('ignores brackets inside strings', () {
      expect(
        addDnaLayer('{"layers": ["a]b"]}', 'c'),
        '{"layers": ["a]b", "c"]}',
      );
    });

    test('ignores an escaped quote inside a string', () {
      expect(
        addDnaLayer(r'{"layers": ["a\"]"]}', 'c'),
        r'{"layers": ["a\"]", "c"]}',
      );
    });

    test('adds a layers key to a config that has none', () {
      final result = addDnaLayer('{\n  "version": 1\n}', 'dna_base');
      expect(result, '{\n  "layers": ["dna_base"],\n  "version": 1\n}');
    });

    test('adds a layers key to an empty object', () {
      expect(addDnaLayer('{}', 'dna_base'), '{\n  "layers": ["dna_base"]}');
    });

    test('throws when the array is not closed', () {
      expect(
        () => addDnaLayer('{"layers": ["a"', 'b'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws when there is no object at all', () {
      expect(() => addDnaLayer('[]', 'b'), throwsA(isA<FormatException>()));
    });

    test('the result of editing the init skeleton stays readable', () {
      const root = '/p';
      var text = dnaConfigSkeleton([]);
      text = addDnaLayer(text, 'dna_base');
      text = addDnaLayer(text, 'dna_dart');

      final host = MemoryDnaHost(files: {'$root/$dnaConfigPath': text});
      final result = readDnaConfig(host, root);
      expect(result.config.layers, ['dna_base', 'dna_dart']);
      expect(result.warnings, isEmpty);
      // The explanatory comments of the skeleton survive.
      expect(text, contains('// The DNA layers, in application order'));
    });
  });
}
