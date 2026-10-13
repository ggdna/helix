// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:helix/src/engine/ask_must_overrides.dart';
import 'package:helix/src/util/dna_config.dart';
import 'package:helix/src/util/dna_fs.dart';
import 'package:helix/src/util/dna_layout.dart';
import 'package:helix/src/util/dna_vars.dart';
import 'package:helix/src/util/select_prompt.dart';
import 'package:helix/src/util/text_prompt.dart';
import 'package:test/test.dart';

void main() {
  const root = '/t';

  /// A DNA package below node_modules with [mustOverride] flags and
  /// [vars] in its own `_vars.json`.
  Map<String, String> npmDna(
    String name, {
    List<String> layers = const [],
    String mustOverride = '{}',
    String vars = '{}',
  }) => {
    '$root/node_modules/$name/package.json': '{"name": "$name"}',
    '$root/node_modules/$name/$dnaConfigPath':
        '{"version": $dnaMustOverrideFormatVersion, '
        '"layers": [${layers.map((l) => '"$l"').join(', ')}], '
        '"mustOverride": $mustOverride}',
    '$root/node_modules/$name/dna/_vars.json': vars,
  };

  /// A project listing [layers], with the guides layer marking
  /// `dnaCopyrightHolder` and the scripts layer marking
  /// `dnaGitQuickCheckPipelineName`.
  MemoryDnaHost project({
    List<String> layers = const ['dna-guides', 'dna-scripts'],
    String? ownVars,
  }) => MemoryDnaHost(
    files: {
      '$root/$dnaConfigPath':
          '{"version": $dnaFormatVersion, '
          '"layers": [${layers.map((l) => '"$l"').join(', ')}]}',
      '$root/$dnaVarsPath': ?ownVars,
      ...npmDna(
        'dna-guides',
        mustOverride: '{"dnaCopyrightHolder": true}',
        vars: '{"dnaCopyrightHolder": "ggsuite"}',
      ),
      ...npmDna(
        'dna-scripts',
        mustOverride: '{"dnaGitQuickCheckPipelineName": true}',
      ),
    },
  );

  final asked = <({String prompt, String? defaultValue})>[];
  final logged = <String>[];

  setUp(() {
    asked.clear();
    logged.clear();
  });

  /// A [TextPrompt] that answers from [answers], or throws [unavailable].
  TextPrompt fakePrompt(
    List<String> answers, {
    SelectPromptUnavailableException? unavailable,
  }) {
    final queue = [...answers];
    return ({required String prompt, String? defaultValue}) async {
      asked.add((prompt: prompt, defaultValue: defaultValue));
      if (unavailable != null) throw unavailable;
      return queue.removeAt(0);
    };
  }

  Map<String, Object?> ownVarsOf(MemoryDnaHost host) => parseDnaVarEntries(
    host.readString('$root/$dnaVarsPath'),
    sourceLabel: 'test',
  ).entries;

  group('missingProjectVars', () {
    test('names every variable the layers require, never their values', () {
      final missing = missingProjectVars(project(), root);
      expect(
        [for (final m in missing) (m.variable, m.requiredBy, m.fromConfigVars)],
        [
          // dna-guides ships "ggsuite" — exactly what must not be taken.
          ('dnaCopyrightHolder', 'dna-guides', null),
          ('dnaGitQuickCheckPipelineName', 'dna-scripts', null),
        ],
      );
    });

    test('offers the value the project put into the vars of _dna.json', () {
      final host = project();
      host.writeString(
        '$root/$dnaConfigPath',
        '{"version": $dnaFormatVersion, '
            '"layers": ["dna-guides"], "vars": {"dnaCopyrightHolder": "Acme"}}',
      );
      expect(missingProjectVars(host, root).single.fromConfigVars, 'Acme');
    });

    test('rejects a project _vars.json that cannot be parsed', () {
      final host = project(ownVars: '{"dnaCopyrightHolder": "Acme",,}');
      expect(() => missingProjectVars(host, root), throwsFormatException);
    });

    test('leaves out what the project sets already', () {
      final host = project(
        ownVars:
            '{"dnaCopyrightHolder": "acme", '
            '"dnaGitQuickCheckPipelineName": null}',
      );
      expect(missingProjectVars(host, root).map((m) => m.variable), [
        'dnaGitQuickCheckPipelineName',
      ]);
    });

    test('is empty when no layer requires anything', () {
      expect(missingProjectVars(project(layers: []), root), isEmpty);
    });
  });

  group('askMustOverrides', () {
    Future<void> ask(MemoryDnaHost host, TextPrompt prompt) => askMustOverrides(
      host: host,
      targetRoot: root,
      prompt: prompt,
      ggLog: logged.add,
    );

    test('asks for each missing variable and writes the answers', () async {
      final host = project();
      await ask(host, fakePrompt(['Acme', 'Quick Check']));
      expect(asked, [
        (
          prompt: 'dnaCopyrightHolder (required by dna-guides)',
          defaultValue: null,
        ),
        (
          prompt: 'dnaGitQuickCheckPipelineName (required by dna-scripts)',
          defaultValue: null,
        ),
      ]);
      expect(ownVarsOf(host), {
        'dnaCopyrightHolder': 'Acme',
        'dnaGitQuickCheckPipelineName': 'Quick Check',
      });
      expect(logged.single, contains('✓ Set dnaCopyrightHolder'));
    });

    test('appends to an existing _vars.json, keeping it', () async {
      final host = project(
        ownVars: '{\n  // ours\n  "dnaCopyrightHolder": "Acme"\n}\n',
      );
      await ask(host, fakePrompt(['Quick Check']));
      expect(host.readString('$root/$dnaVarsPath'), contains('// ours'));
      expect(ownVarsOf(host), {
        'dnaCopyrightHolder': 'Acme',
        'dnaGitQuickCheckPipelineName': 'Quick Check',
      });
    });

    test('asks nothing and writes nothing when all is set', () async {
      final host = project(layers: []);
      await ask(host, fakePrompt([]));
      expect(asked, isEmpty);
      expect(host.existsFile('$root/$dnaVarsPath'), isFalse);
      expect(logged, isEmpty);
    });

    test('names the variables when it cannot ask', () async {
      final host = project();
      await ask(
        host,
        fakePrompt(
          [],
          unavailable: const SelectPromptUnavailableException('no terminal'),
        ),
      );
      expect(host.existsFile('$root/$dnaVarsPath'), isFalse);
      expect(
        logged.single,
        allOf(
          contains('dnaCopyrightHolder, dnaGitQuickCheckPipelineName'),
          contains(dnaVarsPath),
          contains('no terminal'),
        ),
      );
    });

    test('asks nothing when the project _vars.json is broken', () async {
      final host = project(ownVars: '{"dnaCopyrightHolder": "Acme",,}');
      await ask(host, fakePrompt([]));
      expect(asked, isEmpty);
      expect(
        host.readString('$root/$dnaVarsPath'),
        '{"dnaCopyrightHolder": "Acme",,}',
      );
    });

    test('names the variables when writing them fails', () async {
      // Valid JSON, but no object to add the answers to.
      final host = project(ownVars: '[]');
      await ask(host, fakePrompt(['Acme', 'Quick Check']));
      expect(host.readString('$root/$dnaVarsPath'), '[]');
      expect(
        logged.single,
        allOf(contains('! Set dnaCopyrightHolder'), contains('writing it')),
      );
    });

    test('leaves an unresolvable layer tree to the build', () async {
      final host = project(layers: ['dna-missing']);
      await ask(host, fakePrompt([]));
      expect(asked, isEmpty);
      expect(logged, isEmpty);
    });
  });
}
