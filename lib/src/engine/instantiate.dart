// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:typed_data';

import '../util/claude_md.dart';
import '../util/dna_config.dart';
import '../util/dna_fs.dart';
import '../util/dna_layout.dart';
import '../util/dna_manifest.dart';
import '../util/dna_tree_hash.dart';
import '../util/dna_vars.dart';
import '../util/json_merge.dart';
import '../util/jsonc.dart';
import '../util/layer_graph.dart';
import '../util/md_tags.dart';
import '../util/package_resolution.dart';

// .............................................................................
/// The folder a developer opens to edit [layer]: a localized checkout is
/// shown relative to [targetRoot], a registry install by its package name.
String _displayRootOf(ResolvedLayer layer, String targetRoot) =>
    layer.source == PackageSource.path
    ? _relativeTo(layer.root, targetRoot)
    : layer.package;

// .............................................................................
/// [path] relative to [base]; [path] unchanged when the two cannot be
/// related (one absolute, one relative).
String _relativeTo(String path, String base) {
  if (path.startsWith('/') != base.startsWith('/')) return path;
  final from = base.split('/').where((s) => s.isNotEmpty).toList();
  final to = path.split('/').where((s) => s.isNotEmpty).toList();
  var common = 0;
  while (common < from.length &&
      common < to.length &&
      from[common] == to[common]) {
    common++;
  }
  return [
    ...List.filled(from.length - common, '..'),
    ...to.skip(common),
  ].join('/');
}

/// Headline of the per-file guard failure.
const String uncommittedTargetsMessage =
    'Generated files carry invalid changes:';

/// Headline when DNA files escape a leading dot with `dot_`.
const String invalidDotEscapesMessage = 'Invalid dot escapes in dna/:';

/// Commit message of the automatic commit that carries everything the
/// DNA generated.
const String generatedDnaCommitMessage = '#gg: generated DNA';

// .............................................................................
/// Outcome of one instantiation run (see the golden-update semantics in
/// the README): locally changed instances are backed up and overwritten,
/// pending updates are written and reported once, an up-to-date project
/// passes.
class DnaInstantiationResult {
  /// Creates the result.
  const DnaInstantiationResult({
    this.messages = const [],
    this.warnings = const [],
    this.backedUp = const [],
    this.backupDir,
    this.updated = const [],
    this.uncommittedTargets = const [],
    this.sources = const {},
    this.committed = false,
  });

  /// Progress and adoption log lines.
  final List<String> messages;

  /// Non-fatal findings of config parsing and merging.
  final List<String> warnings;

  /// Instances whose content was changed locally — the run copied the
  /// local content into [backupDir] and overwrote them with the DNA
  /// content.
  final List<String> backedUp;

  /// The system-temp folder holding the copies of [backedUp], keeping
  /// their project-relative paths. `null` when nothing was backed up.
  final String? backupDir;

  /// Paths written by this run (instances, dna/ files, CLAUDE.md,
  /// manifest).
  final List<String> updated;

  /// Whether [updated] was committed automatically as
  /// [generatedDnaCommitMessage]. `false` means the files are written
  /// but still need a manual commit (no repository, no git identity).
  final bool committed;

  /// Existing files this run had to overwrite or delete that carry
  /// uncommitted work — the run fails and writes nothing.
  final List<String> uncommittedTargets;

  /// For every reported path: the DNA source file it is produced from,
  /// e.g. `dna-base/dna/doc/develop.md` — the file to edit instead of
  /// the generated one. Paths without a DNA source (the manifest, the
  /// managed CLAUDE.md block) are absent.
  final Map<String, String> sources;

  /// Whether pending writes were blocked by the per-file guard.
  bool get blocked => uncommittedTargets.isNotEmpty;

  /// Whether the project was already fully up to date.
  bool get upToDate => !blocked && (updated.isEmpty || committed);
}

// .............................................................................
/// Runs one instantiation over [targetRoot]: expands the inheritance
/// tree, merges all `dna/` replicas (last override wins), renders markdown
/// markers, substitutes variables, converts file naming and reconciles the
/// generated state with the project — honoring instance ownership from the
/// manifest and the per-file guard (no existing file with uncommitted work
/// is ever overwritten).
Future<DnaInstantiationResult> instantiateDna({
  required DnaHost host,
  required String targetRoot,
  String? baseDnaRoot,
  required String baseVersion,
}) async {
  final messages = <String>[];
  final warnings = <String>[];

  // 1. Config and inheritance tree.
  final configResult = readDnaConfig(host, targetRoot);
  final config = configResult.config;
  warnings.addAll(configResult.warnings);

  // Read once and thread through — every lookup shares the same view of
  // what the package managers resolved.
  final resolution = PackageResolution.read(host, targetRoot);
  final graph = expandLayerGraph(
    host: host,
    targetRoot: targetRoot,
    config: config,
    resolution: resolution,
  );
  warnings.addAll(graph.warnings);

  // `display` names the layer the way a developer opens it: the local
  // folder for a localized checkout, the package name for a registry
  // install.
  final sources = <({String label, String root, String display})>[
    if (baseDnaRoot != null && host.existsDir('$baseDnaRoot/$dnaDirname'))
      // The engine's built-in base DNA is not a package a developer
      // opens — point at the `dna/` folder that overrides it instead.
      (label: 'base', root: baseDnaRoot, display: dnaDirname),
    for (final layer in graph.layers)
      (
        label: layer.name,
        root: layer.root,
        display: '${_displayRootOf(layer, targetRoot)}/$dnaDirname',
      ),
    // The repository's own `dna/` is applied unconditionally and always
    // last — however many layers `_dna.json` declares, and whether or not
    // one of them happens to be another copy of this same package. Every
    // `dna/` is hand-authored source, so it is the one layer that must
    // never lose a conflict, and it must be instantiated even when a
    // declared layer ships nothing at all.
    (label: 'self', root: targetRoot, display: dnaDirname),
  ];
  assert(
    sources.last.label == 'self',
    'the own dna/ must stay the last source',
  );

  // 2. Merge all replicas in order, tracking which DNA file each merged
  // path last came from.
  final merged = <String, Uint8List>{};
  final provenance = <String, String>{};
  var varsChain = <String, Object?>{};
  for (final source in sources) {
    varsChain = _applyLayer(
      host: host,
      merged: merged,
      varsChain: varsChain,
      label: source.label,
      dnaRoot: '${source.root}/$dnaDirname',
      displayRoot: source.display,
      provenance: provenance,
      messages: messages,
      warnings: warnings,
    );
  }

  // The configuration belongs to the developer, and `isDnaContent` is
  // what keeps it out of `merged` — and therefore out of every write and
  // delete path below. The role:dna test asserts the file survives two
  // runs byte-identical, which is what would break first if that
  // exclusion ever went away.

  // 3. Render markdown markers.
  for (final rel in merged.keys.toList()) {
    if (!rel.toLowerCase().endsWith('.md')) continue;
    final text = _decodeText(merged[rel]!);
    if (text == null) continue;
    merged[rel] = _encodeText(renderMarkers(text));
  }

  // 4. Substitute variables, then materialize the merged _vars.json.
  varsChain = mergeDnaVarEntries(varsChain, config.vars);
  final vars = DnaVars.fromEntries(varsChain);
  for (final rel in merged.keys.toList()) {
    final text = _decodeText(merged[rel]!);
    if (text == null) continue;
    merged[rel] = _encodeText(substituteDnaVars(text, vars));
  }
  merged[dnaVarsFilename] = _encodeText(encodeJsonPretty(vars.toJson()));

  // 5. Plan instances.
  final instancePlan = <String, String>{}; // instance path -> merged rel
  for (final rel in merged.keys) {
    if (isPrivatePath(rel)) continue;
    final instancePath = decodeDotSegments(rel);
    if (isForbiddenInstanceTarget(instancePath)) {
      warnings.add('Instance target "$instancePath" is forbidden — skipped.');
      continue;
    }
    final collision = instancePlan[instancePath];
    if (collision != null) {
      throw FormatException(
        'Instance collision: "$rel" and "$collision" both map to '
        '"$instancePath".',
      );
    }
    instancePlan[instancePath] = rel;
  }

  // 6. Produce instance contents.
  final instanceBytes = <String, Uint8List>{
    for (final entry in instancePlan.entries) entry.key: merged[entry.value]!,
  };

  // 6b. Where each project path comes from — the DNA file to edit
  // instead of the generated one.
  final pathSources = <String, String>{
    for (final entry in provenance.entries)
      '$dnaDirname/${entry.key}': entry.value,
    for (final entry in instancePlan.entries)
      if (provenance[entry.value] != null) entry.key: provenance[entry.value]!,
  };

  // 7. Reconcile with the current project state.
  final previous = DnaManifest.read(host, targetRoot);
  final previousHashes = {
    for (final i in previous?.instances ?? const <DnaManifestInstance>[])
      i.path: i.hash,
  };

  final instanceWrites = <String>[];
  // Instances that carry local changes: the DNA content wins, the local
  // content is copied to a folder below the system temp directory.
  final backedUp = <String>[];
  for (final entry in instanceBytes.entries) {
    final path = entry.key;
    final full = '$targetRoot/$path';
    final newBytes = entry.value;
    if (!host.existsFile(full)) {
      instanceWrites.add(path);
      if (!previousHashes.containsKey(path)) {
        messages.add('+ instantiated $path');
      } else {
        messages.add('+ restored missing $path');
      }
      continue;
    }
    final currentBytes = host.readBytes(full);
    if (_bytesEqual(currentBytes, newBytes)) {
      if (!previousHashes.containsKey(path)) {
        messages.add('adopted $path (already up to date)');
      }
      continue;
    }
    final ownedHash = previousHashes[path];
    if (ownedHash == null) {
      instanceWrites.add(path);
      messages.add(
        'adopted $path (overwritten — previous content is in git '
        'history)',
      );
      continue;
    }
    if (hashFileBytes(currentBytes) == ownedHash) {
      instanceWrites.add(path);
      messages.add('~ updated $path');
      continue;
    }
    instanceWrites.add(path);
    backedUp.add(path);
    messages.add('~ updated $path (local changes were backed up)');
  }

  final instanceDeletes = <String>[];
  for (final entry in previousHashes.entries) {
    final path = entry.key;
    if (instanceBytes.containsKey(path)) continue;
    final full = '$targetRoot/$path';
    if (!host.existsFile(full)) continue;
    if (hashFileBytes(host.readBytes(full)) == entry.value) {
      instanceDeletes.add(path);
      messages.add('- removed $path (no longer produced by the DNA)');
    } else {
      warnings.add(
        '$path was modified locally and is no longer produced by the '
        'DNA — left in place, remove manually.',
      );
    }
  }

  // 8. CLAUDE.md managed block.
  String? claudeMdContent;
  List<String>? claudeImports;
  if (config.claude.claudeMdInclude != null) {
    claudeImports = expandClaudeMdIncludes(
      host: host,
      targetRoot: targetRoot,
      include: config.claude.claudeMdInclude!,
      projectedFiles: {
        ...instanceBytes.keys,
        ...merged.keys.map((rel) => '$dnaDirname/$rel'),
      },
    );
    claudeMdContent = updatedClaudeMd(host, targetRoot, claudeImports);
  }

  // 9. New manifest.
  final manifest = DnaManifest(
    layers: [
      if (baseDnaRoot != null && host.existsDir('$baseDnaRoot/$dnaDirname'))
        DnaManifestLayer(
          name: 'base',
          package: 'helix',
          resolvedVersion: baseVersion,
          hash: hashTree(host, '$baseDnaRoot/$dnaDirname'),
        ),
      for (final layer in graph.layers)
        DnaManifestLayer(
          name: layer.name,
          package: layer.package,
          ecosystem: layer.ecosystem.name,
          resolvedVersion: layer.version,
          via: layer.via,
          hash: hashTree(host, '${layer.root}/$dnaDirname'),
        ),
      DnaManifestLayer(
        name: 'self',
        hash: hashTree(host, '$targetRoot/$dnaDirname'),
      ),
    ],
    instances: [
      for (final path in instanceBytes.keys.toList()..sort())
        DnaManifestInstance(
          path: path,
          hash: hashFileBytes(instanceBytes[path]!),
        ),
    ],
    claude: DnaManifestClaude(claudeMdInclude: claudeImports),
    baseVersion: baseVersion,
    baseHash: baseDnaRoot == null
        ? null
        : hashTree(host, '$baseDnaRoot/$dnaDirname'),
  );
  final generatedJson = encodeJsonPretty(manifest.toJson());
  final generatedPath = '$targetRoot/$dnaGeneratedPath';
  final generatedChanged =
      !host.existsFile(generatedPath) ||
      host.readString(generatedPath) != generatedJson;

  final hasChanges =
      instanceWrites.isNotEmpty ||
      instanceDeletes.isNotEmpty ||
      claudeMdContent != null ||
      generatedChanged;
  if (!hasChanges) {
    return DnaInstantiationResult(messages: messages, warnings: warnings);
  }

  // 10. Per-file guard: every *existing* file this run would overwrite or
  // delete must be committed, so the change stays recoverable via git.
  // Unrelated dirty files in the repo do not block the run. Instances
  // with local changes are exempt: their content is preserved in the
  // backup folder, which is the recoverability the guard asks
  // for — and blocking them is what used to make a hand edit a dead end.
  final touched = <String>{
    ...instanceWrites,
    ...instanceDeletes,
    if (claudeMdContent != null) 'CLAUDE.md',
    if (generatedChanged) dnaGeneratedPath,
  }..removeAll(backedUp);
  final existingTouched = touched
      .where((path) => host.existsFile('$targetRoot/$path'))
      .toSet();
  if (existingTouched.isNotEmpty) {
    final uncommitted = await host.uncommittedPaths(targetRoot);
    final blocked = existingTouched.intersection(uncommitted).toList()..sort();
    if (blocked.isNotEmpty) {
      // Nothing was written — the planning messages would only mislead.
      return DnaInstantiationResult(
        messages: [uncommittedTargetsMessage],
        warnings: warnings,
        uncommittedTargets: blocked,
        sources: _sourcesFor(blocked, pathSources),
      );
    }
  }

  // 11. Write. `updated` reads well in reports, `touchedPaths` is what
  // git gets.
  final updated = <String>[];
  final touchedPaths = <String>[];
  void note(String path, {bool removed = false}) {
    updated.add(removed ? '$path (removed)' : path);
    touchedPaths.add(path);
  }

  // The local content first, so nothing is lost if a write fails. It
  // goes to a fresh system-temp folder — inside the project it would
  // become part of the repository and of the next DNA run.
  String? backupDir;
  if (backedUp.isNotEmpty) {
    backupDir = host.createTempDir(dnaBackupDirPrefix);
    for (final path in backedUp) {
      host.writeBytes('$backupDir/$path', host.readBytes('$targetRoot/$path'));
    }
  }
  for (final path in instanceWrites) {
    host.writeBytes('$targetRoot/$path', instanceBytes[path]!);
    note(path);
  }
  for (final path in instanceDeletes) {
    host.deleteFile('$targetRoot/$path');
    note(path, removed: true);
  }
  if (claudeMdContent != null) {
    host.writeString('$targetRoot/CLAUDE.md', claudeMdContent);
    note('CLAUDE.md');
  }
  if (generatedChanged) {
    host.writeString(generatedPath, generatedJson);
    note(dnaGeneratedPath);
  }

  // A folder that only existed to hold generated files goes with them —
  // git does not track directories, so this is a working-tree cleanup
  // and never part of the commit.
  for (final dir in ancestorDirs(
    updated
        .where((u) => u.endsWith(' (removed)'))
        .map((u) => u.substring(0, u.length - ' (removed)'.length)),
  )) {
    final path = '$targetRoot/$dir';
    if (!host.existsDir(path)) continue;
    if (host.listFilesRecursive(path).isNotEmpty) continue;
    host.deleteDir(path);
    messages.add('- removed empty folder $dir');
  }

  // 12. Commit what the DNA generated — it is machine-owned, so it never
  // belongs in the developer's working tree. A repository without git or
  // without an identity keeps the files for a manual commit.
  var committed = false;
  try {
    await host.commitPaths(targetRoot, touchedPaths, generatedDnaCommitMessage);
    committed = true;
    messages.add('committed as "$generatedDnaCommitMessage"');
  } on Object catch (e) {
    warnings.add(
      'Could not commit the generated files ($e) — commit them manually.',
    );
  }

  return DnaInstantiationResult(
    messages: messages,
    warnings: warnings,
    updated: updated,
    committed: committed,
    backedUp: backedUp,
    backupDir: backupDir,
    sources: _sourcesFor(backedUp, pathSources),
  );
}

// .............................................................................
Map<String, String> _sourcesFor(
  List<String> paths,
  Map<String, String> pathSources,
) => {
  for (final path in paths)
    if (pathSources[path] != null) path: pathSources[path]!,
};

// .............................................................................
Map<String, Object?> _applyLayer({
  required DnaHost host,
  required Map<String, Uint8List> merged,
  required Map<String, Object?> varsChain,
  required String label,
  required String dnaRoot,
  required String displayRoot,
  required Map<String, String> provenance,
  required List<String> messages,
  required List<String> warnings,
}) {
  var chain = varsChain;
  final files = host.listFilesRecursive(dnaRoot).where(isDnaContent).toList()
    ..sort();

  final mdOverrides = <String>[];
  final jsonOverrides = <String>[];

  final literalDotfiles = <String>[];

  for (final rel in files) {
    final name = rel.split('/').last;
    if (rel.split('/').any((s) => s.startsWith('.'))) literalDotfiles.add(rel);
    if (name.endsWith(legacyOverridesFileSuffix)) {
      throw FormatException(
        '"$rel" ($label) uses the removed $legacyOverridesFileSuffix '
        'suffix — rename it to X$overridesFileSuffix.',
      );
    }
    for (final suffix in yamlOverridesSuffixes) {
      if (name.endsWith(suffix)) {
        throw FormatException(
          '"$rel" ($label): structural YAML overrides are not supported '
          'yet — replace the whole file in a later layer instead.',
        );
      }
    }
    if (rel == dnaVarsFilename) {
      final parsed = parseDnaVarEntries(
        host.readString('$dnaRoot/$rel'),
        sourceLabel: '$label:$rel',
      );
      warnings.addAll(parsed.warnings);
      chain = mergeDnaVarEntries(chain, parsed.entries);
      continue;
    }
    if (name.endsWith(overridesFileSuffix)) {
      mdOverrides.add(rel);
      continue;
    }
    if (name.endsWith(jsonOverridesSuffix)) {
      jsonOverrides.add(rel);
      continue;
    }
    final bytes = host.readBytes('$dnaRoot/$rel');
    merged[rel] = bytes;
    provenance[rel] = '$displayRoot/$rel';
    if (rel.toLowerCase().endsWith('.md')) {
      final text = _decodeText(bytes);
      if (text != null) {
        warnings.addAll(
          detectLegacyMarkers(text).map((w) => '$label:$rel: $w'),
        );
      }
    }
  }

  // `dart pub publish` drops every path with a leading dot, so a DNA that
  // ships literal dotfiles loses them the moment it is consumed from pub.
  if (literalDotfiles.isNotEmpty) {
    final shown = literalDotfiles.take(3).join(', ');
    final more = literalDotfiles.length > 3 ? ', …' : '';
    warnings.add(
      '$label: ${literalDotfiles.length} dna/ path(s) start with a dot '
      '($shown$more) — dart pub publish drops them. Rename the segment '
      'to "$dotPrefix…", e.g. dna/${dotPrefix}vscode/settings.json.',
    );
  }

  // File-specific markdown overrides …
  // … then file-specific markdown overrides …
  for (final rel in mdOverrides..sort()) {
    final target = rel.substring(0, rel.length - overridesFileSuffix.length);
    final targetRel = '$target.md';
    final targetBytes = merged[targetRel];
    if (targetBytes == null) {
      messages.add('$label: "$rel" has no target file "$targetRel" — skipped.');
      continue;
    }
    final targetText = _decodeText(targetBytes);
    if (targetText == null) continue;
    final parsed = parseTagFile(host.readString('$dnaRoot/$rel'));
    warnings.addAll(parsed.warnings.map((w) => '$label:$rel: $w'));
    final applied = applyTagBlocks(
      targetText,
      parsed.blocks,
      fileLabel: targetRel,
    );
    warnings.addAll(applied.warnings.map((w) => '$label:$rel: $w'));
    merged[targetRel] = _encodeText(applied.content);
    provenance[targetRel] = '$displayRoot/$rel';
  }

  // … then JSON overrides.
  for (final rel in jsonOverrides..sort()) {
    final target = rel.substring(0, rel.length - jsonOverridesSuffix.length);
    final targetRel = '$target.json';
    final targetBytes = merged[targetRel];
    if (targetBytes == null) {
      messages.add('$label: "$rel" has no target file "$targetRel" — skipped.');
      continue;
    }
    final targetValue = parseJsonc(
      _decodeText(targetBytes) ?? '',
      sourceLabel: targetRel,
    );
    final patchValue = parseJsonc(
      host.readString('$dnaRoot/$rel'),
      sourceLabel: '$label:$rel',
    );
    final patched = jsonMergePatch(
      targetValue,
      patchValue,
      context: '$label:$rel',
    );
    warnings.addAll(patched.warnings);
    merged[targetRel] = _encodeText(encodeJsonPretty(patched.value));
    provenance[targetRel] = '$displayRoot/$rel';
  }

  return chain;
}

// .............................................................................
String? _decodeText(Uint8List bytes) {
  if (looksBinary(bytes)) return null;
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return null;
  }
}

Uint8List _encodeText(String text) => Uint8List.fromList(utf8.encode(text));

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
