// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:helix/helix.dart';
import 'package:test/test.dart';

void main() {
  const root = '/p';
  const pubspec =
      'name: p\ndev_dependencies:\n  helix: ^1.0.0\n  test: ^1.0.0\n';
  const packageJson =
      '{"devDependencies": {"@tssuite/helix-js": "^0.6.0", '
      '"vitest": "^3.0.0"}}';
  const oldDartTest = '// Placed by `helix init` — instantiates the DNA\n';

  group('placeDnaCheck', () {
    test('places the Dart check in a Dart project', () {
      final host = MemoryDnaHost(files: {'$root/pubspec.yaml': pubspec});
      final result = placeDnaCheck(host, root);
      expect(result.placed, [dartDnaCheckPath]);
      expect(host.readString('$root/$dartDnaCheckPath'), dartWrapperTest);
      expect(dartWrapperTest, contains('    checkDna,\n'));
      expect(dartWrapperTest, isNot(contains('() => checkDna()')));
      expect(dartWrapperTest, isNot(contains('runDnaTest')));
    });

    test('places the vitest check in a TypeScript project', () {
      final host = MemoryDnaHost(files: {'$root/package.json': packageJson});
      final result = placeDnaCheck(host, root);
      expect(result.placed, [tsDnaCheckPath]);
      expect(host.readString('$root/$tsDnaCheckPath'), tsWrapperTest);
      expect(tsWrapperTest, contains('checkDna()'));
      expect(host.existsFile('$root/$dartDnaCheckPath'), isFalse);
    });

    test('a pubspec.yaml makes a Dart project, even next to package.json', () {
      final host = MemoryDnaHost(
        files: {
          '$root/pubspec.yaml': pubspec,
          '$root/package.json': packageJson,
          '$root/$tsDnaCheckPath': tsWrapperTest,
        },
      );
      final result = placeDnaCheck(host, root);
      expect(result.placed, [dartDnaCheckPath]);
      expect(result.removed, [tsDnaCheckPath]);
      expect(host.existsFile('$root/$tsDnaCheckPath'), isFalse);
    });

    test('replaces an older check and leaves a current one alone', () {
      final host = MemoryDnaHost(
        files: {
          '$root/pubspec.yaml': pubspec,
          '$root/$dartDnaCheckPath': oldDartTest,
        },
      );
      expect(placeDnaCheck(host, root).placed, [dartDnaCheckPath]);
      expect(host.readString('$root/$dartDnaCheckPath'), dartWrapperTest);
      expect(placeDnaCheck(host, root).placed, isEmpty);
    });

    test('keeps a test of the other language that helix did not place', () {
      const own = '// my own spec\n';
      final host = MemoryDnaHost(
        files: {'$root/pubspec.yaml': pubspec, '$root/$tsDnaCheckPath': own},
      );
      expect(placeDnaCheck(host, root).removed, isEmpty);
      expect(host.readString('$root/$tsDnaCheckPath'), own);
    });

    test('removes a Dart check from a TypeScript project', () {
      final host = MemoryDnaHost(
        files: {
          '$root/package.json': packageJson,
          '$root/$dartDnaCheckPath': oldDartTest,
        },
      );
      expect(placeDnaCheck(host, root).removed, [dartDnaCheckPath]);
    });

    test('places nothing without a test framework', () {
      final dart = MemoryDnaHost(
        files: {
          '$root/pubspec.yaml': 'name: p\ndev_dependencies:\n  helix: ^1.0.0\n',
        },
      );
      expect(placeDnaCheck(dart, root).placed, isEmpty);
      final node = MemoryDnaHost(
        files: {
          '$root/package.json':
              '{"devDependencies": {"@tssuite/helix-js": "^0.6.0"}}',
        },
      );
      expect(placeDnaCheck(node, root).placed, isEmpty);
    });

    test('names the dependency a check lacks', () {
      String? missing(Map<String, String> files) =>
          placeDnaCheck(MemoryDnaHost(files: files), root).missing;
      expect(missing({'$root/pubspec.yaml': pubspec}), isNull);
      expect(missing({'$root/pubspec.yaml': 'name: p\n'}), 'helix');
      expect(
        missing({
          '$root/pubspec.yaml': 'name: p\ndev_dependencies:\n  helix: ^1.0.0\n',
        }),
        'test',
      );
      expect(missing({'$root/package.json': packageJson}), isNull);
      expect(missing({'$root/package.json': '{}'}), '@tssuite/helix-js');
      expect(
        missing({
          '$root/package.json':
              '{"devDependencies": {"@tssuite/helix-js": "^0.6.0"}}',
        }),
        'vitest',
      );
      expect(missing({}), isNull);
    });

    test('places nothing without helix', () {
      final dart = MemoryDnaHost(
        files: {
          '$root/pubspec.yaml': 'name: p\ndev_dependencies:\n  test: ^1.0.0\n',
        },
      );
      expect(placeDnaCheck(dart, root).placed, isEmpty);
      final node = MemoryDnaHost(
        files: {
          '$root/package.json': '{"devDependencies": {"vitest": "^3.0.0"}}',
        },
      );
      expect(placeDnaCheck(node, root).placed, isEmpty);
    });

    test('removes a check it placed once helix is gone', () {
      final dart = MemoryDnaHost(
        files: {
          '$root/pubspec.yaml': 'name: p\ndev_dependencies:\n  test: ^1.0.0\n',
          '$root/$dartDnaCheckPath': dartWrapperTest,
        },
      );
      expect(placeDnaCheck(dart, root).removed, [dartDnaCheckPath]);
      final node = MemoryDnaHost(
        files: {
          '$root/package.json': '{"devDependencies": {"vitest": "^3.0.0"}}',
          '$root/$tsDnaCheckPath': tsWrapperTest,
        },
      );
      expect(placeDnaCheck(node, root).removed, [tsDnaCheckPath]);
    });

    test('keeps an own test where helix is gone', () {
      const own = '// my own dna test\n';
      final host = MemoryDnaHost(
        files: {
          '$root/pubspec.yaml': 'name: p\ndev_dependencies:\n  test: ^1.0.0\n',
          '$root/$dartDnaCheckPath': own,
        },
      );
      expect(placeDnaCheck(host, root).removed, isEmpty);
      expect(host.readString('$root/$dartDnaCheckPath'), own);
    });

    test('places the Flutter check where flutter_test is the only test '
        'framework', () {
      final host = MemoryDnaHost(
        files: {
          '$root/pubspec.yaml':
              'name: p\ndependencies:\n  flutter:\n    sdk: flutter\n'
              'dev_dependencies:\n  flutter_test:\n    sdk: flutter\n'
              '  helix: ^1.0.0\n',
        },
      );
      expect(placeDnaCheck(host, root).placed, [dartDnaCheckPath]);
      expect(host.readString('$root/$dartDnaCheckPath'), flutterWrapperTest);
      expect(flutterWrapperTest, contains('package:flutter_test/'));
      expect(flutterWrapperTest, isNot(contains('package:test/')));
    });
  });
}
