// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';

import 'package:yaml/yaml.dart';

import 'dna_config.dart';
import 'dna_fs.dart';
import 'dna_layout.dart';
import 'dna_tree_hash.dart';
import 'package_resolution.dart';

/// Maximum recursion depth of the inheritance tree.
const int maxLayerDepth = 10;

/// Canonical names of the engine itself and its bridges — never DNA
/// layers, because helix's own `dna/` is always the implicit base layer.
const Set<String> enginePackageNames = {'helix', 'helix-js'};

// .............................................................................
/// One resolved layer of the inheritance tree, parents before children.
class ResolvedLayer {
  /// Creates the resolved layer.
  const ResolvedLayer({
    required this.name,
    required this.root,
    required this.package,
    required this.ecosystem,
    required this.source,
    this.version,
    this.via,
  });

  /// Canonical layer identity (lowercase, npm scope dropped, `_` folded
  /// to `-`).
  final String name;

  /// Root folder of the layer checkout (its `dna/` lives below).
  final String root;

  /// Package name as installed (`dna_base`, `@tssuite/dna-base`).
  final String package;

  /// Which ecosystem provided the copy that was used.
  final PackageEcosystem ecosystem;

  /// How the package manager obtained it.
  final PackageSource source;

  /// The resolved version (`null` when unknown).
  final String? version;

  /// Name of the layer that pulled this one in; `null` for direct layers.
  final String? via;
}

// .............................................................................
/// Expands the inheritance tree of [targetRoot]: direct layers come from
/// [config]'s `layers`, parents recursively from each layer's own
/// `dna/_dna.json`. Diamonds are deduplicated by canonical identity (first
/// topological position wins), cycles and unresolvable layers throw.
///
/// A layer's parents are looked up in the layer's own installation first
/// and only then in the target's. pnpm exposes just the direct
/// dependencies at the top level, so a DNA pulled in by another DNA lives
/// under *that* package's `node_modules`, never under the consumer's —
/// with a `link:` checkout as much as with a registry install. pub is the
/// other way round: it flattens everything into the target's
/// `package_config.json` and a package in the cache has no resolution of
/// its own, so the fallback is what carries it.
({List<ResolvedLayer> layers, List<String> warnings}) expandLayerGraph({
  required DnaHost host,
  required String targetRoot,
  required DnaConfig config,
  required PackageResolution resolution,
}) {
  final layers = <ResolvedLayer>[];
  final done = <String>{};
  final inProgress = <String>[];
  final resolutions = <String, PackageResolution>{targetRoot: resolution};
  final warnings = <String>[];

  PackageResolution resolutionOf(String root) => resolutions.putIfAbsent(
        root,
        () => PackageResolution.read(host, root),
      );

  void expand(
    String rawName,
    String? via,
    int depth,
    List<PackageResolution> chain,
  ) {
    final name = canonicalPackageName(rawName);
    if (enginePackageNames.contains(name)) {
      throw const FormatException(
        'helix itself is the engine — its base DNA is always layer 0 '
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

    var copies = const <LocatedPackage>[];
    for (final candidate in chain) {
      copies = candidate.locateAll(rawName);
      if (copies.isNotEmpty) break;
    }
    if (copies.isEmpty) {
      throw FormatException(
        'DNA layer "$rawName" cannot be resolved.\n'
        '  ${chain.first.describeFailure(rawName)}\n'
        '  Declare the DNA as a dependency in pubspec.yaml / package.json '
        'and install it. For local checkouts use gg_localize_refs.',
      );
    }
    final located = copies.first;
    _warnOnDivergentCopies(host, copies, warnings);

    final ownConfig = _readLayerConfig(host, located);
    warnings.addAll(ownConfig.warnings);

    inProgress.add(name);
    final parentChain = [resolutionOf(located.root), ...chain];
    for (final parent in ownConfig.config.layers) {
      if (canonicalPackageName(parent) == name) continue;
      expand(parent, name, depth + 1, parentChain);
    }
    inProgress.removeLast();

    done.add(name);
    layers.add(
      ResolvedLayer(
        name: name,
        root: located.root,
        package: located.packageName,
        ecosystem: located.ecosystem,
        source: located.source,
        version: located.version,
        via: via,
      ),
    );
  }

  for (final name in config.layers) {
    expand(name, null, 1, [resolution]);
  }
  return (
    layers: layers,
    warnings: [
      for (final r in resolutions.values) ...r.warnings,
      ...warnings,
    ],
  );
}

// .............................................................................
/// Reads the config of a resolved layer, insisting that it actually is a
/// DNA package.
///
/// A `dna/` folder alone does not make one — the package has to say so in
/// `dna/_dna.json`. Without that rule any dependency that happens to ship
/// a `dna/` folder would be pulled in as a layer, and a package published
/// before the config moved into `dna/` would silently contribute no
/// parents at all.
({DnaConfig config, List<String> warnings}) _readLayerConfig(
  DnaHost host,
  LocatedPackage located,
) {
  final result = host.existsFile('${located.root}/$dnaConfigPath')
      ? readDnaConfig(host, located.root, packageLabel: located.packageName)
      : null;
  if (result == null || result.config.role != DnaRole.dna) {
    throw FormatException(
      'Package "${located.packageName}" (${located.root}) is not a DNA '
      'package — $dnaConfigPath is missing or does not declare '
      '"role": "dna". A dna/ folder alone does not make a package a DNA '
      'layer.',
    );
  }
  return result;
}

// .............................................................................
/// Warns when the npm and pub copies of a dual-published DNA carry
/// different `dna/` trees — one of the two publications is then stale.
void _warnOnDivergentCopies(
  DnaHost host,
  List<LocatedPackage> copies,
  List<String> warnings,
) {
  if (copies.length < 2) return;
  final hashes = {
    for (final copy in copies) hashTree(host, '${copy.root}/$dnaDirname'),
  };
  if (hashes.length < 2) return;
  warnings.add(
    'DNA "${copies.first.identity}" is installed from both ecosystems and '
    'the two copies differ: '
    '${copies.map((c) => '${c.packageName} ${c.version ?? '?'}').join(' vs ')}'
    '. ${copies.first.packageName} is used — republish the other one.',
  );
}

// .............................................................................
/// Package names declared by the manifests at [root] that resolve to DNA
/// packages — the starting point `helix init` writes into `layers`.
///
/// Only a suggestion: the engine itself never infers layers, so what is
/// not listed in `dna/_dna.json` is not applied.
List<String> suggestDnaLayers(
  DnaHost host,
  String root,
  PackageResolution resolution,
) {
  final names = <String>[];
  final seen = <String>{};

  void add(Iterable<String> candidates) {
    for (final name in candidates) {
      final identity = canonicalPackageName(name);
      if (enginePackageNames.contains(identity)) continue;
      if (!seen.add(identity)) continue;
      final located = resolution.locate(name);
      if (located == null) continue;
      try {
        _readLayerConfig(host, located);
      } on FormatException {
        continue;
      }
      names.add(name);
    }
  }

  final packageJson = '$root/package.json';
  if (host.existsFile(packageJson)) {
    try {
      final doc = jsonDecode(host.readString(packageJson));
      if (doc is Map<String, dynamic>) {
        for (final section in const ['dependencies', 'devDependencies']) {
          final deps = doc[section];
          if (deps is Map<String, dynamic>) add(deps.keys);
        }
      }
    } on FormatException {
      // Not our file to validate.
    }
  }

  final pubspec = '$root/pubspec.yaml';
  if (host.existsFile(pubspec)) {
    try {
      final doc = loadYaml(host.readString(pubspec));
      if (doc is Map) {
        for (final section in const ['dependencies', 'dev_dependencies']) {
          final deps = doc[section];
          if (deps is Map) add(deps.keys.cast<String>());
        }
      }
    } on YamlException {
      // Not our file to validate.
    }
  }
  return names;
}
