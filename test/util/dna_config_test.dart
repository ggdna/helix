// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_dna/src/util/dna_config.dart';
import 'package:gg_dna/src/util/dna_fs.dart';
import 'package:gg_dna/src/util/dna_layout.dart';
import 'package:test/test.dart';

void main() {
  const root = '/repo';

  MemoryDnaHost hostWith(String? config, {Map<String, String>? extra}) =>
      MemoryDnaHost(
        files: {
          if (config != null) '$root/.gg/dna.json': config,
          ...?extra,
        },
      );

  group('readDnaConfig', () {
    test('missing file yields defaults', () {
      final r = readDnaConfig(hostWith(null), root);
      expect(r.config.role, DnaRole.project);
      expect(r.config.order, isNull);
      expect(r.config.pathOverrides, isEmpty);
      expect(r.config.vars, isEmpty);
      expect(r.config.fileNaming, isNull);
      expect(r.config.claude.claudeMdInclude, isNull);
      expect(r.warnings, isEmpty);
    });

    test('parses a full config (JSONC tolerated)', () {
      final r = readDnaConfig(
        hostWith('''
{
  // the role
  "role": "dna",
  "order": ["base-dna", "dna-dart"],
  "dependencies": {
    "base-dna": {"path": "../base-dna"}
  },
  "vars": {"projectName": "my_project"},
  "fileNaming": "snake_case",
  "config": {"claude": {"claude_md": {"include": ["doc/conventions"]}}},
}'''),
        root,
      );
      expect(r.config.role, DnaRole.dna);
      expect(r.config.order, ['base-dna', 'dna-dart']);
      expect(r.config.pathOverrides, {'base-dna': '../base-dna'});
      expect(r.config.vars, {'projectName': 'my_project'});
      expect(r.config.fileNaming, FileNaming.snakeCase);
      expect(r.config.claude.claudeMdInclude, ['doc/conventions']);
      expect(r.warnings, isEmpty);
    });

    test('rejects invalid role, order and fileNaming', () {
      expect(
        () => readDnaConfig(hostWith('{"role": "x"}'), root),
        throwsFormatException,
      );
      expect(
        () => readDnaConfig(hostWith('{"order": "x"}'), root),
        throwsFormatException,
      );
      expect(
        () => readDnaConfig(hostWith('{"order": ["a", "a"]}'), root),
        throwsFormatException,
      );
      expect(
        () => readDnaConfig(hostWith('{"order": [""]}'), root),
        throwsFormatException,
      );
      expect(
        () => readDnaConfig(hostWith('{"fileNaming": "Pascal"}'), root),
        throwsFormatException,
      );
    });

    test('rejects git and version in dependencies with migration hints', () {
      expect(
        () => readDnaConfig(
          hostWith('{"dependencies": {"a": {"git": "url"}}}'),
          root,
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('dev-dependency'),
          ),
        ),
      );
      expect(
        () => readDnaConfig(
          hostWith('{"dependencies": {"a": {"path": "x", "version": "1"}}}'),
          root,
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('package.json/pubspec.yaml'),
          ),
        ),
      );
    });

    test('rejects malformed dependency entries', () {
      expect(
        () => readDnaConfig(hostWith('{"dependencies": "x"}'), root),
        throwsFormatException,
      );
      expect(
        () => readDnaConfig(hostWith('{"dependencies": {"a": "x"}}'), root),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('must be a map'),
          ),
        ),
      );
      expect(
        () => readDnaConfig(hostWith('{"dependencies": {"a": {}}}'), root),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('non-empty path'),
          ),
        ),
      );
      expect(
        () => readDnaConfig(
          hostWith('{"dependencies": {"a": {"path": "  "}}}'),
          root,
        ),
        throwsFormatException,
      );
    });

    test('warns about unknown keys inside config.claude', () {
      final r = readDnaConfig(
        hostWith('{"config": {"claude": {"agents": {}}}}'),
        root,
      );
      expect(r.warnings.single, contains('config.claude key "agents"'));
    });

    test('rejects malformed config sections', () {
      for (final config in [
        '{"config": "x"}',
        '{"config": {"claude": "x"}}',
        '{"config": {"claude": {"claude_md": "x"}}}',
        '{"config": {"claude": {"claude_md": {"include": "x"}}}}',
        '{"config": {"claude": {"claude_md": {"include": [""]}}}}',
        '{"vars": "x"}',
        '{"fileNaming": 1}',
        '[1]',
      ]) {
        expect(
          () => readDnaConfig(hostWith(config), root),
          throwsFormatException,
          reason: config,
        );
      }
    });

    test('config.claude without claude_md yields no includes', () {
      final r = readDnaConfig(hostWith('{"config": {"claude": {}}}'), root);
      expect(r.config.claude.claudeMdInclude, isNull);
    });

    test('normalizes backslashes in path overrides', () {
      final r = readDnaConfig(
        hostWith(r'{"dependencies": {"a": {"path": "..\\a"}}}'),
        root,
      );
      expect(r.config.pathOverrides['a'], '../a');
    });

    test('rejects config.claude.skills with migration hint', () {
      expect(
        () => readDnaConfig(
          hostWith('{"config": {"claude": {"skills": {}}}}'),
          root,
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('dna/.claude/skills'),
          ),
        ),
      );
    });

    test('include present without entries yields empty list', () {
      final r = readDnaConfig(
        hostWith('{"config": {"claude": {"claude_md": {"include": []}}}}'),
        root,
      );
      expect(r.config.claude.claudeMdInclude, isEmpty);
    });

    test('warns on unknown keys', () {
      final r = readDnaConfig(
        hostWith('{"unknown": 1, "config": {"other": {}}}'),
        root,
      );
      expect(r.warnings, hasLength(2));
      expect(r.warnings.first, contains('unknown'));
    });

    test('validates vars with warnings', () {
      final r = readDnaConfig(
        hostWith('{"vars": {"Bad_Key": "x", "ok": "y"}}'),
        root,
      );
      expect(r.config.vars, {'ok': 'y'});
      expect(r.warnings.single, contains('Bad_Key'));
    });
  });

  group('legacy config sources', () {
    test('dna.yaml existence is a migration error', () {
      expect(
        () => readDnaConfig(
          hostWith(null, extra: {'$root/dna.yaml': 'dna:\n  order: []'}),
          root,
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('.gg/dna.json'),
          ),
        ),
      );
    });

    test('dna: block in pubspec.yaml is a migration error', () {
      expect(
        () => readDnaConfig(
          hostWith(
            null,
            extra: {'$root/pubspec.yaml': 'name: x\ndna:\n  order: []'},
          ),
          root,
        ),
        throwsFormatException,
      );
    });

    test('pubspec.yaml without dna block is fine, broken yaml ignored', () {
      final ok = readDnaConfig(
        hostWith(null, extra: {'$root/pubspec.yaml': 'name: x'}),
        root,
      );
      expect(ok.config.role, DnaRole.project);
      final broken = readDnaConfig(
        hostWith(null, extra: {'$root/pubspec.yaml': ': : :'}),
        root,
      );
      expect(broken.config.role, DnaRole.project);
    });

    test('"dna" object in package.json is a migration error', () {
      expect(
        () => readDnaConfig(
          hostWith(
            null,
            extra: {'$root/package.json': '{"dna": {"order": []}}'},
          ),
          root,
        ),
        throwsFormatException,
      );
    });

    test('non-map "dna" field in package.json is foreign and ignored', () {
      final r = readDnaConfig(
        hostWith(null, extra: {'$root/package.json': '{"dna": "other"}'}),
        root,
      );
      expect(r.config.role, DnaRole.project);
    });

    test('broken package.json is ignored', () {
      final r = readDnaConfig(
        hostWith(null, extra: {'$root/package.json': '{broken'}),
        root,
      );
      expect(r.config.role, DnaRole.project);
    });
  });
}
