// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:helix/src/util/process_run.dart';
import 'package:helix/src/util/process_run_io.dart';
import 'package:test/test.dart';

void main() {
  group('ioProcessRun', () {
    test('runs a process and reports its output', () async {
      final result = await ioProcessRun(Platform.resolvedExecutable, [
        '--version',
      ], workingDirectory: Directory.current.path);
      expect(result.isSuccess, isTrue);
      expect(result.exitCode, 0);
      expect('${result.stdout}${result.stderr}', contains('Dart'));
    });

    test('reports a non-zero exit code', () async {
      final result = await ioProcessRun(Platform.resolvedExecutable, [
        'run',
        'no_such_file_5a3f.dart',
      ], workingDirectory: Directory.current.path);
      expect(result.isSuccess, isFalse);
      expect(result.failureOutput, isNotEmpty);
    });

    test('reports a missing executable instead of throwing', () async {
      final result = await ioProcessRun('helix_no_such_executable_5a3f', const [
        '--version',
      ], workingDirectory: Directory.current.path);

      // Either way the caller gets a failure it can report, never a throw.
      expect(result.isSuccess, isFalse);
      expect(result.failureOutput, isNotEmpty);

      if (Platform.isWindows) {
        // Windows runs through a shell, because npm and friends are .cmd
        // shims there. The shell — not dart:io — reports the missing
        // command, so the exit code is the shell's, not ours.
        expect(result.exitCode, isNot(0));
      } else {
        // Elsewhere dart:io throws and the run maps it to our own code.
        expect(result.exitCode, missingExecutableExitCode);
        expect(result.failureOutput, contains('could not be started'));
      }
    });

    test(
      'maps a process that cannot start at all to our own exit code',
      () async {
        // A working directory that does not exist makes dart:io throw on
        // every platform — including Windows, where a missing command
        // alone is swallowed by the shell.
        final result = await ioProcessRun(Platform.resolvedExecutable, const [
          '--version',
        ], workingDirectory: 'helix_no_such_directory_5a3f');
        expect(result.isSuccess, isFalse);
        expect(result.exitCode, missingExecutableExitCode);
        expect(result.failureOutput, contains('could not be started'));
      },
    );
  });
}
