// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:helix/src/util/claude_md.dart';
import 'package:helix/src/util/dna_fs.dart';
import 'package:test/test.dart';

void main() {
  const root = '/p';

  group('expandClaudeMdIncludes', () {
    test('matches projected files and folders first, sorted', () {
      final imports = expandClaudeMdIncludes(
        host: MemoryDnaHost(),
        targetRoot: root,
        include: ['doc/conventions', 'project-structure.md'],
        projectedFiles: {
          'doc/conventions/b-convention.md',
          'doc/conventions/a-convention.md',
          'doc/conventions/nested/deep.md',
          'doc/conventions/not-markdown.txt',
          'project-structure.md',
        },
      );
      expect(imports, [
        'doc/conventions/a-convention.md',
        'doc/conventions/b-convention.md',
        'doc/conventions/nested/deep.md',
        'project-structure.md',
      ]);
    });

    test('falls back to files and folders on disk', () {
      final host = MemoryDnaHost(
        files: {
          '$root/extra/b.md': 'b',
          '$root/extra/a.md': 'a',
          '$root/extra/skip.txt': 'x',
          '$root/single.md': 's',
        },
      );
      final imports = expandClaudeMdIncludes(
        host: host,
        targetRoot: root,
        include: ['extra', 'single.md'],
      );
      expect(imports, ['extra/a.md', 'extra/b.md', 'single.md']);
    });

    test('normalizes backslash include paths', () {
      final imports = expandClaudeMdIncludes(
        host: MemoryDnaHost(),
        targetRoot: root,
        include: [r'doc\conventions'],
        projectedFiles: {'doc/conventions/a.md'},
      );
      expect(imports, ['doc/conventions/a.md']);
    });

    test('throws when an include does not exist', () {
      expect(
        () => expandClaudeMdIncludes(
          host: MemoryDnaHost(),
          targetRoot: root,
          include: ['missing'],
        ),
        throwsA(
          isA<Exception>().having((e) => '$e', 'message', contains('missing')),
        ),
      );
    });
  });

  group('buildClaudeMdBlock', () {
    test('wraps one @import per line between the markers', () {
      expect(buildClaudeMdBlock(['a.md', 'b/c.md']), '''
$claudeMdStartMarker

@a.md
@b/c.md

$claudeMdEndMarker''');
    });

    test('no import leaves the markers alone', () {
      expect(buildClaudeMdBlock([]), '''
$claudeMdStartMarker
$claudeMdEndMarker''');
    });
  });

  group('claudeLayerFileName', () {
    test('turns the bare package name into CLAUDE_<name>.md', () {
      expect(claudeLayerFileName('dna_gg'), 'CLAUDE_dna_gg.md');
      expect(claudeLayerFileName('dna-gg'), 'CLAUDE_dna_gg.md');
      expect(claudeLayerFileName('@ggdna/dna-gg'), 'CLAUDE_dna_gg.md');
      expect(claudeLayerFileName('Helix'), 'CLAUDE_helix.md');
    });
  });

  group('projectPackageName', () {
    test('reads pubspec.yaml first, then package.json', () {
      final host = MemoryDnaHost(
        files: {
          '$root/pubspec.yaml': 'name: from_pub\n',
          '$root/package.json': '{"name": "@org/from-npm"}',
        },
      );
      expect(projectPackageName(host, root), 'from_pub');
      host.deleteFile('$root/pubspec.yaml');
      expect(projectPackageName(host, root), '@org/from-npm');
    });

    test('falls back to the folder name', () {
      final host = MemoryDnaHost(
        files: {
          '/w/my-repo/pubspec.yaml': 'name: [unclosed',
          '/w/my-repo/package.json': '{no json',
        },
      );
      expect(projectPackageName(host, '/w/my-repo'), 'my_repo');
    });
  });

  group('rebaseClaudeLayerImports', () {
    test('prefixes relative imports with ../', () {
      expect(
        rebaseClaudeLayerImports('# T\n\n@doc/a.md\n  @b.md\n'),
        '# T\n\n@../doc/a.md\n  @../b.md\n',
      );
    });

    test('keeps absolute, home and non-import lines', () {
      const text =
          '@/abs/a.md\n@~/home/b.md\n@license\nsee @doc/a.md\n'
          '<!--\n@license\n-->\n';
      expect(rebaseClaudeLayerImports(text), text);
    });

    test('keeps lines inside fenced code blocks', () {
      expect(
        rebaseClaudeLayerImports('```\n@doc/a.md\n```\n@doc/b.md'),
        '```\n@doc/a.md\n```\n@../doc/b.md',
      );
    });
  });

  group('upsertClaudeMdBlock', () {
    const block = '$claudeMdStartMarker\n@a.md\n$claudeMdEndMarker';

    test('appends to empty and non-empty content', () {
      expect(upsertClaudeMdBlock('', block), '$block\n');
      expect(upsertClaudeMdBlock('# Title\n', block), '# Title\n\n$block\n');
    });

    test('replaces an existing block in place', () {
      const existing =
          '# T\n\n$claudeMdStartMarker\n@old.md\n'
          '$claudeMdEndMarker\n\n# After\n';
      expect(
        upsertClaudeMdBlock(existing, block),
        '# T\n\n$block\n\n# After\n',
      );
    });

    test('removes a legacy conventions block', () {
      const existing =
          '# T\n\n'
          '$legacyConventionsStartMarker v=2024 -->\n'
          '@x.md\n'
          '$legacyConventionsEndMarker\n'
          'rest\n';
      final result = upsertClaudeMdBlock(existing, block);
      expect(result, isNot(contains('helix:conventions')));
      expect(result, contains('rest'));
      expect(result, contains(block));
    });

    test('throws on unclosed managed blocks', () {
      expect(
        () => upsertClaudeMdBlock('$claudeMdStartMarker\n@x.md\n', block),
        throwsStateError,
      );
    });
  });

  group('updatedClaudeMd', () {
    test('returns new content when changed, null when unchanged', () {
      final host = MemoryDnaHost();
      final first = updatedClaudeMd(host, root, ['a.md']);
      expect(first, isNotNull);
      host.writeString('$root/CLAUDE.md', first!);
      expect(updatedClaudeMd(host, root, ['a.md']), isNull);
      expect(updatedClaudeMd(host, root, ['b.md']), isNotNull);
    });
  });
}
