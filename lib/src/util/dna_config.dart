// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

/// Files searched for the `dna:` config in the target root, in this
/// order — the block may live in exactly one of them.
const List<String> dnaConfigFilenames = [
  'dna.yaml',
  'package.json',
  'pubspec.yaml',
];

/// One layer from the `dna:` config block — either git ([git] set) or
/// path ([path] set), never both. Values are kept raw as written, so the
/// manifest can detect config drift machine-independently.
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

  /// Raw `git:` value (URL or `gg_*` shorthand); `null` for path layers.
  final String? git;

  /// Raw `path:` value relative to the target root; `null` for git layers.
  final String? path;

  /// Parsed `version:` constraint — the highest matching git tag is cloned.
  final VersionConstraint? versionConstraint;

  /// Raw `version:` string, stored in the manifest for drift detection.
  final String? rawVersionConstraint;

  /// Whether this layer is cloned from git.
  bool get isGit => git != null;
}

// .............................................................................
/// The folder and content root of a path layer: content is `<path>/dna`
/// when that subfolder exists, else the folder itself — shared by sync and
/// `--check` so both always hash and copy the same tree. Backslashes in the
/// configured path are normalized so committed Windows-style paths work on
/// every platform.
({Directory folder, Directory content}) resolvePathLayer(
  String targetRoot,
  DnaLayerConfig layer,
) {
  final raw = layer.path!.replaceAll('\\', '/');
  final folder = Directory(p.normalize(p.join(targetRoot, raw)));
  final dnaSub = Directory(p.join(folder.path, 'dna'));
  return (folder: folder, content: dnaSub.existsSync() ? dnaSub : folder);
}

/// Parsed `dna:` block of a target repo (dna.yaml, package.json, or
/// pubspec.yaml): the ordered layer list (later layers win; the gg_dna
/// base DNA is the implicit lowest layer) plus non-fatal warnings.
class DnaConfig {
  /// Constructor.
  const DnaConfig({required this.layers, required this.warnings});

  /// The configured layers, in `order` order.
  final List<DnaLayerConfig> layers;

  /// Non-fatal findings, e.g. configured layers missing from `order`.
  final List<String> warnings;

  /// Reads the `dna:` block from the first of [dnaConfigFilenames] found
  /// in [targetRoot]; more than one file with a block is a hard error.
  static DnaConfig? read(String targetRoot) {
    final found = <String, DnaConfig>{};
    for (final name in dnaConfigFilenames) {
      final file = File(p.join(targetRoot, name));
      if (!file.existsSync()) continue;
      final content = file.readAsStringSync();
      final config = name.endsWith('.json')
          ? parseJson(content, source: name)
          : parse(content, source: name);
      if (config != null) found[name] = config;
    }
    if (found.length > 1) {
      throw FormatException(
        '`dna:` is configured in more than one file '
        '(${found.keys.join(', ')}) — keep exactly one config source.',
      );
    }
    return found.isEmpty ? null : found.values.single;
  }

  /// Parses a YAML config string — `null` without `dna:`, [FormatException]
  /// on any invalid config (types, duplicates, git/path/version rules).
  static DnaConfig? parse(
    String yamlContent, {
    String source = 'pubspec.yaml',
  }) {
    final Object? doc;
    try {
      doc = loadYaml(yamlContent);
    } on YamlException catch (e) {
      throw FormatException('$source is not valid YAML: ${e.message}');
    }
    return _parseDoc(doc, source);
  }

  /// Parses a JSON config string (package.json style, `"dna"` key) with
  /// the same validation rules as [parse].
  static DnaConfig? parseJson(
    String jsonContent, {
    String source = 'package.json',
  }) {
    final Object? doc;
    try {
      doc = jsonDecode(jsonContent);
    } on FormatException catch (e) {
      throw FormatException('$source is not valid JSON: ${e.message}');
    }
    return _parseDoc(doc, source);
  }

  // ...........................................................................
  static DnaConfig? _parseDoc(Object? doc, String source) {
    if (doc is! Map) return null;
    final dna = doc['dna'];
    if (dna == null) return null;
    if (dna is! Map) {
      throw FormatException(
        '`dna:` in $source must be a map.',
      );
    }

    final order = _readOrder(dna, source);
    final layers = <DnaLayerConfig>[];
    for (final name in order) {
      layers.add(_readLayer(dna, name, source));
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
  static List<String> _readOrder(Map<dynamic, dynamic> dna, String source) {
    final order = dna['order'];
    if (order == null) return const [];
    if (order is! List) {
      throw FormatException(
        '`dna: order:` in $source must be a list of layer names.',
      );
    }
    final names = <String>[];
    for (final entry in order) {
      if (entry is! String || entry.isEmpty) {
        throw FormatException(
          '`dna: order:` in $source must only contain '
          'non-empty layer names.',
        );
      }
      if (names.contains(entry)) {
        throw FormatException(
          '`dna: order:` in $source lists layer "$entry" twice.',
        );
      }
      names.add(entry);
    }
    return names;
  }

  // ...........................................................................
  static DnaLayerConfig _readLayer(
    Map<dynamic, dynamic> dna,
    String name,
    String source,
  ) {
    final raw = dna[name];
    if (raw == null) {
      throw FormatException(
        'dna: layer "$name" is listed in `dna: order:` but has no '
        'configuration map in $source.',
      );
    }
    if (raw is! Map) {
      throw FormatException(
        'dna: layer "$name" in $source must be a map with either '
        '`git:` or `path:`.',
      );
    }

    final git = _readString(raw, 'git', name, source);
    final path = _readString(raw, 'path', name, source);
    final rawVersion = _readString(raw, 'version', name, source);

    if ((git == null) == (path == null)) {
      throw FormatException(
        'dna: layer "$name" in $source must have either `git:` or '
        '`path:` (exactly one of both).',
      );
    }
    if (rawVersion != null && git == null) {
      throw FormatException(
        'dna: layer "$name" in $source must not combine `version:` '
        'with `path:` — version constraints only apply to git layers.',
      );
    }

    VersionConstraint? constraint;
    if (rawVersion != null) {
      try {
        constraint = VersionConstraint.parse(rawVersion);
      } on FormatException {
        throw FormatException(
          'dna: layer "$name" in $source has an invalid `version:` '
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
    String source,
  ) {
    final value = layer[key];
    if (value == null) return null;
    if (value is String && value.isNotEmpty) return value;
    // YAML parses bare numbers like `version: 1.4` as doubles — keep the
    // error actionable instead of surfacing a cast error.
    if (key == 'version' && value is num) return '$value';
    throw FormatException(
      'dna: layer "$name" in $source has an invalid `$key:` value — '
      'expected a non-empty string.',
    );
  }
}
