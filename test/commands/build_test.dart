// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:helix/src/commands/build.dart';
import 'package:helix/src/util/dna_fs.dart';
import 'package:test/test.dart';

void main() {
  final messages = <String>[];

  setUp(messages.clear);

  /// Records how the command called the engine.
  late List<({String? targetRoot, bool hasLog})> calls;
  Object? thrown;

  DnaTestRunner recordingRunner() =>
      ({
        String? targetRoot,
        DnaHost? host,
        String? baseDnaRoot,
        void Function(String message)? log,
      }) async {
        calls.add((targetRoot: targetRoot, hasLog: log != null));
        log?.call('dna is up to date');
        if (thrown != null) throw thrown!;
      };

  Future<void> runBuild(List<String> args) async {
    final runner = CommandRunner<dynamic>('test', 'test')
      ..addCommand(Build(ggLog: messages.add, runner: recordingRunner()));
    await runner.run(['build', ...args]);
  }

  setUp(() {
    calls = [];
    thrown = null;
  });

  group('Build', () {
    test('has the expected name and description', () {
      final command = Build(ggLog: messages.add);
      expect(command.name, 'build');
      expect(
        command.description,
        'Instantiates the DNA and verifies the instances',
      );
    });

    test('instantiates the current folder by default', () async {
      await runBuild([]);
      // null means »the current folder«, the same the placed test passes.
      expect(calls.single.targetRoot, isNull);
    });

    test('instantiates an explicit target', () async {
      await runBuild(['--target', '/p']);
      expect(calls.single.targetRoot, '/p');
    });

    test('normalizes windows separators of the target', () async {
      await runBuild([r'--target', r'C:\proj\a']);
      expect(calls.single.targetRoot, 'C:/proj/a');
    });

    test('routes the DNA report to ggLog', () async {
      await runBuild([]);
      expect(calls.single.hasLog, isTrue);
      expect(messages, ['dna is up to date']);
    });

    test('lets a failed DNA run through — the runner reports it', () async {
      thrown = Exception('LICENSE is missing');
      await expectLater(
        () => runBuild([]),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('LICENSE is missing'),
          ),
        ),
      );
    });

    test('runs the real engine when no runner is injected', () {
      // The default is `runDnaTest` itself; constructing must not run it.
      expect(Build(ggLog: messages.add).argParser.options, contains('target'));
    });
  });
}
