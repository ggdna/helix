// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_dna/src/util/claude_md.dart';
import 'package:gg_dna/src/util/dna_fs.dart';
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
          isA<Exception>().having(
            (e) => '$e',
            'message',
            contains('missing'),
          ),
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
  });

  group('upsertClaudeMdBlock', () {
    const block = '$claudeMdStartMarker\n@a.md\n$claudeMdEndMarker';

    test('appends to empty and non-empty content', () {
      expect(upsertClaudeMdBlock('', block), '$block\n');
      expect(
        upsertClaudeMdBlock('# Title\n', block),
        '# Title\n\n$block\n',
      );
    });

    test('replaces an existing block in place', () {
      const existing = '# T\n\n$claudeMdStartMarker\n@old.md\n'
          '$claudeMdEndMarker\n\n# After\n';
      expect(
        upsertClaudeMdBlock(existing, block),
        '# T\n\n$block\n\n# After\n',
      );
    });

    test('removes a legacy conventions block', () {
      const existing = '# T\n\n'
          '$legacyConventionsStartMarker v=2024 -->\n'
          '@x.md\n'
          '$legacyConventionsEndMarker\n'
          'rest\n';
      final result = upsertClaudeMdBlock(existing, block);
      expect(result, isNot(contains('gg_dna:conventions')));
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
