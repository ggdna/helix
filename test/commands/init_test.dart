// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_dna/src/commands/init.dart';
import 'package:gg_dna/src/util/dna_config.dart';
import 'package:gg_dna/src/util/dna_fs.dart';
import 'package:gg_dna/src/util/dna_layout.dart';
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
      expect(host.existsFile('$root/$dnaConfigPath'), isTrue);
      // dna/ is tracked anyway — no .gitignore surgery needed.
      expect(host.existsFile('$root/.gitignore'), isFalse);
    });

    test('places the vitest wrapper into node projects', () async {
      final host = MemoryDnaHost(files: {'$root/package.json': '{}'});
      await runInit(host);
      expect(host.existsFile('$root/test/dna/dna.spec.ts'), isTrue);
      expect(host.existsFile('$root/test/dna/dna_test.dart'), isFalse);
      expect(
        host.readString('$root/test/dna/dna.spec.ts'),
        contains('@tssuite/gg_dna-js'),
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
          '$root/$dnaConfigPath': '// custom config',
        },
      );
      await runInit(host);
      expect(host.readString('$root/test/dna/dna_test.dart'), '// custom');
      expect(host.readString('$root/$dnaConfigPath'), '// custom config');
      expect(messages.any((m) => m.contains('kept existing')), isTrue);
    });

    test('fails outside of projects', () async {
      final host = MemoryDnaHost();
      await expectLater(
        () => runInit(host),
        throwsA(isA<UsageException>()),
      );
    });

    test('the skeleton parses as a valid empty config', () async {
      final host = MemoryDnaHost(files: {'$root/pubspec.yaml': 'name: x'});
      await runInit(host);
      final r = readDnaConfig(host, root);
      expect(r.config.role, DnaRole.project);
      expect(r.config.layers, isEmpty);
      expect(r.warnings, isEmpty);
    });

    test('pre-fills layers with the installed DNA packages', () async {
      final host = MemoryDnaHost(
        files: {
          '$root/pubspec.yaml': 'name: x\ndependencies:\n  base_dna: ^1.0.0\n',
          '$root/.dart_tool/package_config.json': '{"packages": [ '
              '{"name": "base_dna", "rootUri": "../../cache/base_dna"}]}',
          '/cache/base_dna/pubspec.yaml': 'name: base_dna\nversion: 1.0.0\n',
          '/cache/base_dna/$dnaConfigPath':
              '{"version": $dnaFormatVersion, "role": "dna"}',
          '/cache/base_dna/dna/LICENSE': 'MIT\n',
        },
      );
      await runInit(host);
      expect(readDnaConfig(host, root).config.layers, ['base_dna']);
      expect(messages.any((m) => m.contains('base_dna')), isTrue);
    });
  });
}
