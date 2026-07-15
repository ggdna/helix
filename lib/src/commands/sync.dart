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

import '../util/dna_config.dart';
import '../util/dna_hash.dart';
import '../util/dna_manifest.dart';
import '../util/git_tag_resolver.dart';
import '../util/md_tags.dart';
import 'apply_conventions.dart';
import 'install_skills.dart';

/// Returns the directory the `gg_dna` package is installed in.
typedef PackageRootResolver = Future<String> Function();

/// Asks the user a yes/no question represented by [prompt] and returns `true`
/// for "yes". Used by [Sync] to decide which skills / conventions to install.
typedef YesNoSelector = bool Function(String prompt);

/// Clones the git repo at [url] into [dest], optionally checking out [ref]
/// (a tag or branch). Used by [Sync] for git layers. Injected so tests can
/// stub the network call.
typedef GitCloner = Future<void> Function(
  String url,
  Directory dest, {
  String? ref,
});

/// Reads the current commit SHA of the git repository at [dir]. Used by
/// [Sync] after a clone to capture the layer's exact revision. Returns
/// `null` when the directory is not a git repo.
typedef GitRevParse = Future<String?> Function(Directory dir);

/// Resolves the remote HEAD commit SHA of the git repo at [url] without
/// cloning. Used by [Sync] during `--check` for unconstrained git layers.
typedef GitLsRemote = Future<String?> Function(String url);

/// Lists the tags of the git repo at [url] without cloning, as a map from
/// tag name to commit SHA (peeled SHAs preferred). Returns `null` on
/// failure. Used by [Sync] to resolve `version:` constraints of git layers.
typedef GitLsRemoteTags = Future<Map<String, String>?> Function(String url);

/// Mirrors the `dna/` folder shipped with `gg_dna` into the consuming
/// repository and merges the DNA layers configured in the target's
/// pubspec.yaml `dna:` block on top — later layers win on path collisions.
///
/// Layers can override whole files, or single sections / strings of `.md`
/// files via `X.tag.md` override files (see the md_tags library). After the
/// merge all tag markers are rendered away; `.tag.md` files are consumed
/// and never copied into the target.
///
/// After the copy, the command offers — per skill and per convention — to
/// install them into the project's `.claude/` folder via [InstallSkills]
/// and [ApplyConventions].
class Sync extends Command<dynamic> {
  /// Constructor.
  ///
  /// [packageRootResolver] is the source of truth for the gg_dna content;
  /// the default resolves it via [Isolate.resolvePackageUri] so the command
  /// works both inside the gg_dna repo *and* from a consumer that has
  /// gg_dna in its pub cache.
  ///
  /// [selector] is used for the interactive yes/no prompts. The default
  /// renders an [interact.Select] with two options ("yes"/"no").
  ///
  /// [gitCloner], [gitRevParse], [gitLsRemote], and [gitLsRemoteTags] wrap
  /// the git binary and are injectable for tests.
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

  /// Subdirectory inside `<target>/dna/agents/skills` discovered for the
  /// install-skills prompt phase.
  static const String _dnaSkillsRel = 'dna/agents/skills';

  /// Subdirectory inside `<target>/dna/agents/conventions` discovered for
  /// the apply-conventions prompt phase.
  static const String _dnaConventionsRel = 'dna/agents/conventions';

  @override
  final name = 'sync';

  @override
  final description =
      'Mirror the gg_dna `dna/` folder into <target>/dna and merge the DNA '
      'layers configured in the target pubspec.yaml on top — later layers '
      'win. Then offer to install Claude Code skills and conventions into '
      "the project's .claude folder.\n"
      '\n'
      'Layers are configured in the target pubspec.yaml:\n'
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
        'Configure DNA layers via the `dna:` block in the target '
        'pubspec.yaml.',
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

    if (checkOnly) {
      await _check(sourceDna, dnaDir, config);
      return;
    }

    if (config == null) {
      ggLog('No dna: config found in pubspec.yaml — base sync only.');
    }

    // Resolve ALL layers before wiping the target, so that any error
    // (unreachable remote, unsatisfiable constraint, missing path) leaves
    // the target untouched.
    final resolved = <_ResolvedLayer>[];
    try {
      for (final layer in config?.layers ?? const <DnaLayerConfig>[]) {
        resolved.add(await _resolveLayer(layer, target, dnaDir));
      }

      // Base sync: wipe <target>/dna and copy <source>/dna fresh. The base
      // is layer 0 and follows the same rules as every other layer.
      if (dnaDir.existsSync()) {
        dnaDir.deleteSync(recursive: true);
      }
      _applyLayerContent('base', sourceDna, dnaDir);
      ggLog('Synced ${sourceDna.path} -> ${dnaDir.path}.');
      final baseHash = hashDnaDirectory(sourceDna);

      for (final layer in resolved) {
        _applyLayerContent(layer.config.name, layer.contentRoot, dnaDir);
        ggLog('Applied layer "${layer.config.name}".');
      }

      // Render all markers away, then restore in-dna layer sources
      // verbatim — their markers must survive for the next sync.
      _renderAll(dnaDir);
      for (final layer in resolved) {
        if (layer.restoreTo == null) continue;
        final dest = Directory(layer.restoreTo!);
        if (dest.existsSync()) {
          dest.deleteSync(recursive: true);
        }
        copyDirectory(layer.snapshotRoot!, dest);
      }

      // The final hash MUST be computed after the snapshot restore —
      // otherwise the very next `--check` would report a mismatch.
      final manifest = DnaManifest(
        layers: [
          for (final layer in resolved)
            DnaManifestLayer(
              name: layer.config.name,
              git: layer.config.git,
              path: layer.config.path,
              versionConstraint: layer.config.rawVersionConstraint,
              resolvedVersion: layer.resolvedTag?.version.toString(),
              resolvedTag: layer.resolvedTag?.tag,
              commit: layer.commit,
              hash: layer.hash,
            ),
        ],
        baseVersion: readPackageVersion(packageRoot),
        baseHash: baseHash,
        hash: hashDnaDirectory(dnaDir),
      );
      manifest.write(dnaDir);
      ggLog('Wrote ${p.join(dnaDir.path, dnaManifestFilename)}.');
    } finally {
      for (final layer in resolved) {
        final cleanup = layer.cleanup;
        if (cleanup != null && cleanup.existsSync()) {
          cleanup.deleteSync(recursive: true);
        }
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

  /// Recursively copies the contents of [source] into [target]. Existing
  /// files in [target] at colliding relative paths are overwritten; files
  /// that exist only in [target] are kept (overlay semantics).
  ///
  /// [filter] receives the relative path with forward slashes and may
  /// return `false` to skip an entry (a skipped directory only skips the
  /// directory entry itself, so filters must also match its children).
  static void copyDirectory(
    Directory source,
    Directory target, {
    bool Function(String relPosixPath)? filter,
  }) {
    target.createSync(recursive: true);
    for (final entity in source.listSync(recursive: true, followLinks: false)) {
      final relative = p.relative(entity.path, from: source.path);
      final rel = relative.replaceAll('\\', '/');
      if (filter != null && !filter(rel)) continue;
      final targetPath = p.join(target.path, relative);
      if (entity is Directory) {
        Directory(targetPath).createSync(recursive: true);
      } else if (entity is File) {
        Directory(p.dirname(targetPath)).createSync(recursive: true);
        entity.copySync(targetPath);
      }
    }
  }

  /// Expands a bare `gg_*` repo shorthand to its canonical github URL.
  ///
  /// Returns `https://github.com/ggsuite/<name>.git` when [arg] looks like a
  /// `gg_*` repo name (e.g. `gg_dna_ggsuite` or `gg_dna_ggsuite.git`).
  /// Returns `null` otherwise.
  ///
  /// The shape must be a bare name: it must start with `gg_`, may only
  /// contain word characters, dots, or hyphens after that, and must not
  /// contain slashes, colons, `@`, or whitespace (so real paths and URLs
  /// are never misclassified as a shorthand). A trailing `.git` is
  /// stripped before the URL is built, so callers can write either form.
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
  /// Resolves a configured layer to a local content root — BEFORE the target
  /// is wiped. Git layers are cloned to a temp dir; local path layers inside
  /// `<target>/dna` are snapshotted to a temp dir so they survive the wipe.
  Future<_ResolvedLayer> _resolveLayer(
    DnaLayerConfig config,
    Directory target,
    Directory dnaDir,
  ) async {
    if (config.isGit) {
      return _resolveGitLayer(config);
    }

    final abs = Directory(p.normalize(p.join(target.path, config.path!)));
    if (!abs.existsSync()) {
      throw Exception(
        'Layer "${config.name}": path does not exist: ${abs.path}',
      );
    }
    final dnaSub = Directory(p.join(abs.path, 'dna'));
    final contentSource = dnaSub.existsSync() ? dnaSub : abs;
    if (p.equals(abs.path, dnaDir.path) ||
        p.equals(contentSource.path, dnaDir.path)) {
      throw Exception(
        'Layer "${config.name}" must not point at <target>/dna itself.',
      );
    }

    if (p.isWithin(dnaDir.path, abs.path)) {
      // The layer source lives inside the folder that gets wiped —
      // snapshot it now and restore it verbatim after the sync.
      final tmp = Directory.systemTemp.createTempSync('gg_dna_layer_');
      copyDirectory(abs, tmp);
      final tmpContent =
          dnaSub.existsSync() ? Directory(p.join(tmp.path, 'dna')) : tmp;
      return _ResolvedLayer(
        config: config,
        contentRoot: tmpContent,
        cleanup: tmp,
        snapshotRoot: tmp,
        restoreTo: abs.path,
        hash: hashDnaDirectory(contentSource),
      );
    }

    return _ResolvedLayer(
      config: config,
      contentRoot: contentSource,
      hash: hashDnaDirectory(contentSource),
    );
  }

  // ...........................................................................
  Future<_ResolvedLayer> _resolveGitLayer(DnaLayerConfig config) async {
    final url = _gitUrlOf(config);

    ResolvedTag? resolvedTag;
    if (config.versionConstraint != null) {
      final tags = await _gitLsRemoteTags(url);
      if (tags == null) {
        throw Exception(
          'Layer "${config.name}": cannot list tags of $url',
        );
      }
      resolvedTag = resolveTagForConstraint(tags, config.versionConstraint!);
      if (resolvedTag == null) {
        final available = semverVersionsOf(tags.keys);
        throw Exception(
          'Layer "${config.name}": no tag satisfies '
          '"${config.rawVersionConstraint}". Available versions: '
          '${available.isEmpty ? '(none)' : available.join(', ')}',
        );
      }
      ggLog(
        'Layer "${config.name}": ${config.rawVersionConstraint} '
        '-> ${resolvedTag.tag}',
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
  /// Applies one layer's content to [dnaDir]: full files are copied
  /// (`.tag.md` files, a layer-root `.dna.json`, and `.git/` are skipped),
  /// then the layer's `.tag.md` files patch the current merged state.
  void _applyLayerContent(String name, Directory root, Directory dnaDir) {
    copyDirectory(
      root,
      dnaDir,
      filter: (rel) =>
          rel != dnaManifestFilename &&
          rel != '.git' &&
          !rel.startsWith('.git/') &&
          !rel.endsWith(tagFileSuffix),
    );

    final tagFiles = <String>[];
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final rel =
          p.relative(entity.path, from: root.path).replaceAll('\\', '/');
      if (!rel.endsWith(tagFileSuffix) || rel.startsWith('.git/')) continue;
      tagFiles.add(rel);
    }
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

    // 3) Config drift: the pubspec dna: block must match the manifest.
    final layers = config?.layers ?? const <DnaLayerConfig>[];
    if (!_sameLayerConfig(layers, manifest.layers)) {
      problems.add(
        'dna: config in pubspec.yaml changed since last sync',
      );
    } else {
      // 4) Per-layer freshness.
      for (var i = 0; i < layers.length; i++) {
        await _checkLayer(layers[i], manifest.layers[i], dest, problems);
      }
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
  Future<void> _checkLayer(
    DnaLayerConfig config,
    DnaManifestLayer stored,
    Directory dest,
    List<String> problems,
  ) async {
    if (config.isGit) {
      final url = _gitUrlOf(config);
      if (config.versionConstraint != null) {
        final tags = await _gitLsRemoteTags(url);
        if (tags == null) {
          problems.add('cannot list tags of layer "${config.name}": $url');
          return;
        }
        final now = resolveTagForConstraint(tags, config.versionConstraint!);
        if (now == null) {
          problems.add(
            'no tag of layer "${config.name}" satisfies '
            '"${config.rawVersionConstraint}" anymore',
          );
        } else if (now.version.toString() != stored.resolvedVersion ||
            now.sha != stored.commit) {
          problems.add(
            'layer "${config.name}" has a new matching version '
            '(${stored.resolvedVersion} -> ${now.version})',
          );
        }
        return;
      }
      final sha = await _gitLsRemote(url);
      if (sha == null) {
        problems.add(
          'cannot resolve remote HEAD of layer "${config.name}": $url',
        );
      } else if (sha != stored.commit) {
        problems.add(
          'layer "${config.name}" has new commits '
          '(${stored.commit} -> $sha)',
        );
      }
      return;
    }

    final abs = Directory(p.normalize(p.join(dest.parent.path, config.path!)));
    if (!abs.existsSync()) {
      problems.add(
        'layer "${config.name}" path no longer exists: ${config.path}',
      );
      return;
    }
    final dnaSub = Directory(p.join(abs.path, 'dna'));
    final root = dnaSub.existsSync() ? dnaSub : abs;
    final hashNow = hashDnaDirectory(root);
    if (hashNow != stored.hash) {
      problems.add(
        'layer "${config.name}" has changed '
        '(${stored.hash} -> $hashNow)',
      );
    }
  }

  // ...........................................................................
  static bool _sameLayerConfig(
    List<DnaLayerConfig> config,
    List<DnaManifestLayer> stored,
  ) {
    if (config.length != stored.length) return false;
    for (var i = 0; i < config.length; i++) {
      final a = config[i];
      final b = stored[i];
      if (a.name != b.name ||
          a.git != b.git ||
          a.path != b.path ||
          a.rawVersionConstraint != b.versionConstraint) {
        return false;
      }
    }
    return true;
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
  /// Resolves the gg_dna package root via [Isolate.resolvePackageUri] so the
  /// command works both when run from inside the gg_dna repo *and* from a
  /// consuming repo where gg_dna sits in the pub cache.
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

  /// Default git cloner: shells out to
  /// `git clone --depth 1 [--branch <ref>] <url> <dest>`.
  static Future<void> _defaultGitCloner(
    String url,
    Directory dest, {
    String? ref,
  }) async {
    final result = await Process.run(
      'git',
      [
        'clone',
        '--depth',
        '1',
        if (ref != null) ...['--branch', ref],
        url,
        dest.path,
      ],
      runInShell: true,
    );
    if (result.exitCode != 0) {
      throw Exception(
        'git clone failed (exit ${result.exitCode}): ${result.stderr}',
      );
    }
  }

  /// Default `git rev-parse HEAD` inside [dir]. Returns the SHA, or `null`
  /// when the call fails (e.g. the directory is not a git repo).
  static Future<String?> _defaultGitRevParse(Directory dir) async {
    final result = await Process.run(
      'git',
      ['-C', dir.path, 'rev-parse', 'HEAD'],
      runInShell: true,
    );
    if (result.exitCode != 0) return null;
    final sha = (result.stdout as String).trim();
    return sha.isEmpty ? null : sha;
  }

  /// Default `git ls-remote <url> HEAD`. Returns the SHA, or `null` on
  /// failure (network error, unauthenticated, etc.).
  static Future<String?> _defaultGitLsRemote(String url) async {
    final result = await Process.run(
      'git',
      ['ls-remote', url, 'HEAD'],
      runInShell: true,
    );
    if (result.exitCode != 0) return null;
    final out = (result.stdout as String).trim();
    if (out.isEmpty) return null;
    final firstLine = out.split('\n').first;
    final firstToken = firstLine.split(RegExp(r'\s+')).first.trim();
    return firstToken.isEmpty ? null : firstToken;
  }

  /// Default `git ls-remote --tags <url>`. Returns tag name -> SHA (peeled
  /// preferred), or `null` on failure.
  static Future<Map<String, String>?> _defaultGitLsRemoteTags(
    String url,
  ) async {
    final result = await Process.run(
      'git',
      ['ls-remote', '--tags', url],
      runInShell: true,
    );
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
    this.snapshotRoot,
    this.restoreTo,
    this.commit,
    this.resolvedTag,
    this.hash,
  });

  /// The pubspec config this layer was resolved from.
  final DnaLayerConfig config;

  /// The folder whose content gets merged into `<target>/dna`.
  final Directory contentRoot;

  /// Temp folder (clone or snapshot) to delete after the sync.
  final Directory? cleanup;

  /// Snapshot of the original layer folder — restored to [restoreTo]
  /// verbatim after the sync (for layers living inside `<target>/dna`).
  final Directory? snapshotRoot;

  /// Absolute path the snapshot gets restored to, or `null`.
  final String? restoreTo;

  /// Commit SHA of the cloned layer. `null` for path layers.
  final String? commit;

  /// The tag a `version:` constraint resolved to. `null` otherwise.
  final ResolvedTag? resolvedTag;

  /// Content hash of the layer's dna root at resolve time.
  final String? hash;
}
