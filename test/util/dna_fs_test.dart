// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_dna/src/util/dna_fs.dart';
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

    test('uncommittedPaths reflects the seeded set', () {
      expect(host.uncommittedPaths('/repo'), isEmpty);
      final dirty = MemoryDnaHost(uncommitted: {'LICENSE'});
      expect(dirty.uncommittedPaths('/repo'), {'LICENSE'});
    });
  });
}
