// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:helix/src/util/dna_config.dart';
import 'package:helix/src/util/dna_fs.dart';
import 'package:helix/src/util/dna_layout.dart';
import 'package:test/test.dart';

void main() {
  const root = '/repo';

  /// Writes [config] to `dna/_dna.json`, injecting the format version
  /// unless the literal states one itself.
  MemoryDnaHost hostWith(String? config, {Map<String, String>? extra}) {
    final withVersion = config == null || config.contains('"version"')
        ? config
        : config.replaceFirst('{', '{"version": $dnaFormatVersion,');
    return MemoryDnaHost(
      files: {'$root/$dnaConfigPath': ?withVersion, ...?extra},
    );
  }

  group('readDnaConfig', () {
    test('missing file yields defaults', () {
      final r = readDnaConfig(hostWith(null), root);
      expect(r.config.layers, isEmpty);
      expect(r.config.vars, isEmpty);
      expect(r.config.claude.claudeMdInclude, isNull);
      expect(r.warnings, isEmpty);
    });

    test('a dna/ folder without _dna.json is an error', () {
      final host = hostWith(
        null,
        extra: {'$root/$dnaDirname/doc/develop.md': '# Develop\n'},
      );
      expect(
        () => readDnaConfig(host, root),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains(dnaConfigPath), contains('helix init')),
          ),
        ),
      );
    });

    test('parses a full config (JSONC tolerated)', () {
      final r = readDnaConfig(
        hostWith('''
{
  // the role
  "role": "dna",
  "layers": ["dna_base", "@tssuite/dna-dart"],
  "vars": {"dnaProjectName": "my_project"},
  "claude": {"claudeMdInclude": ["doc/conventions"]},
}'''),
        root,
      );
      expect(r.config.layers, ['dna_base', '@tssuite/dna-dart']);
      expect(r.config.vars, {'dnaProjectName': 'my_project'});
      expect(r.config.claude.claudeMdInclude, ['doc/conventions']);
      expect(r.warnings, hasLength(1));
      expect(r.warnings.single, contains('"role" is no longer used'));
    });

    test('requires the format version', () {
      MemoryDnaHost raw(String config) =>
          MemoryDnaHost(files: {'$root/$dnaConfigPath': config});
      expect(
        () => readDnaConfig(raw('{"role": "dna"}'), root),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('"version" is missing'),
          ),
        ),
      );
      expect(
        () => readDnaConfig(raw('{"version": 5}'), root),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('not supported'),
          ),
        ),
      );
    });

    test('names the package when a layer config is broken', () {
      expect(
        () => readDnaConfig(
          hostWith('{"layers": "x"}'),
          root,
          packageLabel: '@tssuite/dna-base',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('@tssuite/dna-base'),
          ),
        ),
      );
    });

    test('rejects invalid layers and vars', () {
      for (final config in [
        '{"layers": "x"}',
        '{"layers": ["a", "a"]}',
        '{"layers": [""]}',
        '{"layers": [1]}',
        '{"vars": "x"}',
        '[1]',
      ]) {
        expect(
          () => readDnaConfig(hostWith(config), root),
          throwsFormatException,
          reason: config,
        );
      }
    });

    test('rejects a path where a package name belongs', () {
      expect(
        () => readDnaConfig(hostWith('{"layers": ["../dna_base"]}'), root),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('looks like a path'), contains('gg_localize_refs')),
          ),
        ),
      );
    });

    test('rejects malformed claude sections', () {
      for (final config in [
        '{"claude": "x"}',
        '{"claude": {"claudeMdInclude": "x"}}',
        '{"claude": {"claudeMdInclude": [""]}}',
      ]) {
        expect(
          () => readDnaConfig(hostWith(config), root),
          throwsFormatException,
          reason: config,
        );
      }
    });

    test('claude without claudeMdInclude leaves CLAUDE.md alone', () {
      final r = readDnaConfig(hostWith('{"claude": {}}'), root);
      expect(r.config.claude.claudeMdInclude, isNull);
    });

    test('claudeMdInclude present but empty manages an empty block', () {
      final r = readDnaConfig(
        hostWith('{"claude": {"claudeMdInclude": []}}'),
        root,
      );
      expect(r.config.claude.claudeMdInclude, isEmpty);
    });

    test('warns about unknown keys, at both levels', () {
      final r = readDnaConfig(
        hostWith('{"unknown": 1, "claude": {"agents": {}}}'),
        root,
      );
      expect(r.warnings, hasLength(2));
      expect(r.warnings.first, contains('unknown key "unknown"'));
      expect(r.warnings.last, contains('claude key "agents"'));
    });

    test('the removed dependencies key is just unknown now', () {
      final r = readDnaConfig(
        hostWith('{"dependencies": {"a": {"path": "../a"}}}'),
        root,
      );
      expect(r.warnings.single, contains('unknown key "dependencies"'));
      expect(r.config.layers, isEmpty);
    });

    test('rejects vars that do not start with dna', () {
      expect(
        () => readDnaConfig(hostWith('{"vars": {"projectName": "x"}}'), root),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('dnaProjectName'),
          ),
        ),
      );
    });

    test('a legacy .gg/dna.json is simply not read', () {
      final r = readDnaConfig(
        hostWith(null, extra: {'$root/.gg/dna.json': '{"role": "dna"}'}),
        root,
      );
      expect(r.warnings, isEmpty);
    });
  });
}
