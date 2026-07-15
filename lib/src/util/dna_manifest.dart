// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'dna_hash.dart';

/// One layer entry in the sync manifest.
///
/// Stores the raw pubspec config values ([git]/[path]/[versionConstraint])
/// so `--check` can detect config drift machine-independently, plus the
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

  /// Restores a layer from its [toJson] representation.
  factory DnaManifestLayer.fromJson(Map<String, dynamic> data) =>
      DnaManifestLayer(
        name: data['name'] as String? ?? '',
        git: data['git'] as String?,
        path: data['path'] as String?,
        versionConstraint: data['versionConstraint'] as String?,
        resolvedVersion: data['resolvedVersion'] as String?,
        resolvedTag: data['resolvedTag'] as String?,
        commit: data['commit'] as String?,
        hash: data['hash'] as String?,
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

/// Sync manifest written to `<target>/dna/.dna.json` after every successful
/// `gg_dna sync`. Stores enough information for a later `--check` to verify
/// the target is still in sync with the source without re-doing the full
/// file walk.
class DnaManifest {
  /// Constructor.
  const DnaManifest({
    this.layers = const [],
    this.baseVersion,
    this.baseHash,
    this.hash,
  });

  /// Manifest format version written by this gg_dna. [read] rejects
  /// manifests of other versions (e.g. pre-2.0 files) by returning `null`.
  static const int formatVersion = 2;

  /// The layers that were merged during the last sync, in order.
  final List<DnaManifestLayer> layers;

  /// `version:` field of the gg_dna package that produced the last sync.
  final String? baseVersion;

  /// Content hash of the gg_dna package's `dna/` folder at sync time.
  final String? baseHash;

  /// Content hash of `<target>/dna/` after the sync (layers merged in,
  /// markers rendered, snapshots restored).
  final String? hash;

  /// Reads the manifest at `<dnaDir>/.dna.json`. Returns `null` when the
  /// file does not exist, cannot be parsed as JSON, or has a different
  /// format version (e.g. was written by gg_dna 1.x).
  static DnaManifest? read(Directory dnaDir) {
    final file = File(p.join(dnaDir.path, dnaManifestFilename));
    if (!file.existsSync()) return null;
    try {
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      if (data['version'] != formatVersion) return null;
      final layers = data['layers'] as List<dynamic>? ?? const [];
      return DnaManifest(
        layers: [
          for (final layer in layers)
            DnaManifestLayer.fromJson(layer as Map<String, dynamic>),
        ],
        baseVersion: data['baseVersion'] as String?,
        baseHash: data['baseHash'] as String?,
        hash: data['hash'] as String?,
      );
    } on FormatException {
      return null;
    }
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

/// Returns the `version:` field from the `pubspec.yaml` at [packageRoot], or
/// `null` when the file does not exist or no version line is present.
///
/// Uses a simple regex so this hot path does not need to parse the whole
/// pubspec as YAML.
String? readPackageVersion(String packageRoot) {
  final file = File(p.join(packageRoot, 'pubspec.yaml'));
  if (!file.existsSync()) return null;
  final match = RegExp(r'^version:\s*(.+)$', multiLine: true)
      .firstMatch(file.readAsStringSync());
  return match?.group(1)?.trim();
}
