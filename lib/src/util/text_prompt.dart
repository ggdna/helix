// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'select_prompt.dart';

/// Thrown by any prompt of helix — select or text — that cannot ask its
/// question. One type for both, so a caller injecting its own prompts
/// signals "nobody to ask" the same way everywhere.
typedef PromptUnavailableException = SelectPromptUnavailableException;

/// Asks the user for a line of text and returns the answer, never empty.
/// [defaultValue], when given, is what an empty answer takes.
///
/// The seam for the values `helix init` and `helix add` ask for — the
/// variables a layer marks `mustOverride` — kept out of the tests and the
/// engine the same way [SelectPrompt] is.
///
/// Throws [PromptUnavailableException] when there is nobody to ask.
typedef TextPrompt = Future<String> Function({
  required String prompt,
  String? defaultValue,
});
