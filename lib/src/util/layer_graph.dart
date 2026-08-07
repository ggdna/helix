// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';

import 'package:yaml/yaml.dart';

import 'dna_config.dart';
import 'dna_fs.dart';
import 'dna_layout.dart';

/// Maximum recursion depth of the inheritance tree.
const int maxLayerDepth = 10;

/// The engine package never counts as a DNA layer — its `dna/` folder is
/// always the implicit base layer.
const String enginePackageName = 'gg-dna';

// .............................................................................
/// One resolved layer of the inheritance tree, parents before children.
class ResolvedLayer {
  /// Creates the resolved layer.
  const ResolvedLayer({
    required this.name,
    required this.root,
    this.package,
    this.path,
    this.version,
    this.via,
  });

  /// Canonical layer name (lowercased, `_` folded to `-`).
  final String name;

  /// Root folder of the layer checkout (its `dna/` lives below).
  final String root;

  /// Resolved package name as installed (`null` for path overrides).
  final String? package;

  /// Path override relative to the target root (`null` for packages).
  final String? path;

  /// Version from the package's own manifest (`null` when unknown).
  final String? version;

  /// Name of the layer that pulled this one in; `null` for direct layers.
  final String? via;
}

// .............................................................................
/// Canonical layer identity: lowercase, `_` folded to `-` (npm kebab and
/// pub snake names of the same DNA collapse to one identity).
String canonicalLayerName(String name) =>
    name.toLowerCase().replaceAll('_', '-');

// .............................................................................
/// Expands the inheritance tree of [targetRoot]: direct layers come from
/// [config]'s `order` (or the dev-dependency declaration order), parents
/// are read recursively from each layer's own `.gg/dna.json` (or its
/// dependency declaration order). Diamonds are deduplicated by canonical
/// name (first topological position wins), cycles and unresolvable layers
/// throw.
({List<ResolvedLayer> layers, List<String> warnings}) expandLayerGraph({
  required DnaHost host,
  required String targetRoot,
  required DnaConfig config,
}) {
  final warnings = <String>[];
  final layers = <ResolvedLayer>[];
  final done = <String>{};
  final inProgress = <String>[];

  void expand(String rawName, String? via, int depth) {
    final name = canonicalLayerName(rawName);
    if (name == enginePackageName) {
      throw const FormatException(
        'gg_dna itself is the engine — its base DNA is always layer 0 '
        'and must not be listed as a DNA layer.',
      );
    }
    if (done.contains(name)) return;
    if (inProgress.contains(name)) {
      throw FormatException(
        'DNA cycle detected: ${[...inProgress, name].join(' -> ')}.',
      );
    }
    if (depth > maxLayerDepth) {
      throw FormatException(
        'DNA tree deeper than $maxLayerDepth layers at "$name".',
      );
    }

    final located = _locate(host, targetRoot, config, rawName);
    if (located == null) {
      throw FormatException(
        'DNA layer "$rawName" cannot be resolved — declare it as '
        'dev-dependency and run pnpm install / dart pub get, or add a '
        'path override to $dnaConfigPath.',
      );
    }
    if (!host.existsDir('${located.root}/$dnaDirname')) {
      throw FormatException(
        'DNA layer "$rawName" (${located.root}) has no dna/ folder.',
      );
    }
    if (host.existsDir('${located.root}/$dnaDirname/src')) {
      throw FormatException(legacySrcLayoutError(rawName));
    }

    inProgress.add(name);
    final ownConfig = readDnaConfig(host, located.root);
    warnings.addAll(ownConfig.warnings.map((w) => '$rawName: $w'));
    // Parents of a DNA package are its regular dependencies — its
    // dev-dependencies (test tooling, the engine itself) never
    // contribute layers.
    final parentNames = ownConfig.config.order ??
        defaultDnaOrder(
          host,
          targetRoot,
          manifestRoot: located.root,
          config: config,
          includeDevDependencies: false,
        );
    for (final parent in parentNames) {
      if (canonicalLayerName(parent) == name) continue;
      expand(parent, name, depth + 1);
    }
    inProgress.removeLast();

    done.add(name);
    layers.add(
      ResolvedLayer(
        name: name,
        root: located.root,
        package: located.package,
        path: located.path,
        version: located.version,
        via: via,
      ),
    );
  }

  final directOrder = config.order ??
      defaultDnaOrder(
        host,
        targetRoot,
        manifestRoot: targetRoot,
        config: config,
      );
  for (final name in directOrder) {
    expand(name, null, 1);
  }
  return (layers: layers, warnings: warnings);
}

// .............................................................................
/// The default layer order: names of dependencies (and, for the target
/// itself, dev-dependencies) of the manifests at [manifestRoot]
/// (package.json before pubspec.yaml, regular before dev), keeping only
/// those that resolve to DNA packages. The engine package gg_dna never
/// counts.
List<String> defaultDnaOrder(
  DnaHost host,
  String targetRoot, {
  required String manifestRoot,
  required DnaConfig config,
  bool includeDevDependencies = true,
}) {
  final names = <String>[];
  final seen = <String>{};

  void add(Iterable<String> candidates) {
    for (final name in candidates) {
      final canonical = canonicalLayerName(name);
      if (canonical == enginePackageName) continue;
      if (!seen.add(canonical)) continue;
      final located = _locate(host, targetRoot, config, name);
      if (located == null) continue;
      if (!host.existsDir('${located.root}/$dnaDirname')) continue;
      names.add(name);
    }
  }

  final packageJson = '$manifestRoot/package.json';
  if (host.existsFile(packageJson)) {
    try {
      final doc = jsonDecode(host.readString(packageJson));
      if (doc is Map<String, dynamic>) {
        final deps = doc['dependencies'];
        final devDeps = doc['devDependencies'];
        if (deps is Map<String, dynamic>) add(deps.keys);
        if (includeDevDependencies && devDeps is Map<String, dynamic>) {
          add(devDeps.keys);
        }
      }
    } on FormatException {
      // Not our file to validate.
    }
  }

  final pubspec = '$manifestRoot/pubspec.yaml';
  if (host.existsFile(pubspec)) {
    try {
      final doc = loadYaml(host.readString(pubspec));
      if (doc is Map) {
        final deps = doc['dependencies'];
        final devDeps = doc['dev_dependencies'];
        if (deps is Map) add(deps.keys.cast<String>());
        if (includeDevDependencies && devDeps is Map) {
          add(devDeps.keys.cast<String>());
        }
      }
    } on YamlException {
      // Not our file to validate.
    }
  }
  return names;
}

// .............................................................................
({String root, String? package, String? path, String? version})? _locate(
  DnaHost host,
  String targetRoot,
  DnaConfig config,
  String rawName,
) {
  final canonical = canonicalLayerName(rawName);

  // 1. Path overrides from the target's config (any depth).
  for (final entry in config.pathOverrides.entries) {
    if (canonicalLayerName(entry.key) != canonical) continue;
    final root = entry.value.startsWith('/')
        ? entry.value
        : '$targetRoot/${entry.value}';
    return (root: root, package: null, path: entry.value, version: null);
  }

  // 2. node_modules of the target (npm/pnpm — kebab and raw name).
  for (final candidate in {rawName, canonical}) {
    final root = '$targetRoot/node_modules/$candidate';
    if (host.existsDir(root)) {
      return (
        root: root,
        package: candidate,
        path: null,
        version: _manifestVersion(host, root),
      );
    }
  }

  // 3. package_config.json of the target (pub — snake name).
  final snake = canonical.replaceAll('-', '_');
  final packageConfigPath = '$targetRoot/.dart_tool/package_config.json';
  if (host.existsFile(packageConfigPath)) {
    try {
      final doc = jsonDecode(host.readString(packageConfigPath));
      if (doc is Map<String, dynamic>) {
        for (final pkg in (doc['packages'] as List?) ?? const []) {
          if (pkg is! Map<String, dynamic>) continue;
          if (pkg['name'] != snake && pkg['name'] != rawName) continue;
          final rootUri = pkg['rootUri'] as String?;
          if (rootUri == null) continue;
          final root = _resolveRootUri(rootUri, targetRoot);
          return (
            root: root,
            package: pkg['name'] as String,
            path: null,
            version: _manifestVersion(host, root),
          );
        }
      }
    } on FormatException {
      // Not our file to validate.
    }
  }
  return null;
}

// .............................................................................
String _resolveRootUri(String rootUri, String targetRoot) {
  if (rootUri.startsWith('file://')) {
    return Uri.parse(rootUri).toFilePath(windows: false);
  }
  // Relative URIs are relative to the .dart_tool folder.
  final base = Uri.parse('$targetRoot/.dart_tool/');
  final resolved = base.resolve(rootUri).path;
  return resolved.endsWith('/')
      ? resolved.substring(0, resolved.length - 1)
      : resolved;
}

// .............................................................................
String? _manifestVersion(DnaHost host, String packageRoot) {
  final packageJson = '$packageRoot/package.json';
  if (host.existsFile(packageJson)) {
    try {
      final doc = jsonDecode(host.readString(packageJson));
      if (doc is Map<String, dynamic> && doc['version'] is String) {
        return doc['version'] as String;
      }
    } on FormatException {
      // Fall through to pubspec.
    }
  }
  final pubspec = '$packageRoot/pubspec.yaml';
  if (host.existsFile(pubspec)) {
    try {
      final doc = loadYaml(host.readString(pubspec));
      if (doc is Map && doc['version'] != null) {
        return '${doc['version']}';
      }
    } on YamlException {
      // No version then.
    }
  }
  return null;
}
