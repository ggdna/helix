// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:helix/src/util/select_prompt.dart';
import 'package:helix/src/util/select_prompt_io.dart';
import 'package:test/test.dart';

void main() {
  const options = ['Dart', 'TypeScript'];

  final written = StringBuffer();

  setUp(written.clear);

  /// A prompt that answers with [lines], one per read, then end of input.
  SelectPrompt prompt(List<String?> lines, {bool hasTerminal = true}) {
    final answers = [...lines];
    return stdinSelectPrompt(
      hasTerminal: () => hasTerminal,
      readLine: () => answers.isEmpty ? null : answers.removeAt(0),
      write: written.write,
    );
  }

  group('stdinSelectPrompt', () {
    test('defaults to the real stdin and stdout', () {
      // The io defaults are only constructed here — reading them would
      // block the test. Their coverage is ignored for that reason.
      expect(stdinSelectPrompt(), isNotNull);
    });

    test('lists the options numbered and returns the index picked', () async {
      final index = await prompt(['2'])(prompt: 'Which?', options: options);
      expect(index, 1);
      expect(
        written.toString(),
        'Which?\n'
        '  1) Dart\n'
        '  2) TypeScript\n'
        'Choose [1-2] (1): ',
      );
    });

    test('takes the first option on empty input', () async {
      expect(await prompt([''])(prompt: 'Which?', options: options), 0);
      expect(await prompt(['  '])(prompt: 'Which?', options: options), 0);
    });

    test('asks again after an answer that is not an option', () async {
      final index = await prompt(['x', '0', '3', ' 1 '])(
        prompt: 'Which?',
        options: options,
      );
      expect(index, 0);
      expect(
        'Please enter a number between 1 and 2.'.allMatches(written.toString()),
        hasLength(3),
      );
      expect('Choose [1-2] (1): '.allMatches(written.toString()), hasLength(4));
    });

    test('throws when stdin is not a terminal, without writing', () async {
      await expectLater(
        () => prompt(['1'], hasTerminal: false)(
          prompt: 'Which?',
          options: options,
        ),
        throwsA(
          isA<SelectPromptUnavailableException>().having(
            (e) => e.reason,
            'reason',
            'stdin is not a terminal',
          ),
        ),
      );
      expect(written.toString(), isEmpty);
    });

    test('throws when stdin ends before an answer', () async {
      await expectLater(
        () => prompt(['x'])(prompt: 'Which?', options: options),
        throwsA(
          isA<SelectPromptUnavailableException>().having(
            (e) => e.reason,
            'reason',
            'stdin was closed',
          ),
        ),
      );
    });
  });
}
