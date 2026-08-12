// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:helix/src/commands/sync.dart';
import 'package:test/test.dart';

void main() {
  group('Sync', () {
    final messages = <String>[];

    setUp(messages.clear);

    CommandRunner<dynamic> makeRunner() =>
        CommandRunner<dynamic>('test', 'test')
          ..addCommand(Sync(ggLog: messages.add));

    test('fails with the helix init migration hint', () async {
      await expectLater(
        () => makeRunner().run(['sync']),
        throwsA(
          isA<UsageException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('removed in helix 5.0'),
              contains('helix init'),
              contains('dev-dependencies'),
            ),
          ),
        ),
      );
      expect(messages, isEmpty);
    });

    test('describes itself as removed', () {
      final sync = Sync(ggLog: messages.add);
      expect(sync.name, 'sync');
      expect(sync.description, contains('Removed since helix 5.0'));
    });
  });
}
