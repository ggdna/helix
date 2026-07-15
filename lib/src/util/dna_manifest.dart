// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'dna_config.dart';
import 'dna_hash.dart';

/// One layer entry in the sync manifest: the raw pubspec config values (for
/// machine-independent drift detection via [matchesConfig]) plus the
/// resolution results of the last sync.
class DnaManifestLayer {
  /// Constructor.
  const DnaManifestLayer({
    required this.name,
    this.git,
    this.path,
    this.versionConstraint,
    this.resolvedVersion,
    this.resolvedTag,
    this.commit,
    this.hash,
  });

  /// Creates the entry for [config] plus its resolution results.
  factory DnaManifestLayer.fromConfig(
    DnaLayerConfig config, {
    String? resolvedVersion,
    String? resolvedTag,
    String? commit,
    String? hash,
  }) =>
      DnaManifestLayer(
        name: config.name,
        git: config.git,
        path: config.path,
        versionConstraint: config.rawVersionConstraint,
        resolvedVersion: resolvedVersion,
        resolvedTag: resolvedTag,
        commit: commit,
        hash: hash,
      );

  /// Restores a layer from [toJson]; fields of unexpected type are absent.
  factory DnaManifestLayer.fromJson(Map<String, dynamic> data) =>
      DnaManifestLayer(
        name: _string(data, 'name') ?? '',
        git: _string(data, 'git'),
        path: _string(data, 'path'),
        versionConstraint: _string(data, 'versionConstraint'),
        resolvedVersion: _string(data, 'resolvedVersion'),
        resolvedTag: _string(data, 'resolvedTag'),
        commit: _string(data, 'commit'),
        hash: _string(data, 'hash'),
      );

  /// Layer name as listed in `dna: order:`.
  final String name;

  /// Raw `git:` value from the pubspec. `null` for path layers.
  final String? git;

  /// Raw `path:` value from the pubspec. `null` for git layers.
  final String? path;

  /// Raw `version:` constraint from the pubspec. `null` when unconstrained.
  final String? versionConstraint;

  /// The version the constraint resolved to at sync time, e.g. `1.5.0`.
  final String? resolvedVersion;

  /// The git tag [resolvedVersion] came from, e.g. `v1.5.0`.
  final String? resolvedTag;

  /// Commit SHA of the cloned layer. `null` for path layers.
  final String? commit;

  /// Content hash of the layer's dna root at sync time.
  final String? hash;

  /// Whether this entry was produced by [config] (drift detection).
  bool matchesConfig(DnaLayerConfig config) =>
      name == config.name &&
      git == config.git &&
      path == config.path &&
      versionConstraint == config.rawVersionConstraint;

  /// JSON representation used by [DnaManifest.write] and tests.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'git': git,
        'path': path,
        'versionConstraint': versionConstraint,
        'resolvedVersion': resolvedVersion,
        'resolvedTag': resolvedTag,
        'commit': commit,
        'hash': hash,
      };
}

/// Sync manifest at `<target>/dna/.dna.json` — everything a later `--check`
/// needs to verify the target is still in sync (base and result hashes plus
/// per-layer config and resolution data).
class DnaManifest {
  /// Constructor.
  const DnaManifest({
    this.layers = const [],
    this.baseVersion,
    this.baseHash,
    this.hash,
  });

  /// Manifest format version; [read] rejects all others (e.g. pre-2.0).
  static const int formatVersion = 2;

  /// The layers that were merged during the last sync, in order.
  final List<DnaManifestLayer> layers;

  /// `version:` field of the gg_dna package that produced the last sync.
  final String? baseVersion;

  /// Content hash of the gg_dna package's `dna/` folder at sync time.
  final String? baseHash;

  /// Content hash of `<target>/dna/` after the completed sync.
  final String? hash;

  /// Reads `<dnaDir>/.dna.json`; `null` when missing, invalid, or not v2.
  static DnaManifest? read(Directory dnaDir) {
    final file = File(p.join(dnaDir.path, dnaManifestFilename));
    if (!file.existsSync()) return null;
    final Object? data;
    try {
      data = jsonDecode(file.readAsStringSync());
    } on FormatException {
      return null;
    }
    if (data is! Map<String, dynamic>) return null;
    if (data['version'] != formatVersion) return null;
    final rawLayers = data['layers'];
    final layers = <DnaManifestLayer>[];
    if (rawLayers is List) {
      for (final layer in rawLayers) {
        if (layer is! Map<String, dynamic>) return null;
        layers.add(DnaManifestLayer.fromJson(layer));
      }
    }
    return DnaManifest(
      layers: layers,
      baseVersion: _string(data, 'baseVersion'),
      baseHash: _string(data, 'baseHash'),
      hash: _string(data, 'hash'),
    );
  }

  /// Writes `this` to `<dnaDir>/.dna.json` as pretty-printed JSON.
  void write(Directory dnaDir) {
    final file = File(p.join(dnaDir.path, dnaManifestFilename));
    file.parent.createSync(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    file.writeAsStringSync('${encoder.convert(toJson())}\n');
  }

  /// JSON representation used by [write] and tests.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': formatVersion,
        'layers': [for (final layer in layers) layer.toJson()],
        'baseVersion': baseVersion,
        'baseHash': baseHash,
        'hash': hash,
      };
}

/// Returns [key] from [data] when it is a string, `null` otherwise.
String? _string(Map<String, dynamic> data, String key) {
  final value = data[key];
  return value is String ? value : null;
}

/// Returns the pubspec `version:` at [packageRoot], `null` when absent.
String? readPackageVersion(String packageRoot) {
  final file = File(p.join(packageRoot, 'pubspec.yaml'));
  if (!file.existsSync()) return null;
  final match = RegExp(r'^version:\s*(.+)$', multiLine: true)
      .firstMatch(file.readAsStringSync());
  return match?.group(1)?.trim();
}
