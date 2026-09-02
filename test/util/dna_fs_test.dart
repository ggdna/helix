// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:helix/src/util/dna_fs.dart';
import 'package:helix/src/util/dna_layout.dart';
import 'package:test/test.dart';

void main() {
  group('MemoryDnaHost', () {
    late MemoryDnaHost host;

    setUp(() {
      host = MemoryDnaHost(
        files: {
          '/repo/dna/doc/develop.md': '# Develop',
          '/repo/dna/_vars.json': '{"a": "1"}',
          '/repo/LICENSE': 'MIT',
        },
      );
    });

    test('exists, read, write, delete', () {
      expect(host.existsFile('/repo/LICENSE'), isTrue);
      expect(host.existsFile('/repo/nope'), isFalse);
      expect(host.existsDir('/repo/dna'), isTrue);
      expect(host.existsDir('/repo/nope'), isFalse);
      expect(host.readString('/repo/LICENSE'), 'MIT');
      host.writeString('/repo/new/file.txt', 'x');
      expect(host.readString('/repo/new/file.txt'), 'x');
      host.deleteFile('/repo/LICENSE');
      expect(host.existsFile('/repo/LICENSE'), isFalse);
      host.deleteDir('/repo/dna');
      expect(host.existsDir('/repo/dna'), isFalse);
    });

    test('normalizes paths', () {
      expect(host.existsFile('/repo/./dna/../LICENSE'), isTrue);
    });

    test('realPath follows a seeded link and passes anything else on', () {
      final linked = MemoryDnaHost(links: {'/repo/link': '/repo/target'});
      expect(linked.realPath('/repo/link'), '/repo/target');
      expect(linked.realPath('/repo/other'), '/repo/other');
      // Without links a host resolves nothing — the base implementation.
      expect(host.realPath('/repo/dna'), '/repo/dna');
    });

    test('createDir is a no-op — folders exist implicitly', () {
      host.createDir('/repo/empty');
      expect(host.existsDir('/repo/empty'), isFalse);
    });

    test('listFilesRecursive returns sorted relative posix paths', () {
      expect(host.listFilesRecursive('/repo/dna'), [
        '_vars.json',
        'doc/develop.md',
      ]);
      expect(host.listFilesRecursive('/repo/missing'), isEmpty);
    });

    test('rename moves files and whole directories', () {
      host.rename('/repo/LICENSE', '/repo/LICENSE.bak');
      expect(host.existsFile('/repo/LICENSE.bak'), isTrue);
      host.rename('/repo/dna', '/repo/dna2');
      expect(host.readString('/repo/dna2/doc/develop.md'), '# Develop');
      expect(host.existsDir('/repo/dna'), isFalse);
    });

    test('read of missing file throws', () {
      expect(() => host.readBytes('/repo/nope'), throwsArgumentError);
    });

    test('commitPaths records the commit and clears the paths', () async {
      final dirty = MemoryDnaHost(uncommitted: {'a.md', 'b.md'});
      await dirty.commitPaths('/repo', ['a.md'], '#gg: generated DNA');
      expect(dirty.commits.single.paths, ['a.md']);
      expect(dirty.commits.single.message, '#gg: generated DNA');
      expect(await dirty.uncommittedPaths('/repo'), {'b.md'});
    });

    test('commitPaths throws when commitError is set', () async {
      final failing = MemoryDnaHost()..commitError = 'no git identity';
      await expectLater(
        () => failing.commitPaths('/repo', ['a.md'], 'msg'),
        throwsA(
          isA<Exception>().having(
            (e) => '$e',
            'message',
            contains('no git identity'),
          ),
        ),
      );
      expect(failing.commits, isEmpty);
    });

    test('createTempDir hands out a fresh path outside the project', () {
      final first = host.createTempDir(dnaBackupDirPrefix);
      final second = host.createTempDir(dnaBackupDirPrefix);
      expect(first, contains(dnaBackupDirPrefix));
      expect(second, isNot(first));
      // Usable right away, and nothing lives there yet.
      expect(host.listFilesRecursive(first), isEmpty);
      host.writeString('$first/a.md', '# a\n');
      expect(host.readString('$first/a.md'), '# a\n');
    });

    test('uncommittedPaths reflects the seeded set', () async {
      expect(await host.uncommittedPaths('/repo'), isEmpty);
      final dirty = MemoryDnaHost(uncommitted: {'LICENSE'});
      expect(await dirty.uncommittedPaths('/repo'), {'LICENSE'});
    });
  });
}
