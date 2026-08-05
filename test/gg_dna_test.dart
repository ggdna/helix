// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_args/gg_args.dart';
import 'package:gg_dna/gg_dna.dart';
import 'package:test/test.dart';

void main() {
  final messages = <String>[];

  setUp(messages.clear);

  group('GgDna()', () {
    final ggDna = GgDna(ggLog: messages.add);

    final CommandRunner<dynamic> runner = CommandRunner<dynamic>(
      'ggDna',
      'Description goes here.',
    )..addCommand(ggDna);

    test('should allow to run init from the command line', () async {
      final tmp = await Directory.systemTemp.createTemp('gg_dna_test_');
      try {
        await File('${tmp.path}/pubspec.yaml').writeAsString('name: x\n');
        await runner.run(['ggDna', 'init', '--target', tmp.path]);
        expect(
          File('${tmp.path}/test/dna/dna_test.dart').existsSync(),
          isTrue,
        );
        expect(messages.any((m) => m.contains('DNA initialized')), isTrue);
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('sync fails with the migration hint', () async {
      await expectLater(
        () => runner.run(['ggDna', 'sync']),
        throwsA(
          isA<UsageException>().having(
            (e) => e.message,
            'message',
            contains('gg_dna init'),
          ),
        ),
      );
    });

    test('should show all sub commands', () async {
      final (subCommands, errorMessage) = await missingSubCommands(
        directory: Directory('lib/src/commands'),
        command: ggDna,
      );
      expect(subCommands, isEmpty, reason: errorMessage);
    });
  });
}
