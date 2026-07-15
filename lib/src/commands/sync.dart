// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';
import 'dart:isolate';

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';
import 'package:interact/interact.dart' as interact;
import 'package:path/path.dart' as p;

import '../util/copy_directory.dart';
import '../util/dna_config.dart';
import '../util/dna_hash.dart';
import '../util/dna_manifest.dart';
import '../util/git_tag_resolver.dart';
import '../util/md_tags.dart';
import 'apply_conventions.dart';
import 'install_skills.dart';

/// Returns the directory the `gg_dna` package is installed in.
typedef PackageRootResolver = Future<String> Function();

/// Asks the yes/no question [prompt]; `true` means "yes".
typedef YesNoSelector = bool Function(String prompt);

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
/// of the target repo's `dna:` config on top (later layers win, `X.tag.md`
/// files patch sections/strings), then offers to install the synced skills
/// and conventions. All git and prompt access is injectable for tests.
class Sync extends Command<dynamic> {
  /// Constructor.
  Sync({
    required this.ggLog,
    PackageRootResolver? packageRootResolver,
    YesNoSelector? selector,
    GitCloner? gitCloner,
    GitRevParse? gitRevParse,
    GitLsRemote? gitLsRemote,
    GitLsRemoteTags? gitLsRemoteTags,
  })  : _packageRootResolver = packageRootResolver ?? _defaultPackageRoot,
        _selector = selector ?? _defaultSelector,
        _gitCloner = gitCloner ?? _defaultGitCloner,
        _gitRevParse = gitRevParse ?? _defaultGitRevParse,
        _gitLsRemote = gitLsRemote ?? _defaultGitLsRemote,
        _gitLsRemoteTags = gitLsRemoteTags ?? _defaultGitLsRemoteTags {
    argParser
      ..addOption(
        'source',
        abbr: 's',
        help: 'Source folder containing the base gg_dna content. Defaults to '
            'the root of the resolved gg_dna package. The `dna/` subfolder '
            'of this path is mirrored into <target>/dna.',
      )
      ..addOption(
        'target',
        abbr: 't',
        help: 'Target folder. Defaults to <cwd>.',
      )
      ..addFlag(
        'check',
        abbr: 'c',
        help: 'Verify <target>/dna is up to date without writing anything. '
            'Skips the interactive install/apply phase.',
        negatable: false,
      )
      ..addFlag(
        'no-install',
        help: 'Skip the post-sync install-skills / apply-conventions phase.',
        negatable: false,
      );
  }

  /// The log function.
  final GgLog ggLog;

  final PackageRootResolver _packageRootResolver;
  final YesNoSelector _selector;
  final GitCloner _gitCloner;
  final GitRevParse _gitRevParse;
  final GitLsRemote _gitLsRemote;
  final GitLsRemoteTags _gitLsRemoteTags;

  /// Skills folder scanned for the install-skills prompt phase.
  static const String _dnaSkillsRel = 'dna/agents/skills';

  /// Conventions folder scanned for the apply-conventions prompt phase.
  static const String _dnaConventionsRel = 'dna/agents/conventions';

  @override
  final name = 'sync';

  @override
  final description =
      'Mirror the gg_dna `dna/` folder into <target>/dna and merge the DNA '
      'layers configured in the target repo on top — later layers '
      'win. Then offer to install Claude Code skills and conventions into '
      "the project's .claude folder.\n"
      '\n'
      'Layers are configured in exactly one of '
      '${dnaConfigFilenames.join(', ')}\n'
      '(in package.json under the `"dna"` key) in the target root:\n'
      '\n'
      '  dna:\n'
      '    order:\n'
      '      - dna_company\n'
      '      - dna_repo\n'
      '    dna_company:\n'
      '      git: https://github.com/acme/dna_company.git\n'
      '      version: ^1.4.0\n'
      '    dna_repo:\n'
      '      path: dna/_override\n'
      '\n'
      '  * `git:` layers are cloned; a `version:` semver constraint is\n'
      '    resolved against the repo tags (highest matching tag wins).\n'
      '    `gg_*` shorthands expand to https://github.com/ggsuite/<name>.\n'
      '  * `path:` layers are local folders (relative to the target root).\n'
      '    A path inside <target>/dna (e.g. dna/_override) survives the\n'
      '    sync verbatim.\n'
      '  * `X.tag.md` files patch sections and strings of the merged\n'
      '    `X.md`; they are consumed, not copied.';

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
    final noInstall = argResults!['no-install'] as bool;

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

    // Resolve all layers up front and in parallel — any error (unreachable
    // remote, unsatisfiable constraint, missing path) leaves the target
    // untouched; temps of already resolved layers are cleaned up.
    final resolved = <_ResolvedLayer>[];
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
      _buildAndSwap(
        sourceDna: sourceDna,
        dnaDir: dnaDir,
        staging: staging,
        backup: backup,
        resolved: resolved,
        packageRoot: packageRoot,
      );
    } finally {
      resolved.forEach(_cleanupLayer);
      // A failed build leaves the staging folder behind — remove it. After
      // a successful swap it no longer exists.
      if (staging.existsSync()) {
        staging.deleteSync(recursive: true);
      }
    }

    if (noInstall) {
      return;
    }

    await _promptAndInstallSkills(target);
    await _promptAndApplyConventions(target);
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
    return Directory(p.join(root, 'dna'));
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
  /// Builds the merged dna tree in [staging] and rename-swaps it into place.
  void _buildAndSwap({
    required Directory sourceDna,
    required Directory dnaDir,
    required Directory staging,
    required Directory backup,
    required List<_ResolvedLayer> resolved,
    required String packageRoot,
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
  }

  // ...........................................................................
  /// Resolves a layer to a local content root (clone or snapshot temp).
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
    if (!folder.existsSync()) {
      // In-dna override layers may not exist yet — git does not track empty
      // folders, so fresh clones of a consumer repo must still sync.
      if (p.isWithin(dnaDir.path, folder.path)) {
        ggLog(
          'Layer "${config.name}": ${config.path} does not exist yet '
          '— skipped.',
        );
        return _ResolvedLayer(config: config, contentRoot: folder);
      }
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
    if (p.equals(folder.path, dnaDir.path) ||
        p.equals(resolved.content.path, dnaDir.path)) {
      throw Exception(
        'Layer "${config.name}" must not point at <target>/dna itself.',
      );
    }

    if (p.isWithin(dnaDir.path, folder.path)) {
      // The layer source lives inside the folder that gets replaced —
      // snapshot it now so the new tree can carry it over verbatim.
      final tmp = Directory.systemTemp.createTempSync('gg_dna_layer_');
      copyDirectory(folder, tmp);
      final tmpContent = p.equals(resolved.content.path, folder.path)
          ? tmp
          : Directory(p.join(tmp.path, 'dna'));
      return _ResolvedLayer(
        config: config,
        contentRoot: tmpContent,
        cleanup: tmp,
        restoreRel: p.relative(folder.path, from: dnaDir.path),
        hash: hashDnaDirectory(resolved.content),
      );
    }

    return _ResolvedLayer(
      config: config,
      contentRoot: resolved.content,
      hash: hashDnaDirectory(resolved.content),
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
      final dna = Directory(p.join(tmp.path, 'dna'));
      if (!dna.existsSync()) {
        throw Exception(
          'Layer "${config.name}" does not contain a dna/ folder: '
          '${dna.path}',
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
  /// Copies one layer into [dnaDir], then applies its `.tag.md` patches.
  void _applyLayerContent(String name, Directory root, Directory dnaDir) {
    if (!root.existsSync()) return;

    // Copy all dna content; collect the tag files instead of copying them.
    final tagFiles = <String>[];
    copyDirectory(
      root,
      dnaDir,
      skip: (rel) {
        if (!isDnaContent(rel)) return true;
        if (rel.endsWith(tagFileSuffix)) {
          tagFiles.add(rel);
          return true;
        }
        return false;
      },
    );
    tagFiles.sort();

    for (final rel in tagFiles) {
      final targetRel =
          '${rel.substring(0, rel.length - tagFileSuffix.length)}.md';
      final targetFile = File(p.join(dnaDir.path, targetRel));
      if (!targetFile.existsSync()) {
        ggLog(
          'Layer "$name": $rel has no target file $targetRel — skipped.',
        );
        continue;
      }
      final parsed =
          parseTagFile(File(p.join(root.path, rel)).readAsStringSync());
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
  /// Strips all tag markers from every `.md` file under [dnaDir].
  void _renderAll(Directory dnaDir) {
    for (final entity in dnaDir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.md')) continue;
      final content = entity.readAsStringSync();
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
        '  - missing or pre-2.0 format: '
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

    // 3) Config drift: the configured dna: block must match the manifest.
    final layers = config?.layers ?? const <DnaLayerConfig>[];
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

    final resolved = resolvePathLayer(dest.parent.path, config);
    if (!resolved.folder.existsSync() &&
        !p.isWithin(dest.path, resolved.folder.path)) {
      return ['layer "${config.name}" path no longer exists: ${config.path}'];
    }
    // Missing in-dna layers hash to null — consistent with a sync that
    // skipped them as empty.
    final hashNow = hashDnaDirectory(resolved.content);
    if (hashNow != stored.hash) {
      return [
        'layer "${config.name}" has changed (${stored.hash} -> $hashNow)',
      ];
    }
    return const [];
  }

  // ...........................................................................
  Future<void> _promptAndInstallSkills(Directory target) async {
    final skillsRoot = Directory(p.join(target.path, _dnaSkillsRel));
    if (!skillsRoot.existsSync()) {
      return;
    }
    final skills = InstallSkills.discoverSkills(skillsRoot);
    if (skills.isEmpty) {
      return;
    }

    ggLog('');
    ggLog('Claude Code Skills:');
    final selected = <String>[];
    for (final skill in skills) {
      final name = p.basename(skill.path);
      if (_selector('  Install /$name?')) {
        selected.add(name);
      }
    }

    if (selected.isEmpty) {
      ggLog('  (no skills selected)');
      return;
    }

    final dest = Directory(p.join(target.path, '.claude', 'skills'));
    final runner = CommandRunner<dynamic>('gg_dna', 'gg_dna sub-runner')
      ..addCommand(InstallSkills(ggLog: ggLog));
    await runner.run([
      'install-skills',
      '--source',
      skillsRoot.path,
      '--dest',
      dest.path,
      '--only',
      selected.join(','),
    ]);
  }

  Future<void> _promptAndApplyConventions(Directory target) async {
    final convRoot = Directory(p.join(target.path, _dnaConventionsRel));
    if (!convRoot.existsSync()) {
      return;
    }
    final docs = ApplyConventions.discoverConventions(convRoot);
    if (docs.isEmpty) {
      return;
    }

    ggLog('');
    ggLog('Claude Code Conventions:');
    final selected = <String>[];
    for (final doc in docs) {
      final name = p.basename(doc.path);
      if (_selector('  Apply $name?')) {
        selected.add(name);
      }
    }

    if (selected.isEmpty) {
      ggLog('  (no conventions selected)');
      return;
    }

    final runner = CommandRunner<dynamic>('gg_dna', 'gg_dna sub-runner')
      ..addCommand(ApplyConventions(ggLog: ggLog));
    await runner.run([
      'apply-conventions',
      '--source',
      convRoot.path,
      '--target',
      target.path,
      '--only',
      selected.join(','),
    ]);
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

  /// Default yes/no selector that renders a two-option [interact.Select].
  static bool _defaultSelector(String prompt) {
    final choice = interact.Select(
      prompt: prompt,
      options: const ['yes', 'no'],
      initialIndex: 0,
    ).interact();
    return choice == 0;
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
