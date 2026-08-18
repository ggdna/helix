// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'process_run.dart';

/// [ProcessRun] backed by `dart:io` — together with `dna_fs_io.dart` the
/// only binding of this package to the real platform.
///
/// A missing executable is reported as [missingExecutableExitCode] instead
/// of thrown: on Windows `npm`, `pnpm` and `yarn` are `.cmd` shims, which
/// is also why the run goes through a shell there.
ProcessRunResult ioProcessRun(
  String executable,
  List<String> args, {
  required String workingDirectory,
}) {
  try {
    final result = Process.runSync(
      executable,
      args,
      workingDirectory: workingDirectory,
      runInShell: Platform.isWindows,
    );
    return ProcessRunResult(
      exitCode: result.exitCode,
      stdout: '${result.stdout}',
      stderr: '${result.stderr}',
    );
  } on ProcessException catch (e) {
    return ProcessRunResult(
      exitCode: missingExecutableExitCode,
      stderr: '${e.executable} could not be started: ${e.message}',
    );
  }
}
