// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_dna/src/util/claude_skills.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gg_dna_claude_skills_');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  void writeSkill(String root, String name, [String content = 'skill']) {
    final file = File(p.join(tmp.path, root, name, 'SKILL.md'));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  String installedContent(String name) => File(
        p.join(tmp.path, claudeSkillsRel, name, 'SKILL.md'),
      ).readAsStringSync();

  bool installedExists(String name) =>
      Directory(p.join(tmp.path, claudeSkillsRel, name)).existsSync();

  group('discoverSkills', () {
    test('lists only folders containing SKILL.md, sorted', () {
      writeSkill('src', 'beta');
      writeSkill('src', 'alpha');
      Directory(p.join(tmp.path, 'src', 'no-skill'))
          .createSync(recursive: true);
      final names = discoverSkills(Directory(p.join(tmp.path, 'src')))
          .map((d) => p.basename(d.path))
          .toList();
      expect(names, ['alpha', 'beta']);
    });
  });

  group('syncClaudeSkills', () {
    test('installs configured skills without prompting', () {
      writeSkill('dna/agents/skills', 'demo');
      final result = syncClaudeSkills(
        targetRoot: tmp.path,
        include: ['dna/agents/skills'],
        previouslyInstalled: const [],
      );
      expect(result.installed, ['demo']);
      expect(result.removed, isEmpty);
      expect(result.warnings, isEmpty);
      expect(installedContent('demo'), 'skill');
    });

    test('overwrites skills gg_dna installed before', () {
      writeSkill('dna/agents/skills', 'demo', 'new');
      writeSkill(claudeSkillsRel.replaceAll('/', p.separator), 'demo', 'old');
      final result = syncClaudeSkills(
        targetRoot: tmp.path,
        include: ['dna/agents/skills'],
        previouslyInstalled: ['demo'],
      );
      expect(result.installed, ['demo']);
      expect(installedContent('demo'), 'new');
    });

    test('never touches hand-installed skills, warns instead', () {
      writeSkill('dna/agents/skills', 'demo', 'new');
      writeSkill(claudeSkillsRel.replaceAll('/', p.separator), 'demo', 'mine');
      final result = syncClaudeSkills(
        targetRoot: tmp.path,
        include: ['dna/agents/skills'],
        previouslyInstalled: const [],
      );
      expect(result.installed, isEmpty);
      expect(result.warnings.single, contains('"demo"'));
      expect(installedContent('demo'), 'mine');
    });

    test('removes owned skills that are no longer configured', () {
      writeSkill(claudeSkillsRel.replaceAll('/', p.separator), 'gone');
      writeSkill(claudeSkillsRel.replaceAll('/', p.separator), 'mine');
      final result = syncClaudeSkills(
        targetRoot: tmp.path,
        include: const [],
        previouslyInstalled: ['gone', 'already-deleted'],
      );
      expect(result.installed, isEmpty);
      expect(result.removed, ['gone', 'already-deleted']);
      expect(installedExists('gone'), isFalse);
      // Hand-installed skills survive.
      expect(installedExists('mine'), isTrue);
    });

    test('later include folders win on name collisions', () {
      writeSkill('first', 'demo', 'first');
      writeSkill('second', 'demo', 'second');
      final result = syncClaudeSkills(
        targetRoot: tmp.path,
        include: ['first', 'second'],
        previouslyInstalled: const [],
      );
      expect(result.installed, ['demo']);
      expect(installedContent('demo'), 'second');
    });

    test('throws when an include folder does not exist', () {
      expect(
        () => syncClaudeSkills(
          targetRoot: tmp.path,
          include: ['missing'],
          previouslyInstalled: const [],
        ),
        throwsA(
          isA<Exception>().having(
            (e) => '$e',
            'message',
            contains('missing'),
          ),
        ),
      );
    });
  });
}
