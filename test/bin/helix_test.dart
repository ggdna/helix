// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:test/test.dart';

import '../../bin/helix.dart';

void main() {
  group('run(args, log)', () {
    test('runs init against an explicit target', () async {
      final tmp = await Directory.systemTemp.createTemp('helix_bin_test_');
      try {
        await File('${tmp.path}/pubspec.yaml').writeAsString('name: x\n');

        final messages = <String>[];
        await run(args: ['init', '--target', tmp.path], ggLog: messages.add);

        expect(File('${tmp.path}/test/dna/dna_test.dart').existsSync(), isTrue);
        expect(
          messages.any((m) => m.contains('DNA initialized')),
          isTrue,
          reason: 'messages: $messages',
        );
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });
}
