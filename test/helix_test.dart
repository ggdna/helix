// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_args/gg_args.dart';
import 'package:helix/helix.dart';
import 'package:test/test.dart';

void main() {
  final messages = <String>[];

  setUp(messages.clear);

  group('Helix()', () {
    final helix = Helix(ggLog: messages.add);

    final CommandRunner<dynamic> runner = CommandRunner<dynamic>(
      'helix',
      'Description goes here.',
    )..addCommand(helix);

    test('should allow to run init from the command line', () async {
      final tmp = await Directory.systemTemp.createTemp('helix_test_');
      try {
        await File('${tmp.path}/pubspec.yaml').writeAsString('name: x\n');
        await runner.run(['helix', 'init', '--target', tmp.path]);
        expect(File('${tmp.path}/test/dna/dna_test.dart').existsSync(), isTrue);
        expect(messages.any((m) => m.contains('DNA initialized')), isTrue);
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('should show all sub commands', () async {
      final (subCommands, errorMessage) = await missingSubCommands(
        directory: Directory('lib/src/commands'),
        command: helix,
      );
      expect(subCommands, isEmpty, reason: errorMessage);
    });
  });
}
