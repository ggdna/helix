// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';
import 'dart:isolate';

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';
import 'package:path/path.dart' as p;

import '../util/claude_md.dart';
import '../util/claude_skills.dart';
import '../util/copy_directory.dart';
import '../util/dna_config.dart';
import '../util/dna_hash.dart';
import '../util/dna_manifest.dart';
import '../util/git_tag_resolver.dart';
import '../util/md_tags.dart';

/// Returns the directory the `gg_dna` package is installed in.
typedef PackageRootResolver = Future<String> Function();

/// Clones [url] into [dest], optionally checking out the tag/branch [ref].
typedef GitCloner = Future<void> Function(
  String url,
  Directory dest, {
  String? ref,
});

/// Reads the HEAD commit SHA of the repo at [dir]; `null` outside a repo.
typedef GitRevParse = Future<String?> Function(Directory dir);

/// Resolves the remote HEAD SHA of [url] without cloning; `null` on failure.
typedef GitLsRemote = Future<String?> Function(String url);

/// Lists the tags of [url] as name -> SHA (peeled); `null` on failure.
typedef GitLsRemoteTags = Future<Map<String, String>?> Function(String url);

/// Mirrors the gg_dna `dna/` folder into the target, merges the DNA layers
/// of the target repo's `dna:` config on top (later layers win,
/// `X.overrides.md` files patch sections/strings), then applies the
/// `config: claude:`
/// section: the managed CLAUDE.md block and the configured skills — all
/// non-interactive. All git access is injectable for tests.
class Sync extends Command<dynamic> {
  /// Constructor.
  Sync({
    required this.ggLog,
    PackageRootResolver? packageRootResolver,
    GitCloner? gitCloner,
    GitRevParse? gitRevParse,
    GitLsRemote? gitLsRemote,
    GitLsRemoteTags? gitLsRemoteTags,
  })  : _packageRootResolver = packageRootResolver ?? _defaultPackageRoot,
        _gitCloner = gitCloner ?? _defaultGitCloner,
        _gitRevParse = gitRevParse ?? _defaultGitRevParse,
        _gitLsRemote = gitLsRemote ?? _defaultGitLsRemote,
        _gitLsRemoteTags = gitLsRemoteTags ?? _defaultGitLsRemoteTags {
    argParser
      ..addOption(
        'source',
        abbr: 's',
        help: 'Source folder containing the base gg_dna content. Defaults to '
            'the root of the resolved gg_dna package. The `dna/src` '
            'subfolder of this path is mirrored into <target>/dna.',
      )
      ..addOption(
        'target',
        abbr: 't',
        help: 'Target folder. Defaults to <cwd>.',
      )
      ..addFlag(
        'check',
        abbr: 'c',
        help: 'Verify <target>/dna, CLAUDE.md and the installed skills are '
            'up to date without writing anything.',
        negatable: false,
      );
  }

  /// The log function.
  final GgLog ggLog;

  final PackageRootResolver _packageRootResolver;
  final GitCloner _gitCloner;
  final GitRevParse _gitRevParse;
  final GitLsRemote _gitLsRemote;
  final GitLsRemoteTags _gitLsRemoteTags;

  @override
  final name = 'sync';

  @override
  final description =
      'Mirror the gg_dna base DNA (dna/src) into <target>/dna and merge '
      'the DNA layers configured in the target repo on top — later layers '
      'win, <target>/dna/src is applied automatically as the last layer. '
      'Then apply the `config: claude:` section: maintain the managed '
      '@-import block in CLAUDE.md and install the configured skills into '
      "the project's .claude/skills folder — without prompting.\n"
      '\n'
      'The configuration lives in exactly one of '
      '${dnaConfigFilenames.join(', ')}\n'
      '(in package.json under the `"dna"` key) in the target root:\n'
      '\n'
      '  dna:\n'
      '    order:\n'
      '      - dna_company\n'
      '      - dna_project\n'
      '    dependencies:\n'
      '      dna_company:\n'
      '        git: https://github.com/acme/dna_company.git\n'
      '        version: ^1.4.0\n'
      '      dna_project:\n'
      '        path: ../dna_project\n'
      '    config:\n'
      '      claude:\n'
      '        claude_md:\n'
      '          include:\n'
      '            - dna/agents/conventions\n'
      '            - project_structure.md\n'
      '        skills:\n'
      '          include:\n'
      '            - dna/agents/skills\n'
      '\n'
      '  * every layer ships its mergeable DNA under `dna/src`.\n'
      '  * `git:` layers are cloned; a `version:` semver constraint is\n'
      '    resolved against the repo tags (highest matching tag wins).\n'
      '    `gg_*` shorthands expand to https://github.com/ggsuite/<name>.\n'
      '  * `path:` layers are local folders (relative to the target root).\n'
      '  * `<target>/dna/src` is the implicit last layer — it survives\n'
      '    the sync verbatim and is never listed in the config.\n'
      '  * `X.overrides.md` files patch sections (`## [@tag] …`) and\n'
      '    strings (`{{@tag:default}}`) of the merged `X.md`; a\n'
      '    `global.overrides.md` rewrites string tags in every file.\n'
      '    Overrides files are consumed, not copied.\n'
      '  * `claude_md: include:` entries (files or folders) become\n'
      '    @-import lines in a managed block in CLAUDE.md.\n'
      '  * `skills: include:` folders are mirrored into .claude/skills;\n'
      '    only skills gg_dna installed are overwritten or removed.';

  @override
  Future<void> run() async {
    if (argResults!.rest.isNotEmpty) {
      throw UsageException(
        'Positional overlay arguments were removed in gg_dna 2.0. '
        'Configure DNA layers via the `dna:` block in the target repo '
        '(${dnaConfigFilenames.join(', ')}).',
        usage,
      );
    }

    final packageRoot = await _packageRootResolver();
    final sourceDna = _resolveSourceDna(
      argResults!['source'] as String?,
      packageRoot,
    );
    final target = _resolveTarget(argResults!['target'] as String?);
    final checkOnly = argResults!['check'] as bool;

    if (!sourceDna.existsSync()) {
      throw UsageException(
        'Source dna folder does not exist: ${sourceDna.path}',
        usage,
      );
    }

    final DnaConfig? config;
    try {
      config = DnaConfig.read(target.path);
    } on FormatException catch (e) {
      throw UsageException(e.message, usage);
    }
    for (final warning in config?.warnings ?? const <String>[]) {
      ggLog(warning);
    }

    final dnaDir = Directory(p.join(target.path, 'dna'));
    final staging = Directory(p.join(target.path, '.gg_dna_staging'));
    final backup = Directory(p.join(target.path, '.gg_dna_backup'));

    // Crash recovery: a previous sync was interrupted between the two swap
    // renames — bring the backup back before doing anything else.
    if (!dnaDir.existsSync() && backup.existsSync()) {
      ggLog('Recovering ${dnaDir.path} from an interrupted sync.');
      backup.renameSync(dnaDir.path);
    }

    if (checkOnly) {
      await _check(sourceDna, dnaDir, config);
      return;
    }

    if (config == null) {
      ggLog(
        'No dna: config found (${dnaConfigFilenames.join(', ')}) '
        '— base sync only.',
      );
    }

    // Skill ownership of the previous sync — must be read before the swap
    // replaces the manifest.
    final previousManifest = DnaManifest.read(dnaDir);

    // Resolve all layers up front and in parallel — any error (unreachable
    // remote, unsatisfiable constraint, missing path) leaves the target
    // untouched; temps of already resolved layers are cleaned up.
    final resolved = <_ResolvedLayer>[];
    final DnaManifest manifest;
    try {
      resolved.addAll(
        await Future.wait(
          [
            for (final layer in config?.layers ?? const <DnaLayerConfig>[])
              _resolveLayer(layer, target, dnaDir),
          ],
          cleanUp: _cleanupLayer,
        ),
      );
      // <target>/dna/src is the implicit last layer.
      resolved.add(_resolveImplicitSrcLayer(target, dnaDir));
      manifest = _buildAndSwap(
        sourceDna: sourceDna,
        dnaDir: dnaDir,
        staging: staging,
        backup: backup,
        resolved: resolved,
        packageRoot: packageRoot,
        config: config,
        previousManifest: previousManifest,
      );
    } finally {
      resolved.forEach(_cleanupLayer);
      // A failed build leaves the staging folder behind — remove it. After
      // a successful swap it no longer exists.
      if (staging.existsSync()) {
        staging.deleteSync(recursive: true);
      }
    }

    _applyClaudeConfig(
      target: target,
      dnaDir: dnaDir,
      config: config,
      manifest: manifest,
      previousManifest: previousManifest,
    );
  }

  // ===========================================================================
  // Public helpers (also used by tests)
  // ===========================================================================

  /// Expands bare `gg_*` names to ggsuite github URLs; `null` otherwise.
  static String? expandShorthand(String arg) {
    final name = arg.endsWith('.git') ? arg.substring(0, arg.length - 4) : arg;
    if (!RegExp(r'^gg_[A-Za-z0-9._-]+$').hasMatch(name)) return null;
    return 'https://github.com/ggsuite/$name.git';
  }

  // ===========================================================================
  // Private
  // ===========================================================================

  Directory _resolveSourceDna(String? raw, String packageRoot) {
    final root = (raw != null && raw.isNotEmpty) ? raw : packageRoot;
    return Directory(p.join(root, 'dna', 'src'));
  }

  Directory _resolveTarget(String? raw) {
    if (raw != null && raw.isNotEmpty) {
      return Directory(raw);
    }
    // coverage:ignore-start
    return Directory.current;
    // coverage:ignore-end
  }

  // ...........................................................................
  /// Deletes the temp clone/snapshot of [layer], if any.
  static void _cleanupLayer(_ResolvedLayer layer) {
    final cleanup = layer.cleanup;
    if (cleanup != null && cleanup.existsSync()) {
      cleanup.deleteSync(recursive: true);
    }
  }

  // ...........................................................................
  /// Builds the merged dna tree in [staging] and rename-swaps it into
  /// place. Returns the manifest it wrote — the claude phase updates its
  /// `installedSkills` afterwards.
  DnaManifest _buildAndSwap({
    required Directory sourceDna,
    required Directory dnaDir,
    required Directory staging,
    required Directory backup,
    required List<_ResolvedLayer> resolved,
    required String packageRoot,
    required DnaConfig? config,
    required DnaManifest? previousManifest,
  }) {
    // Leftovers of an earlier interrupted sync.
    if (staging.existsSync()) {
      staging.deleteSync(recursive: true);
    }
    if (backup.existsSync()) {
      backup.deleteSync(recursive: true);
    }

    // The base is layer 0 and follows the same rules as every layer.
    _applyLayerContent('base', sourceDna, staging);
    final baseHash = hashDnaDirectory(sourceDna);

    for (final layer in resolved) {
      _applyLayerContent(layer.config.name, layer.contentRoot, staging);
      ggLog('Applied layer "${layer.config.name}".');
    }

    // Render all markers away, then restore in-dna layer sources verbatim —
    // their markers must survive for the next sync.
    _renderAll(staging);
    for (final layer in resolved) {
      if (layer.restoreRel == null) continue;
      final dest = Directory(p.join(staging.path, layer.restoreRel!));
      if (dest.existsSync()) {
        dest.deleteSync(recursive: true);
      }
      copyDirectory(layer.cleanup!, dest);
    }

    // The final hash MUST be computed after the snapshot restore — only
    // relative paths enter it, so staging and post-swap dna/ agree.
    // installedSkills carries the previous ownership until the claude
    // phase succeeds — a failing skill sync must not orphan owned skills.
    final manifest = DnaManifest(
      layers: [
        for (final layer in resolved)
          DnaManifestLayer.fromConfig(
            layer.config,
            resolvedVersion: layer.resolvedTag?.version.toString(),
            resolvedTag: layer.resolvedTag?.tag,
            commit: layer.commit,
            hash: layer.hash,
          ),
      ],
      claude: DnaManifestClaude(
        claudeMdInclude: config?.claude?.claudeMdInclude,
        skillsInclude: config?.claude?.skillsInclude,
        installedSkills: previousManifest?.claude.installedSkills ?? const [],
      ),
      baseVersion: readPackageVersion(packageRoot),
      baseHash: baseHash,
      hash: hashDnaDirectory(staging),
    );
    manifest.write(staging);

    // Swap the fully built tree into place. The two renames are the only
    // destructive moment; if the second one fails, the previous dna/ still
    // exists as the backup folder — nothing is ever lost.
    if (dnaDir.existsSync()) {
      dnaDir.renameSync(backup.path);
    }
    staging.renameSync(dnaDir.path);
    if (backup.existsSync()) {
      backup.deleteSync(recursive: true);
    }
    ggLog('Synced ${sourceDna.path} -> ${dnaDir.path}.');
    ggLog('Wrote ${p.join(dnaDir.path, dnaManifestFilename)}.');
    return manifest;
  }

  // ...........................................................................
  /// The implicit last layer: `<target>/dna/src` — never configured in
  /// the `dna:` block, always applied on top of all configured layers.
  static const DnaLayerConfig implicitSrcLayer =
      DnaLayerConfig(name: 'src', path: 'dna/src');

  // ...........................................................................
  /// Resolves a configured layer to a local content root (clone or the
  /// `<path>/dna/src` folder). Layers pointing into `<target>/dna` are a
  /// hard error — repo-local overrides live in the implicit `dna/src`.
  Future<_ResolvedLayer> _resolveLayer(
    DnaLayerConfig config,
    Directory target,
    Directory dnaDir,
  ) async {
    if (config.isGit) {
      return _resolveGitLayer(config);
    }

    final resolved = resolvePathLayer(target.path, config);
    final folder = resolved.folder;
    if (p.equals(folder.path, dnaDir.path) ||
        p.isWithin(dnaDir.path, folder.path)) {
      throw Exception(
        'Layer "${config.name}": path layers inside <target>/dna are no '
        'longer supported — move the content to <target>/dna/src (applied '
        'automatically as the last layer) and remove the layer entry.',
      );
    }
    if (!folder.existsSync()) {
      if (FileSystemEntity.isFileSync(folder.path)) {
        throw Exception(
          'Layer "${config.name}": path is a file, not a folder: '
          '${folder.path}',
        );
      }
      throw Exception(
        'Layer "${config.name}": path does not exist: ${folder.path}',
      );
    }
    if (!resolved.content.existsSync()) {
      throw Exception(
        'Layer "${config.name}" does not contain a dna/src folder: '
        '${resolved.content.path} — since gg_dna 4.0 the mergeable DNA '
        'of a layer lives under dna/src.',
      );
    }

    return _ResolvedLayer(
      config: config,
      contentRoot: resolved.content,
      hash: hashDnaDirectory(resolved.content),
    );
  }

  // ...........................................................................
  /// Resolves the implicit `<target>/dna/src` layer: missing folders are
  /// skipped as empty (git does not track empty folders); existing ones
  /// are snapshotted so the new tree carries them over verbatim.
  _ResolvedLayer _resolveImplicitSrcLayer(Directory target, Directory dnaDir) {
    final folder = Directory(p.join(dnaDir.path, 'src'));
    if (!folder.existsSync()) {
      return _ResolvedLayer(config: implicitSrcLayer, contentRoot: folder);
    }
    final tmp = Directory.systemTemp.createTempSync('gg_dna_layer_');
    copyDirectory(folder, tmp);
    return _ResolvedLayer(
      config: implicitSrcLayer,
      contentRoot: tmp,
      cleanup: tmp,
      restoreRel: 'src',
      hash: hashDnaDirectory(folder),
    );
  }

  // ...........................................................................
  Future<_ResolvedLayer> _resolveGitLayer(DnaLayerConfig config) async {
    final url = _gitUrlOf(config);

    ResolvedTag? resolvedTag;
    if (config.versionConstraint != null) {
      final result = await _resolveConstraint(config, url);
      if (result.problem != null) {
        throw Exception('Layer "${config.name}": ${result.problem}');
      }
      resolvedTag = result.tag;
      ggLog(
        'Layer "${config.name}": ${config.rawVersionConstraint} '
        '-> ${resolvedTag!.tag}',
      );
    }

    final tmp = Directory.systemTemp.createTempSync('gg_dna_layer_');
    try {
      ggLog('Cloning $url into ${tmp.path} …');
      await _gitCloner(url, tmp, ref: resolvedTag?.tag);
      final dna = Directory(p.join(tmp.path, 'dna', 'src'));
      if (!dna.existsSync()) {
        throw Exception(
          'Layer "${config.name}" does not contain a dna/src folder: '
          '${dna.path} — since gg_dna 4.0 the mergeable DNA of a layer '
          'repo lives under dna/src.',
        );
      }
      final commit = resolvedTag?.sha ?? await _gitRevParse(tmp);
      return _ResolvedLayer(
        config: config,
        contentRoot: dna,
        cleanup: tmp,
        commit: commit,
        resolvedTag: resolvedTag,
        hash: hashDnaDirectory(dna),
      );
    } catch (_) {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      rethrow;
    }
  }

  // ...........................................................................
  /// Resolves the constraint of [config] against the tags of [url];
  /// exactly one of `tag` and `problem` is set (shared by sync and check).
  Future<({ResolvedTag? tag, String? problem})> _resolveConstraint(
    DnaLayerConfig config,
    String url,
  ) async {
    final tags = await _gitLsRemoteTags(url);
    if (tags == null) {
      return (tag: null, problem: 'cannot list tags of $url');
    }
    final resolved = resolveTagForConstraint(tags, config.versionConstraint!);
    if (resolved == null) {
      final available = semverVersionsOf(tags.keys);
      return (
        tag: null,
        problem: 'no tag satisfies "${config.rawVersionConstraint}". '
            'Available versions: '
            '${available.isEmpty ? '(none)' : available.join(', ')}',
      );
    }
    return (tag: resolved, problem: null);
  }

  // ...........................................................................
  /// Expands `gg_*` shorthands in the `git:` value of [config].
  String _gitUrlOf(DnaLayerConfig config) {
    final shorthand = expandShorthand(config.git!);
    if (shorthand != null) {
      ggLog('Resolved shorthand "${config.git}" -> $shorthand');
      return shorthand;
    }
    return config.git!;
  }

  // ...........................................................................
  /// Copies one layer into [dnaDir], applies its `global.overrides.md`
  /// to every `.md` file, then its file-specific `X.overrides.md`
  /// patches (file-specific wins within the layer).
  void _applyLayerContent(String name, Directory root, Directory dnaDir) {
    if (!root.existsSync()) return;

    // Copy all dna content; collect the overrides files instead of
    // copying them. The pre-4.0 suffix is a hard error, not a skip.
    final overridesFiles = <String>[];
    copyDirectory(
      root,
      dnaDir,
      skip: (rel) {
        if (!isDnaContent(rel)) return true;
        if (rel.endsWith(legacyOverridesFileSuffix)) {
          throw Exception(
            'Layer "$name": $rel uses the pre-4.0 suffix — rename '
            '"$legacyOverridesFileSuffix" files to '
            '"$overridesFileSuffix".',
          );
        }
        if (rel.endsWith(overridesFileSuffix)) {
          overridesFiles.add(rel);
          return true;
        }
        if (rel == 'global.md') {
          ggLog(
            'Layer "$name": global.md is a reserved name — the file is '
            'copied, but it cannot be patched by an overrides file '
            '($globalOverridesFilename is always the global one).',
          );
        }
        return false;
      },
    );
    overridesFiles.sort();

    // The global overrides of this layer come first — file-specific
    // overrides of the same layer win over them.
    if (overridesFiles.remove(globalOverridesFilename)) {
      _applyGlobalOverrides(name, root, dnaDir);
    }

    for (final rel in overridesFiles) {
      final targetRel =
          '${rel.substring(0, rel.length - overridesFileSuffix.length)}.md';
      final targetFile = File(p.join(dnaDir.path, targetRel));
      if (!targetFile.existsSync()) {
        ggLog(
          'Layer "$name": $rel has no target file $targetRel — skipped.',
        );
        continue;
      }
      final content = File(p.join(root.path, rel)).readAsStringSync();
      for (final finding in detectLegacyMarkers(content)) {
        ggLog('Layer "$name" ($rel): $finding');
      }
      final parsed = parseTagFile(content);
      for (final warning in parsed.warnings) {
        ggLog('Layer "$name" ($rel): $warning');
      }
      final applied = applyTagBlocks(
        targetFile.readAsStringSync(),
        parsed.blocks,
        fileLabel: targetRel,
      );
      for (final warning in applied.warnings) {
        ggLog('Layer "$name": $warning');
      }
      targetFile.writeAsStringSync(applied.content);
    }
  }

  // ...........................................................................
  /// Applies the string blocks of `<layer>/global.overrides.md` to every
  /// `.md` file merged so far. Heading-form blocks warn and are skipped;
  /// tags that match no placeholder in any file warn once.
  void _applyGlobalOverrides(String name, Directory root, Directory dnaDir) {
    final content =
        File(p.join(root.path, globalOverridesFilename)).readAsStringSync();
    for (final finding in detectLegacyMarkers(content)) {
      ggLog('Layer "$name" ($globalOverridesFilename): $finding');
    }
    final parsed = parseTagFile(content);
    for (final warning in parsed.warnings) {
      ggLog('Layer "$name" ($globalOverridesFilename): $warning');
    }

    final blocks = <TagBlock>[];
    for (final block in parsed.blocks) {
      if (block.isHeadingForm) {
        ggLog(
          'Layer "$name" ($globalOverridesFilename): heading-form block '
          '"[@${block.tag}]" is not supported in global overrides — '
          'skipped.',
        );
        continue;
      }
      if (block.content.contains('\n')) {
        ggLog(
          'Layer "$name" ($globalOverridesFilename): replacement for tag '
          '"${block.tag}" spans multiple lines — collapsed to a single '
          'line.',
        );
      }
      if (block.content.contains('}}')) {
        ggLog(
          'Layer "$name" ($globalOverridesFilename): replacement value '
          'for tag "${block.tag}" contains "}}" — later overrides and '
          'rendering may truncate it.',
        );
      }
      blocks.add(block);
    }
    if (blocks.isEmpty) return;

    final foundTags = <String>{};
    for (final entity in dnaDir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.md')) continue;
      final original = entity.readAsStringSync();
      final updated =
          applyGlobalStringBlocks(original, blocks, foundTags: foundTags);
      if (updated != original) {
        entity.writeAsStringSync(updated);
      }
    }
    for (final block in blocks) {
      if (!foundTags.contains(block.tag)) {
        ggLog(
          'Layer "$name" ($globalOverridesFilename): tag "${block.tag}" '
          'not found in any file — skipped.',
        );
      }
    }
  }

  // ...........................................................................
  /// Strips all tag markers from every `.md` file under [dnaDir] and
  /// warns about leftover pre-4.0 notation (which stays literal).
  void _renderAll(Directory dnaDir) {
    for (final entity in dnaDir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.md')) continue;
      final content = entity.readAsStringSync();
      final rel =
          p.relative(entity.path, from: dnaDir.path).replaceAll('\\', '/');
      for (final finding in detectLegacyMarkers(content)) {
        ggLog('$rel: $finding');
      }
      final rendered = renderMarkers(content);
      if (rendered != content) {
        entity.writeAsStringSync(rendered);
      }
    }
  }

  // ...........................................................................
  Future<void> _check(
    Directory source,
    Directory dest,
    DnaConfig? config,
  ) async {
    if (!dest.existsSync()) {
      ggLog('  - missing: ${dest.path}');
      throw Exception('dna/ out of date — run `gg_dna sync` to fix.');
    }

    final manifest = DnaManifest.read(dest);
    if (manifest == null) {
      ggLog(
        '  - missing or pre-4.0 format: '
        '${p.join(dest.path, dnaManifestFilename)}',
      );
      throw Exception(
        'No usable .dna.json found — run `gg_dna sync` first.',
      );
    }

    final problems = <String>[];

    // 1) Local check: target/dna content must match the stored hash.
    final localHash = hashDnaDirectory(dest);
    if (localHash != manifest.hash) {
      problems.add(
        'local files modified since last sync '
        '(${manifest.hash} -> $localHash)',
      );
    }

    // 2) Source check: base hash must match.
    final baseHashNow = hashDnaDirectory(source);
    if (baseHashNow != manifest.baseHash) {
      problems.add(
        'base source has changed since last sync '
        '(${manifest.baseHash} -> $baseHashNow)',
      );
    }

    // 3) Config drift: the configured dna: block plus the implicit
    // <target>/dna/src layer must match the manifest.
    final layers = <DnaLayerConfig>[
      ...config?.layers ?? const <DnaLayerConfig>[],
      implicitSrcLayer,
    ];
    final drifted = layers.length != manifest.layers.length ||
        [
          for (var i = 0; i < layers.length; i++)
            manifest.layers[i].matchesConfig(layers[i]),
        ].contains(false);
    if (drifted) {
      problems.add(
        'dna: config changed since last sync',
      );
    } else {
      // 4) Per-layer freshness, checked in parallel.
      final layerProblems = await Future.wait([
        for (var i = 0; i < layers.length; i++)
          _checkLayer(layers[i], manifest.layers[i], dest),
      ]);
      problems.addAll(layerProblems.expand((list) => list));
    }

    // 5) config: claude: — CLAUDE.md block and installed skills.
    problems.addAll(_checkClaude(dest.parent, config, manifest));

    if (problems.isEmpty) {
      ggLog('dna/ is up to date.');
      return;
    }

    for (final problem in problems) {
      ggLog('  - $problem');
    }
    throw Exception('dna/ out of date — run `gg_dna sync` to fix.');
  }

  // ...........................................................................
  /// Returns the `config: claude:` problems: config drift, an outdated
  /// CLAUDE.md block, missing/outdated owned skills, and owned skills
  /// that are no longer configured.
  List<String> _checkClaude(
    Directory target,
    DnaConfig? config,
    DnaManifest manifest,
  ) {
    final problems = <String>[];
    final claude = config?.claude;

    if (!manifest.claude.matchesConfig(claude)) {
      problems.add('claude config changed since last sync');
      return problems;
    }

    final claudeMdInclude = claude?.claudeMdInclude;
    if (claudeMdInclude != null) {
      try {
        final imports = expandClaudeMdIncludes(target.path, claudeMdInclude);
        final block = buildClaudeMdBlock(imports);
        final file = File(p.join(target.path, 'CLAUDE.md'));
        if (!file.existsSync()) {
          problems.add('missing: ${file.path}');
        } else {
          final content = file.readAsStringSync();
          if (upsertClaudeMdBlock(content, block) != content) {
            problems.add('CLAUDE.md block out of date');
          }
        }
      } catch (e) {
        problems.add('CLAUDE.md check failed: $e');
      }
    }

    try {
      final sources = <String, Directory>{};
      for (final entry in claude?.skillsInclude ?? const <String>[]) {
        final dir = Directory(
          p.normalize(p.join(target.path, entry.replaceAll('\\', '/'))),
        );
        for (final skill in discoverSkills(dir)) {
          sources[p.basename(skill.path)] = skill;
        }
      }
      final owned = manifest.claude.installedSkills;
      for (final name in sources.keys.toList()..sort()) {
        final dest = Directory(p.join(target.path, claudeSkillsRel, name));
        if (!dest.existsSync()) {
          // A sync would install this skill (fresh or owned re-install).
          problems.add('skill "$name" is not installed');
          continue;
        }
        // Present but not owned is a hand-installed skill — the sync
        // leaves it alone, so the check does too.
        if (owned.contains(name) &&
            hashDnaDirectory(dest) != hashDnaDirectory(sources[name]!)) {
          problems.add('skill "$name" is out of date');
        }
      }
      for (final name in owned) {
        if (sources.containsKey(name)) continue;
        final dest = Directory(p.join(target.path, claudeSkillsRel, name));
        if (dest.existsSync()) {
          problems.add(
            'skill "$name" is no longer configured but still installed',
          );
        }
      }
    } catch (e) {
      problems.add('skills check failed: $e');
    }

    return problems;
  }

  // ...........................................................................
  /// Returns the freshness problems of one layer (empty when up to date).
  Future<List<String>> _checkLayer(
    DnaLayerConfig config,
    DnaManifestLayer stored,
    Directory dest,
  ) async {
    if (config.isGit) {
      final url = _gitUrlOf(config);
      if (config.versionConstraint != null) {
        final result = await _resolveConstraint(config, url);
        if (result.problem != null) {
          return ['layer "${config.name}": ${result.problem}'];
        }
        final now = result.tag!;
        if (now.version.toString() != stored.resolvedVersion ||
            now.sha != stored.commit) {
          return [
            'layer "${config.name}" has a new matching version '
                '(${stored.resolvedVersion} -> ${now.version})',
          ];
        }
        return const [];
      }
      final sha = await _gitLsRemote(url);
      if (sha == null) {
        return ['cannot resolve remote HEAD of layer "${config.name}": $url'];
      }
      if (sha != stored.commit) {
        return [
          'layer "${config.name}" has new commits '
              '(${stored.commit} -> $sha)',
        ];
      }
      return const [];
    }

    // The implicit src layer: hash <target>/dna/src itself. A missing
    // folder hashes to null — consistent with a sync that skipped it.
    if (config.name == implicitSrcLayer.name) {
      final hashNow = hashDnaDirectory(Directory(p.join(dest.path, 'src')));
      if (hashNow != stored.hash) {
        return [
          'layer "src" (<target>/dna/src) has changed '
              '(${stored.hash} -> $hashNow)',
        ];
      }
      return const [];
    }

    final resolved = resolvePathLayer(dest.parent.path, config);
    if (!resolved.folder.existsSync()) {
      return ['layer "${config.name}" path no longer exists: ${config.path}'];
    }
    // A missing dna/src content folder hashes to null and is reported as
    // a mismatch against the stored hash.
    final hashNow = hashDnaDirectory(resolved.content);
    if (hashNow != stored.hash) {
      return [
        'layer "${config.name}" has changed (${stored.hash} -> $hashNow)',
      ];
    }
    return const [];
  }

  // ...........................................................................
  /// Applies `config: claude:` after the swap: upserts the managed
  /// CLAUDE.md block and mirrors the configured skills. Rewrites the
  /// manifest so `installedSkills` reflects the new ownership.
  void _applyClaudeConfig({
    required Directory target,
    required Directory dnaDir,
    required DnaConfig? config,
    required DnaManifest manifest,
    required DnaManifest? previousManifest,
  }) {
    final claude = config?.claude;

    final claudeMdInclude = claude?.claudeMdInclude;
    if (claudeMdInclude != null) {
      final imports = expandClaudeMdIncludes(target.path, claudeMdInclude);
      if (writeClaudeMd(target.path, imports)) {
        ggLog('Updated CLAUDE.md (${imports.length} @-import(s)).');
      }
    }

    final result = syncClaudeSkills(
      targetRoot: target.path,
      include: claude?.skillsInclude ?? const [],
      previouslyInstalled: previousManifest?.claude.installedSkills ?? const [],
    );
    for (final warning in result.warnings) {
      ggLog(warning);
    }
    for (final name in result.installed) {
      ggLog('  + installed skill $name');
    }
    for (final name in result.removed) {
      ggLog('  - removed skill $name (no longer configured)');
    }

    DnaManifest(
      layers: manifest.layers,
      claude: DnaManifestClaude(
        claudeMdInclude: claude?.claudeMdInclude,
        skillsInclude: claude?.skillsInclude,
        installedSkills: result.installed,
      ),
      baseVersion: manifest.baseVersion,
      baseHash: manifest.baseHash,
      hash: manifest.hash,
    ).write(dnaDir);
  }

  // coverage:ignore-start
  /// Resolves the gg_dna package root (works from repo and pub cache).
  static Future<String> _defaultPackageRoot() async {
    final libUri = await Isolate.resolvePackageUri(
      Uri.parse('package:gg_dna/gg_dna.dart'),
    );
    if (libUri != null) {
      return Directory.fromUri(libUri.resolve('../')).path;
    }
    var dir = File.fromUri(Platform.script).parent;
    for (var i = 0; i < 5; i++) {
      if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) {
        return dir.path;
      }
      dir = dir.parent;
    }
    return Directory.current.path;
  }

  /// Runs git with [args]; shared plumbing of the default git wrappers.
  static Future<ProcessResult> _git(List<String> args) =>
      Process.run('git', args, runInShell: true);

  /// Default cloner: `git clone --depth 1 [--branch <ref>] <url> <dest>`.
  static Future<void> _defaultGitCloner(
    String url,
    Directory dest, {
    String? ref,
  }) async {
    final result = await _git([
      'clone',
      '--depth',
      '1',
      if (ref != null) ...['--branch', ref],
      url,
      dest.path,
    ]);
    if (result.exitCode != 0) {
      throw Exception(
        'git clone failed (exit ${result.exitCode}): ${result.stderr}',
      );
    }
  }

  /// Default `git rev-parse HEAD` inside [dir]; `null` on failure.
  static Future<String?> _defaultGitRevParse(Directory dir) async {
    final result = await _git(['-C', dir.path, 'rev-parse', 'HEAD']);
    if (result.exitCode != 0) return null;
    final sha = (result.stdout as String).trim();
    return sha.isEmpty ? null : sha;
  }

  /// Default `git ls-remote <url> HEAD`; `null` on failure.
  static Future<String?> _defaultGitLsRemote(String url) async {
    final result = await _git(['ls-remote', url, 'HEAD']);
    if (result.exitCode != 0) return null;
    final out = (result.stdout as String).trim();
    if (out.isEmpty) return null;
    final firstLine = out.split('\n').first;
    final firstToken = firstLine.split(RegExp(r'\s+')).first.trim();
    return firstToken.isEmpty ? null : firstToken;
  }

  /// Default `git ls-remote --tags <url>`; `null` on failure.
  static Future<Map<String, String>?> _defaultGitLsRemoteTags(
    String url,
  ) async {
    final result = await _git(['ls-remote', '--tags', url]);
    if (result.exitCode != 0) return null;
    return parseLsRemoteTags(result.stdout as String);
  }
  // coverage:ignore-end
}

// .............................................................................
/// A configured layer resolved to a local content root, ready to be applied.
class _ResolvedLayer {
  _ResolvedLayer({
    required this.config,
    required this.contentRoot,
    this.cleanup,
    this.restoreRel,
    this.commit,
    this.resolvedTag,
    this.hash,
  });

  /// The dna: config this layer was resolved from.
  final DnaLayerConfig config;

  /// The folder whose content gets merged into `<target>/dna`.
  final Directory contentRoot;

  /// Temp clone or snapshot to delete after the sync.
  final Directory? cleanup;

  /// Where under `<target>/dna` the snapshot in [cleanup] gets restored.
  final String? restoreRel;

  /// Commit SHA of the cloned layer; `null` for path layers.
  final String? commit;

  /// The tag a `version:` constraint resolved to; `null` otherwise.
  final ResolvedTag? resolvedTag;

  /// Content hash of the layer's dna root at resolve time.
  final String? hash;
}
