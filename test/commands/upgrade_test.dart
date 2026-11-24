// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:helix/helix.dart';
import 'package:helix/src/commands/upgrade.dart';
import 'package:test/test.dart';

void main() {
  final messages = <String>[];
  late List<({String? targetRoot, bool quiet})> calls;

  setUp(() {
    messages.clear();
    calls = [];
  });

  DnaTestRunner recordingRunner() =>
      ({
        String? targetRoot,
        DnaHost? host,
        String? baseDnaRoot,
        void Function(String message)? log,
        bool workspace = false,
        bool quiet = false,
      }) async {
        calls.add((targetRoot: targetRoot, quiet: quiet));
      };

  /// A Dart project in `/repo` with its repository and an old DNA test.
  MemoryDnaHost dartRepo() => MemoryDnaHost(
    files: {
      '/repo/.git/HEAD': 'ref: refs/heads/main',
      '/repo/pubspec.yaml':
          'name: p\ndev_dependencies:\n  helix: ^1.0.0\n  test: ^1.0.0\n',
      '/repo/test/dna/dna_test.dart': '// Placed by `helix init` — old\n',
    },
  );

  Future<void> runUpgrade(
    List<String> args,
    DnaHost host, {
    String workingDir = '/repo',
  }) async {
    final runner = CommandRunner<dynamic>('test', 'test')
      ..addCommand(
        Upgrade(
          ggLog: messages.add,
          runner: recordingRunner(),
          host: host,
          workingDir: workingDir,
        ),
      );
    await runner.run(['upgrade', ...args]);
  }

  group('Upgrade', () {
    test('has the expected name', () {
      expect(Upgrade(ggLog: messages.add).name, 'upgrade');
      expect(Helix(ggLog: messages.add).subcommands.keys, contains('upgrade'));
    });

    test('replaces the DNA check, then instantiates the DNA', () async {
      final host = dartRepo();
      await runUpgrade([], host);
      expect(host.readString('/repo/$dartDnaCheckPath'), dartWrapperTest);
      expect(messages, contains(contains('Placed $dartDnaCheckPath')));
      expect(calls.single.targetRoot, '/repo');
      expect(calls.single.quiet, isFalse);
    });

    test('a quiet run reports nothing of its own', () async {
      final host = dartRepo()
        ..writeString('/repo/$tsDnaCheckPath', tsWrapperTest);
      await runUpgrade(['--quiet'], host);
      expect(host.existsFile('/repo/$tsDnaCheckPath'), isFalse);
      expect(messages, isEmpty);
      expect(calls.single.quiet, isTrue);
    });

    test('reports a removed check of the other language', () async {
      final host = dartRepo()
        ..writeString('/repo/$tsDnaCheckPath', tsWrapperTest);
      await runUpgrade(['--target', '/repo'], host);
      expect(messages, contains(contains('Removed $tsDnaCheckPath')));
    });

    test('reports that it runs in the repository root', () async {
      await runUpgrade([], dartRepo(), workingDir: '/repo/lib/src');
      expect(messages.first, contains('/repo'));
      expect(calls.single.targetRoot, '/repo');
    });
  });
}
