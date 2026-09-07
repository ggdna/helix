// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:helix/helix.dart';
import 'package:test/test.dart';

void main() {
  group('SelectPromptUnavailableException', () {
    test('carries the reason and names itself', () {
      const e = SelectPromptUnavailableException('no terminal');
      expect(e.reason, 'no terminal');
      expect(e.toString(), 'SelectPromptUnavailableException: no terminal');
    });
  });
}
