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
    test('runs a process and reports its output', () {
      final result = ioProcessRun(Platform.resolvedExecutable, [
        '--version',
      ], workingDirectory: Directory.current.path);
      expect(result.isSuccess, isTrue);
      expect(result.exitCode, 0);
      expect('${result.stdout}${result.stderr}', contains('Dart'));
    });

    test('reports a non-zero exit code', () {
      final result = ioProcessRun(Platform.resolvedExecutable, [
        'run',
        'no_such_file_5a3f.dart',
      ], workingDirectory: Directory.current.path);
      expect(result.isSuccess, isFalse);
      expect(result.failureOutput, isNotEmpty);
    });

    test('reports a missing executable instead of throwing', () {
      final result = ioProcessRun('helix_no_such_executable_5a3f', const [
        '--version',
      ], workingDirectory: Directory.current.path);
      expect(result.exitCode, missingExecutableExitCode);
      expect(result.failureOutput, contains('could not be started'));
    });
  });
}
