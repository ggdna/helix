// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';

import '../engine/run_dna_test.dart';
import '../util/dna_fs.dart';

/// Signature of [runDnaTest] — the seam that lets [Test] be tested
/// without a project on disk.
typedef DnaTestRunner = Future<void> Function({
  String? targetRoot,
  DnaHost? host,
  String? baseDnaRoot,
  void Function(String message)? log,
});

// .............................................................................
/// Runs one DNA instantiation and verification from the command line —
/// exactly what the placed test does in a project that has a test
/// framework, and the way to run the DNA cycle in a project that has none.
class Test extends Command<dynamic> {
  /// Constructor. [runner] is injectable for tests.
  Test({required this.ggLog, DnaTestRunner? runner})
    : _runner = runner ?? runDnaTest {
    argParser.addOption(
      'target',
      abbr: 't',
      help: 'The project folder to instantiate.',
      defaultsTo: '.',
    );
  }

  /// The log function.
  final GgLog ggLog;

  final DnaTestRunner _runner;

  @override
  final name = 'test';

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
