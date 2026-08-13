// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';

import '../util/dna_config.dart';
import '../util/dna_fs.dart';
import '../util/dna_fs_io.dart';
import '../util/dna_layout.dart';
import '../util/layer_graph.dart';
import '../util/package_resolution.dart';

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

  // "dna" for DNA packages, "project" (the default) for consumers.
  "role": "project",

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
/// Places the DNA wrapper test and a `dna/_dna.json` skeleton into a
/// project. The actual instantiation runs inside the placed test on every
/// test run.
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
        'No pubspec.yaml or package.json found in "$root" — run helix '
        'init inside a project.',
      );
    }

    if (isDart) {
      _place('$root/test/dna/dna_test.dart', dartWrapperTest);
    }
    if (isNode) {
      _place('$root/test/dna/dna.spec.ts', tsWrapperTest);
    }
    final layers = suggestDnaLayers(
      _host,
      root,
      PackageResolution.read(_host, root),
    );
    _place('$root/$dnaConfigPath', dnaConfigSkeleton(layers));

    ggLog(
      layers.isEmpty
          ? 'DNA initialized. Declare the DNA packages you want as '
                'dependencies, run pnpm install / dart pub get, list them '
                'in "layers" of $dnaConfigPath, commit, then run your '
                'tests — the first run instantiates the DNA.'
          : 'DNA initialized with ${layers.join(', ')}. Commit, then run '
                'your tests — the first run instantiates the DNA.',
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
}
