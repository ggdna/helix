// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import 'package:gg_dna/src/util/dna_vars.dart';
import 'package:test/test.dart';

void main() {
  group('parseDnaVarEntries', () {
    test('parses strings, coerces numbers and bools', () {
      final r = parseDnaVarEntries(
        '{"projectName": "myProject", "year": 2026, "flag": true}',
        sourceLabel: 'v',
      );
      expect(r.entries, {
        'projectName': 'myProject',
        'year': '2026',
        'flag': 'true',
      });
      expect(r.warnings, isEmpty);
    });

    test('keeps null as deletion marker', () {
      final r = parseDnaVarEntries('{"a": null}', sourceLabel: 'v');
      expect(r.entries.containsKey('a'), isTrue);
      expect(r.entries['a'], isNull);
    });

    test('warns on non-camelCase keys and skips them', () {
      final r = parseDnaVarEntries(
        '{"My_Key": "x", "ok": "y"}',
        sourceLabel: 'v',
      );
      expect(r.entries, {'ok': 'y'});
      expect(r.warnings.single, contains('My_Key'));
    });

    test('warns when a key carries the dna prefix', () {
      final r = parseDnaVarEntries('{"dnaFoo": "x"}', sourceLabel: 'v');
      expect(r.warnings.single, contains('without the prefix'));
    });

    test('skips nested values with warning', () {
      final r = parseDnaVarEntries('{"a": {"b": 1}}', sourceLabel: 'v');
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
        '{\n  // company\n  "company": "ggsuite",\n}',
        sourceLabel: 'v',
      );
      expect(r.entries, {'company': 'ggsuite'});
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
    const vars = DnaVars(values: {'projectName': 'gg_template_project'});

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
      const vars = DnaVars(values: {'myVar': 'foo'});
      expect(substituteDnaVars('dnaMyVariant', vars), 'dnaMyVariant');
      expect(substituteDnaVars('dna_my_vars', vars), 'dna_my_vars');
      expect(substituteDnaVars('xdnaMyVar', vars), 'xdnaMyVar');
    });

    test('supports composites', () {
      const vars = DnaVars(values: {'myClass': 'myValue'});
      expect(
        substituteDnaVars('class DnaMyClassTest {}', vars),
        'class MyValueTest {}',
      );
      expect(substituteDnaVars('dna_my_class_test', vars), 'my_value_test');
    });

    test('inserts non-identifier values verbatim for every form', () {
      const vars = DnaVars(values: {'copyrightHolder': 'MY GREAT Limited'});
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
        values: {'project': 'p', 'projectName': 'longWins'},
      );
      expect(substituteDnaVars('dnaProjectName', vars), 'longWins');
      expect(substituteDnaVars('dnaProject', vars), 'p');
    });

    test('unknown references stay literal', () {
      expect(substituteDnaVars('dnaUnknownThing', vars), 'dnaUnknownThing');
    });

    test('replaces inside JSON keys and values', () {
      const vars = DnaVars(values: {'myKey': 'realKey', 'myVal': 'realVal'});
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
