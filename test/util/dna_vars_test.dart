// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import 'package:helix/src/util/dna_vars.dart';
import 'package:test/test.dart';

void main() {
  group('parseDnaVarEntries', () {
    test('parses strings, coerces numbers and bools', () {
      final r = parseDnaVarEntries(
        '{"dnaProjectName": "myProject", "dnaYear": 2026, "dnaFlag": true}',
        sourceLabel: 'v',
      );
      expect(r.entries, {
        'dnaProjectName': 'myProject',
        'dnaYear': '2026',
        'dnaFlag': 'true',
      });
      expect(r.warnings, isEmpty);
    });

    test('keeps null as deletion marker', () {
      final r = parseDnaVarEntries('{"dnaA": null}', sourceLabel: 'v');
      expect(r.entries.containsKey('dnaA'), isTrue);
      expect(r.entries['dnaA'], isNull);
    });

    test('throws on a key without the dna prefix, naming the rename', () {
      expect(
        () => parseDnaVarEntries('{"projectName": "x"}', sourceLabel: 'v'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('projectName'), contains('dnaProjectName')),
          ),
        ),
      );
    });

    test('throws on a prefixed key that is not camelCase', () {
      expect(
        () => parseDnaVarEntries('{"dna_my_key": "x"}', sourceLabel: 'v'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => parseDnaVarEntries('{"dna": "x"}', sourceLabel: 'v'),
        throwsA(isA<FormatException>()),
      );
    });

    test('skips nested values with warning', () {
      final r = parseDnaVarEntries('{"dnaA": {"b": 1}}', sourceLabel: 'v');
      expect(r.entries, isEmpty);
      expect(r.warnings.single, contains('must be string'));
    });

    test('warns on invalid JSON and on non-objects', () {
      expect(
        parseDnaVarEntries('nope', sourceLabel: 'v').warnings.single,
        contains('v'),
      );
      expect(
        parseDnaVarEntries('[1]', sourceLabel: 'v').warnings.single,
        contains('expected a JSON object'),
      );
    });

    test('tolerates comments (JSONC)', () {
      final r = parseDnaVarEntries(
        '{\n  // company\n  "dnaCompany": "ggsuite",\n}',
        sourceLabel: 'v',
      );
      expect(r.entries, {'dnaCompany': 'ggsuite'});
    });
  });

  group('mergeDnaVarEntries', () {
    test('later wins, null deletes', () {
      final merged = mergeDnaVarEntries(
        {'a': '1', 'b': '2'},
        {'b': '3', 'a': null, 'c': '4'},
      );
      expect(merged, {'b': '3', 'c': '4'});
    });
  });

  group('expandDnaVarValues', () {
    test('resolves values that reference other variables', () {
      expect(
        expandDnaVarValues({
          'dnaOrg': 'acme',
          'dnaTitle': 'Made by dnaOrg',
          'dnaFooter': 'dnaTitle — all rights reserved',
        }),
        {
          'dnaOrg': 'acme',
          'dnaTitle': 'Made by acme',
          'dnaFooter': 'Made by acme — all rights reserved',
        },
      );
    });

    test('references inside values honor the casing of their form', () {
      expect(
        expandDnaVarValues({
          'dnaProject': 'my-project',
          'dnaLib': 'dna_project/lib',
          'dnaClass': 'DnaProject',
        }),
        {
          'dnaProject': 'my-project',
          'dnaLib': 'my_project/lib',
          'dnaClass': 'MyProject',
        },
      );
    });

    test('unknown references stay literal', () {
      expect(
        expandDnaVarValues({'dnaA': 'x dnaUnknown'}),
        {'dnaA': 'x dnaUnknown'},
      );
    });

    test('detects a cycle between two variables', () {
      expect(
        () => expandDnaVarValues({'dnaA': 'dnaB', 'dnaB': 'dnaA'}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('Cyclic variable reference'),
              contains('dnaA'),
              contains('dnaB'),
            ),
          ),
        ),
      );
    });

    test('detects a self-reference and a longer cycle', () {
      expect(
        () => expandDnaVarValues({'dnaA': 'see dnaA'}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => expandDnaVarValues({
          'dnaA': 'dnaB',
          'dnaB': 'dnaC',
          'dnaC': 'dnaA',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('resolves a chain up to the pass limit', () {
      Map<String, String> chain(int length) => {
            for (var i = 0; i < length; i++)
              'dnaV$i': i == length - 1 ? 'end' : 'dnaV${i + 1}',
          };
      expect(
        expandDnaVarValues(chain(maxDnaVarExpansions))['dnaV0'],
        'end',
      );
      expect(
        () => expandDnaVarValues(chain(maxDnaVarExpansions + 3)),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('levels deep'),
              contains('at most $maxDnaVarExpansions'),
            ),
          ),
        ),
      );
    });

    test('fromEntries expands, so the effective set is fully resolved', () {
      final vars = DnaVars.fromEntries({
        'dnaOrg': 'acme',
        'dnaTitle': 'by dnaOrg',
        'dnaGone': null,
      });
      expect(vars.values, {'dnaOrg': 'acme', 'dnaTitle': 'by acme'});
    });
  });

  group('splitIntoWords', () {
    test('splits camel, snake, kebab and mixed forms', () {
      expect(splitIntoWords('projectName'), ['project', 'name']);
      expect(splitIntoWords('gg_template_project'), [
        'gg',
        'template',
        'project',
      ]);
      expect(splitIntoWords('my-var'), ['my', 'var']);
      expect(splitIntoWords('GgTemplateProject'), [
        'gg',
        'template',
        'project',
      ]);
    });
  });

  group('substituteDnaVars', () {
    const vars = DnaVars(values: {'dnaProjectName': 'gg_template_project'});

    test('replaces all five reference forms case-adaptively', () {
      const content = '''
class DnaProjectName {}
var dnaProjectName;
snake: dna_project_name
screaming: DNA_PROJECT_NAME
kebab: dna-project-name''';
      expect(substituteDnaVars(content, vars), '''
class GgTemplateProject {}
var ggTemplateProject;
snake: gg_template_project
screaming: GG_TEMPLATE_PROJECT
kebab: gg-template-project''');
    });

    test('respects word boundaries — no partial-name matches', () {
      const vars = DnaVars(values: {'dnaMyVar': 'foo'});
      expect(substituteDnaVars('dnaMyVariant', vars), 'dnaMyVariant');
      expect(substituteDnaVars('dna_my_vars', vars), 'dna_my_vars');
      expect(substituteDnaVars('xdnaMyVar', vars), 'xdnaMyVar');
    });

    test('supports composites', () {
      const vars = DnaVars(values: {'dnaMyClass': 'myValue'});
      expect(
        substituteDnaVars('class DnaMyClassTest {}', vars),
        'class MyValueTest {}',
      );
      expect(substituteDnaVars('dna_my_class_test', vars), 'my_value_test');
    });

    test('inserts non-identifier values verbatim for every form', () {
      const vars = DnaVars(values: {'dnaCopyrightHolder': 'MY GREAT Limited'});
      expect(
        substituteDnaVars('(c) dnaCopyrightHolder', vars),
        '(c) MY GREAT Limited',
      );
      expect(
        substituteDnaVars('(c) DNA_COPYRIGHT_HOLDER', vars),
        '(c) MY GREAT Limited',
      );
    });

    test('longer variable names win over shorter prefixes', () {
      const vars = DnaVars(
        values: {'dnaProject': 'p', 'dnaProjectName': 'longWins'},
      );
      expect(substituteDnaVars('dnaProjectName', vars), 'longWins');
      expect(substituteDnaVars('dnaProject', vars), 'p');
    });

    test('unknown references stay literal', () {
      expect(substituteDnaVars('dnaUnknownThing', vars), 'dnaUnknownThing');
    });

    test('replaces inside JSON keys and values', () {
      const vars = DnaVars(
        values: {'dnaMyKey': 'realKey', 'dnaMyVal': 'realVal'},
      );
      expect(
        substituteDnaVars('{"dnaMyKey": "dnaMyVal"}', vars),
        '{"realKey": "realVal"}',
      );
    });
  });

  group('renderValue / isCaseConvertible', () {
    test('convertible identifiers are re-cased', () {
      expect(isCaseConvertible('gg_template_project'), isTrue);
      expect(
        renderValue('gg_template_project', DnaVarForm.pascal),
        'GgTemplateProject',
      );
      expect(renderValue('ggTemplate', DnaVarForm.kebab), 'gg-template');
    });

    test('values with spaces, newlines or leading digits stay verbatim', () {
      expect(isCaseConvertible('MY GREAT Limited'), isFalse);
      expect(isCaseConvertible('a\nb'), isFalse);
      expect(isCaseConvertible('2026'), isFalse);
      expect(renderValue('2026', DnaVarForm.screaming), '2026');
    });
  });

  group('looksBinary', () {
    test('detects NUL bytes, accepts text', () {
      expect(looksBinary(Uint8List.fromList([65, 0, 66])), isTrue);
      expect(looksBinary(Uint8List.fromList('hello'.codeUnits)), isFalse);
    });
  });

  group('DnaVars', () {
    test('fromEntries drops deletion markers', () {
      final vars = DnaVars.fromEntries({'a': '1', 'b': null});
      expect(vars.values, {'a': '1'});
      expect(vars.toJson(), {'a': '1'});
    });
  });
}
