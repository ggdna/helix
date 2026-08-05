// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';

import 'commands/init.dart';
import 'commands/sync.dart';

/// The command line interface for GgDna
class GgDna extends Command<dynamic> {
  /// Constructor
  GgDna({required this.ggLog}) {
    addSubcommand(Init(ggLog: ggLog));
    addSubcommand(Sync(ggLog: ggLog));
  }

  /// The log function
  final GgLog ggLog;

  // ...........................................................................
  @override
  final name = 'ggDna';
  @override
  final description = 'The DNA engine — resolves the DNA packages declared as '
      'dev-dependencies (base_dna, dna_dart, dna-ts, …) and instantiates '
      'their content into this repo. Run `gg_dna init` once; the placed '
      'test keeps the project in sync.';
}
