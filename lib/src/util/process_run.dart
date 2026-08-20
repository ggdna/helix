// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

/// Exit code reported when the executable itself could not be started —
/// the shell convention for »command not found«. `Process.runSync` throws
/// in that case instead of returning a code, and a missing `pnpm` is a
/// normal outcome `helix init` reports rather than a crash.
const int missingExecutableExitCode = 127;

/// What a finished process reported.
class ProcessRunResult {
  /// Creates the result.
  const ProcessRunResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });

  /// Exit code of the process, [missingExecutableExitCode] when it could
  /// not be started at all.
  final int exitCode;

  /// What the process wrote to stdout.
  final String stdout;

  /// What the process wrote to stderr.
  final String stderr;

  /// Whether the process succeeded.
  bool get isSuccess => exitCode == 0;

  /// What to show after a failure: stderr, or stdout when stderr is empty
  /// — package managers report on either channel.
  String get failureOutput => (stderr.trim().isEmpty ? stdout : stderr).trim();
}

/// Runs [executable] with [args] in [workingDirectory].
///
/// The seam that keeps the process calls of `helix init` — `npm init`,
/// `pnpm add`, `dart pub add` — out of the tests and out of the engine:
/// the engine core never runs a process, and the command layer gets its
/// runner injected.
///
/// Asynchronous so the default implementation can route through
/// `package:gg_process`'s `GgProcessDelegate` — the seam that keeps this
/// package working under `dart compile wasm`, where `Process.runSync`
/// throws.
typedef ProcessRun = Future<ProcessRunResult> Function(
  String executable,
  List<String> args, {
  required String workingDirectory,
});
