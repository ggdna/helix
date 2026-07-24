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
    test('runs sync with an explicit source and target', () async {
      final tmp = await Directory.systemTemp.createTemp('gg_dna_bin_test_');
      try {
        final source = Directory('${tmp.path}/pkg/dna');
        await source.create(recursive: true);
        await File('${source.path}/a.md').writeAsString('A');
        final target = Directory('${tmp.path}/target');
        await target.create();

        final messages = <String>[];
        await run(
          args: [
            'sync',
            '--source',
            '${tmp.path}/pkg',
            '--target',
            target.path,
          ],
          ggLog: messages.add,
        );

        expect(
          messages.any((m) => m.contains('Synced')),
          isTrue,
          reason: 'messages: $messages',
        );
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });
}
