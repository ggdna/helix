// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io' show ProcessException;

import 'package:gg_process/gg_process.dart';

import 'process_run.dart';

/// [ProcessRun] backed by `package:gg_process` — together with
/// `dna_fs_io.dart` the only binding of this package to the real platform.
///
/// Routes through [GgProcessDelegate.current] and
/// [GgPlatformDelegate.current] rather than calling `dart:io`'s `Process`
/// and `Platform` directly, so this also works when `helix` runs inside
/// `gg` compiled with `dart compile wasm` — `Process.runSync` and
/// `Platform.isWindows` throw `UnsupportedError` there, the delegates do
/// not.
///
/// A missing executable is reported as [missingExecutableExitCode] instead
/// of thrown: on Windows `npm`, `pnpm` and `yarn` are `.cmd` shims, which
/// is also why the run goes through a shell there.
Future<ProcessRunResult> ioProcessRun(
  String executable,
  List<String> args, {
  required String workingDirectory,
}) async {
  try {
    final result = await ggRunProcess(
      executable,
      args,
      workingDirectory: workingDirectory,
      runInShell: GgPlatformDelegate.current.isWindows,
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
