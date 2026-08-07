// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_dna/src/commands/init.dart';
import 'package:gg_dna/src/util/dna_fs.dart';
import 'package:test/test.dart';

void main() {
  const root = '/p';
  final messages = <String>[];

  setUp(messages.clear);

  Future<void> runInit(MemoryDnaHost host) async {
    final runner = CommandRunner<dynamic>('test', 'test')
      ..addCommand(Init(ggLog: messages.add, host: host));
    await runner.run(['init', '--target', root]);
  }

  group('Init', () {
    test('places the Dart wrapper into Dart projects', () async {
      final host = MemoryDnaHost(files: {'$root/pubspec.yaml': 'name: x'});
      await runInit(host);
      expect(host.existsFile('$root/test/dna/dna_test.dart'), isTrue);
      expect(host.existsFile('$root/test/dna/dna.spec.ts'), isFalse);
      expect(
        host.readString('$root/test/dna/dna_test.dart'),
        contains('runDnaTest'),
      );
      expect(host.existsFile('$root/.gg/dna.json'), isTrue);
      expect(
        host.readString('$root/.gitignore'),
        contains('!.gg/dna.json'),
      );
    });

    test('places the vitest wrapper into node projects', () async {
      final host = MemoryDnaHost(files: {'$root/package.json': '{}'});
      await runInit(host);
      expect(host.existsFile('$root/test/dna/dna.spec.ts'), isTrue);
      expect(host.existsFile('$root/test/dna/dna_test.dart'), isFalse);
      expect(
        host.readString('$root/test/dna/dna.spec.ts'),
        contains('@tssuite/gg-dna'),
      );
    });

    test('places both wrappers into hybrid projects', () async {
      final host = MemoryDnaHost(
        files: {'$root/pubspec.yaml': 'name: x', '$root/package.json': '{}'},
      );
      await runInit(host);
      expect(host.existsFile('$root/test/dna/dna_test.dart'), isTrue);
      expect(host.existsFile('$root/test/dna/dna.spec.ts'), isTrue);
    });

    test('is idempotent and keeps existing files', () async {
      final host = MemoryDnaHost(
        files: {
          '$root/pubspec.yaml': 'name: x',
          '$root/test/dna/dna_test.dart': '// custom',
          '$root/.gitignore': '.gg/*\n!.gg/gg.json\n!.gg/dna.json\n',
        },
      );
      await runInit(host);
      expect(host.readString('$root/test/dna/dna_test.dart'), '// custom');
      expect(messages.any((m) => m.contains('kept existing')), isTrue);
      expect(
        RegExp('!\\.gg/dna\\.json')
            .allMatches(host.readString('$root/.gitignore'))
            .length,
        1,
      );
    });

    test('appends the gitignore exception to existing content', () async {
      final host = MemoryDnaHost(
        files: {
          '$root/pubspec.yaml': 'name: x',
          '$root/.gitignore': '.gg/*\n!.gg/gg.json\n',
        },
      );
      await runInit(host);
      expect(
        host.readString('$root/.gitignore'),
        '.gg/*\n!.gg/gg.json\n!.gg/dna.json\n',
      );
    });

    test('fails outside of projects', () async {
      final host = MemoryDnaHost();
      await expectLater(
        () => runInit(host),
        throwsA(isA<UsageException>()),
      );
    });

    test('skeleton config parses as valid empty config', () async {
      final host = MemoryDnaHost(files: {'$root/pubspec.yaml': 'name: x'});
      await runInit(host);
      // The placed skeleton must not break the engine's config reader.
      expect(
        host.readString('$root/.gg/dna.json'),
        contains('DNA configuration'),
      );
    });
  });
}
