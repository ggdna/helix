// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';

import 'commands/add.dart';
import 'commands/build.dart';
import 'commands/init.dart';
import 'util/select_prompt.dart';

export 'util/select_prompt.dart';

/// The command line interface for Helix
class Helix extends Command<dynamic> {
  /// Constructor. [selectPrompt] replaces the plain terminal prompt of
  /// `init` — `gg` passes its own menus here.
  Helix({required this.ggLog, SelectPrompt? selectPrompt}) {
    addSubcommand(Add(ggLog: ggLog));
    addSubcommand(Init(ggLog: ggLog, selectPrompt: selectPrompt));
    addSubcommand(Build(ggLog: ggLog));
  }

  /// The log function
  final GgLog ggLog;

  // ...........................................................................
  @override
  final name = 'helix';
  @override
  final description =
      'The DNA engine — resolves the DNA packages declared as '
      'dev-dependencies (dna_guides, dna_dart, dna-ts, …) and instantiates '
      'their content into this repo. Run `helix init` once; from then on '
      'the placed test — or `helix build` — keeps the project in sync.';
}
