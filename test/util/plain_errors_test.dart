// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:helix/src/util/plain_errors.dart';
import 'package:test/test.dart';

void main() {
  group('withPlainFormatErrors', () {
    test('returns what the body returns', () async {
      expect(await withPlainFormatErrors(() async => 42), 42);
    });

    test('turns a FormatException into a plain Exception', () async {
      await expectLater(
        () => withPlainFormatErrors<void>(
          () async => throw const FormatException('broken config'),
        ),
        throwsA(
          isA<Exception>()
              .having((e) => e, 'type', isNot(isA<FormatException>()))
              .having((e) => '$e', 'message', 'Exception: broken config'),
        ),
      );
    });

    test('lets every other error through unchanged', () async {
      await expectLater(
        () => withPlainFormatErrors<void>(() async => throw StateError('x')),
        throwsStateError,
      );
    });
  });
}
