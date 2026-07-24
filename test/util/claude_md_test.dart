// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_dna/src/util/claude_md.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gg_dna_claude_md_');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  void write(String rel, [String content = 'x']) {
    final file = File(p.join(tmp.path, rel));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  group('expandClaudeMdIncludes', () {
    test('keeps files and expands folders to sorted .md files', () {
      write('project_structure.md');
      write('dna/agents/conventions/b-convention.md');
      write('dna/agents/conventions/a-convention.md');
      write('dna/agents/conventions/nested/deep.md');
      write('dna/agents/conventions/not-markdown.txt');

      final imports = expandClaudeMdIncludes(
        tmp.path,
        ['dna/agents/conventions', 'project_structure.md'],
      );
      expect(imports, [
        'dna/agents/conventions/a-convention.md',
        'dna/agents/conventions/b-convention.md',
        'dna/agents/conventions/nested/deep.md',
        'project_structure.md',
      ]);
    });

    test('normalizes backslash include paths', () {
      write('dna/agents/conventions/a.md');
      final imports = expandClaudeMdIncludes(
        tmp.path,
        [r'dna\agents\conventions'],
      );
      expect(imports, ['dna/agents/conventions/a.md']);
    });

    test('throws when an include does not exist', () {
      expect(
        () => expandClaudeMdIncludes(tmp.path, ['missing.md']),
        throwsA(
          isA<Exception>().having(
            (e) => '$e',
            'message',
            contains('missing.md'),
          ),
        ),
      );
    });
  });

  group('buildClaudeMdBlock', () {
    test('wraps one @-import line per path in the markers', () {
      expect(
        buildClaudeMdBlock(['a.md', 'dir/b.md']),
        '$claudeMdStartMarker\n'
        '@a.md\n'
        '@dir/b.md\n'
        '$claudeMdEndMarker',
      );
    });

    test('an empty include list yields an empty block', () {
      expect(
        buildClaudeMdBlock(const []),
        '$claudeMdStartMarker\n$claudeMdEndMarker',
      );
    });
  });

  group('upsertClaudeMdBlock', () {
    const block = '$claudeMdStartMarker\n@a.md\n$claudeMdEndMarker';

    test('appends to empty and non-empty content', () {
      expect(upsertClaudeMdBlock('', block), '$block\n');
      expect(
        upsertClaudeMdBlock('# Title\n\nText.\n', block),
        '# Title\n\nText.\n\n$block\n',
      );
    });

    test('replaces an existing block and keeps surrounding text', () {
      final old = buildClaudeMdBlock(['old.md']);
      final content = '# Title\n\n$old\n\nFooter.\n';
      expect(
        upsertClaudeMdBlock(content, block),
        '# Title\n\n$block\n\nFooter.\n',
      );
    });

    test('removes a leftover pre-3.0 conventions block', () {
      const legacy = '$legacyConventionsStartMarker v=2026-01-01 -->\n'
          '@.claude/conventions/code-conventions.md\n'
          '$legacyConventionsEndMarker\n';
      const content = '# Title\n\n$legacy\nBody.\n';
      final result = upsertClaudeMdBlock(content, block);
      expect(result, isNot(contains('gg_dna:conventions')));
      expect(result, contains('Body.'));
      expect(result, contains(block));
    });

    test('keeps an unterminated legacy block untouched', () {
      const broken = '# T\n\n$legacyConventionsStartMarker v=x -->\n@a.md\n';
      expect(upsertClaudeMdBlock(broken, block), contains('conventions'));
    });

    test('throws on a start marker without end marker', () {
      expect(
        () => upsertClaudeMdBlock('$claudeMdStartMarker\n@a.md\n', block),
        throwsStateError,
      );
    });
  });

  group('writeClaudeMd', () {
    test('creates CLAUDE.md when missing', () {
      expect(writeClaudeMd(tmp.path, ['a.md']), isTrue);
      final content = File(p.join(tmp.path, 'CLAUDE.md')).readAsStringSync();
      expect(content, '${buildClaudeMdBlock(['a.md'])}\n');
    });

    test('is idempotent', () {
      expect(writeClaudeMd(tmp.path, ['a.md']), isTrue);
      expect(writeClaudeMd(tmp.path, ['a.md']), isFalse);
    });

    test('updates only the managed block of an existing file', () {
      write('CLAUDE.md', '# Mine\n\nKeep me.\n');
      expect(writeClaudeMd(tmp.path, ['a.md']), isTrue);
      final content = File(p.join(tmp.path, 'CLAUDE.md')).readAsStringSync();
      expect(content, startsWith('# Mine\n\nKeep me.\n'));
      expect(content, contains('@a.md'));

      expect(writeClaudeMd(tmp.path, ['b.md']), isTrue);
      final updated = File(p.join(tmp.path, 'CLAUDE.md')).readAsStringSync();
      expect(updated, startsWith('# Mine\n\nKeep me.\n'));
      expect(updated, contains('@b.md'));
      expect(updated, isNot(contains('@a.md')));
    });
  });
}
