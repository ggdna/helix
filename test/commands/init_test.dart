// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart' show cH2;
import 'package:helix/helix.dart' show cAction, cCmd, cDetail;
import 'package:helix/src/commands/init.dart';
import 'package:helix/src/engine/base_dna.dart';
import 'package:helix/src/engine/instantiate.dart';
import 'package:helix/src/util/dna_config.dart';
import 'package:helix/src/util/dna_fs.dart';
import 'package:helix/src/util/dna_layout.dart';
import 'package:helix/src/util/package_managers.dart';
import 'package:helix/src/util/process_run.dart';
import 'package:helix/src/util/select_prompt.dart';
import 'package:test/test.dart';

void main() {
  const root = '/p';
  const dartProject = 'name: x\ndev_dependencies:\n  test: ^1.31.2\n';
  const nodeProject = '{"devDependencies": {"vitest": "^4.0.0"}}';

  final messages = <String>[];
  final commands = <String>[];
  final prompts = <({String prompt, List<String> options})>[];

  setUp(() {
    messages.clear();
    commands.clear();
    prompts.clear();
  });

  /// A [SelectPrompt] that records the question and answers [answer] —
  /// or throws [unavailable] instead, like a prompt without a terminal.
  SelectPrompt fakePrompt({
    int answer = 0,
    SelectPromptUnavailableException? unavailable,
  }) => ({required String prompt, required List<String> options}) async {
    prompts.add((prompt: prompt, options: options));
    if (unavailable != null) throw unavailable;
    return answer;
  };

  const dart = 0;
  const typescript = 1;

  /// A [ProcessRun] that records its calls instead of running them.
  /// [onRun] simulates what the real command would write to disk.
  ProcessRun fakeRun({
    int exitCode = 0,
    String stderr = '',
    void Function(String executable, List<String> args)? onRun,
  }) =>
      (
        String executable,
        List<String> args, {
        required String workingDirectory,
      }) async {
        commands.add('$executable ${args.join(' ')}');
        onRun?.call(executable, args);
        return ProcessRunResult(exitCode: exitCode, stderr: stderr);
      };

  Future<void> runInit(
    MemoryDnaHost host, {
    ProcessRun? processRun,
    SelectPrompt? selectPrompt,
    List<String> args = const [],
  }) async {
    final runner = CommandRunner<dynamic>('test', 'test')
      ..addCommand(
        Init(
          ggLog: messages.add,
          host: host,
          processRun: processRun ?? fakeRun(),
          selectPrompt: selectPrompt ?? fakePrompt(answer: typescript),
        ),
      );
    await runner.run(['init', '--target', root, ...args]);
  }

  group('Init', () {
    test('defaults to the real file system and package managers', () {
      // Coverage of the io seams is attributed per test file, so the
      // default wiring is constructed here and not only end to end in
      // test/helix_test.dart.
      final command = Init(ggLog: messages.add);
      expect(command.name, 'init');
      expect(command.argParser.options, contains('target'));
      expect(command.argParser.options, contains('language'));
    });

    group('manifests', () {
      test('asks for the language when neither manifest is there', () async {
        final host = MemoryDnaHost();
        await runInit(host, selectPrompt: fakePrompt(answer: dart));
        expect(prompts, hasLength(1));
        expect(prompts.single.prompt, contains('No pubspec.yaml'));
        expect(prompts.single.prompt, contains('"$root"'));
        expect(prompts.single.options, ['Dart', 'TypeScript']);
      });

      test('runs npm init when TypeScript is chosen', () async {
        final host = MemoryDnaHost();
        await runInit(
          host,
          selectPrompt: fakePrompt(answer: typescript),
          processRun: fakeRun(
            onRun: (executable, args) {
              if (args.first == 'init') {
                host.writeString('$root/package.json', '{}');
              }
            },
          ),
        );
        expect(commands.first, 'npm ${npmInitArgs.join(' ')}');
        expect(host.existsFile('$root/package.json'), isTrue);
        expect(host.existsFile('$root/pubspec.yaml'), isFalse);
        expect(messages, contains(cDetail('✓ Created package.json')));
      });

      test('writes a pubspec.yaml when Dart is chosen', () async {
        final host = MemoryDnaHost();
        await runInit(host, selectPrompt: fakePrompt(answer: dart));
        expect(host.readString('$root/pubspec.yaml'), pubspecSkeleton('p'));
        expect(host.existsFile('$root/package.json'), isFalse);
        expect(messages, contains(cDetail('✓ Created pubspec.yaml (p)')));
        // And the Dart path continues from there.
        expect(commands, ['dart pub add dev:helix']);
        expect(commands.any((c) => c.contains('init')), isFalse);
      });

      test('--language decides without asking', () async {
        final host = MemoryDnaHost();
        await runInit(host, args: ['--language', 'dart']);
        expect(prompts, isEmpty);
        expect(host.existsFile('$root/pubspec.yaml'), isTrue);

        final node = MemoryDnaHost();
        await runInit(
          node,
          args: ['-l', 'typescript'],
          selectPrompt: fakePrompt(answer: dart),
          processRun: fakeRun(
            onRun: (executable, args) {
              if (args.first == 'init') {
                node.writeString('$root/package.json', '{}');
              }
            },
          ),
        );
        expect(prompts, isEmpty);
        expect(node.existsFile('$root/package.json'), isTrue);
        expect(node.existsFile('$root/pubspec.yaml'), isFalse);
      });

      test('--language rejects what is neither dart nor typescript', () async {
        await expectLater(
          () => runInit(MemoryDnaHost(), args: ['--language', 'rust']),
          throwsA(isA<UsageException>()),
        );
      });

      test('fails with the --language hint when it cannot ask', () async {
        final host = MemoryDnaHost();
        await expectLater(
          () => runInit(
            host,
            selectPrompt: fakePrompt(
              unavailable: const SelectPromptUnavailableException(
                'stdin is not a terminal',
              ),
            ),
          ),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('No pubspec.yaml and no package.json in "$root"'),
                contains('stdin is not a terminal'),
                contains('--language dart|typescript'),
              ),
            ),
          ),
        );
        expect(commands, isEmpty);
        expect(host.files, isEmpty);
      });

      test('adds the engine after bootstrapping the package.json', () async {
        final host = MemoryDnaHost();
        await runInit(
          host,
          processRun: fakeRun(
            onRun: (executable, args) {
              if (args.first == 'init') {
                host.writeString('$root/package.json', '{}');
              }
            },
          ),
        );
        expect(commands, contains('npm install -D @tssuite/helix-js'));
      });

      test('fails when npm init does not produce a package.json', () async {
        final host = MemoryDnaHost();
        await expectLater(
          () => runInit(
            host,
            processRun: fakeRun(exitCode: 127, stderr: 'npm: not found'),
          ),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              allOf(contains('npm init -y'), contains('npm: not found')),
            ),
          ),
        );
      });

      test('leaves an existing manifest alone and does not ask', () async {
        final host = MemoryDnaHost(files: {'$root/pubspec.yaml': dartProject});
        await runInit(host, args: ['--language', 'typescript']);
        expect(prompts, isEmpty);
        expect(commands.any((c) => c.contains('init')), isFalse);
        expect(host.existsFile('$root/package.json'), isFalse);
      });
    });

    group('dev dependencies', () {
      test('adds @tssuite/helix-js with npm by default', () async {
        final host = MemoryDnaHost(files: {'$root/package.json': '{}'});
        await runInit(host);
        expect(commands, ['npm install -D @tssuite/helix-js']);
        expect(
          messages,
          contains(cDetail('✓ npm install -D @tssuite/helix-js')),
        );
      });

      test('uses pnpm when a pnpm lock file is there', () async {
        final host = MemoryDnaHost(
          files: {'$root/package.json': '{}', '$root/pnpm-lock.yaml': ''},
        );
        await runInit(host);
        expect(commands, ['pnpm add -D @tssuite/helix-js']);
      });

      test('uses yarn when a yarn lock file is there', () async {
        final host = MemoryDnaHost(
          files: {'$root/package.json': '{}', '$root/yarn.lock': ''},
        );
        await runInit(host);
        expect(commands, ['yarn add -D @tssuite/helix-js']);
      });

      test('the packageManager field wins over a lock file', () async {
        final host = MemoryDnaHost(
          files: {
            '$root/package.json': '{"packageManager": "yarn@4.5.0"}',
            '$root/pnpm-lock.yaml': '',
          },
        );
        await runInit(host);
        expect(commands, ['yarn add -D @tssuite/helix-js']);
      });

      test('adds helix with dart pub in Dart projects', () async {
        final host = MemoryDnaHost(files: {'$root/pubspec.yaml': dartProject});
        await runInit(host);
        expect(commands, ['dart pub add dev:helix']);
      });

      test('adds helix with flutter pub in Flutter projects', () async {
        final host = MemoryDnaHost(
          files: {
            '$root/pubspec.yaml':
                'name: x\ndependencies:\n  flutter:\n    sdk: flutter\n',
          },
        );
        await runInit(host);
        expect(commands, ['flutter pub add dev:helix']);
      });

      test('adds both engines in hybrid projects', () async {
        final host = MemoryDnaHost(
          files: {
            '$root/pubspec.yaml': dartProject,
            '$root/package.json': nodeProject,
          },
        );
        await runInit(host);
        expect(commands, [
          'npm install -D @tssuite/helix-js',
          'dart pub add dev:helix',
        ]);
      });

      test('keeps an already declared dev dependency', () async {
        final host = MemoryDnaHost(
          files: {
            '$root/pubspec.yaml':
                'name: x\ndev_dependencies:\n  helix: ^1.0.0\n',
            '$root/package.json':
                '{"devDependencies": {"@tssuite/helix-js": "^1.0.0"}}',
          },
        );
        await runInit(host);
        expect(commands, isEmpty);
        expect(
          messages.where((m) => m.contains('✓ Kept existing dev dependency')),
          hasLength(2),
        );
      });

      test('reports a failed command instead of aborting', () async {
        final host = MemoryDnaHost(files: {'$root/pubspec.yaml': dartProject});
        await runInit(
          host,
          processRun: fakeRun(exitCode: 66, stderr: 'no network'),
        );
        expect(
          messages,
          contains(
            '! dart pub add dev:helix failed — run it manually:\nno network',
          ),
        );
        // The rest of the initialization still happened.
        expect(host.existsFile('$root/$dnaConfigPath'), isTrue);
      });
    });

    group('placed files', () {
      test('places the config', () async {
        final host = MemoryDnaHost(files: {'$root/pubspec.yaml': dartProject});
        await runInit(host);
        expect(host.existsFile('$root/$dnaConfigPath'), isTrue);
        // dna/ is tracked anyway — no .gitignore surgery needed.
        expect(host.existsFile('$root/.gitignore'), isFalse);
      });

      test('places the Dart wrapper when package:test is declared', () async {
        final host = MemoryDnaHost(files: {'$root/pubspec.yaml': dartProject});
        await runInit(host);
        expect(
          host.readString('$root/test/dna/dna_test.dart'),
          contains('runDnaTest'),
        );
        expect(host.existsFile('$root/test/dna/dna.spec.ts'), isFalse);
      });

      test('places the vitest wrapper when vitest is declared', () async {
        final host = MemoryDnaHost(files: {'$root/package.json': nodeProject});
        await runInit(host);
        expect(
          host.readString('$root/test/dna/dna.spec.ts'),
          contains('@tssuite/helix-js'),
        );
        expect(host.existsFile('$root/test/dna/dna_test.dart'), isFalse);
      });

      test('places both wrappers in hybrid projects', () async {
        final host = MemoryDnaHost(
          files: {
            '$root/pubspec.yaml': dartProject,
            '$root/package.json': nodeProject,
          },
        );
        await runInit(host);
        expect(host.existsFile('$root/test/dna/dna_test.dart'), isTrue);
        expect(host.existsFile('$root/test/dna/dna.spec.ts'), isTrue);
      });

      test(
        'places no wrapper, and no error, without a test framework',
        () async {
          final host = MemoryDnaHost(files: {'$root/pubspec.yaml': 'name: x'});
          await runInit(host);
          expect(host.existsDir('$root/test'), isFalse);
          // A project without a test framework is a shape, not a problem:
          // `helix build` runs the instantiation there.
          expect(messages.any((m) => m.contains('No test framework')), isFalse);
          expect(
            messages.any((m) => m.contains('gg dna add <dnaPackage>')),
            isTrue,
          );
        },
      );

      test('is idempotent and keeps existing files', () async {
        final host = MemoryDnaHost(
          files: {
            '$root/pubspec.yaml': dartProject,
            '$root/test/dna/dna_test.dart': '// custom',
            '$root/$dnaConfigPath': '// custom config',
          },
        );
        await runInit(host);
        expect(host.readString('$root/test/dna/dna_test.dart'), '// custom');
        expect(host.readString('$root/$dnaConfigPath'), '// custom config');
        expect(
          messages.where((m) => m.contains('✓ Kept existing')),
          hasLength(2),
        );
      });
    });

    group('the closing message', () {
      test('is a headline and the command that comes next', () async {
        final host = MemoryDnaHost(files: {'$root/pubspec.yaml': dartProject});
        await runInit(host);
        expect(messages.sublist(messages.length - 5), [
          '',
          cH2('✓ Initialized.'),
          '',
          '${cAction('Add dna by running ')}'
              '${cCmd('gg dna add <dnaPackage>')}${cAction('.')}',
          '',
        ]);
      });

      test('the steps above are checked off in the detail color', () async {
        final host = MemoryDnaHost(files: {'$root/pubspec.yaml': dartProject});
        await runInit(host);
        final steps = messages.takeWhile((m) => m.isNotEmpty);
        expect(steps, isNotEmpty);
        for (final step in steps) {
          final plain = step.replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '');
          expect(step, cDetail(plain), reason: 'not in the detail color');
          expect(plain, isNot(startsWith('+ ')));
          expect(plain, startsWith('✓ '));
        }
        expect(
          steps.where((m) => m.contains('✓ Placed ')),
          hasLength(2), // config, wrapper test
        );
      });

      test('reports the layers it pre-filled before them', () async {
        final host = MemoryDnaHost(
          files: {
            '$root/pubspec.yaml':
                'name: x\ndependencies:\n  dna_guides: ^1.0.0\n',
            '$root/.dart_tool/package_config.json':
                '{"packages": [ '
                '{"name": "dna_guides", "rootUri": "../../cache/dna_guides"}]}',
            '/cache/dna_guides/pubspec.yaml':
                'name: dna_guides\nversion: 1.0.0\n',
            '/cache/dna_guides/$dnaConfigPath':
                '{"version": $dnaFormatVersion, "role": "dna"}',
            '/cache/dna_guides/dna/LICENSE': 'MIT\n',
          },
        );
        await runInit(host);
        expect(messages, contains(cDetail('✓ Layers: dna_guides')));
        expect(
          messages.any((m) => m.contains('gg dna add <dnaPackage>')),
          isTrue,
        );
      });
    });

    group('the config skeleton', () {
      test('parses as a valid empty config', () async {
        final host = MemoryDnaHost(files: {'$root/pubspec.yaml': dartProject});
        await runInit(host);
        final r = readDnaConfig(host, root);
        expect(r.config.layers, isEmpty);
        expect(r.warnings, isEmpty);
      });

      test('pre-fills layers with the installed DNA packages', () async {
        final host = MemoryDnaHost(
          files: {
            '$root/pubspec.yaml':
                'name: x\ndependencies:\n  dna_guides: ^1.0.0\n',
            '$root/.dart_tool/package_config.json':
                '{"packages": [ '
                '{"name": "dna_guides", "rootUri": "../../cache/dna_guides"}]}',
            '/cache/dna_guides/pubspec.yaml':
                'name: dna_guides\nversion: 1.0.0\n',
            '/cache/dna_guides/$dnaConfigPath':
                '{"version": $dnaFormatVersion, "role": "dna"}',
            '/cache/dna_guides/dna/LICENSE': 'MIT\n',
          },
        );
        await runInit(host);
        expect(readDnaConfig(host, root).config.layers, ['dna_guides']);
        expect(messages.any((m) => m.contains('dna_guides')), isTrue);
      });
    });

    group('the getting-started doc', () {
      test('is not placed, and no run creates it', () async {
        // The base DNA used to ship `dna/doc/hello_world.md`. It does not
        // any more: `init` writes no doc, and a run against the base
        // leaves the project without one.
        final host = MemoryDnaHost(files: {'$root/pubspec.yaml': dartProject});
        await runInit(host);
        expect(host.existsFile('$root/dna/doc/hello_world.md'), isFalse);

        for (final rel in baseDnaFiles.keys) {
          host.writeString('/base/dna/$rel', baseDnaFiles[rel]!);
        }
        final result = await instantiateDna(
          host: host,
          targetRoot: root,
          baseDnaRoot: '/base',
          baseVersion: '1.0.0',
        );

        expect(result.blocked, isFalse);
        expect(host.existsFile('$root/doc/hello_world.md'), isFalse);
      });
    });
  });
}
