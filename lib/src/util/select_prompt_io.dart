// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'select_prompt.dart';

/// Whether stdin is attached to a terminal.
typedef HasTerminal = bool Function();

/// Reads one line from stdin; `null` at end of input.
typedef ReadLine = String? Function();

/// Writes [text] to the terminal, no newline appended.
typedef Write = void Function(String text);

// coverage:ignore-start
bool _stdinHasTerminal() => stdin.hasTerminal;
String? _stdinReadLine() => stdin.readLineSync();
void _stdoutWrite(String text) => stdout.write(text);
// coverage:ignore-end

/// A [SelectPrompt] that asks on the terminal: a numbered list on stdout,
/// the answer as a number on stdin. Empty input takes the first option.
///
/// Together with `dna_fs_io.dart` and `process_run_io.dart` one of the
/// bindings of this package to the real platform. Deliberately plain —
/// the arrow-key menus of the gg suite come from `package:interact`,
/// which reaches `dart:ffi` and would keep helix out of a wasm build.
/// `gg` injects those menus from outside instead.
///
/// [hasTerminal], [readLine] and [write] replace stdin and stdout in
/// tests — `dart test` hands the test isolate a stdin whose `hasTerminal`
/// differs per platform, so the check must be injected, not observed.
SelectPrompt stdinSelectPrompt({
  HasTerminal hasTerminal = _stdinHasTerminal,
  ReadLine readLine = _stdinReadLine,
  Write write = _stdoutWrite,
}) => ({required String prompt, required List<String> options}) async {
  if (!hasTerminal()) {
    throw const SelectPromptUnavailableException('stdin is not a terminal');
  }

  write('$prompt\n');
  for (var i = 0; i < options.length; i++) {
    write('  ${i + 1}) ${options[i]}\n');
  }

  while (true) {
    write('Choose [1-${options.length}] (1): ');
    final line = readLine();
    if (line == null) {
      throw const SelectPromptUnavailableException('stdin was closed');
    }
    final answer = line.trim();
    if (answer.isEmpty) return 0;
    final number = int.tryParse(answer);
    if (number != null && number >= 1 && number <= options.length) {
      return number - 1;
    }
    write('Please enter a number between 1 and ${options.length}.\n');
  }
};
