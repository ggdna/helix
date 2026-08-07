// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:test/test.dart';

import '../../bin/gg_dna.dart';

void main() {
  group('run(args, log)', () {
    test('runs init against an explicit target', () async {
      final tmp = await Directory.systemTemp.createTemp('gg_dna_bin_test_');
      try {
        await File('${tmp.path}/pubspec.yaml').writeAsString('name: x\n');

        final messages = <String>[];
        await run(
          args: ['init', '--target', tmp.path],
          ggLog: messages.add,
        );

        expect(
          File('${tmp.path}/test/dna/dna_test.dart').existsSync(),
          isTrue,
        );
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
