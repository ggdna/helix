// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:helix/src/util/dna_fs.dart';
import 'package:helix/src/util/dna_fs_io.dart';
import 'package:helix/src/util/git_root.dart';
import 'package:test/test.dart';

void main() {
  /// A repository in `/repo` with a nested `lib/src` folder.
  MemoryDnaHost repository() => MemoryDnaHost(
    files: {
      '/repo/.git/HEAD': 'ref: refs/heads/main',
      '/repo/lib/src/a.dart': '',
    },
  );

  group('findGitRoot', () {
    test('finds the repository from its own root', () {
      expect(findGitRoot(repository(), '/repo'), '/repo');
    });

    test('finds the repository from a nested folder', () {
      expect(findGitRoot(repository(), '/repo/lib/src'), '/repo');
    });

    test('finds the nearest of nested repositories', () {
      final host = repository()
        ..writeString('/repo/packages/b/.git', 'gitdir: ../../.git/modules/b');
      expect(findGitRoot(host, '/repo/packages/b/lib'), '/repo/packages/b');
    });

    test('accepts a .git file of a worktree or submodule', () {
      final host = MemoryDnaHost(
        files: {'/wt/.git': 'gitdir: /repo/.git/worktrees/wt'},
      );
      expect(findGitRoot(host, '/wt/lib'), '/wt');
    });

    test('follows a symlink before walking up', () {
      final host = repository()..links['/link'] = '/repo/lib';
      expect(findGitRoot(host, '/link'), '/repo');
    });

    test('returns null outside any repository', () {
      expect(findGitRoot(repository(), '/other/lib'), isNull);
    });

    group('on the real file system', () {
      late Directory tmp;
      late String real;

      setUp(() {
        tmp = Directory.systemTemp.createTempSync('helix_git_root_test_');
        real = tmp.resolveSymbolicLinksSync().replaceAll(r'\', '/');
        Directory('${tmp.path}/.git').createSync();
        Directory('${tmp.path}/lib/src').createSync(recursive: true);
      });

      tearDown(() => tmp.deleteSync(recursive: true));

      test('finds the repository from a nested folder', () {
        expect(findGitRoot(IoDnaHost(), '${tmp.path}/lib/src'), real);
      });

      test('stops at the root of the drive', () {
        // The walk up ends at the drive root (`C:/` on Windows), whether
        // or not a repository lies above the temp folder.
        Directory('${tmp.path}/.git').deleteSync();
        final found = findGitRoot(IoDnaHost(), '${tmp.path}/lib/src');
        expect(found == null || !found.startsWith(real), isTrue);
      });
    });
  });

  group('projectRoot', () {
    test('moves from a nested folder to the repository root', () {
      expect(projectRoot(repository(), '/repo/lib/src'), '/repo');
    });

    test('keeps the working folder at the repository root', () {
      expect(projectRoot(repository(), '/repo'), '/repo');
      // The current folder stays ».«, as the placed test passes it.
      expect(projectRoot(MemoryDnaHost(), '.'), '.');
    });

    test('keeps the working folder outside any repository', () {
      expect(projectRoot(repository(), '/other/lib'), '/other/lib');
    });
  });

  group('resolveTarget', () {
    test('takes an explicit target as it is, posix-separated', () {
      final moved = <String>[];
      expect(
        resolveTarget(
          repository(),
          r'C:\proj\a',
          '/repo/lib',
          onMoved: moved.add,
        ),
        'C:/proj/a',
      );
      expect(moved, isEmpty);
    });

    test('searches the repository root without a target', () {
      final moved = <String>[];
      expect(
        resolveTarget(repository(), null, '/repo/lib', onMoved: moved.add),
        '/repo',
      );
      expect(moved, ['/repo']);
    });

    test('reports nothing when it stays in the working folder', () {
      final moved = <String>[];
      expect(
        resolveTarget(repository(), null, '/repo', onMoved: moved.add),
        '/repo',
      );
      expect(moved, isEmpty);
    });

    test('works without a listener', () {
      expect(resolveTarget(repository(), null, '/repo/lib'), '/repo');
    });
  });
}
