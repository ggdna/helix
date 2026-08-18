// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';

import 'package:yaml/yaml.dart';

import 'dna_fs.dart';

/// The npm package that runs the DNA engine in node projects: helix
/// compiled to WebAssembly. This is the name the placed vitest spec
/// imports from, and the one published to npm — plain `@tssuite/helix`
/// does not exist there.
const String helixNodePackage = '@tssuite/helix-js';

/// The pub package that runs the DNA engine in Dart projects.
const String helixPubPackage = 'helix';

/// The node test framework the placed spec imports — without it the spec
/// would not run, so `helix init` does not place one.
const String nodeTestPackage = 'vitest';

/// The Dart test package the placed test imports.
const String dartTestPackage = 'test';

/// Arguments that create a `package.json` from npm's defaults.
const List<String> npmInitArgs = ['init', '-y'];

// .............................................................................
/// A node package manager `helix init` drives.
enum NodePackageManager {
  /// pnpm — what the DNA repositories themselves use.
  pnpm,

  /// yarn.
  yarn,

  /// npm — ships with node and bootstraps a project that has no manifest
  /// at all.
  npm;

  /// The executable to call. The enum names are the executable names.
  String get executable => name;

  /// The arguments that install [package] as a dev dependency.
  List<String> addDevArgs(String package) => switch (this) {
    NodePackageManager.pnpm ||
    NodePackageManager.yarn => ['add', '-D', package],
    NodePackageManager.npm => ['install', '-D', package],
  };
}

// .............................................................................
/// The node package manager of the project at [root].
///
/// The `packageManager` field wins — corepack pins the manager there, and
/// a declaration beats a guess. Then the lock file that is present.
/// [NodePackageManager.npm] is the fallback: it ships with node, and it is
/// what `helix init` bootstraps a fresh project with.
NodePackageManager detectNodePackageManager(DnaHost host, String root) {
  final declared = readPackageJson(host, root)?['packageManager'];
  if (declared is String) {
    for (final manager in NodePackageManager.values) {
      if (declared.startsWith(manager.name)) return manager;
    }
  }
  if (host.existsFile('$root/pnpm-lock.yaml')) return NodePackageManager.pnpm;
  if (host.existsFile('$root/yarn.lock')) return NodePackageManager.yarn;
  return NodePackageManager.npm;
}

// .............................................................................
/// The decoded `package.json` of the project at [root]; `null` when there
/// is none or it does not parse — it is not this package's file to
/// validate.
Map<String, dynamic>? readPackageJson(DnaHost host, String root) {
  final path = '$root/package.json';
  if (!host.existsFile(path)) return null;
  try {
    final doc = jsonDecode(host.readString(path));
    return doc is Map<String, dynamic> ? doc : null;
  } on FormatException {
    return null;
  }
}

// .............................................................................
/// The decoded `pubspec.yaml` of the project at [root]; `null` when there
/// is none or it does not parse.
Map<dynamic, dynamic>? readPubspec(DnaHost host, String root) {
  final path = '$root/pubspec.yaml';
  if (!host.existsFile(path)) return null;
  try {
    final doc = loadYaml(host.readString(path));
    return doc is Map ? doc : null;
  } on YamlException {
    return null;
  }
}

// .............................................................................
/// Whether the `package.json` of the project at [root] declares [package]
/// as a dependency or dev dependency.
bool declaresNodeDependency(DnaHost host, String root, String package) =>
    _declares(readPackageJson(host, root), const [
      'dependencies',
      'devDependencies',
    ], package);

// .............................................................................
/// Whether the `pubspec.yaml` of the project at [root] declares [package]
/// as a dependency or dev dependency.
bool declaresPubDependency(DnaHost host, String root, String package) =>
    _declares(readPubspec(host, root), const [
      'dependencies',
      'dev_dependencies',
    ], package);

bool _declares(Map<dynamic, dynamic>? doc, List<String> sections, String name) {
  if (doc == null) return false;
  for (final section in sections) {
    final deps = doc[section];
    if (deps is Map && deps.containsKey(name)) return true;
  }
  return false;
}

// .............................................................................
/// Whether the project at [root] is a Flutter project: its pubspec carries
/// a `flutter:` section or depends on the Flutter SDK. `dart pub` cannot
/// resolve an SDK dependency, so such a project is served by `flutter pub`.
bool isFlutterProject(DnaHost host, String root) {
  final doc = readPubspec(host, root);
  if (doc == null) return false;
  if (doc['flutter'] != null) return true;
  final deps = doc['dependencies'];
  return deps is Map && deps.containsKey('flutter');
}

// .............................................................................
/// The executable that manages the pub dependencies of the project at
/// [root] — `flutter` in a Flutter project, `dart` everywhere else.
String pubExecutable(DnaHost host, String root) =>
    isFlutterProject(host, root) ? 'flutter' : 'dart';

// .............................................................................
/// The arguments that add [package] as a pub dev dependency.
List<String> pubAddDevArgs(String package) => ['pub', 'add', 'dev:$package'];
