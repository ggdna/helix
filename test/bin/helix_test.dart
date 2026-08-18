// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:helix/src/commands/init.dart';
import 'package:test/test.dart';

import '../../bin/helix.dart';

void main() {
  group('run(args, log)', () {
    test('runs init against an explicit target', () async {
      final tmp = await Directory.systemTemp.createTemp('helix_bin_test_');
      try {
        // helix and package:test are declared, so init neither runs a
        // package manager nor skips the wrapper — this test stays offline.
        await File('${tmp.path}/pubspec.yaml').writeAsString('''
name: x
dev_dependencies:
  helix: ^1.0.0
  test: ^1.31.2
''');

        final messages = <String>[];
        await run(args: ['init', '--target', tmp.path], ggLog: messages.add);

        expect(File('${tmp.path}/test/dna/dna_test.dart').existsSync(), isTrue);
        expect(File('${tmp.path}/$helloWorldDnaPath').existsSync(), isTrue);
        expect(
          messages.any((m) => m.contains('gg dna build')),
          isTrue,
          reason: 'messages: $messages',
        );
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });
}
