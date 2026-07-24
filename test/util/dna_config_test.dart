// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_dna/src/util/dna_config.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

import '../helpers/sample_folder.dart';

void main() {
  group('DnaConfig', () {
    group('read', () {
      test('parses the real sample target pubspec.yaml', () {
        final config = DnaConfig.read(p.join(sampleRoot(), 'target'));

        expect(config, isNotNull);
        expect(config!.warnings, isEmpty);
        expect(config.layers, hasLength(2));

        final company = config.layers[0];
        expect(company.name, 'dna_company');
        expect(company.isGit, isTrue);
        expect(company.git, 'https://github.com/acme/dna_company.git');
        expect(company.path, isNull);
        expect(company.rawVersionConstraint, '^1.4.0');
        expect(
          company.versionConstraint!.allows(Version.parse('1.5.0')),
          isTrue,
        );
        expect(
          company.versionConstraint!.allows(Version.parse('2.0.0')),
          isFalse,
        );

        final project = config.layers[1];
        expect(project.name, 'dna_project');
        expect(project.isGit, isFalse);
        expect(project.path, '../dna_project');
        expect(project.versionConstraint, isNull);
      });

      test('parses the real sample target_ts package.json', () {
        final config = DnaConfig.read(p.join(sampleRoot(), 'target_ts'));

        expect(config, isNotNull);
        expect(config!.warnings, isEmpty);
        expect(config.layers.single.name, 'dna_project');
        expect(config.layers.single.path, '../dna_project');
      });

      test(
          'parses the real sample target_yaml dna.yaml and skips the '
          'dna-less package.json', () {
        final config = DnaConfig.read(p.join(sampleRoot(), 'target_yaml'));

        expect(config, isNotNull);
        expect(config!.layers, isEmpty);
        expect(config.warnings, isEmpty);
      });

      test('returns null when no config file exists', () {
        final tmp = Directory.systemTemp.createTempSync('dna_config_test_');
        try {
          expect(DnaConfig.read(tmp.path), isNull);
        } finally {
          tmp.deleteSync(recursive: true);
        }
      });

      test('returns null when pubspec.yaml has no dna key', () {
        final tmp = Directory.systemTemp.createTempSync('dna_config_test_');
        try {
          File(p.join(tmp.path, 'pubspec.yaml'))
              .writeAsStringSync('name: foo\nversion: 1.0.0\n');
          expect(DnaConfig.read(tmp.path), isNull);
        } finally {
          tmp.deleteSync(recursive: true);
        }
      });

      test('throws when dna.yaml exists without a dna: block', () {
        final tmp = Directory.systemTemp.createTempSync('dna_config_test_');
        try {
          File(p.join(tmp.path, 'dna.yaml')).writeAsStringSync(
            'order:\n  - a\ndependencies:\n  a:\n    path: ../a\n',
          );
          expect(
            () => DnaConfig.read(tmp.path),
            throwsA(
              isA<FormatException>().having(
                (e) => e.message,
                'message',
                contains('no top-level `dna:` block'),
              ),
            ),
          );
        } finally {
          tmp.deleteSync(recursive: true);
        }
      });

      test('ignores a foreign non-map dna field in package.json', () {
        final tmp = Directory.systemTemp.createTempSync('dna_config_test_');
        try {
          File(p.join(tmp.path, 'package.json'))
              .writeAsStringSync('{"name": "x", "dna": "some-npm-thing"}');
          expect(DnaConfig.read(tmp.path), isNull);

          // It also does not conflict with the real config source.
          File(p.join(tmp.path, 'dna.yaml')).writeAsStringSync(
            'dna:\n'
            '  order:\n'
            '    - a\n'
            '  dependencies:\n'
            '    a:\n'
            '      path: ../a\n',
          );
          final config = DnaConfig.read(tmp.path);
          expect(config!.layers.single.name, 'a');
          expect(config.warnings, isEmpty);
        } finally {
          tmp.deleteSync(recursive: true);
        }
      });

      test('defers undecodable files when another file has the config', () {
        final tmp = Directory.systemTemp.createTempSync('dna_config_test_');
        try {
          File(p.join(tmp.path, 'package.json')).writeAsStringSync('{broken,}');
          File(p.join(tmp.path, 'dna.yaml')).writeAsStringSync(
            'dna:\n'
            '  order:\n'
            '    - a\n'
            '  dependencies:\n'
            '    a:\n'
            '      path: ../a\n',
          );
          final config = DnaConfig.read(tmp.path);
          expect(config!.layers.single.name, 'a');
          expect(
            config.warnings.single,
            allOf(contains('not valid JSON'), contains('ignored')),
          );
        } finally {
          tmp.deleteSync(recursive: true);
        }
      });

      test('throws for undecodable files when no config is found', () {
        final tmp = Directory.systemTemp.createTempSync('dna_config_test_');
        try {
          File(p.join(tmp.path, 'package.json')).writeAsStringSync('{broken,}');
          expect(
            () => DnaConfig.read(tmp.path),
            throwsA(
              isA<FormatException>().having(
                (e) => e.message,
                'message',
                contains('not valid JSON'),
              ),
            ),
          );
        } finally {
          tmp.deleteSync(recursive: true);
        }
      });

      test('throws when more than one file configures dna', () {
        final tmp = Directory.systemTemp.createTempSync('dna_config_test_');
        try {
          const block = 'dna:\n'
              '  order:\n'
              '    - a\n'
              '  dependencies:\n'
              '    a:\n'
              '      path: ../a\n';
          File(p.join(tmp.path, 'dna.yaml')).writeAsStringSync(block);
          File(p.join(tmp.path, 'pubspec.yaml'))
              .writeAsStringSync('name: foo\n$block');
          expect(
            () => DnaConfig.read(tmp.path),
            throwsA(
              isA<FormatException>().having(
                (e) => e.message,
                'message',
                allOf(
                  contains('more than one file'),
                  contains('dna.yaml'),
                  contains('pubspec.yaml'),
                ),
              ),
            ),
          );
        } finally {
          tmp.deleteSync(recursive: true);
        }
      });

      test('keeps the claude config when merging broken-file warnings', () {
        final tmp = Directory.systemTemp.createTempSync('dna_config_test_');
        try {
          File(p.join(tmp.path, 'package.json')).writeAsStringSync('{broken,}');
          File(p.join(tmp.path, 'dna.yaml')).writeAsStringSync(
            'dna:\n'
            '  order: []\n'
            '  config:\n'
            '    claude:\n'
            '      claude_md:\n'
            '        include:\n'
            '          - project_structure.md\n',
          );
          final config = DnaConfig.read(tmp.path);
          expect(
            config!.claude!.claudeMdInclude,
            ['project_structure.md'],
          );
          expect(config.warnings.single, contains('not valid JSON'));
        } finally {
          tmp.deleteSync(recursive: true);
        }
      });
    });

    group('parse', () {
      test('returns null for non-map or dna-less documents', () {
        expect(DnaConfig.parse(''), isNull);
        expect(DnaConfig.parse('just a string'), isNull);
        expect(DnaConfig.parse('name: foo\n'), isNull);
      });

      test('keeps gg_* shorthands raw', () {
        final config = DnaConfig.parse(
          'dna:\n'
          '  order:\n'
          '    - company\n'
          '  dependencies:\n'
          '    company:\n'
          '      git: gg_dna_company\n',
        );
        expect(config!.layers.single.git, 'gg_dna_company');
      });

      test('empty or absent order yields zero layers plus orphan warnings', () {
        final config = DnaConfig.parse(
          'dna:\n'
          '  dependencies:\n'
          '    orphan:\n'
          '      path: ../somewhere\n',
        );
        expect(config!.layers, isEmpty);
        expect(config.warnings, hasLength(1));
        expect(config.warnings.single, contains('orphan'));
        expect(config.warnings.single, contains('ignored'));

        final empty = DnaConfig.parse('dna:\n  order: []\n');
        expect(empty!.layers, isEmpty);
        expect(empty.warnings, isEmpty);
      });

      test('warns about configured layers missing from order', () {
        final config = DnaConfig.parse(
          'dna:\n'
          '  order:\n'
          '    - used\n'
          '  dependencies:\n'
          '    used:\n'
          '      path: ../used\n'
          '    unused:\n'
          '      path: ../unused\n',
        );
        expect(config!.layers, hasLength(1));
        expect(config.warnings.single, contains('"unused"'));
      });

      test('throws with a migration hint on pre-3.0 layer syntax', () {
        expect(
          () => DnaConfig.parse(
            'dna:\n'
            '  order:\n'
            '    - a\n'
            '  a:\n'
            '    path: ../a\n',
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('pre-3.0'),
                contains('dependencies'),
              ),
            ),
          ),
        );
      });

      test('warns about unknown keys under dna:', () {
        final config = DnaConfig.parse(
          'dna:\n'
          '  order: []\n'
          '  something: else\n',
        );
        expect(config!.warnings.single, contains('"something"'));
      });

      test('throws when dependencies is not a map', () {
        expect(
          () => DnaConfig.parse('dna:\n  dependencies: 42\n'),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('`dna: dependencies:`'),
            ),
          ),
        );
      });

      test('throws when dna is not a map', () {
        expect(
          () => DnaConfig.parse('dna: 42\n'),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('must be a map'),
            ),
          ),
        );
      });

      test('throws when order is not a list of non-empty strings', () {
        expect(
          () => DnaConfig.parse('dna:\n  order: 42\n'),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => DnaConfig.parse('dna:\n  order:\n    - 42\n'),
          throwsA(isA<FormatException>()),
        );
      });

      test('throws on duplicate names in order', () {
        expect(
          () => DnaConfig.parse(
            'dna:\n'
            '  order:\n'
            '    - a\n'
            '    - a\n'
            '  dependencies:\n'
            '    a:\n'
            '      path: ../a\n',
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('twice'),
            ),
          ),
        );
      });

      test('throws when an ordered layer has no configuration map', () {
        expect(
          () => DnaConfig.parse('dna:\n  order:\n    - missing\n'),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('no configuration map'),
            ),
          ),
        );
      });

      test('throws when a layer config is not a map', () {
        expect(
          () => DnaConfig.parse(
            'dna:\n'
            '  order:\n'
            '    - a\n'
            '  dependencies:\n'
            '    a: 42\n',
          ),
          throwsA(isA<FormatException>()),
        );
      });

      test('throws when a layer has both git and path or neither', () {
        expect(
          () => DnaConfig.parse(
            'dna:\n'
            '  order:\n'
            '    - a\n'
            '  dependencies:\n'
            '    a:\n'
            '      git: https://example.com/a.git\n'
            '      path: ../a\n',
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('exactly one'),
            ),
          ),
        );
        expect(
          () => DnaConfig.parse(
            'dna:\n'
            '  order:\n'
            '    - a\n'
            '  dependencies:\n'
            '    a:\n'
            '      version: ^1.0.0\n',
          ),
          throwsA(isA<FormatException>()),
        );
      });

      test('throws when version is combined with path', () {
        expect(
          () => DnaConfig.parse(
            'dna:\n'
            '  order:\n'
            '    - a\n'
            '  dependencies:\n'
            '    a:\n'
            '      path: ../a\n'
            '      version: ^1.0.0\n',
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('only apply to git layers'),
            ),
          ),
        );
      });

      test('throws on an unparsable version constraint', () {
        expect(
          () => DnaConfig.parse(
            'dna:\n'
            '  order:\n'
            '    - a\n'
            '  dependencies:\n'
            '    a:\n'
            '      git: https://example.com/a.git\n'
            '      version: not-a-version\n',
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('invalid `version:` constraint'),
            ),
          ),
        );
      });

      test('throws on invalid git or path values', () {
        expect(
          () => DnaConfig.parse(
            'dna:\n'
            '  order:\n'
            '    - a\n'
            '  dependencies:\n'
            '    a:\n'
            '      git: 42\n',
          ),
          throwsA(isA<FormatException>()),
        );
      });

      test('throws on invalid YAML', () {
        expect(
          () => DnaConfig.parse('dna: [unclosed\n'),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('not valid YAML'),
            ),
          ),
        );
      });

      test('names the source file in error messages', () {
        expect(
          () => DnaConfig.parse('dna: 42\n', source: 'dna.yaml'),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('dna.yaml'),
            ),
          ),
        );
      });

      test('resolvePathLayer normalizes backslash paths', () {
        const layer = DnaLayerConfig(name: 'project', path: r'..\dna_project');
        final resolved = resolvePathLayer(
          p.join(sampleRoot(), 'target'),
          layer,
        );
        expect(p.basename(resolved.folder.path), 'dna_project');
      });

      test('resolvePathLayer content is always <path>/dna/src', () {
        final config = DnaConfig.read(p.join(sampleRoot(), 'target'))!;
        final project = config.layers[1];

        final projectRoot = resolvePathLayer(
          p.join(sampleRoot(), 'target'),
          project,
        );
        expect(p.basename(projectRoot.folder.path), 'dna_project');
        expect(
          projectRoot.content.path,
          p.join(projectRoot.folder.path, 'dna', 'src'),
        );
      });

      test('rejects a layer named src — dna/src is implicit', () {
        expect(
          () => DnaConfig.parse(
            'dna:\n'
            '  order:\n'
            '    - src\n'
            '  dependencies:\n'
            '    src:\n'
            '      path: ../src\n',
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('applied automatically'),
            ),
          ),
        );
      });

      test('parseJson reads a package.json dna block', () {
        final config = DnaConfig.parseJson(
          '{"name": "x", "dna": {"order": ["a"], '
          '"dependencies": {"a": {"path": "../a"}}}}',
        );
        expect(config!.layers.single.name, 'a');
        expect(config.layers.single.path, '../a');
      });

      test('parseJson returns null without dna key or non-map doc', () {
        expect(DnaConfig.parseJson('{"name": "x"}'), isNull);
        expect(DnaConfig.parseJson('[1, 2]'), isNull);
      });

      test('parseJson throws on a non-map dna value unless told to ignore', () {
        expect(
          () => DnaConfig.parseJson('{"dna": "x"}'),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('must be a map'),
            ),
          ),
        );
        expect(
          DnaConfig.parseJson('{"dna": "x"}', ignoreNonMapDna: true),
          isNull,
        );
      });

      test('parseJson throws on invalid JSON with the source name', () {
        expect(
          () => DnaConfig.parseJson('{broken'),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              allOf(contains('package.json'), contains('not valid JSON')),
            ),
          ),
        );
      });

      test('parseJson validates with the same rules as parse', () {
        expect(
          () => DnaConfig.parseJson(
            '{"dna": {"order": ["a"], "dependencies": '
            '{"a": {"path": "../a", "version": "^1.0.0"}}}}',
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('only apply to git layers'),
                contains('package.json'),
              ),
            ),
          ),
        );
      });

      test('accepts an exact version constraint', () {
        final config = DnaConfig.parse(
          'dna:\n'
          '  order:\n'
          '    - a\n'
          '  dependencies:\n'
          '    a:\n'
          '      git: https://example.com/a.git\n'
          '      version: 1.4.0\n',
        );
        final layer = config!.layers.single;
        expect(layer.rawVersionConstraint, '1.4.0');
        expect(
          layer.versionConstraint!.allows(Version.parse('1.4.0')),
          isTrue,
        );
        expect(
          layer.versionConstraint!.allows(Version.parse('1.4.1')),
          isFalse,
        );
      });
    });

    group('config: claude:', () {
      test('parses claude_md and skills include lists', () {
        final config = DnaConfig.parse(
          'dna:\n'
          '  order: []\n'
          '  config:\n'
          '    claude:\n'
          '      claude_md:\n'
          '        include:\n'
          '          - dna/agents/conventions\n'
          '          - project_structure.md\n'
          '      skills:\n'
          '        include:\n'
          '          - dna/agents/skills\n',
        );
        expect(config!.warnings, isEmpty);
        expect(
          config.claude!.claudeMdInclude,
          ['dna/agents/conventions', 'project_structure.md'],
        );
        expect(config.claude!.skillsInclude, ['dna/agents/skills']);
      });

      test('parses the same structure from package.json', () {
        final config = DnaConfig.parseJson(
          '{"dna": {"order": [], "config": {"claude": '
          '{"claude_md": {"include": ["a.md"]}, '
          '"skills": {"include": ["skills"]}}}}}',
        );
        expect(config!.claude!.claudeMdInclude, ['a.md']);
        expect(config.claude!.skillsInclude, ['skills']);
      });

      test('claude is null when config or claude section is absent', () {
        expect(DnaConfig.parse('dna:\n  order: []\n')!.claude, isNull);
        expect(
          DnaConfig.parse('dna:\n  order: []\n  config: {}\n')!.claude,
          isNull,
        );
      });

      test('absent subsections yield null include lists', () {
        final config = DnaConfig.parse(
          'dna:\n'
          '  order: []\n'
          '  config:\n'
          '    claude:\n'
          '      claude_md:\n'
          '        include:\n'
          '          - a.md\n',
        );
        expect(config!.claude!.claudeMdInclude, ['a.md']);
        expect(config.claude!.skillsInclude, isNull);
      });

      test('a subsection without include yields an empty list', () {
        final config = DnaConfig.parse(
          'dna:\n'
          '  order: []\n'
          '  config:\n'
          '    claude:\n'
          '      skills: {}\n',
        );
        expect(config!.claude!.skillsInclude, isEmpty);
        expect(config.claude!.claudeMdInclude, isNull);
      });

      test('warns about unknown keys under config and claude', () {
        final config = DnaConfig.parse(
          'dna:\n'
          '  order: []\n'
          '  config:\n'
          '    other_tool: {}\n'
          '    claude:\n'
          '      unknown: {}\n',
        );
        expect(config!.warnings, hasLength(2));
        expect(config.warnings[0], contains('other_tool'));
        expect(config.warnings[1], contains('unknown'));
      });

      test('throws when config, claude, or a subsection is not a map', () {
        expect(
          () => DnaConfig.parse('dna:\n  config: 42\n'),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => DnaConfig.parse('dna:\n  config:\n    claude: 42\n'),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => DnaConfig.parse(
            'dna:\n  config:\n    claude:\n      claude_md: 42\n',
          ),
          throwsA(isA<FormatException>()),
        );
      });

      test('throws when include is not a list of non-empty strings', () {
        expect(
          () => DnaConfig.parse(
            'dna:\n'
            '  config:\n'
            '    claude:\n'
            '      skills:\n'
            '        include: 42\n',
          ),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => DnaConfig.parse(
            'dna:\n'
            '  config:\n'
            '    claude:\n'
            '      skills:\n'
            '        include:\n'
            '          - 42\n',
          ),
          throwsA(isA<FormatException>()),
        );
      });
    });
  });
}
