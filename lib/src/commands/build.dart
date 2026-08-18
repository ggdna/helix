// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';

import '../engine/run_dna_test.dart';

/// Builds the DNA of a project: one instantiation plus the verification of
/// the instances — exactly what the placed test does in a project that has
/// a test framework, and the way to run the DNA cycle in one that has none.
class Build extends Command<dynamic> {
  /// Constructor. [runner] is injectable for tests.
  Build({required this.ggLog, DnaTestRunner? runner})
    : _runner = runner ?? runDnaTest {
    argParser.addOption(
      'target',
      abbr: 't',
      help: 'The project folder to build.',
      defaultsTo: '.',
    );
  }

  /// The log function.
  final GgLog ggLog;

  final DnaTestRunner _runner;

  @override
  final name = 'build';

  @override
  final description = 'Instantiates the DNA and verifies the instances';

  // ...........................................................................
  @override
  Future<void> run() async {
    final target = argResults!['target'] as String;
    // `null` is what the placed test passes: the current folder, absolute.
    await _runner(
      targetRoot: target == '.' ? null : target.replaceAll(r'\', '/'),
      log: ggLog,
    );
  }
}
