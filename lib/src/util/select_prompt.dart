// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

/// Lets the user pick one of [options] and returns the index picked.
///
/// The seam that keeps the one question `helix init` asks — Dart or
/// TypeScript, in a folder that has neither manifest — out of the tests
/// and out of the engine: the command layer gets its prompt injected, the
/// way it gets its process runner. `gg` answers through its own prompts,
/// so `gg dna init` draws the same menu as the rest of the gg suite.
///
/// Throws [SelectPromptUnavailableException] when there is nobody to ask —
/// stdin is not a terminal, say. The caller then reports how to answer
/// on the command line instead.
typedef SelectPrompt = Future<int> Function({
  required String prompt,
  required List<String> options,
});

/// Thrown by a [SelectPrompt] that cannot ask its question.
class SelectPromptUnavailableException implements Exception {
  /// Creates the exception. [reason] says why the prompt cannot be shown.
  const SelectPromptUnavailableException(this.reason);

  /// Why the prompt cannot be shown.
  final String reason;

  @override
  String toString() => 'SelectPromptUnavailableException: $reason';
}
