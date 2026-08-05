// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_dna/src/util/dna_fs_io.dart';
import 'package:test/test.dart';

void main() {
  group('IoDnaHost', () {
    late Directory tmp;
    late IoDnaHost host;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('gg_dna_fs_io_test_');
      host = IoDnaHost(git: (_, __) => '');
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

    test('uncommittedPaths asks git for prefix and porcelain status', () {
      final calls = <List<String>>[];
      final probe = IoDnaHost(
        git: (dir, args) {
          calls.add(args);
          if (args.first == 'rev-parse') return '\n';
          return ' M lib/a.dart\n?? doc/new.md\n';
        },
      );
      expect(probe.uncommittedPaths('/repo'), {'lib/a.dart', 'doc/new.md'});
      expect(calls.first, ['rev-parse', '--show-prefix']);
      expect(calls.last, contains('-uall'));
    });

    test('uncommittedPaths strips the subdirectory prefix', () {
      final probe = IoDnaHost(
        git: (dir, args) => args.first == 'rev-parse'
            ? 'pkg/app/\n'
            : ' M pkg/app/LICENSE\n M other/x.txt\n',
      );
      expect(probe.uncommittedPaths('/repo/pkg/app'), {'LICENSE'});
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
