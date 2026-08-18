// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:helix/src/util/dna_fs.dart';
import 'package:helix/src/util/package_managers.dart';
import 'package:test/test.dart';

void main() {
  const root = '/p';

  group('NodePackageManager', () {
    test('the enum name is the executable', () {
      expect(NodePackageManager.pnpm.executable, 'pnpm');
      expect(NodePackageManager.yarn.executable, 'yarn');
      expect(NodePackageManager.npm.executable, 'npm');
    });

    test('addDevArgs speaks each manager s dialect', () {
      expect(NodePackageManager.pnpm.addDevArgs('a'), ['add', '-D', 'a']);
      expect(NodePackageManager.yarn.addDevArgs('a'), ['add', '-D', 'a']);
      expect(NodePackageManager.npm.addDevArgs('a'), ['install', '-D', 'a']);
    });
  });

  group('detectNodePackageManager', () {
    test('falls back to npm — it ships with node', () {
      final host = MemoryDnaHost(files: {'$root/package.json': '{}'});
      expect(detectNodePackageManager(host, root), NodePackageManager.npm);
    });

    test('reads the packageManager field', () {
      for (final manager in NodePackageManager.values) {
        final host = MemoryDnaHost(
          files: {
            '$root/package.json': '{"packageManager": "${manager.name}@1"}',
          },
        );
        expect(detectNodePackageManager(host, root), manager);
      }
    });

    test('ignores an unknown packageManager field', () {
      final host = MemoryDnaHost(
        files: {'$root/package.json': '{"packageManager": "bun@1.0.0"}'},
      );
      expect(detectNodePackageManager(host, root), NodePackageManager.npm);
    });

    test('ignores a non-string packageManager field', () {
      final host = MemoryDnaHost(
        files: {
          '$root/package.json': '{"packageManager": 3}',
          '$root/pnpm-lock.yaml': '',
        },
      );
      expect(detectNodePackageManager(host, root), NodePackageManager.pnpm);
    });

    test('reads the lock files', () {
      final pnpm = MemoryDnaHost(files: {'$root/pnpm-lock.yaml': ''});
      expect(detectNodePackageManager(pnpm, root), NodePackageManager.pnpm);

      final yarn = MemoryDnaHost(files: {'$root/yarn.lock': ''});
      expect(detectNodePackageManager(yarn, root), NodePackageManager.yarn);

      final npm = MemoryDnaHost(files: {'$root/package-lock.json': ''});
      expect(detectNodePackageManager(npm, root), NodePackageManager.npm);
    });
  });

  group('readPackageJson', () {
    test('returns the decoded document', () {
      final host = MemoryDnaHost(
        files: {'$root/package.json': '{"name": "a"}'},
      );
      expect(readPackageJson(host, root)!['name'], 'a');
    });

    test('returns null without a package.json', () {
      expect(readPackageJson(MemoryDnaHost(), root), isNull);
    });

    test('returns null for a broken package.json', () {
      final host = MemoryDnaHost(files: {'$root/package.json': '{'});
      expect(readPackageJson(host, root), isNull);
    });

    test('returns null when the document is not a map', () {
      final host = MemoryDnaHost(files: {'$root/package.json': '[]'});
      expect(readPackageJson(host, root), isNull);
    });
  });

  group('readPubspec', () {
    test('returns the decoded document', () {
      final host = MemoryDnaHost(files: {'$root/pubspec.yaml': 'name: a'});
      expect(readPubspec(host, root)!['name'], 'a');
    });

    test('returns null without a pubspec.yaml', () {
      expect(readPubspec(MemoryDnaHost(), root), isNull);
    });

    test('returns null for a broken pubspec.yaml', () {
      final host = MemoryDnaHost(files: {'$root/pubspec.yaml': '\tname: [a'});
      expect(readPubspec(host, root), isNull);
    });

    test('returns null when the document is not a map', () {
      final host = MemoryDnaHost(files: {'$root/pubspec.yaml': '- a'});
      expect(readPubspec(host, root), isNull);
    });
  });

  group('declaresNodeDependency', () {
    test('finds dependencies and devDependencies', () {
      final host = MemoryDnaHost(
        files: {
          '$root/package.json':
              '{"dependencies": {"a": "1"}, "devDependencies": {"b": "2"}}',
        },
      );
      expect(declaresNodeDependency(host, root, 'a'), isTrue);
      expect(declaresNodeDependency(host, root, 'b'), isTrue);
      expect(declaresNodeDependency(host, root, 'c'), isFalse);
    });

    test('is false without a package.json', () {
      expect(declaresNodeDependency(MemoryDnaHost(), root, 'a'), isFalse);
    });

    test('ignores a section that is not a map', () {
      final host = MemoryDnaHost(
        files: {'$root/package.json': '{"dependencies": "a"}'},
      );
      expect(declaresNodeDependency(host, root, 'a'), isFalse);
    });
  });

  group('declaresPubDependency', () {
    test('finds dependencies and dev_dependencies', () {
      final host = MemoryDnaHost(
        files: {
          '$root/pubspec.yaml':
              'name: x\ndependencies:\n  a: ^1.0.0\n'
              'dev_dependencies:\n  b: ^2.0.0\n',
        },
      );
      expect(declaresPubDependency(host, root, 'a'), isTrue);
      expect(declaresPubDependency(host, root, 'b'), isTrue);
      expect(declaresPubDependency(host, root, 'c'), isFalse);
    });

    test('is false without a pubspec.yaml', () {
      expect(declaresPubDependency(MemoryDnaHost(), root, 'a'), isFalse);
    });
  });

  group('isFlutterProject', () {
    test('is true for a flutter section', () {
      final host = MemoryDnaHost(
        files: {
          '$root/pubspec.yaml':
              'name: x\nflutter:\n  uses-material-design: true\n',
        },
      );
      expect(isFlutterProject(host, root), isTrue);
      expect(pubExecutable(host, root), 'flutter');
    });

    test('is true for a dependency on the Flutter SDK', () {
      final host = MemoryDnaHost(
        files: {
          '$root/pubspec.yaml':
              'name: x\ndependencies:\n  flutter:\n    sdk: flutter\n',
        },
      );
      expect(isFlutterProject(host, root), isTrue);
    });

    test('is false for a plain Dart package', () {
      final host = MemoryDnaHost(files: {'$root/pubspec.yaml': 'name: x'});
      expect(isFlutterProject(host, root), isFalse);
      expect(pubExecutable(host, root), 'dart');
    });

    test('is false when there is no pubspec at all', () {
      expect(isFlutterProject(MemoryDnaHost(), root), isFalse);
    });

    test('ignores a dependencies section that is not a map', () {
      final host = MemoryDnaHost(
        files: {'$root/pubspec.yaml': 'name: x\ndependencies: none\n'},
      );
      expect(isFlutterProject(host, root), isFalse);
    });
  });

  group('pubAddDevArgs', () {
    test('adds to the dev dependencies', () {
      expect(pubAddDevArgs('helix'), ['pub', 'add', 'dev:helix']);
    });
  });
}
