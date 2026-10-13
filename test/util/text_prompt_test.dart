// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:helix/helix.dart';
import 'package:test/test.dart';

void main() {
  /// Asks [prompt] the way `helix init` does.
  Future<String> ask(TextPrompt prompt, {String? defaultValue}) =>
      prompt(prompt: 'dnaOrg', defaultValue: defaultValue);

  group('TextPrompt', () {
    test('is exported for gg to inject its own prompt', () async {
      Future<String> fallback({
        required String prompt,
        String? defaultValue,
      }) async => defaultValue ?? prompt;

      expect(await ask(fallback, defaultValue: 'acme'), 'acme');
      expect(await ask(fallback), 'dnaOrg');
    });
  });
}
