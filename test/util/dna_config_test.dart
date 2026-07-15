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
        expect(config.layers, hasLength(3));

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

        final repo = config.layers[2];
        expect(repo.name, 'dna_repo');
        expect(repo.path, 'dna/_override');
      });

      test('parses the real sample target_ts package.json', () {
        final config = DnaConfig.read(p.join(sampleRoot(), 'target_ts'));

        expect(config, isNotNull);
        expect(config!.warnings, isEmpty);
        expect(config.layers, hasLength(2));
        expect(config.layers[0].name, 'dna_project');
        expect(config.layers[0].path, '../dna_project');
        expect(config.layers[1].name, 'dna_repo');
        expect(config.layers[1].path, 'dna/_override');
      });

      test(
          'parses the real sample target_yaml dna.yaml and skips the '
          'dna-less package.json', () {
        final config = DnaConfig.read(p.join(sampleRoot(), 'target_yaml'));

        expect(config, isNotNull);
        expect(config!.layers.single.name, 'dna_repo');
        expect(config.layers.single.path, 'dna/_override');
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
            'order:\n  - a\na:\n  path: ../a\n',
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
            'dna:\n  order:\n    - a\n  a:\n    path: ../a\n',
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
            'dna:\n  order:\n    - a\n  a:\n    path: ../a\n',
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
              '  a:\n'
              '    path: ../a\n';
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
          '  company:\n'
          '    git: gg_dna_company\n',
        );
        expect(config!.layers.single.git, 'gg_dna_company');
      });

      test('empty or absent order yields zero layers plus orphan warnings', () {
        final config = DnaConfig.parse(
          'dna:\n'
          '  orphan:\n'
          '    path: ../somewhere\n',
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
          '  used:\n'
          '    path: ../used\n'
          '  unused:\n'
          '    path: ../unused\n',
        );
        expect(config!.layers, hasLength(1));
        expect(config.warnings.single, contains('"unused"'));
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
            '  a:\n'
            '    path: ../a\n',
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
            '  a: 42\n',
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
            '  a:\n'
            '    git: https://example.com/a.git\n'
            '    path: ../a\n',
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
            '  a:\n'
            '    version: ^1.0.0\n',
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
            '  a:\n'
            '    path: ../a\n'
            '    version: ^1.0.0\n',
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
            '  a:\n'
            '    git: https://example.com/a.git\n'
            '    version: not-a-version\n',
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
            '  a:\n'
            '    git: 42\n',
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
        const layer = DnaLayerConfig(name: 'repo', path: r'dna\_override');
        final resolved = resolvePathLayer(
          p.join(sampleRoot(), 'target'),
          layer,
        );
        expect(p.basename(resolved.folder.path), '_override');
        expect(p.basename(p.dirname(resolved.folder.path)), 'dna');
      });

      test('resolvePathLayer prefers the dna/ subfolder when present', () {
        final config = DnaConfig.read(p.join(sampleRoot(), 'target'))!;
        final project = config.layers[1];
        final repo = config.layers[2];

        // Repo-style layer: content root is the dna/ subfolder.
        final projectRoot = resolvePathLayer(
          p.join(sampleRoot(), 'target'),
          project,
        );
        expect(p.basename(projectRoot.folder.path), 'dna_project');
        expect(p.basename(projectRoot.content.path), 'dna');

        // Direct-content layer: content root is the folder itself.
        final repoRoot = resolvePathLayer(
          p.join(sampleRoot(), 'target'),
          repo,
        );
        expect(p.basename(repoRoot.folder.path), '_override');
        expect(repoRoot.content.path, repoRoot.folder.path);
      });

      test('parseJson reads a package.json dna block', () {
        final config = DnaConfig.parseJson(
          '{"name": "x", "dna": {"order": ["a"], "a": {"path": "../a"}}}',
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
            '{"dna": {"order": ["a"], "a": {"path": "../a", '
            '"version": "^1.0.0"}}}',
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
          '  a:\n'
          '    git: https://example.com/a.git\n'
          '    version: 1.4.0\n',
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
  });
}
