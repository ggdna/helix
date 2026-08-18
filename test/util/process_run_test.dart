// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:helix/src/util/process_run.dart';
import 'package:test/test.dart';

void main() {
  group('ProcessRunResult', () {
    test('exit code 0 is a success', () {
      const result = ProcessRunResult(exitCode: 0, stdout: 'done');
      expect(result.isSuccess, isTrue);
      expect(result.stdout, 'done');
      expect(result.stderr, isEmpty);
    });

    test('any other exit code is a failure', () {
      const result = ProcessRunResult(exitCode: 1);
      expect(result.isSuccess, isFalse);
    });

    group('failureOutput', () {
      test('is stderr when there is one', () {
        const result = ProcessRunResult(
          exitCode: 1,
          stdout: 'progress',
          stderr: '  boom\n',
        );
        expect(result.failureOutput, 'boom');
      });

      test('falls back to stdout — package managers use both', () {
        const result = ProcessRunResult(
          exitCode: 1,
          stdout: 'ERR! nope\n',
          stderr: '   ',
        );
        expect(result.failureOutput, 'ERR! nope');
      });

      test('is empty when the process said nothing', () {
        const result = ProcessRunResult(exitCode: 1);
        expect(result.failureOutput, isEmpty);
      });
    });
  });
}
