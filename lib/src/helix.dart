// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';

import 'commands/init.dart';

/// The command line interface for Helix
class Helix extends Command<dynamic> {
  /// Constructor
  Helix({required this.ggLog}) {
    addSubcommand(Init(ggLog: ggLog));
  }

  /// The log function
  final GgLog ggLog;

  // ...........................................................................
  @override
  final name = 'helix';
  @override
  final description =
      'The DNA engine — resolves the DNA packages declared as '
      'dev-dependencies (dna_base, dna_dart, dna-ts, …) and instantiates '
      'their content into this repo. Run `helix init` once; the placed '
      'test keeps the project in sync.';
}
