// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_console_colors/gg_console_colors.dart' show cH2;
import 'package:gg_log/gg_log.dart';

import '../engine/base_dna.dart';
import '../engine/run_dna_test.dart';
import '../util/dna_config.dart';
import '../util/dna_fs.dart';
import '../util/dna_fs_io.dart';
import '../util/dna_layout.dart';
import '../util/layer_graph.dart';
import '../util/package_managers.dart';
import '../util/package_resolution.dart';
import '../util/process_run.dart';
import '../util/process_run_io.dart';

// The getting-started doc lives with the rest of the base DNA; `init`
// places a copy of it, so it stays reachable from here.
export '../engine/base_dna.dart' show helloWorldDnaPath, helloWorldDoc;

/// Content of the placed Dart wrapper test.
const String dartWrapperTest = '''
// Placed by `helix init` — instantiates and verifies this project's DNA
// on every test run. The logic lives in the helix dev-dependency and is
// updated through normal dependency updates.

import 'package:helix/helix.dart';
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
// Placed by `helix init` — instantiates and verifies this project's DNA
// on every test run. The logic lives in the @tssuite/helix-js
// dev-dependency and is updated through normal dependency updates.

import { runDnaTest } from '@tssuite/helix-js';
import { test } from 'vitest';

test(
  'dna is instantiated and unmodified',
  async () => {
    await runDnaTest();
  },
  120000,
);
''';

/// Skeleton written to `dna/_dna.json` when it does not exist yet, with
/// [layers] pre-filled from the DNA packages the project has installed.
String dnaConfigSkeleton(List<String> layers) {
  final list = layers.map((l) => '"$l"').join(', ');
  return '''
{
  // DNA configuration — the only place DNA config lives.
  // The engine only ever reads this file; dna/_generated.json is its
  // output. Comments and trailing commas are tolerated.
  "version": $dnaFormatVersion,

  // The DNA layers, in application order — later layers win. Package
  // names as declared in pubspec.yaml / package.json, never paths.
  // Transitive parents come from each layer's own dna/_dna.json.
  "layers": [$list]

  // "vars": { "dnaProjectName": "my-project" },
  // "claude": { "claudeMdInclude": ["doc/conventions"] }
}
''';
}

// .............................................................................
/// Prepares a project for the DNA engine: makes sure there is a manifest,
/// adds helix as a dev dependency, and places the configuration, the
/// getting-started doc and the wrapper test. The instantiation itself runs
/// inside that test on every test run.
class Init extends Command<dynamic> {
  /// Constructor. [host] and [processRun] are the injectable seams to the
  /// file system and to the package managers.
  Init({required this.ggLog, DnaHost? host, ProcessRun? processRun})
    : _host = host ?? IoDnaHost(),
      _processRun = processRun ?? ioProcessRun {
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

  final ProcessRun _processRun;

  @override
  final name = 'init';

  @override
  final description = 'Places the DNA test that instantiates the project DNA';

  // ...........................................................................
  @override
  Future<void> run() async {
    final target = (argResults!['target'] as String).replaceAll(r'\', '/');
    final root = target == '.' ? '.' : target;

    final isDart = _host.existsFile('$root/pubspec.yaml');
    var isNode = _host.existsFile('$root/package.json');
    if (!isDart && !isNode) {
      await _npmInit(root);
      isNode = true;
    }

    if (isNode) await _addNodeDevDependency(root);
    if (isDart) await _addPubDevDependency(root);

    final layers = suggestDnaLayers(
      _host,
      root,
      PackageResolution.read(_host, root),
    );
    _place('$root/$dnaConfigPath', dnaConfigSkeleton(layers));
    _place('$root/$helloWorldDnaPath', helloWorldDoc);

    // Without a test framework no wrapper is placed — that is a project
    // shape, not a problem: `helix build` runs the same instantiation.
    if (isDart && declaresPubDependency(_host, root, dartTestPackage)) {
      _place('$root/test/dna/dna_test.dart', dartWrapperTest);
    }
    if (isNode && declaresNodeDependency(_host, root, nodeTestPackage)) {
      _place('$root/test/dna/dna.spec.ts', tsWrapperTest);
    }

    if (layers.isNotEmpty) {
      ggLog(cDetail('✓ Layers: ${layers.join(', ')}'));
    }
    ggLog('');
    ggLog(cH2('✓ Initialized.'));
    ggLog('');
    // Concatenated, never nested: a cCmd inside a cAction resets the
    // yellow and the rest of the sentence loses it.
    ggLog(
      '${cAction('Add dna by running ')}'
      '${cCmd('gg dna add <dnaPackage>')}${cAction('.')}',
    );
    ggLog('');
  }

  // ...........................................................................
  /// Bootstraps a `package.json` with npm's defaults — the way on from a
  /// folder that is neither a Dart nor a node project.
  Future<void> _npmInit(String root) async {
    final result = await _processRun(
      NodePackageManager.npm.executable,
      npmInitArgs,
      workingDirectory: root,
    );
    if (!result.isSuccess || !_host.existsFile('$root/package.json')) {
      usageException(
        'No pubspec.yaml and no package.json in "$root", and '
        '${NodePackageManager.npm.executable} '
        '${npmInitArgs.join(' ')} did not create one:\n'
        '${result.failureOutput}',
      );
    }
    ggLog(cDetail('✓ Created package.json'));
  }

  // ...........................................................................
  /// Adds the DNA engine to the node dev dependencies, with the package
  /// manager this project uses.
  Future<void> _addNodeDevDependency(String root) async {
    if (declaresNodeDependency(_host, root, helixNodePackage)) {
      ggLog(cDetail('✓ Kept existing dev dependency $helixNodePackage'));
      return;
    }
    final manager = detectNodePackageManager(_host, root);
    await _addDevDependency(
      root,
      manager.executable,
      manager.addDevArgs(helixNodePackage),
    );
  }

  // ...........................................................................
  /// Adds the DNA engine to the pub dev dependencies.
  Future<void> _addPubDevDependency(String root) async {
    if (declaresPubDependency(_host, root, helixPubPackage)) {
      ggLog(cDetail('✓ Kept existing dev dependency $helixPubPackage'));
      return;
    }
    await _addDevDependency(
      root,
      pubExecutable(_host, root),
      pubAddDevArgs(helixPubPackage),
    );
  }

  // ...........................................................................
  /// Runs one dependency-adding command. A failure is reported with the
  /// command to repeat by hand instead of aborting: the configuration and
  /// the doc are worth placing either way.
  Future<void> _addDevDependency(
    String root,
    String executable,
    List<String> args,
  ) async {
    final command = '$executable ${args.join(' ')}';
    final result = await _processRun(executable, args, workingDirectory: root);
    if (result.isSuccess) {
      ggLog(cDetail('✓ $command'));
      return;
    }
    ggLog('! $command failed — run it manually:\n${result.failureOutput}');
  }

  // ...........................................................................
  void _place(String path, String content) {
    if (_host.existsFile(path)) {
      ggLog(cDetail('✓ Kept existing $path'));
      return;
    }
    _host.writeString(path, content);
    ggLog(cDetail('✓ Placed $path'));
  }
}
