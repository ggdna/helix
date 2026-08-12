// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_dna/src/util/dna_layout.dart';
import 'package:test/test.dart';

void main() {
  group('isPrivatePath', () {
    test('any segment starting with _ is private', () {
      expect(isPrivatePath('_vars.json'), isTrue);
      expect(isPrivatePath('_internal/notes.md'), isTrue);
      expect(isPrivatePath('doc/_drafts/x.md'), isTrue);
      expect(isPrivatePath('doc/develop.md'), isFalse);
      expect(isPrivatePath('.vscode/settings.json'), isFalse);
    });
  });

  group('decodeDotSegments', () {
    test('every dot- segment becomes a leading dot', () {
      expect(
        decodeDotSegments('dot-vscode/settings.json'),
        '.vscode/settings.json',
      );
      expect(
        decodeDotSegments('dot-claude/skills/init/SKILL.md'),
        '.claude/skills/init/SKILL.md',
      );
      expect(decodeDotSegments('dot-prettierrc'), '.prettierrc');
      expect(decodeDotSegments('doc/dot-hidden.md'), 'doc/.hidden.md');
    });

    test('dot_ is not decoded — checkDotEscapes rejects it instead', () {
      expect(
        decodeDotSegments('dot_vscode/settings.json'),
        'dot_vscode/settings.json',
      );
      expect(decodeDotSegments('doc/dot_hidden.md'), 'doc/dot_hidden.md');
    });

    test('leaves everything else alone', () {
      expect(decodeDotSegments('doc/develop.md'), 'doc/develop.md');
      // Not a segment prefix — only a leading `dot-` escapes.
      expect(decodeDotSegments('doc/my-dot-file.md'), 'doc/my-dot-file.md');
      expect(decodeDotSegments('doc/my_dot_file.md'), 'doc/my_dot_file.md');
      expect(
        decodeDotSegments('.vscode/settings.json'),
        '.vscode/settings.json',
      );
    });
  });

  group('invalidDotSegment', () {
    test('reports the offending segment', () {
      expect(invalidDotSegment('dot_vscode/settings.json'), 'dot_vscode');
      expect(invalidDotSegment('doc/dot_hidden.md'), 'dot_hidden.md');
    });

    test('null for dot- and everything else', () {
      expect(invalidDotSegment('dot-vscode/settings.json'), isNull);
      expect(invalidDotSegment('doc/my_dot_file.md'), isNull);
      expect(invalidDotSegment('_vars.json'), isNull);
    });
  });

  group('isForbiddenInstanceTarget', () {
    test('git internals and CLAUDE.md are forbidden', () {
      expect(isForbiddenInstanceTarget('.git'), isTrue);
      expect(isForbiddenInstanceTarget('.git/config'), isTrue);
      expect(isForbiddenInstanceTarget('CLAUDE.md'), isTrue);
      expect(isForbiddenInstanceTarget('.claude/skills/x/SKILL.md'), isFalse);
      expect(isForbiddenInstanceTarget('doc/claude.md'), isFalse);
    });
  });

  group('ancestorDirs', () {
    test('lists every ancestor, deepest first', () {
      expect(ancestorDirs(['doc/guides/a.md']), [
        'doc/guides',
        'doc',
      ]);
    });

    test('deduplicates; deepest first, alphabetical within a depth', () {
      expect(
        ancestorDirs(['doc/a.md', 'doc/guides/b.md', 'x/y/z/c.md']),
        ['x/y/z', 'doc/guides', 'x/y', 'doc', 'x'],
      );
    });

    test('root-level files have no ancestors', () {
      expect(ancestorDirs(['LICENSE']), isEmpty);
      expect(ancestorDirs(const []), isEmpty);
    });
  });
}
