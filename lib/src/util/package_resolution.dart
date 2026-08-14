// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';

import 'package:yaml/yaml.dart';

import 'dna_fs.dart';

/// The package ecosystem a DNA layer was installed from.
enum PackageEcosystem {
  /// Installed by pnpm, below `node_modules/`.
  node,

  /// Installed by pub, listed in `.dart_tool/package_config.json`.
  pub,
}

/// How the package manager obtained a package.
enum PackageSource {
  /// From a registry (pub.dev, npm) — pinned by version and integrity.
  registry,

  /// From a local folder: pub `path:`, pnpm `link:`. This is what
  /// gg_localize_refs produces for a workspace checkout.
  path,

  /// From a git repository.
  git,
}

// .............................................................................
/// A package the target has installed, with the folder it lives in.
class LocatedPackage {
  /// Creates the record.
  const LocatedPackage({
    required this.identity,
    required this.packageName,
    required this.ecosystem,
    required this.root,
    required this.source,
    this.version,
  });

  /// Canonical identity (lowercase, npm scope stripped, `_` folded to
  /// `-`) — `@tssuite/dna-base` and `dna_base` share it.
  final String identity;

  /// The package name as installed, in its ecosystem's spelling.
  final String packageName;

  /// Which ecosystem provided it.
  final PackageEcosystem ecosystem;

  /// Posix folder that contains the package's `dna/`.
  final String root;

  /// How the package manager obtained it.
  final PackageSource source;

  /// The resolved version; `null` when nothing states one.
  final String? version;
}

// .............................................................................
/// Canonical package identity: lowercase, npm scope dropped, `_` folded
/// to `-`.
///
/// The same DNA published to both registries collapses to one identity:
/// `@tssuite/dna-base`, `dna-base` and `dna_base` are all `dna-base`. A
/// repository may therefore declare it in `package.json` *and*
/// `pubspec.yaml` — dual publication is the normal case — without the
/// layer being applied twice.
String canonicalPackageName(String name) {
  final bare = name.startsWith('@') && name.contains('/')
      ? name.substring(name.indexOf('/') + 1)
      : name;
  return bare.toLowerCase().replaceAll('_', '-');
}

// .............................................................................
/// One entry of a lock file.
class _LockEntry {
  const _LockEntry({required this.source, this.version, this.path});

  final PackageSource source;
  final String? version;

  /// Folder of a [PackageSource.path] entry, as written in the lock file.
  final String? path;
}

// .............................................................................
/// What the target's package managers resolved: the installed names, their
/// versions and the folders they live in.
///
/// Lock files answer *what* and *whether*; `.dart_tool/package_config.json`
/// and `node_modules/` answer *where*. For a registry package the lock
/// carries an identity (name, version, integrity) but no folder —
/// reconstructing one would mean reimplementing pub-cache and pnpm-store
/// layout rules (`PUB_CACHE`, host sanitisation, `virtualStoreDir`, name
/// mangling, `nodeLinker`), undocumented internals that change between
/// releases. So the lock is read for identity and version, and the
/// package managers' own resolution output for the path.
class PackageResolution {
  PackageResolution._({
    required this._host,
    required this._targetRoot,
    required this._nodeLock,
    required this._pubLock,
    required this._pubRoots,
    required this.warnings,
  }) {
    _nodeNames = _byIdentity([..._nodeLock.keys]);
    _pubNames = _byIdentity([..._pubLock.keys, ..._pubRoots.keys]);
  }

  final DnaHost _host;
  final String _targetRoot;
  final Map<String, _LockEntry> _nodeLock;
  final Map<String, _LockEntry> _pubLock;
  final Map<String, String> _pubRoots;
  late final Map<String, List<String>> _nodeNames;
  late final Map<String, List<String>> _pubNames;

  /// Problems found while reading the lock files — never fatal.
  final List<String> warnings;

  // ...........................................................................
  /// Reads everything the target's package managers know.
  factory PackageResolution.read(DnaHost host, String targetRoot) {
    final warnings = <String>[];
    return PackageResolution._(
      host: host,
      targetRoot: targetRoot,
      nodeLock: _readPnpmLock(host, targetRoot, warnings),
      pubLock: _readPubspecLock(host, targetRoot, warnings),
      pubRoots: _readPackageConfig(host, targetRoot, warnings),
      warnings: warnings,
    );
  }

  // ...........................................................................
  /// Locates the package [declaredName] refers to; `null` when it is not
  /// installed. The first entry of [locateAll].
  LocatedPackage? locate(String declaredName) {
    final all = locateAll(declaredName);
    return all.isEmpty ? null : all.first;
  }

  // ...........................................................................
  /// Every installed copy of [declaredName], node before pub.
  ///
  /// A DNA published to both registries is installed twice, and the two
  /// copies are expected to carry the same `dna/` tree — the caller
  /// compares them and warns when they drifted apart. node comes first
  /// because the npm tarball is the complete one: pub drops every dotfile
  /// from `dna/`.
  List<LocatedPackage> locateAll(String declaredName) {
    final identity = canonicalPackageName(declaredName);
    final found = <LocatedPackage>[];

    for (final name in _nodeCandidates(declaredName, identity)) {
      final root = '$_targetRoot/node_modules/$name';
      if (!_host.existsDir(root)) continue;
      found.add(
        _hit(identity, name, PackageEcosystem.node, root, _nodeLock[name]),
      );
      break;
    }

    for (final name in _pubCandidates(declaredName, identity)) {
      final rootUri = _pubRoots[name];
      if (rootUri == null) continue;
      final root = resolveRootUri(rootUri, _targetRoot);
      if (!_host.existsDir(root)) continue;
      found.add(
        _hit(identity, name, PackageEcosystem.pub, root, _pubLock[name]),
      );
      break;
    }
    if (found.isNotEmpty) return found;

    // Only reachable when the workspace was localized but not reinstalled:
    // the lock already names the sibling folder while node_modules and
    // package_config.json still point at the registry copy.
    for (final entry in [
      for (final name in _nodeCandidates(declaredName, identity))
        (name: name, lock: _nodeLock[name], eco: PackageEcosystem.node),
      for (final name in _pubCandidates(declaredName, identity))
        (name: name, lock: _pubLock[name], eco: PackageEcosystem.pub),
    ]) {
      final lockPath = entry.lock?.path;
      if (lockPath == null) continue;
      final root = lockPath.startsWith('/')
          ? lockPath
          : normalizePosix('$_targetRoot/$lockPath');
      if (!_host.existsDir(root)) continue;
      return [_hit(identity, entry.name, entry.eco, root, entry.lock)];
    }

    return found;
  }

  // ...........................................................................
  /// Explains why [declaredName] could not be located — which names were
  /// tried where, and what the lock files know about it.
  String describeFailure(String declaredName) {
    final identity = canonicalPackageName(declaredName);
    final lines = <String>[
      'identity:            $identity',
      'node_modules/:       tried '
          '${_nodeCandidates(declaredName, identity).join(', ')}',
      'package_config.json: tried '
          '${_pubCandidates(declaredName, identity).join(', ')}',
    ];

    final known = <String>[
      for (final name in _nodeCandidates(declaredName, identity))
        if (_nodeLock[name] != null)
          'pnpm-lock.yaml knows $name ${_nodeLock[name]!.version ?? ''}'.trim(),
      for (final name in _pubCandidates(declaredName, identity))
        if (_pubLock[name] != null)
          'pubspec.lock knows $name ${_pubLock[name]!.version ?? ''}'.trim(),
    ];
    lines.add(
      known.isEmpty
          ? 'lock files:          not declared anywhere'
          : '${known.join('; ')} — declared but not installed. '
                'Run pnpm install / dart pub get.',
    );
    return lines.join('\n  ');
  }

  // ...........................................................................
  /// The version to record for a package located at [root].
  ///
  /// Never crosses ecosystems: a pub tarball ships `pubspec.yaml` *and*
  /// `package.json`, so reading the wrong one reports the other
  /// registry's version. For a registry package the lock is authoritative;
  /// for a `path`/`link` package the manifest on disk is, because a
  /// localized sibling can bump its version without a re-resolve.
  String? _versionFor(
    String root,
    PackageEcosystem ecosystem,
    _LockEntry? lock,
  ) {
    final manifest = ecosystem == PackageEcosystem.node
        ? _packageJsonVersion('$root/package.json')
        : _pubspecVersion('$root/pubspec.yaml');

    if (lock == null) return manifest;
    if (lock.source == PackageSource.path) return manifest ?? lock.version;
    if (manifest != null && lock.version != null && manifest != lock.version) {
      warnings.add(
        '$root: the lock file pins ${lock.version} but the installed '
        'package declares $manifest — run pnpm install / dart pub get.',
      );
    }
    return lock.version ?? manifest;
  }

  // ...........................................................................
  String? _packageJsonVersion(String path) {
    if (!_host.existsFile(path)) return null;
    try {
      final doc = jsonDecode(_host.readString(path));
      if (doc is Map<String, dynamic> && doc['version'] is String) {
        return doc['version'] as String;
      }
    } on FormatException {
      // Not our file to validate.
    }
    return null;
  }

  // ...........................................................................
  String? _pubspecVersion(String path) {
    if (!_host.existsFile(path)) return null;
    try {
      final doc = loadYaml(_host.readString(path));
      if (doc is Map && doc['version'] != null) return '${doc['version']}';
    } on YamlException {
      // Not our file to validate.
    }
    return null;
  }

  // ...........................................................................
  LocatedPackage _hit(
    String identity,
    String name,
    PackageEcosystem ecosystem,
    String root,
    _LockEntry? lock,
  ) => LocatedPackage(
    identity: identity,
    packageName: name,
    ecosystem: ecosystem,
    root: root,
    source: lock?.source ?? PackageSource.registry,
    version: _versionFor(root, ecosystem, lock),
  );

  // ...........................................................................
  // Candidates cover the spelling written in the config, the canonical
  // one, and whatever the ecosystem actually installed — that last group
  // is what lets a pub-declared parent (`dna_base`) resolve inside a
  // node-only consumer where the package is `@tssuite/dna-base`.
  List<String> _nodeCandidates(String declared, String identity) =>
      _candidates([declared, identity], _nodeNames[identity]);

  List<String> _pubCandidates(String declared, String identity) => _candidates([
    declared,
    identity.replaceAll('-', '_'),
  ], _pubNames[identity]);

  static List<String> _candidates(List<String> first, List<String>? installed) {
    final out = <String>[];
    for (final name in [...first, ...?installed]) {
      if (!out.contains(name)) out.add(name);
    }
    return out;
  }

  static Map<String, List<String>> _byIdentity(List<String> names) {
    final out = <String, List<String>>{};
    for (final name in names) {
      out.putIfAbsent(canonicalPackageName(name), () => []).add(name);
    }
    return out;
  }
}

// .............................................................................
/// Collapses `.` and `..` segments of the posix path [path].
String normalizePosix(String path) {
  final parts = <String>[];
  for (final part in path.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..' && parts.isNotEmpty && parts.last != '..') {
      parts.removeLast();
      continue;
    }
    parts.add(part);
  }
  return (path.startsWith('/') ? '/' : '') + parts.join('/');
}

// .............................................................................
/// Resolves a `package_config.json` `rootUri` against [targetRoot].
/// Relative URIs are relative to the `.dart_tool` folder.
String resolveRootUri(String rootUri, String targetRoot) {
  if (rootUri.startsWith('file://')) {
    return Uri.parse(rootUri).toFilePath(windows: false);
  }
  final base = Uri.parse('$targetRoot/.dart_tool/');
  final resolved = base.resolve(rootUri).path;
  return resolved.endsWith('/')
      ? resolved.substring(0, resolved.length - 1)
      : resolved;
}

// .............................................................................
// Lock file readers. Each is total: a missing file yields an empty map, a
// malformed one an empty map plus a warning. Resolution must keep working
// without them — they sharpen identity and versions, they do not gate.

Map<String, _LockEntry> _readPnpmLock(
  DnaHost host,
  String targetRoot,
  List<String> warnings,
) {
  final out = <String, _LockEntry>{};
  final path = '$targetRoot/pnpm-lock.yaml';
  if (!host.existsFile(path)) {
    for (final other in const ['package-lock.json', 'yarn.lock']) {
      if (host.existsFile('$targetRoot/$other')) {
        warnings.add(
          '$other found but no pnpm-lock.yaml — DNA repositories use pnpm. '
          'Run `pnpm import` and delete $other.',
        );
      }
    }
    return out;
  }

  final Object? doc;
  try {
    doc = loadYaml(host.readString(path));
  } on YamlException catch (e) {
    warnings.add('pnpm-lock.yaml could not be read ($e) — ignored.');
    return out;
  }
  if (doc is! Map) return out;

  // `importers` is the only place a `link:` target appears.
  final importers = doc['importers'];
  if (importers is Map) {
    for (final importer in importers.values) {
      if (importer is! Map) continue;
      for (final section in const [
        'dependencies',
        'devDependencies',
        'optionalDependencies',
      ]) {
        final deps = importer[section];
        if (deps is! Map) continue;
        for (final entry in deps.entries) {
          final spec = entry.value;
          final raw = (spec is Map ? spec['version'] : spec)?.toString();
          if (raw == null) continue;
          out['${entry.key}'] = raw.startsWith('link:')
              ? _LockEntry(
                  source: PackageSource.path,
                  path: raw.substring('link:'.length),
                )
              : _LockEntry(
                  source: PackageSource.registry,
                  version: _pnpmVersion(raw),
                );
        }
      }
    }
  }

  // `packages` enumerates every installed name — the identity index.
  final packages = doc['packages'];
  if (packages is Map) {
    for (final key in packages.keys) {
      final text = '$key';
      final head = text.contains('(')
          ? text.substring(0, text.indexOf('('))
          : text;
      final at = head.lastIndexOf('@');
      if (at <= 0) continue;
      out.putIfAbsent(head.substring(0, at), () {
        return _LockEntry(
          source: PackageSource.registry,
          version: head.substring(at + 1),
        );
      });
    }
  }
  return out;
}

// .............................................................................
/// `4.1.10(vitest@4.1.10)` → `4.1.10`.
String _pnpmVersion(String raw) =>
    raw.contains('(') ? raw.substring(0, raw.indexOf('(')) : raw;

// .............................................................................
Map<String, _LockEntry> _readPubspecLock(
  DnaHost host,
  String targetRoot,
  List<String> warnings,
) {
  final out = <String, _LockEntry>{};
  final path = '$targetRoot/pubspec.lock';
  if (!host.existsFile(path)) return out;

  final Object? doc;
  try {
    doc = loadYaml(host.readString(path));
  } on YamlException catch (e) {
    warnings.add('pubspec.lock could not be read ($e) — ignored.');
    return out;
  }
  if (doc is! Map) return out;
  final packages = doc['packages'];
  if (packages is! Map) return out;

  for (final entry in packages.entries) {
    final value = entry.value;
    if (value is! Map) continue;
    final description = value['description'];
    final source = switch ('${value['source']}') {
      'path' => PackageSource.path,
      'git' => PackageSource.git,
      _ => PackageSource.registry,
    };
    out['${entry.key}'] = _LockEntry(
      source: source,
      version: value['version']?.toString(),
      path: source == PackageSource.path && description is Map
          ? description['path']?.toString()
          : null,
    );
  }
  return out;
}

// .............................................................................
Map<String, String> _readPackageConfig(
  DnaHost host,
  String targetRoot,
  List<String> warnings,
) {
  final out = <String, String>{};
  final path = '$targetRoot/.dart_tool/package_config.json';
  if (!host.existsFile(path)) return out;

  final Object? doc;
  try {
    doc = jsonDecode(host.readString(path));
  } on FormatException catch (e) {
    warnings.add('package_config.json could not be read ($e) — ignored.');
    return out;
  }
  if (doc is! Map<String, dynamic>) return out;

  for (final package in (doc['packages'] as List?) ?? const []) {
    if (package is! Map<String, dynamic>) continue;
    final name = package['name'];
    final rootUri = package['rootUri'];
    if (name is! String || rootUri is! String) continue;
    out[name] = rootUri;
  }
  return out;
}
