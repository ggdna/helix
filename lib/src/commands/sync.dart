// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';

/// Migration stub: `helix sync` was replaced by `helix init` — the
/// instantiation itself runs inside the placed test.
class Sync extends Command<dynamic> {
  /// Constructor.
  Sync({required this.ggLog});

  /// The log function.
  final GgLog ggLog;

  @override
  final name = 'sync';

  @override
  final description =
      'Removed since helix 5.0 — run `helix init` once; instantiation '
      'runs in your tests.';

  // ...........................................................................
  @override
  Future<void> run() async {
    usageException(
      'helix sync was removed in helix 5.0. Run `helix init` once — '
      'the placed test instantiates the DNAs declared as '
      'dev-dependencies on every test run.',
    );
  }
}
