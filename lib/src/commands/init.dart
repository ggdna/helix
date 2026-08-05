// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';

import '../util/dna_config.dart';
import '../util/dna_fs.dart';
import '../util/dna_fs_io.dart';

/// Content of the placed Dart wrapper test.
const String dartWrapperTest = '''
// Placed by `gg_dna init` — instantiates and verifies this project's DNA
// on every test run. The logic lives in the gg_dna dev-dependency and is
// updated through normal dependency updates.

import 'package:gg_dna/gg_dna.dart';
import 'package:test/test.dart';

void main() {
  test(
    'dna is instantiated and unmodified',
    () => runDnaTest(),
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
''';

/// Content of the placed vitest wrapper spec.
const String tsWrapperTest = '''
// Placed by `gg_dna init` — instantiates and verifies this project's DNA
// on every test run. The logic lives in the @tssuite/gg-dna
// dev-dependency and is updated through normal dependency updates.

import { runDnaTest } from '@tssuite/gg-dna';
import { test } from 'vitest';

test(
  'dna is instantiated and unmodified',
  async () => {
    await runDnaTest();
  },
  120000,
);
''';

/// Skeleton written to `.gg/dna.json` when it does not exist yet.
const String dnaConfigSkeleton = '''
{
  // DNA configuration (gg_dna 5.0) — all keys are optional.
  //
  // "role": "project",           // "dna" for DNA repositories
  // "order": ["base_dna"],       // default: dev-dependency order
  // "vars": { "projectName": "my-project" },
  // "fileNaming": "snake_case",  // camelCase | kebab-case | keep
  // "dependencies": { "base_dna": { "path": "../base_dna" } },
  // "config": {
  //   "claude": { "claude_md": { "include": ["doc/conventions"] } }
  // }
}
''';

// .............................................................................
/// Places the DNA wrapper test, a `.gg/dna.json` skeleton and the
/// `.gitignore` exception into a project. The actual instantiation runs
/// inside the placed test on every test run.
class Init extends Command<dynamic> {
  /// Constructor.
  Init({required this.ggLog, DnaHost? host}) : _host = host ?? IoDnaHost() {
    argParser.addOption(
      'target',
      abbr: 't',
      help: 'The project folder to initialize.',
      defaultsTo: '.',
    );
  }

  /// The log function.
  final GgLog ggLog;

  final DnaHost _host;

  @override
  final name = 'init';

  @override
  final description =
      'Places the DNA test into the project — the test instantiates the '
      'DNAs declared as dev-dependencies on every test run.';

  // ...........................................................................
  @override
  Future<void> run() async {
    final target = (argResults!['target'] as String).replaceAll(r'\', '/');
    final root = target == '.' ? '.' : target;

    final isDart = _host.existsFile('$root/pubspec.yaml');
    final isNode = _host.existsFile('$root/package.json');
    if (!isDart && !isNode) {
      usageException(
        'No pubspec.yaml or package.json found in "$root" — run gg_dna '
        'init inside a project.',
      );
    }

    if (isDart) {
      _place('$root/test/dna/dna_test.dart', dartWrapperTest);
    }
    if (isNode) {
      _place('$root/test/dna/dna.spec.ts', tsWrapperTest);
    }
    _place('$root/$dnaConfigPath', dnaConfigSkeleton);
    _ensureGitignoreException(root);

    ggLog(
      'DNA initialized. Declare DNA packages as dev-dependencies, run '
      'pnpm install / dart pub get, commit, then run your tests — the '
      'first run instantiates the DNA.',
    );
  }

  // ...........................................................................
  void _place(String path, String content) {
    if (_host.existsFile(path)) {
      ggLog('kept existing $path');
      return;
    }
    _host.writeString(path, content);
    ggLog('+ placed $path');
  }

  // ...........................................................................
  void _ensureGitignoreException(String root) {
    final path = '$root/.gitignore';
    const exception = '!.gg/dna.json';
    final existing = _host.existsFile(path) ? _host.readString(path) : '';
    if (existing.split('\n').any((line) => line.trim() == exception)) {
      return;
    }
    final updated = existing.isEmpty
        ? '$exception\n'
        : '${existing.trimRight()}\n$exception\n';
    _host.writeString(path, updated);
    ggLog('+ added $exception to .gitignore');
  }
}
