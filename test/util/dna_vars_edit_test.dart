// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:helix/src/util/dna_vars.dart';
import 'package:helix/src/util/dna_vars_edit.dart';
import 'package:test/test.dart';

void main() {
  /// The entries [text] parses to — what the engine will read.
  Map<String, Object?> parsed(String text) =>
      parseDnaVarEntries(text, sourceLabel: 'test').entries;

  group('addDnaVars', () {
    test('creates a fresh file when there is none', () {
      final text = addDnaVars(null, {'dnaOrg': 'acme', 'dnaName': 'x'});
      expect(text, '{\n  "dnaOrg": "acme",\n  "dnaName": "x"\n}\n');
    });

    test('fills an empty object', () {
      expect(
        addDnaVars('{}\n', {'dnaOrg': 'acme'}),
        '{\n  "dnaOrg": "acme"\n}\n',
      );
    });

    test('appends after the last entry, keeping comments', () {
      const before = '''
{
  // The identity of the organization.
  "dnaCompany": "Acme" // trailing note
}
''';
      final text = addDnaVars(before, {'dnaOrg': 'acme'});
      expect(text, '''
{
  // The identity of the organization.
  "dnaCompany": "Acme", // trailing note
  "dnaOrg": "acme"
}
''');
      expect(parsed(text), {'dnaCompany': 'Acme', 'dnaOrg': 'acme'});
    });

    test('adds no second comma after a trailing one', () {
      final text = addDnaVars('{\n  "dnaA": "a",\n}\n', {'dnaB': 'b'});
      expect(parsed(text), {'dnaA': 'a', 'dnaB': 'b'});
      expect(text, isNot(contains(',,')));
    });

    test('a body of comments only needs no comma', () {
      const before =
          '{\n  // nothing yet, see /* below */\n  /* "dnaX" */\n}\n';
      final text = addDnaVars(before, {'dnaB': 'b'});
      expect(parsed(text), {'dnaB': 'b'});
      expect(text, contains('// nothing yet'));
    });

    test('ignores comment markers and commas inside strings', () {
      final text = addDnaVars('{"dnaUrl": "https://x.org/a,"}', {'dnaB': 'b'});
      expect(parsed(text), {'dnaUrl': 'https://x.org/a,', 'dnaB': 'b'});
      final escaped = addDnaVars(r'{"dnaQ": "say \"hi\""}', {'dnaB': 'b'});
      expect(parsed(escaped), {'dnaQ': 'say "hi"', 'dnaB': 'b'});
    });

    test('rejects a closing brace that is commented out', () {
      expect(
        () => addDnaVars('{"dnaA": "a" // x}', {'dnaB': 'b'}),
        throwsFormatException,
      );
      expect(
        () => addDnaVars('{"dnaA": "a" /* x}', {'dnaB': 'b'}),
        throwsFormatException,
      );
    });

    test('skips braces in comments around the object', () {
      const before = '// {header}\n{\n  "dnaA": "a"\n}\n// see {docs}\n';
      final text = addDnaVars(before, {'dnaB': 'b'});
      expect(parsed(text), {'dnaA': 'a', 'dnaB': 'b'});
      expect(text, startsWith('// {header}\n{'));
      expect(text, endsWith('}\n// see {docs}\n'));
    });

    test('sets a key that carries the deletion marker in place', () {
      const before = '{\n  "dnaA": null, // inherited one dropped\n}\n';
      final text = addDnaVars(before, {'dnaA': 'x'});
      expect(text, '{\n  "dnaA": "x", // inherited one dropped\n}\n');
    });

    test('a deletion marker inside a comment is not touched', () {
      final text = addDnaVars('{\n  // "dnaA": null\n}', {'dnaA': 'x'});
      expect(text, contains('// "dnaA": null'));
      expect(parsed(text), {'dnaA': 'x'});
    });

    test('escapes the values it writes', () {
      final text = addDnaVars(null, {'dnaHolder': 'A "B" C\\D'});
      expect(parsed(text), {'dnaHolder': 'A "B" C\\D'});
    });

    test('leaves the text alone when there is nothing to add', () {
      expect(addDnaVars('{ /* x */ }', {}), '{ /* x */ }');
    });

    test('rejects text without an object', () {
      expect(() => addDnaVars('[]', {'dnaB': 'b'}), throwsFormatException);
      expect(() => addDnaVars('} {', {'dnaB': 'b'}), throwsFormatException);
    });
  });
}
