// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';

import 'dna_fs.dart';
import 'dna_tree_hash.dart';
import 'json_merge.dart';

/// Manifest format written by gg_dna 5.x.
const int dnaManifestFormatVersion = 5;

// .............................................................................
/// One resolved layer of the inheritance tree.
class DnaManifestLayer {
  /// Creates the layer record.
  const DnaManifestLayer({
    required this.name,
    this.package,
    this.path,
    this.resolvedVersion,
    this.via,
    this.hash,
  });

  /// Reads a layer from decoded JSON.
  factory DnaManifestLayer.fromJson(Map<String, dynamic> json) =>
      DnaManifestLayer(
        name: json['name'] as String,
        package: json['package'] as String?,
        path: json['path'] as String?,
        resolvedVersion: json['resolvedVersion'] as String?,
        via: json['via'] as String?,
        hash: json['hash'] as String?,
      );

  /// Canonical layer name (kebab package name or override name).
  final String name;

  /// Resolved package name (`null` for path overrides and the base layer).
  final String? package;

  /// Path override relative to the target root (`null` for packages).
  final String? path;

  /// The version the package manager resolved (`null` when unknown).
  final String? resolvedVersion;

  /// Name of the layer that pulled this one in recursively; `null` for
  /// directly configured layers.
  final String? via;

  /// Content hash of the layer's `dna/` tree at instantiation time.
  final String? hash;

  /// JSON representation.
  Map<String, dynamic> toJson() => {
        'name': name,
        'package': package,
        'path': path,
        'resolvedVersion': resolvedVersion,
        'via': via,
        'hash': hash,
      };
}

// .............................................................................
/// One instantiated (public) file owned by the DNA.
class DnaManifestInstance {
  /// Creates the instance record.
  const DnaManifestInstance({required this.path, required this.hash});

  /// Reads an instance from decoded JSON.
  factory DnaManifestInstance.fromJson(Map<String, dynamic> json) =>
      DnaManifestInstance(
        path: json['path'] as String,
        hash: json['hash'] as String,
      );

  /// Project-relative posix path of the instance (converted naming).
  final String path;

  /// Content hash of the instance at instantiation time.
  final String hash;

  /// JSON representation.
  Map<String, dynamic> toJson() => {'path': path, 'hash': hash};
}

// .............................................................................
/// The Claude section of the manifest.
class DnaManifestClaude {
  /// Creates the record.
  const DnaManifestClaude({this.claudeMdInclude});

  /// Reads the section from decoded JSON.
  factory DnaManifestClaude.fromJson(Map<String, dynamic> json) =>
      DnaManifestClaude(
        claudeMdInclude: (json['claudeMdInclude'] as List?)?.cast<String>(),
      );

  /// The configured CLAUDE.md includes at instantiation time.
  final List<String>? claudeMdInclude;

  /// JSON representation.
  Map<String, dynamic> toJson() => {'claudeMdInclude': claudeMdInclude};
}

// .............................................................................
/// The bookkeeping gg_dna writes below `<target>/dna/`.
///
/// Two files, because they answer two questions:
/// - `_dna.json` — which layers produced the current state, and their
///   hashes.
/// - `_instances.json` — which project files the DNA owns.
///
/// The effective variables are part of neither: they live in
/// `dna/_vars.json`, the merged file the DNA itself ships.
class DnaManifest {
  /// Creates the manifest.
  const DnaManifest({
    required this.layers,
    required this.instances,
    this.claude = const DnaManifestClaude(),
    required this.baseVersion,
    this.baseHash,
    this.hash,
  });

  /// The resolved layers in application order.
  final List<DnaManifestLayer> layers;

  /// All DNA-owned instances with their generated hashes.
  final List<DnaManifestInstance> instances;

  /// The Claude section.
  final DnaManifestClaude claude;

  /// gg_dna version that wrote the manifest.
  final String baseVersion;

  /// Hash of gg_dna's own base DNA at instantiation time.
  final String? baseHash;

  /// Hash of the generated `dna/` tree (`null` for role: dna).
  final String? hash;

  /// JSON representation of `_dna.json` — layers and hashes.
  Map<String, dynamic> toJson() => {
        'version': dnaManifestFormatVersion,
        'layers': layers.map((l) => l.toJson()).toList(),
        'claude': claude.toJson(),
        'baseVersion': baseVersion,
        'baseHash': baseHash,
        'hash': hash,
      };

  /// JSON representation of `_instances.json` — the files the DNA owns.
  Map<String, dynamic> instancesToJson() => {
        'version': dnaManifestFormatVersion,
        'instances': instances.map((i) => i.toJson()).toList(),
      };

  // ...........................................................................
  /// Reads the manifest of [targetRoot]; `null` when missing or not
  /// format v5.
  static DnaManifest? read(DnaHost host, String targetRoot) {
    var path = '$targetRoot/dna/$dnaManifestFilename';
    if (!host.existsFile(path)) {
      // Repositories written before the rename still carry the old file.
      path = '$targetRoot/dna/$legacyDnaManifestFilename';
      if (!host.existsFile(path)) return null;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(host.readString(path));
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    if (decoded['version'] != dnaManifestFormatVersion) return null;
    return DnaManifest(
      layers: [
        for (final l in (decoded['layers'] as List?) ?? const [])
          DnaManifestLayer.fromJson(l as Map<String, dynamic>),
      ],
      // Instances live in their own file; repositories written before
      // the split still carry them inside the manifest.
      instances: _readInstances(host, targetRoot) ??
          [
            for (final i in (decoded['instances'] as List?) ?? const [])
              DnaManifestInstance.fromJson(i as Map<String, dynamic>),
          ],
      claude: decoded['claude'] is Map<String, dynamic>
          ? DnaManifestClaude.fromJson(
              decoded['claude'] as Map<String, dynamic>,
            )
          : const DnaManifestClaude(),
      baseVersion: decoded['baseVersion'] as String? ?? 'unknown',
      baseHash: decoded['baseHash'] as String?,
      hash: decoded['hash'] as String?,
    );
  }

  // ...........................................................................
  /// Writes both bookkeeping files below `<targetRoot>/dna/`.
  void write(DnaHost host, String targetRoot) {
    host.writeString(
      '$targetRoot/dna/$dnaManifestFilename',
      encodeJsonPretty(toJson()),
    );
    host.writeString(
      '$targetRoot/dna/$dnaInstancesFilename',
      encodeJsonPretty(instancesToJson()),
    );
  }
}

// .............................................................................
List<DnaManifestInstance>? _readInstances(DnaHost host, String targetRoot) {
  var path = '$targetRoot/dna/$dnaInstancesFilename';
  if (!host.existsFile(path)) {
    // Written before the `_` convention was applied to this file.
    path = '$targetRoot/dna/$legacyDnaInstancesFilename';
    if (!host.existsFile(path)) return null;
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(host.readString(path));
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;
  if (decoded['version'] != dnaManifestFormatVersion) return null;
  return [
    for (final i in (decoded['instances'] as List?) ?? const [])
      DnaManifestInstance.fromJson(i as Map<String, dynamic>),
  ];
}
