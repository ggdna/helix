// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_dna/src/util/copy_directory.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('copyDirectory', () {
    late Directory tmp;
    late Directory source;
    late Directory target;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('copy_directory_test_');
      source = Directory(p.join(tmp.path, 'source'))..createSync();
      target = Directory(p.join(tmp.path, 'target'));
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    void write(String rel, String content) {
      final file = File(p.join(source.path, rel));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    test('copies files with overlay semantics', () {
      write('a.md', 'A');
      write('sub/b.md', 'B');
      Directory(p.join(source.path, 'empty')).createSync();
      File(p.join(target.path, 'keep.md'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('KEEP');

      copyDirectory(source, target);

      expect(File(p.join(target.path, 'a.md')).readAsStringSync(), 'A');
      expect(File(p.join(target.path, 'sub', 'b.md')).readAsStringSync(), 'B');
      expect(Directory(p.join(target.path, 'empty')).existsSync(), isTrue);
      expect(File(p.join(target.path, 'keep.md')).readAsStringSync(), 'KEEP');
    });

    test('overwrites colliding files', () {
      write('a.md', 'NEW');
      File(p.join(target.path, 'a.md'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('OLD');

      copyDirectory(source, target);

      expect(File(p.join(target.path, 'a.md')).readAsStringSync(), 'NEW');
    });

    test('skips entries the skip predicate excludes', () {
      write('a.md', 'A');
      write('.git/config', 'git');
      write('sub/x.tag.md', 'tag');

      final skipped = <String>[];
      copyDirectory(
        source,
        target,
        skip: (rel) {
          final skip = rel == '.git' ||
              rel.startsWith('.git/') ||
              rel.endsWith('.tag.md');
          if (skip) skipped.add(rel);
          return skip;
        },
      );

      expect(File(p.join(target.path, 'a.md')).existsSync(), isTrue);
      expect(Directory(p.join(target.path, '.git')).existsSync(), isFalse);
      expect(
        File(p.join(target.path, 'sub', 'x.tag.md')).existsSync(),
        isFalse,
      );
      expect(skipped, containsAll(['.git', '.git/config', 'sub/x.tag.md']));
    });
  });
}
