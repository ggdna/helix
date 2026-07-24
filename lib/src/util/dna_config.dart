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

/// Files searched for the `dna:` config — exactly one may contain it.
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
/// The folder and content root of a path layer: content is always the
/// `<path>/dna/src` subfolder — shared by sync and `--check` so both
/// always hash and copy the same tree (the sync errors when it is
/// missing, the check reports a hash mismatch). Backslashes in the
/// configured path are normalized so committed Windows-style paths work
/// on every platform.
({Directory folder, Directory content}) resolvePathLayer(
  String targetRoot,
  DnaLayerConfig layer,
) {
  final raw = layer.path!.replaceAll('\\', '/');
  final folder = Directory(p.normalize(p.join(targetRoot, raw)));
  return (
    folder: folder,
    content: Directory(p.join(folder.path, 'dna', 'src')),
  );
}

/// The `dna: config: claude:` section — which files/folders end up as
/// `@`-imports in the managed CLAUDE.md block and which skill folders get
/// installed into `.claude/skills/`. A `null` include list means the
/// corresponding subsection is absent (vs. explicitly empty).
class DnaClaudeConfig {
  /// Constructor.
  const DnaClaudeConfig({this.claudeMdInclude, this.skillsInclude});

  /// `claude_md: include:` — files/folders referenced from CLAUDE.md.
  final List<String>? claudeMdInclude;

  /// `skills: include:` — folders whose skills are installed.
  final List<String>? skillsInclude;
}

/// Parsed `dna:` block of a target repo (dna.yaml, package.json, or
/// pubspec.yaml): the ordered layer list (later layers win; the gg_dna
/// base DNA is the implicit lowest layer), the tool config, and
/// non-fatal warnings.
class DnaConfig {
  /// Constructor.
  const DnaConfig({
    required this.layers,
    required this.warnings,
    this.claude,
  });

  /// The configured layers, in `order` order.
  final List<DnaLayerConfig> layers;

  /// Non-fatal findings, e.g. configured layers missing from `order`.
  final List<String> warnings;

  /// The `config: claude:` section; `null` when absent.
  final DnaClaudeConfig? claude;

  /// Reads the `dna:` block from [dnaConfigFilenames] in [targetRoot].
  static DnaConfig? read(String targetRoot) {
    final found = <String, DnaConfig>{};
    final broken = <String>[];
    for (final name in dnaConfigFilenames) {
      final file = File(p.join(targetRoot, name));
      if (!file.existsSync()) continue;
      final content = file.readAsStringSync();
      final DnaConfig? config;
      try {
        // A foreign top-level "dna" field of another npm tool must not be
        // mistaken for gg_dna config — non-map values are ignored there.
        config = name == 'package.json'
            ? parseJson(content, source: name, ignoreNonMapDna: true)
            : parse(content, source: name);
      } on _DecodeException catch (e) {
        // Undecodable files only fail the sync when no other file
        // provides the config — they may belong to another toolchain.
        broken.add(e.message);
        continue;
      }
      if (name == 'dna.yaml' && config == null) {
        throw const FormatException(
          'dna.yaml contains no top-level `dna:` block — use the same '
          '`dna:` syntax as in pubspec.yaml.',
        );
      }
      if (config != null) found[name] = config;
    }
    if (found.length > 1) {
      throw FormatException(
        '`dna:` is configured in more than one file '
        '(${found.keys.join(', ')}) — keep exactly one config source.',
      );
    }
    if (found.isEmpty) {
      if (broken.isNotEmpty) throw FormatException(broken.join('\n'));
      return null;
    }
    final config = found.values.single;
    if (broken.isEmpty) return config;
    return DnaConfig(
      layers: config.layers,
      claude: config.claude,
      warnings: [
        ...config.warnings,
        for (final message in broken)
          '$message — ignored, dna: config found in ${found.keys.single}.',
      ],
    );
  }

  /// Parses YAML config — `null` without `dna:`, throws on invalid config.
  static DnaConfig? parse(
    String yamlContent, {
    String source = 'pubspec.yaml',
  }) =>
      _parseDoc(_decode(() => loadYaml(yamlContent), 'YAML', source), source);

  /// Parses JSON config (package.json style) with the same rules as [parse].
  static DnaConfig? parseJson(
    String jsonContent, {
    String source = 'package.json',
    bool ignoreNonMapDna = false,
  }) =>
      _parseDoc(
        _decode(() => jsonDecode(jsonContent), 'JSON', source),
        source,
        ignoreNonMapDna: ignoreNonMapDna,
      );

  // ...........................................................................
  /// Runs [decode], converting YAML/JSON errors to a [_DecodeException].
  static Object? _decode(
    Object? Function() decode,
    String kind,
    String source,
  ) {
    try {
      return decode();
    } on YamlException catch (e) {
      throw _DecodeException('$source is not valid $kind: ${e.message}');
    } on FormatException catch (e) {
      throw _DecodeException('$source is not valid $kind: ${e.message}');
    }
  }

  // ...........................................................................
  static DnaConfig? _parseDoc(
    Object? doc,
    String source, {
    bool ignoreNonMapDna = false,
  }) {
    if (doc is! Map) return null;
    final dna = doc['dna'];
    if (dna == null) return null;
    if (dna is! Map) {
      if (ignoreNonMapDna) return null;
      throw FormatException(
        '`dna:` in $source must be a map.',
      );
    }

    final order = _readOrder(dna, source);
    final dependencies = _readDependencies(dna, source);

    final warnings = <String>[];
    for (final key in dna.keys) {
      if (key == 'order' || key == 'dependencies' || key == 'config') {
        continue;
      }
      // A map with git:/path: under dna: is the pre-3.0 layer syntax —
      // fail loudly (and before the missing-dependency error) instead of
      // silently dropping the layer.
      final value = dna[key];
      if (value is Map &&
          (value.containsKey('git') || value.containsKey('path'))) {
        throw FormatException(
          'dna: layer "$key" in $source uses the pre-3.0 syntax — since '
          'gg_dna 3.0 layers live under `dna: dependencies:`. Move the '
          'layer maps into a `dependencies:` block (see README).',
        );
      }
      warnings.add('dna: unknown key "$key" in $source — ignored.');
    }

    final layers = <DnaLayerConfig>[];
    for (final name in order) {
      layers.add(_readLayer(dependencies, name, source));
    }
    for (final key in dependencies.keys) {
      if (order.contains(key)) continue;
      warnings.add(
        'dna: layer "$key" is configured in `dependencies:` but not '
        'listed in `dna: order:` — ignored.',
      );
    }

    final claude = _readClaudeConfig(dna, source, warnings);
    return DnaConfig(layers: layers, warnings: warnings, claude: claude);
  }

  // ...........................................................................
  static Map<dynamic, dynamic> _readDependencies(
    Map<dynamic, dynamic> dna,
    String source,
  ) {
    final dependencies = dna['dependencies'];
    if (dependencies == null) return const {};
    if (dependencies is! Map) {
      throw FormatException(
        '`dna: dependencies:` in $source must be a map of layer '
        'configurations.',
      );
    }
    return dependencies;
  }

  // ...........................................................................
  /// Reads `config: claude:`; `null` when absent. Unknown keys warn.
  static DnaClaudeConfig? _readClaudeConfig(
    Map<dynamic, dynamic> dna,
    String source,
    List<String> warnings,
  ) {
    final config = dna['config'];
    if (config == null) return null;
    if (config is! Map) {
      throw FormatException('`dna: config:` in $source must be a map.');
    }
    for (final key in config.keys) {
      if (key != 'claude') {
        warnings.add(
          'dna: unknown key "config: $key" in $source — ignored.',
        );
      }
    }
    final claude = config['claude'];
    if (claude == null) return null;
    if (claude is! Map) {
      throw FormatException(
        '`dna: config: claude:` in $source must be a map.',
      );
    }
    for (final key in claude.keys) {
      if (key != 'claude_md' && key != 'skills') {
        warnings.add(
          'dna: unknown key "config: claude: $key" in $source — ignored.',
        );
      }
    }
    return DnaClaudeConfig(
      claudeMdInclude: _readIncludeList(claude, 'claude_md', source),
      skillsInclude: _readIncludeList(claude, 'skills', source),
    );
  }

  // ...........................................................................
  /// Reads `config: claude: <section>: include:` as a list of non-empty
  /// strings; `null` when the section is absent.
  static List<String>? _readIncludeList(
    Map<dynamic, dynamic> claude,
    String section,
    String source,
  ) {
    final raw = claude[section];
    if (raw == null) return null;
    if (raw is! Map) {
      throw FormatException(
        '`dna: config: claude: $section:` in $source must be a map '
        'with an `include:` list.',
      );
    }
    final include = raw['include'];
    if (include == null) return const [];
    if (include is! List) {
      throw FormatException(
        '`dna: config: claude: $section: include:` in $source must be '
        'a list of paths.',
      );
    }
    final result = <String>[];
    for (final entry in include) {
      if (entry is! String || entry.isEmpty) {
        throw FormatException(
          '`dna: config: claude: $section: include:` in $source must '
          'only contain non-empty path strings.',
        );
      }
      result.add(entry);
    }
    return result;
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
      if (entry == 'src') {
        throw FormatException(
          '`dna: order:` in $source must not contain a layer named '
          '"src" — <target>/dna/src is applied automatically as the '
          'last layer.',
        );
      }
      names.add(entry);
    }
    return names;
  }

  // ...........................................................................
  static DnaLayerConfig _readLayer(
    Map<dynamic, dynamic> dependencies,
    String name,
    String source,
  ) {
    final raw = dependencies[name];
    if (raw == null) {
      throw FormatException(
        'dna: layer "$name" is listed in `dna: order:` but has no '
        'configuration map under `dna: dependencies:` in $source.',
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

// .............................................................................
/// A config file that could not be decoded at all (vs. invalid dna config).
class _DecodeException extends FormatException {
  _DecodeException(super.message);
}
