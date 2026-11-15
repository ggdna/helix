// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';

import '../engine/dna_check_wrapper.dart';
import '../engine/run_dna_test.dart';
import '../util/dna_fs.dart';
import '../util/dna_fs_io.dart';
import '../util/git_root.dart';
import '../util/plain_errors.dart';

/// Brings a project to the current DNA: places the newest DNA check —
/// the Dart check in a Dart project, the vitest check in a TypeScript
/// project — and instantiates the DNA of the installed layers, like
/// `helix build`.
class Upgrade extends Command<dynamic> {
  /// Constructor. [runner], [host] and `workingDir` — the folder the
  /// repository root is searched from, the current one by default — are
  /// injectable for tests.
  Upgrade({
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
          'The project folder to upgrade. Defaults to the root of the '
          'repository the current folder lies in.',
    );
    argParser.addFlag(
      'quiet',
      help:
          'Do not report the placed check, the instantiated files and a '
          'failed automatic commit — for a caller that prints its own '
          'summary.',
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
  final name = 'upgrade';

  @override
  final description =
      'Places the newest DNA check and instantiates the DNA of the '
      'installed layers';

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
    final check = placeDnaCheck(_host, root);
    if (!quiet) {
      for (final path in check.placed) {
        ggLog(cDetail('✓ Placed $path'));
      }
      for (final path in check.removed) {
        ggLog(cDetail('✓ Removed $path'));
      }
    }
    await withPlainFormatErrors(
      () => _runner(
        targetRoot: root == '.' ? null : root,
        log: ggLog,
        quiet: quiet,
      ),
    );
  }
}
