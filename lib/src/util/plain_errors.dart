// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

/// Runs [run] and reports a [FormatException] as a plain [Exception] with
/// the same message and stack trace.
///
/// The command runner strips »Exception: « from what it prints, which
/// turns a FormatException into a message starting with »Format«. The
/// configuration errors of helix are written for a person to read, so
/// every command reports them through here.
Future<T> withPlainFormatErrors<T>(Future<T> Function() run) async {
  try {
    return await run();
  } on FormatException catch (e, stack) {
    Error.throwWithStackTrace(Exception(e.message), stack);
  }
}
