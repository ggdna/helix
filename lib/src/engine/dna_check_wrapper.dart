// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import '../util/dna_fs.dart';
import '../util/package_managers.dart';

/// Project path of the placed Dart check.
const String dartDnaCheckPath = 'test/dna/dna_test.dart';

/// Project path of the placed vitest check.
const String tsDnaCheckPath = 'test/dna/dna.spec.ts';

/// First line of every check helix places — marks a file helix may
/// replace or remove.
const String dnaCheckMarker = '// Placed by `helix';

/// Content of the placed Dart check.
const String dartWrapperTest = '''
// Placed by `helix init` and `helix upgrade` — checks on every test run
// that the files this project's DNA generated are unchanged. It writes
// nothing; `gg dna build` applies DNA updates.

import 'package:helix/helix.dart';
import 'package:test/test.dart';

void main() {
  test(
    'generated dna files are unchanged',
    checkDna,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
''';

/// Content of the placed Dart check in a Flutter project, which tests
/// with `flutter_test` instead of `test`.
const String flutterWrapperTest = '''
// Placed by `helix init` and `helix upgrade` — checks on every test run
// that the files this project's DNA generated are unchanged. It writes
// nothing; `gg dna build` applies DNA updates.

import 'package:flutter_test/flutter_test.dart';
import 'package:helix/helix.dart';

void main() {
  test(
    'generated dna files are unchanged',
    checkDna,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
''';

/// The Flutter test package the placed Flutter check imports.
const String flutterTestPackage = 'flutter_test';

/// Content of the placed vitest check.
const String tsWrapperTest = '''
// Placed by `helix init` and `helix upgrade` — checks on every test run
// that the files this project's DNA generated are unchanged. It writes
// nothing; `gg dna build` applies DNA updates.

import { checkDna } from '@tssuite/helix-js';
import { test } from 'vitest';

test(
  'generated dna files are unchanged',
  async () => {
    await checkDna();
  },
  120000,
);
''';

/// The checks [placeDnaCheck] wrote and removed, project-relative, and the
/// dependency the project lacks for a check — `null` when it has a check
/// or has no manifest at all.
typedef DnaCheckPlacement = ({
  List<String> placed,
  List<String> removed,
  String? missing,
});

// .............................................................................
/// Places the DNA check of the project in [root], replacing an older one.
///
/// A project with a `pubspec.yaml` is a Dart project and gets the Dart
/// check — the Flutter variant when it tests with `flutter_test` only; one
/// with only a `package.json` gets the vitest check. The check runs the
/// engine the project depends on, so it is placed only where the project
/// declares it (`helix`, or `@tssuite/helix-js`) next to its test framework
/// (`test` or `flutter_test`, or `vitest`) — anything else is a project
/// shape, not a problem. A check helix placed earlier that no longer fits
/// the project is removed.
DnaCheckPlacement placeDnaCheck(DnaHost host, String root) {
  final placed = <String>[];
  final removed = <String>[];
  final isDart = host.existsFile('$root/pubspec.yaml');
  final isNode = !isDart && host.existsFile('$root/package.json');

  void place(String path, String content) {
    final full = '$root/$path';
    if (host.existsFile(full) && host.readString(full) == content) return;
    host.writeString(full, content);
    placed.add(path);
  }

  void remove(String path) {
    final full = '$root/$path';
    if (!host.existsFile(full)) return;
    if (!host.readString(full).startsWith(dnaCheckMarker)) return;
    host.deleteFile(full);
    removed.add(path);
  }

  String? missing;
  if (isDart) {
    final String? content;
    if (declaresPubDependency(host, root, dartTestPackage)) {
      content = dartWrapperTest;
    } else if (declaresPubDependency(host, root, flutterTestPackage)) {
      content = flutterWrapperTest;
    } else {
      content = null;
    }
    if (!declaresPubDependency(host, root, helixPubPackage)) {
      missing = helixPubPackage;
    } else if (content == null) {
      missing = dartTestPackage;
    }
    if (missing == null) {
      place(dartDnaCheckPath, content!);
    } else {
      remove(dartDnaCheckPath);
    }
    remove(tsDnaCheckPath);
  } else if (isNode) {
    if (!declaresNodeDependency(host, root, helixNodePackage)) {
      missing = helixNodePackage;
    } else if (!declaresNodeDependency(host, root, nodeTestPackage)) {
      missing = nodeTestPackage;
    }
    if (missing == null) {
      place(tsDnaCheckPath, tsWrapperTest);
    } else {
      remove(tsDnaCheckPath);
    }
    remove(dartDnaCheckPath);
  }
  return (placed: placed, removed: removed, missing: missing);
}
