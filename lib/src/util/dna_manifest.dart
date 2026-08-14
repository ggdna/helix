// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';

import 'dna_fs.dart';
import 'dna_layout.dart';

/// Path of the engine-owned bookkeeping relative to the project root.
const String dnaGeneratedPath = '$dnaDirname/$dnaGeneratedFilename';

// .............................................................................
/// One resolved layer of the inheritance tree.
class DnaManifestLayer {
  /// Creates the layer record.
  const DnaManifestLayer({
    required this.name,
    this.package,
    this.ecosystem,
    this.resolvedVersion,
    this.via,
    this.hash,
  });

  /// Reads a layer from decoded JSON.
  factory DnaManifestLayer.fromJson(Map<String, dynamic> json) =>
      DnaManifestLayer(
        name: json['name'] as String,
        package: json['package'] as String?,
        ecosystem: json['ecosystem'] as String?,
        resolvedVersion: json['resolvedVersion'] as String?,
        via: json['via'] as String?,
        hash: json['hash'] as String?,
      );

  /// Canonical layer identity, or `base`/`self` for the implicit layers.
  final String name;

  /// Package name as installed (`null` for the `self` layer).
  final String? package;

  /// Ecosystem the copy came from: `node` or `pub` (`null` when neither).
  final String? ecosystem;

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
    'ecosystem': ecosystem,
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
/// The bookkeeping helix writes to `<target>/dna/_generated.json`.
///
/// It is the engine's half of the `dna/` folder: which layers produced the
/// current state, and which project files the DNA owns. The other half,
/// `dna/_dna.json`, belongs to the developer and is only ever read.
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

  /// helix version that wrote the manifest.
  final String baseVersion;

  /// Hash of helix's own base DNA at instantiation time.
  final String? baseHash;

  /// Hash of the generated `dna/` tree (`null` for role: dna).
  final String? hash;

  /// JSON representation of `dna/_generated.json`.
  Map<String, dynamic> toJson() => {
    'version': dnaFormatVersion,
    'layers': layers.map((l) => l.toJson()).toList(),
    'claude': claude.toJson(),
    'baseVersion': baseVersion,
    'baseHash': baseHash,
    'hash': hash,
    'instances': instances.map((i) => i.toJson()).toList(),
  };

  // ...........................................................................
  /// Reads the manifest of [targetRoot]; `null` only when the file is
  /// absent, which means this project has never been instantiated.
  ///
  /// A file that exists but cannot be used throws instead of yielding
  /// `null`. The distinction is load-bearing: `null` makes every existing
  /// instance count as unowned, and unowned instances get adopted and
  /// overwritten without a backup — so a `null` for "unreadable" would
  /// silently destroy local edits the backup is supposed to preserve.
  static DnaManifest? read(DnaHost host, String targetRoot) {
    final path = '$targetRoot/$dnaGeneratedPath';
    if (!host.existsFile(path)) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(host.readString(path));
    } on FormatException catch (e) {
      throw FormatException('$dnaGeneratedPath is not valid JSON ($e). $_fix');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        '$dnaGeneratedPath must contain an object. $_fix',
      );
    }
    final version = decoded['version'];
    if (version != dnaFormatVersion) {
      throw FormatException(
        '$dnaGeneratedPath was written in format version $version — this '
        'helix writes version $dnaFormatVersion. $_fix',
      );
    }

    return DnaManifest(
      layers: [
        for (final l in (decoded['layers'] as List?) ?? const [])
          DnaManifestLayer.fromJson(l as Map<String, dynamic>),
      ],
      instances: [
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

  static const String _fix =
      'Delete it and re-run — the DNA re-adopts the existing files. Commit '
      'any hand edits you want to keep first.';
}
