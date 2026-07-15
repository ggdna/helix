// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

/// One layer entry from the `dna:` block of a target repo's pubspec.yaml.
///
/// A layer is either a git layer ([git] set) or a path layer ([path] set) —
/// never both. The raw values are kept exactly as written in the pubspec so
/// callers can resolve them (shorthand expansion, relative paths) and so the
/// sync manifest can detect config drift machine-independently.
class DnaLayerConfig {
  /// Constructor.
  const DnaLayerConfig({
    required this.name,
    this.git,
    this.path,
    this.versionConstraint,
    this.rawVersionConstraint,
  });

  /// Layer name as listed in `dna: order:`.
  final String name;

  /// Raw `git:` value as written (git URL or `gg_*` shorthand). `null` for
  /// path layers.
  final String? git;

  /// Raw `path:` value as written (absolute, or relative to the target repo
  /// root). `null` for git layers.
  final String? path;

  /// Parsed `version:` semver constraint. Only allowed on git layers; the
  /// highest git tag satisfying it is cloned.
  final VersionConstraint? versionConstraint;

  /// Raw `version:` string as written in the pubspec. Stored in the manifest
  /// for drift detection.
  final String? rawVersionConstraint;

  /// Whether this layer is cloned from git.
  bool get isGit => git != null;
}

/// Parsed `dna:` block of a target repo's pubspec.yaml.
///
/// ```yaml
/// dna:
///   order:
///     - dna_company
///     - dna_repo
///   dna_company:
///     git: https://github.com/acme/dna_company.git
///     version: ^1.4.0
///   dna_repo:
///     path: dna/_override
/// ```
///
/// Layers are applied in `order` — later entries win on collisions. The
/// gg_dna base DNA is always the implicit lowest layer and not part of this
/// config.
class DnaConfig {
  /// Constructor.
  const DnaConfig({required this.layers, required this.warnings});

  /// The configured layers, in `order` order.
  final List<DnaLayerConfig> layers;

  /// Non-fatal findings, e.g. configured layers missing from `order`.
  final List<String> warnings;

  /// Reads the `dna:` block from `<targetRoot>/pubspec.yaml`.
  ///
  /// Returns `null` when the pubspec or the `dna:` key is absent. Throws a
  /// [FormatException] when the pubspec is not valid YAML or the `dna:`
  /// block is invalid (see [parse] for the validation rules).
  static DnaConfig? read(String targetRoot) {
    final file = File(p.join(targetRoot, 'pubspec.yaml'));
    if (!file.existsSync()) return null;
    return parse(file.readAsStringSync());
  }

  /// Parses the `dna:` block from an already-loaded pubspec YAML string.
  ///
  /// Returns `null` when no `dna:` key is present. Throws [FormatException]
  /// when the config is invalid:
  ///   - `dna:` is not a map, `order:` is not a list of strings
  ///   - duplicate names in `order`
  ///   - a name in `order` has no configuration map
  ///   - a layer has both `git:` and `path:`, or neither
  ///   - `version:` on a path layer, or an unparsable `version:` constraint
  static DnaConfig? parse(String pubspecContent) {
    final Object? doc;
    try {
      doc = loadYaml(pubspecContent);
    } on YamlException catch (e) {
      throw FormatException('pubspec.yaml is not valid YAML: ${e.message}');
    }
    if (doc is! Map) return null;
    final dna = doc['dna'];
    if (dna == null) return null;
    if (dna is! Map) {
      throw const FormatException(
        '`dna:` in pubspec.yaml must be a map.',
      );
    }

    final order = _readOrder(dna);
    final layers = <DnaLayerConfig>[];
    for (final name in order) {
      layers.add(_readLayer(dna, name));
    }

    final warnings = <String>[];
    for (final key in dna.keys) {
      if (key == 'order' || order.contains(key)) continue;
      warnings.add(
        'dna: layer "$key" is configured but not listed in '
        '`dna: order:` — ignored.',
      );
    }

    return DnaConfig(layers: layers, warnings: warnings);
  }

  // ...........................................................................
  static List<String> _readOrder(Map<dynamic, dynamic> dna) {
    final order = dna['order'];
    if (order == null) return const [];
    if (order is! List) {
      throw const FormatException(
        '`dna: order:` in pubspec.yaml must be a list of layer names.',
      );
    }
    final names = <String>[];
    for (final entry in order) {
      if (entry is! String || entry.isEmpty) {
        throw const FormatException(
          '`dna: order:` in pubspec.yaml must only contain '
          'non-empty layer names.',
        );
      }
      if (names.contains(entry)) {
        throw FormatException(
          '`dna: order:` in pubspec.yaml lists layer "$entry" twice.',
        );
      }
      names.add(entry);
    }
    return names;
  }

  // ...........................................................................
  static DnaLayerConfig _readLayer(Map<dynamic, dynamic> dna, String name) {
    final raw = dna[name];
    if (raw == null) {
      throw FormatException(
        'dna: layer "$name" is listed in `dna: order:` but has no '
        'configuration map in pubspec.yaml.',
      );
    }
    if (raw is! Map) {
      throw FormatException(
        'dna: layer "$name" in pubspec.yaml must be a map with either '
        '`git:` or `path:`.',
      );
    }

    final git = _readString(raw, 'git', name);
    final path = _readString(raw, 'path', name);
    final rawVersion = _readString(raw, 'version', name);

    if ((git == null) == (path == null)) {
      throw FormatException(
        'dna: layer "$name" in pubspec.yaml must have either `git:` or '
        '`path:` (exactly one of both).',
      );
    }
    if (rawVersion != null && git == null) {
      throw FormatException(
        'dna: layer "$name" in pubspec.yaml must not combine `version:` '
        'with `path:` — version constraints only apply to git layers.',
      );
    }

    VersionConstraint? constraint;
    if (rawVersion != null) {
      try {
        constraint = VersionConstraint.parse(rawVersion);
      } on FormatException {
        throw FormatException(
          'dna: layer "$name" in pubspec.yaml has an invalid `version:` '
          'constraint: "$rawVersion".',
        );
      }
    }

    return DnaLayerConfig(
      name: name,
      git: git,
      path: path,
      versionConstraint: constraint,
      rawVersionConstraint: rawVersion,
    );
  }

  // ...........................................................................
  static String? _readString(
    Map<dynamic, dynamic> layer,
    String key,
    String name,
  ) {
    final value = layer[key];
    if (value == null) return null;
    if (value is String && value.isNotEmpty) return value;
    // YAML parses bare numbers like `version: 1.4` as doubles — keep the
    // error actionable instead of surfacing a cast error.
    if (key == 'version' && value is num) return '$value';
    throw FormatException(
      'dna: layer "$name" in pubspec.yaml has an invalid `$key:` value — '
      'expected a non-empty string.',
    );
  }
}
