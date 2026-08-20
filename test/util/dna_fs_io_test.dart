// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:helix/src/util/dna_fs_io.dart';
import 'package:helix/src/util/dna_layout.dart';
import 'package:test/test.dart';

void main() {
  group('IoDnaHost', () {
    late Directory tmp;
    late IoDnaHost host;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('helix_fs_io_test_');
      host = IoDnaHost(git: (_, _) async => '');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    String path(String rel) => '${tmp.path}/$rel';

    test('write creates parents, read round-trips, list is relative', () {
      host.writeString(path('a/b/c.txt'), 'content');
      expect(host.existsFile(path('a/b/c.txt')), isTrue);
      expect(host.existsDir(path('a/b')), isTrue);
      expect(host.readString(path('a/b/c.txt')), 'content');
      host.writeString(path('a/d.txt'), 'x');
      expect(host.listFilesRecursive(path('a')), ['b/c.txt', 'd.txt']);
    });

    test('listFilesRecursive of a missing folder is empty', () {
      expect(host.listFilesRecursive(path('nope')), isEmpty);
    });

    test('rename, delete file and dir', () {
      host.writeString(path('a/one.txt'), '1');
      host.rename(path('a/one.txt'), path('a/two.txt'));
      expect(host.existsFile(path('a/two.txt')), isTrue);
      host.rename(path('a'), path('b'));
      expect(host.existsFile(path('b/two.txt')), isTrue);
      host.deleteFile(path('b/two.txt'));
      host.deleteFile(path('b/two.txt'));
      expect(host.existsFile(path('b/two.txt')), isFalse);
      host.deleteDir(path('b'));
      host.deleteDir(path('b'));
      expect(host.existsDir(path('b')), isFalse);
    });

    test('createDir creates recursively', () {
      host.createDir(path('x/y/z'));
      expect(host.existsDir(path('x/y/z')), isTrue);
    });

    test('uncommittedPaths asks git for prefix and porcelain status', () async {
      final calls = <List<String>>[];
      final probe = IoDnaHost(
        git: (dir, args) async {
          calls.add(args);
          if (args.first == 'rev-parse') return '\n';
          return ' M lib/a.dart\n?? doc/new.md\n';
        },
      );
      expect(await probe.uncommittedPaths('/repo'), {
        'lib/a.dart',
        'doc/new.md',
      });
      expect(calls.first, ['rev-parse', '--show-prefix']);
      expect(calls.last, contains('-uall'));
    });

    test('uncommittedPaths strips the subdirectory prefix', () async {
      final probe = IoDnaHost(
        git: (dir, args) async => args.first == 'rev-parse'
            ? 'pkg/app/\n'
            : ' M pkg/app/LICENSE\n M other/x.txt\n',
      );
      expect(await probe.uncommittedPaths('/repo/pkg/app'), {'LICENSE'});
    });
  });

  group('IoDnaHost.createTempDir', () {
    test('creates a fresh folder below the system temp directory', () {
      final host = IoDnaHost();
      final dir = host.createTempDir(dnaBackupDirPrefix);
      try {
        expect(Directory(dir).existsSync(), isTrue);
        expect(dir, contains(dnaBackupDirPrefix));
        expect(dir, isNot(contains(r'\')));
        expect(
          dir,
          startsWith(Directory.systemTemp.absolute.path.replaceAll(r'\', '/')),
        );
        // A second call never returns the same folder.
        final other = host.createTempDir(dnaBackupDirPrefix);
        expect(other, isNot(dir));
        Directory(other).deleteSync();
      } finally {
        if (Directory(dir).existsSync()) Directory(dir).deleteSync();
      }
    });
  });

  group('IoDnaHost.commitPaths', () {
    test('stages and commits exactly the given paths', () async {
      final calls = <List<String>>[];
      final probe = IoDnaHost(
        git: (dir, args) async {
          calls.add(args);
          return args.first == 'diff' ? 'a.txt\n' : '';
        },
      );
      await probe.commitPaths('/repo', [
        'a.txt',
        'dna/b.md',
      ], '#gg: generated DNA');
      expect(calls, [
        ['add', '-A', '--', 'a.txt', 'dna/b.md'],
        ['diff', '--cached', '--name-only', '--', 'a.txt', 'dna/b.md'],
        ['commit', '-m', '#gg: generated DNA', '--', 'a.txt', 'dna/b.md'],
      ]);
    });

    test('skips the commit when the paths are identical to HEAD', () async {
      final calls = <List<String>>[];
      final probe = IoDnaHost(
        git: (dir, args) async {
          calls.add(args);
          // Nothing staged — `git commit` would exit non-zero here.
          return args.first == 'diff' ? '\n' : '';
        },
      );
      await probe.commitPaths('/repo', ['a.txt'], '#gg: generated DNA');
      expect(calls.map((c) => c.first), ['add', 'diff']);
    });

    test('does nothing without paths', () async {
      var called = false;
      final probe = IoDnaHost(
        git: (_, _) async {
          called = true;
          return '';
        },
      );
      await probe.commitPaths('/repo', const [], 'msg');
      expect(called, isFalse);
    });

    test('really commits in a git repository', () async {
      final tmp = Directory.systemTemp.createTempSync('helix_commit_test_');
      try {
        final host = IoDnaHost();
        String git(List<String> args) => Process.runSync(
          'git',
          args,
          workingDirectory: tmp.path,
        ).stdout.toString();
        git(['init', '-q']);
        git(['config', 'user.email', 't@t']);
        git(['config', 'user.name', 't']);
        host.writeString('${tmp.path}/generated.md', '# generated\n');
        host.writeString('${tmp.path}/mine.md', '# mine\n');

        await host.commitPaths(tmp.path, [
          'generated.md',
        ], '#gg: generated DNA');

        expect(git(['log', '-1', '--pretty=%s']).trim(), '#gg: generated DNA');

        // Committing the same content again is a no-op, not a failure —
        // restoring a locally changed instance ends up exactly here.
        await host.commitPaths(tmp.path, [
          'generated.md',
        ], '#gg: generated DNA');
        expect(git(['log', '--pretty=%s']).trim().split('\n'), hasLength(1));
        // The unrelated file stayed in the working tree.
        expect(await host.uncommittedPaths(tmp.path), {'mine.md'});
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });
  });

  group('parseGitStatusPaths', () {
    test('reads every porcelain status code', () {
      expect(
        parseGitStatusPaths(
          ' M modified.txt\n'
          'A  added.txt\n'
          ' D deleted.txt\n'
          '?? untracked.txt\n'
          'MM staged-and-modified.txt\n',
        ),
        {
          'modified.txt',
          'added.txt',
          'deleted.txt',
          'untracked.txt',
          'staged-and-modified.txt',
        },
      );
    });

    test('renames contribute both paths, quotes are stripped', () {
      expect(parseGitStatusPaths('R  old.txt -> new.txt\n'), {
        'old.txt',
        'new.txt',
      });
      expect(parseGitStatusPaths(' M "doc/mit umlaut.md"\n'), {
        'doc/mit umlaut.md',
      });
    });

    test('ignores empty and truncated lines', () {
      expect(parseGitStatusPaths('\n \n'), isEmpty);
    });
  });
}
