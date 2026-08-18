// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:helix/helix.dart' show cAction, cCmd, cDetail, cError;
import 'package:helix/src/commands/add.dart';
import 'package:helix/src/commands/init.dart';
import 'package:helix/src/util/dna_config.dart';
import 'package:helix/src/util/dna_fs.dart';
import 'package:helix/src/util/process_run.dart';
import 'package:test/test.dart';

void main() {
  const root = '/p';
  const dartProject = 'name: x\ndev_dependencies:\n  test: ^1.31.2\n';
  const gitUrl = 'https://github.com/ggsuite/dna_base.git';

  final messages = <String>[];
  final commands = <String>[];

  /// The builds `add` triggered: one entry per call, with its target.
  final builds = <String?>[];

  setUp(() {
    messages.clear();
    commands.clear();
    builds.clear();
  });

  ProcessRun fakeRun({int exitCode = 0, String stderr = ''}) =>
      (
        String executable,
        List<String> args, {
        required String workingDirectory,
      }) {
        commands.add('$executable ${args.join(' ')}');
        return ProcessRunResult(exitCode: exitCode, stderr: stderr);
      };

  Future<void> runAdd(
    MemoryDnaHost host,
    List<String> args, {
    ProcessRun? processRun,
    Object? buildThrows,
  }) async {
    final runner = CommandRunner<dynamic>('test', 'test')
      ..addCommand(
        Add(
          ggLog: messages.add,
          host: host,
          processRun: processRun ?? fakeRun(),
          dnaTest:
              ({
                String? targetRoot,
                DnaHost? host,
                String? baseDnaRoot,
                void Function(String message)? log,
              }) async {
                builds.add(targetRoot);
                log?.call('+ instantiated LICENSE');
                if (buildThrows != null) throw buildThrows;
              },
        ),
      );
    await runner.run(['add', ...args, '--target', root]);
  }

  /// A project with a DNA config, as `helix init` leaves it.
  ///
  /// [installed] fakes what the package manager would have left behind: the
  /// packages are locatable in both ecosystems and carry a `dna/_dna.json`
  /// with [role] — that is what `helix add` checks after installing.
  MemoryDnaHost project({
    String? pubspec = dartProject,
    String? packageJson,
    String? config,
    String? pnpmLock,
    List<String> installed = const [],
    String role = 'dna',
    bool shipsDnaConfig = true,
  }) {
    final packageConfig = jsonEncode({
      'packages': [
        for (final name in installed)
          {'name': name, 'rootUri': '../../cache/$name'},
      ],
    });
    return MemoryDnaHost(
      files: {
        '$root/pubspec.yaml': ?pubspec,
        '$root/package.json': ?packageJson,
        '$root/pnpm-lock.yaml': ?pnpmLock,
        '$root/$dnaConfigPath': config ?? dnaConfigSkeleton([]),
        if (installed.isNotEmpty)
          '$root/.dart_tool/package_config.json': packageConfig,
        for (final name in installed) ...{
          // A file below the folder is what makes it exist in memory.
          '/cache/$name/README.md': '# $name',
          '$root/node_modules/$name/README.md': '# $name',
          if (shipsDnaConfig) ...{
            '/cache/$name/$dnaConfigPath': '{"version": 1, "role": "$role"}',
            '$root/node_modules/$name/$dnaConfigPath':
                '{"version": 1, "role": "$role"}',
          },
        },
      },
    );
  }

  List<String> layersOf(MemoryDnaHost host) =>
      readDnaConfig(host, root).config.layers;

  group('Add', () {
    test('defaults to the real file system and package managers', () {
      final command = Add(ggLog: messages.add);
      expect(command.name, 'add');
      expect(
        command.description,
        'Adds a DNA layer — a package name or a git URL',
      );
      expect(command.argParser.options, contains('target'));
    });

    group('the build at the end', () {
      test('builds the DNA that was just added', () async {
        final host = project(installed: ['dna_dart']);
        await runAdd(host, ['dna_dart']);
        expect(builds, [root]);
        // The engine report reaches the user.
        expect(messages.last, '+ instantiated LICENSE');
      });

      test('builds the current folder when no target is given', () async {
        // Seeded at the working folder instead of below /p, because that is
        // what `--target` defaults to.
        final host = MemoryDnaHost(
          files: {
            'pubspec.yaml': dartProject,
            dnaConfigPath: dnaConfigSkeleton([]),
            '.dart_tool/package_config.json':
                '{"packages": [{"name": "dna_dart", '
                '"rootUri": "file:///cache/dna_dart"}]}',
            '/cache/dna_dart/README.md': '# dna_dart',
            '/cache/dna_dart/$dnaConfigPath': '{"version": 1, "role": "dna"}',
          },
        );
        final runner = CommandRunner<dynamic>('test', 'test')
          ..addCommand(
            Add(
              ggLog: messages.add,
              host: host,
              processRun: fakeRun(),
              dnaTest: ({
                String? targetRoot,
                DnaHost? host,
                String? baseDnaRoot,
                void Function(String message)? log,
              }) async => builds.add(targetRoot),
            ),
          );
        await runner.run(['add', 'dna_dart']);
        // `null` means »the current folder«, as the placed test passes it.
        expect(builds, [null]);
      });

      test('builds even when nothing changed', () async {
        final host = project(
          pubspec: 'name: x\ndev_dependencies:\n  dna_dart: ^1.0.0\n',
          config: dnaConfigSkeleton(['dna_dart']),
          installed: ['dna_dart'],
        );
        await runAdd(host, ['dna_dart']);
        expect(commands, isEmpty);
        expect(builds, [root]);
      });

      test('reports a failing build', () async {
        final host = project(installed: ['dna_dart']);
        await expectLater(
          () => runAdd(host, [
            'dna_dart',
          ], buildThrows: Exception('LICENSE is missing')),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'toString',
              contains('LICENSE is missing'),
            ),
          ),
        );
        // The layer was added before the build ran.
        expect(layersOf(host), ['dna_dart']);
      });

      test('does not build when the add was refused', () async {
        final host = project(installed: ['dna_dart'], shipsDnaConfig: false);
        await expectLater(() => runAdd(host, ['dna_dart']), throwsA(anything));
        expect(builds, isEmpty);
      });
    });

    group('pub packages', () {
      test('adds the dev dependency and the layer', () async {
        final host = project(installed: ['dna_dart']);
        await runAdd(host, ['dna_dart']);
        expect(commands, ['dart pub add dev:dna_dart']);
        expect(layersOf(host), ['dna_dart']);
        expect(messages, contains(cDetail('✓ dart pub add dev:dna_dart')));
        expect(
          messages,
          contains(cDetail('✓ Added layer "dna_dart" to $dnaConfigPath')),
        );
      });

      test('appends to the layers that are already there', () async {
        final host = project(
          config: dnaConfigSkeleton(['dna_base']),
          installed: ['dna_dart'],
        );
        await runAdd(host, ['dna_dart']);
        // The last layer wins, so a new one goes to the end.
        expect(layersOf(host), ['dna_base', 'dna_dart']);
      });

      test('uses flutter pub in a Flutter project', () async {
        final host = project(
          installed: ['dna_dart'],
          pubspec: 'name: x\ndependencies:\n  flutter:\n    sdk: flutter\n',
        );
        await runAdd(host, ['dna_dart']);
        expect(commands, ['flutter pub add dev:dna_dart']);
      });

      test('keeps a dependency that is already declared', () async {
        final host = project(
          installed: ['dna_dart'],
          pubspec: 'name: x\ndev_dependencies:\n  dna_dart: ^1.0.0\n',
        );
        await runAdd(host, ['dna_dart']);
        expect(commands, isEmpty);
        expect(
          messages,
          contains(cDetail('✓ Kept existing dev dependency dna_dart')),
        );
        // The layer is still added — that is the point of the command.
        expect(layersOf(host), ['dna_dart']);
      });

      test('keeps a layer that is already listed', () async {
        final host = project(
          config: dnaConfigSkeleton(['dna_dart']),
          installed: ['dna_dart'],
        );
        await runAdd(host, ['dna_dart']);
        expect(commands, ['dart pub add dev:dna_dart']);
        expect(layersOf(host), ['dna_dart']);
        expect(
          messages,
          contains(
            cDetail('✓ Kept existing layer "dna_dart" in $dnaConfigPath'),
          ),
        );
      });
    });

    group('npm packages', () {
      test('adds a scoped name with the projects package manager', () async {
        final host = project(
          pubspec: null,
          packageJson: '{}',
          pnpmLock: '',
          installed: ['@tssuite/dna-base'],
        );
        await runAdd(host, ['@tssuite/dna-base']);
        expect(commands, ['pnpm add -D @tssuite/dna-base']);
        expect(layersOf(host), ['@tssuite/dna-base']);
      });

      test('a dashed name goes to node even in a hybrid project', () async {
        final host = project(packageJson: '{}', installed: ['dna-ts']);
        await runAdd(host, ['dna-ts']);
        expect(commands, ['npm install -D dna-ts']);
      });

      test('a pub-shaped name goes to pub in a hybrid project', () async {
        final host = project(packageJson: '{}', installed: ['dna_dart']);
        await runAdd(host, ['dna_dart']);
        expect(commands, ['dart pub add dev:dna_dart']);
      });

      test('rejects an npm name without a package.json', () async {
        final host = project();
        await expectLater(
          () => runAdd(host, ['@tssuite/dna-base']),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              allOf(contains('npm package name'), contains('package.json')),
            ),
          ),
        );
        expect(commands, isEmpty);
      });

      test('keeps a node dependency that is already declared', () async {
        final host = project(
          installed: ['dna-ts'],
          pubspec: null,
          packageJson: '{"devDependencies": {"dna-ts": "^1.0.0"}}',
        );
        await runAdd(host, ['dna-ts']);
        expect(commands, isEmpty);
        expect(layersOf(host), ['dna-ts']);
      });
    });

    group('git targets', () {
      test('adds a pub git dependency under the repository name', () async {
        final host = project(installed: ['dna_base']);
        await runAdd(host, [gitUrl]);
        expect(commands, ['dart pub add dev:dna_base@{git: $gitUrl}']);
        expect(layersOf(host), ['dna_base']);
      });

      test('adds a node git dependency with a git+ protocol', () async {
        final host = project(
          pubspec: null,
          packageJson: '{}',
          installed: ['dna_base'],
        );
        await runAdd(host, ['git@github.com:ggsuite/dna_base.git']);
        expect(commands, [
          'npm install -D git+ssh://git@github.com/ggsuite/dna_base.git',
        ]);
        expect(layersOf(host), ['dna_base']);
      });

      test('uses the name the package manager declared', () async {
        // npm writes the name from the repository's own package.json —
        // `dna_base.git` lands as `@tssuite/dna-base`, and that is the
        // name the engine resolves a layer by.
        final host = project(
          pubspec: null,
          packageJson: '{}',
          installed: ['@tssuite/dna-base'],
        );
        await runAdd(
          host,
          [gitUrl],
          processRun: (executable, args, {required workingDirectory}) {
            commands.add('$executable ${args.join(' ')}');
            host.writeString(
              '$root/package.json',
              '{"devDependencies": {"@tssuite/dna-base": "github:o/r"}}',
            );
            return const ProcessRunResult(exitCode: 0);
          },
        );
        expect(layersOf(host), ['@tssuite/dna-base']);
        expect(
          messages,
          contains(cDetail('$gitUrl is declared as @tssuite/dna-base')),
        );
      });

      test('adds the git dependency even when the name is declared', () async {
        // The declared name may point somewhere else — a git target always
        // runs, and the package manager decides what to do with it.
        final host = project(
          installed: ['dna_base'],
          pubspec: null,
          packageJson: '{"devDependencies": {"dna_base": "^1.0.0"}}',
        );
        await runAdd(host, [gitUrl]);
        expect(commands, ['npm install -D git+$gitUrl']);
      });
    });

    group('failures', () {
      test('requires a dna config and names how to get one', () async {
        final host = MemoryDnaHost(files: {'$root/pubspec.yaml': dartProject});
        await expectLater(
          () => runAdd(host, ['dna_dart']),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'toString',
              allOf(
                contains(cError('Not initialized.')),
                contains(cAction('Run')),
                contains(cCmd('gg dna init')),
                contains(cAction('first.')),
                // A state to fix, not a usage error: no usage block.
                isNot(contains('Usage:')),
              ),
            ),
          ),
        );
        expect(commands, isEmpty);
        expect(builds, isEmpty);
      });

      test('requires a manifest', () async {
        final host = MemoryDnaHost(
          files: {'$root/$dnaConfigPath': dnaConfigSkeleton([])},
        );
        await expectLater(
          () => runAdd(host, ['dna_dart']),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'toString',
              allOf(
                contains(cError('No pubspec.yaml and no package.json.')),
                contains(cCmd('gg dna init')),
                isNot(contains('Usage:')),
              ),
            ),
          ),
        );
      });

      test('requires a target to add', () async {
        await expectLater(
          () => runAdd(project(), []),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              contains('Pass the DNA to add'),
            ),
          ),
        );
      });

      test('adds one DNA at a time', () async {
        await expectLater(
          () => runAdd(project(), ['dna_base', 'dna_dart']),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              contains('one DNA at a time'),
            ),
          ),
        );
      });

      test('reports an empty target', () async {
        await expectLater(
          () => runAdd(project(), ['  ']),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              contains('Nothing to add'),
            ),
          ),
        );
      });

      test('does not touch the config when the install fails', () async {
        final host = project(installed: ['dna_dart']);
        await expectLater(
          () => runAdd(host, [
            'dna_dart',
          ], processRun: fakeRun(exitCode: 66, stderr: 'no such package')),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'toString',
              allOf(
                contains('dart pub add dev:dna_dart failed'),
                contains('no such package'),
                // The package manager already said everything.
                isNot(contains('Usage:')),
              ),
            ),
          ),
        );
        expect(layersOf(host), isEmpty);
      });

      test('complains when the package ships no DNA', () async {
        final host = project(installed: ['dna_dart'], shipsDnaConfig: false);
        await expectLater(
          () => runAdd(host, ['dna_dart']),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'toString',
              allOf(
                contains('dna_dart does not ship a DNA'),
                contains('role": "dna"'),
                contains('Nothing was added to $dnaConfigPath'),
              ),
            ),
          ),
        );
        // The dependency was installed, the config stays untouched.
        expect(commands, ['dart pub add dev:dna_dart']);
        expect(layersOf(host), isEmpty);
      });

      test('complains when the package does not declare role dna', () async {
        // A dna/ folder alone does not make a package a DNA layer.
        final host = project(installed: ['dna_dart'], role: 'project');
        await expectLater(
          () => runAdd(host, ['dna_dart']),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'toString',
              contains('does not ship a DNA'),
            ),
          ),
        );
        expect(layersOf(host), isEmpty);
      });

      test('complains when a git repo ships no DNA, naming the url', () async {
        final host = project(
          pubspec: null,
          packageJson: '{}',
          installed: ['dna_base'],
          shipsDnaConfig: false,
        );
        await expectLater(
          () => runAdd(host, [gitUrl]),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'toString',
              contains('$gitUrl does not ship a DNA'),
            ),
          ),
        );
        expect(layersOf(host), isEmpty);
      });

      test('complains when the installed package is not found', () async {
        // Nothing was installed — the fake package manager only reported
        // success.
        final host = project();
        await expectLater(
          () => runAdd(host, ['dna_dart']),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'toString',
              allOf(
                contains('cannot be found'),
                contains('Nothing was added to $dnaConfigPath'),
              ),
            ),
          ),
        );
        expect(layersOf(host), isEmpty);
      });

      test('reports a broken config before installing anything', () async {
        final host = project(config: '{"version": 99}');
        await expectLater(
          () => runAdd(host, ['dna_dart']),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'toString',
              allOf(
                contains('format version 99 is not supported'),
                // Readable: no mangled »Format« prefix from the runner.
                isNot(startsWith('FormatException')),
              ),
            ),
          ),
        );
        expect(commands, isEmpty);
      });
    });
  });
}
