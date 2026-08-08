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

    test('leaves everything else alone', () {
      expect(decodeDotSegments('doc/develop.md'), 'doc/develop.md');
      // Not a segment prefix — only a leading `dot-` escapes.
      expect(decodeDotSegments('doc/my-dot-file.md'), 'doc/my-dot-file.md');
      expect(
        decodeDotSegments('.vscode/settings.json'),
        '.vscode/settings.json',
      );
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

  group('parseFileNaming', () {
    test('parses valid values, null passes through', () {
      expect(parseFileNaming('snake_case'), FileNaming.snakeCase);
      expect(parseFileNaming('camelCase'), FileNaming.camelCase);
      expect(parseFileNaming('kebab-case'), FileNaming.kebabCase);
      expect(parseFileNaming('keep'), FileNaming.keep);
      expect(parseFileNaming(null), isNull);
    });

    test('throws on unknown values', () {
      expect(() => parseFileNaming('PascalCase'), throwsFormatException);
    });
  });

  group('convertSegmentNaming', () {
    test('converts the part before the first dot', () {
      expect(
        convertSegmentNaming('dna-test.dart', FileNaming.snakeCase),
        'dna_test.dart',
      );
      expect(
        convertSegmentNaming('create-branch.js', FileNaming.camelCase),
        'createBranch.js',
      );
      expect(
        convertSegmentNaming('create_branch.js', FileNaming.kebabCase),
        'create-branch.js',
      );
    });

    test('keeps multi-dot extensions intact', () {
      expect(
        convertSegmentNaming('dna.spec.ts', FileNaming.camelCase),
        'dna.spec.ts',
      );
      expect(
        convertSegmentNaming('my-comp.spec.ts', FileNaming.camelCase),
        'myComp.spec.ts',
      );
      expect(
        convertSegmentNaming('typescript.code-snippets', FileNaming.snakeCase),
        'typescript.code-snippets',
      );
    });

    test('names with uppercase letters and dotfiles stay untouched', () {
      expect(
        convertSegmentNaming('LICENSE', FileNaming.snakeCase),
        'LICENSE',
      );
      expect(
        convertSegmentNaming('README.md', FileNaming.camelCase),
        'README.md',
      );
      expect(
        convertSegmentNaming('.gitattributes', FileNaming.snakeCase),
        '.gitattributes',
      );
    });

    test('keep returns the segment unchanged', () {
      expect(convertSegmentNaming('a-b.md', FileNaming.keep), 'a-b.md');
      expect(
        convertSegmentNaming('create_branch.js', FileNaming.keep),
        'create_branch.js',
      );
    });

    test('single-word names stay untouched', () {
      expect(
        convertSegmentNaming('develop.md', FileNaming.snakeCase),
        'develop.md',
      );
      expect(convertSegmentNaming('scripts', FileNaming.camelCase), 'scripts');
    });
  });

  group('convertPathNaming', () {
    test('converts every segment', () {
      expect(
        convertPathNaming('test/dna/dna-test.dart', FileNaming.snakeCase),
        'test/dna/dna_test.dart',
      );
      expect(
        convertPathNaming(
          'my-folder/install-node-mac.md',
          FileNaming.camelCase,
        ),
        'myFolder/installNodeMac.md',
      );
    });

    test('keep leaves everything alone', () {
      expect(
        convertPathNaming('a-b/c-d.md', FileNaming.keep),
        'a-b/c-d.md',
      );
    });

    test('dot-rooted tool trees keep canonical names', () {
      expect(
        convertPathNaming(
          '.claude/skills/new-project/SKILL.md',
          FileNaming.snakeCase,
        ),
        '.claude/skills/new-project/SKILL.md',
      );
      expect(
        convertPathNaming(
          '.github/workflows/my-pipeline.yaml',
          FileNaming.camelCase,
        ),
        '.github/workflows/my-pipeline.yaml',
      );
    });
  });

  group('rewriteRenamedReferences', () {
    test('replaces literally, longest keys first', () {
      final renames = {
        'create-branch.js': 'create_branch.js',
        'create-branch.js.md': 'create_branch.js.md',
      };
      expect(
        rewriteRenamedReferences(
          'run node scripts/create-branch.js and read create-branch.js.md',
          renames,
        ),
        'run node scripts/create_branch.js and read create_branch.js.md',
      );
    });

    test('no renames returns content unchanged', () {
      expect(rewriteRenamedReferences('x', {}), 'x');
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
