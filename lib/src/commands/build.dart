// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';

import '../engine/run_dna_test.dart';
import '../util/dna_fs.dart';
import '../util/dna_fs_io.dart';
import '../util/git_root.dart';

/// Builds the DNA of a project: one instantiation plus the verification of
/// the instances — exactly what the placed test does in a project that has
/// a test framework, and the way to run the DNA cycle in one that has none.
class Build extends Command<dynamic> {
  /// Constructor. [runner], [host] and `workingDir` — the folder the
  /// repository root is searched from, the current one by default — are
  /// injectable for tests.
  Build({
    required this.ggLog,
    DnaTestRunner? runner,
    DnaHost? host,
    this._workingDir = '.',
  }) : _runner = runner ?? runDnaTest,
       _host = host ?? IoDnaHost() {
    argParser.addOption(
      'target',
      abbr: 't',
      help:
          'The project folder to build. Defaults to the root of the '
          'repository the current folder lies in.',
    );
    argParser.addFlag(
      'workspace',
      help:
          'Only instantiate .claude/ and CLAUDE.md — for a bare .ocean '
          'ticket workspace, not a package of its own.',
      defaultsTo: false,
      negatable: false,
    );
    argParser.addFlag(
      'quiet',
      help:
          'Do not report the instantiated files and a failed automatic '
          'commit — for a caller that prints its own summary.',
      defaultsTo: false,
      negatable: false,
    );
  }

  /// The log function.
  final GgLog ggLog;

  final DnaTestRunner _runner;

  final DnaHost _host;

  final String _workingDir;

  @override
  final name = 'build';

  @override
  final description = 'Instantiates the DNA and verifies the instances';

  // ...........................................................................
  @override
  Future<void> run() async {
    final quiet = argResults!['quiet'] as bool;
    final root = resolveTarget(
      _host,
      argResults!['target'] as String?,
      _workingDir,
      onMoved: quiet ? null : (root) => ggLog(describeRepositoryRoot(root)),
    );
    // `null` is what the placed test passes: the current folder, absolute.
    await _runner(
      targetRoot: root == '.' ? null : root,
      log: ggLog,
      workspace: argResults!['workspace'] as bool,
      quiet: quiet,
    );
  }
}
