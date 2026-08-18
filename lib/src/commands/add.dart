// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:args/command_runner.dart';
import 'package:gg_log/gg_log.dart';

import '../engine/run_dna_test.dart';
import '../util/add_target.dart';
import '../util/dna_config.dart';
import '../util/dna_config_edit.dart';
import '../util/dna_fs.dart';
import '../util/dna_fs_io.dart';
import '../util/dna_layout.dart';
import '../util/layer_graph.dart';
import '../util/package_managers.dart';
import '../util/package_resolution.dart';
import '../util/process_run.dart';
import '../util/process_run_io.dart';

/// Adds a DNA layer to a project: the package or git reference becomes a
/// dev dependency, and its name becomes the last entry of `layers` in
/// `dna/_dna.json`.
class Add extends Command<dynamic> {
  /// Constructor. [host] and [processRun] are the injectable seams to the
  /// file system and to the package managers.
  Add({required this.ggLog, DnaHost? host, ProcessRun? processRun})
    : _host = host ?? IoDnaHost(),
      _processRun = processRun ?? ioProcessRun {
    argParser.addOption(
      'target',
      abbr: 't',
      help: 'The project folder to add the DNA to.',
      defaultsTo: '.',
    );
  }

  /// The log function.
  final GgLog ggLog;

  final DnaHost _host;

  final ProcessRun _processRun;

  @override
  final name = 'add';

  @override
  final description = 'Adds a DNA layer — a package name or a git URL';

  // ...........................................................................
  @override
  Future<void> run() async {
    // The command runner strips »Exception: « from what it prints, which
    // turns a FormatException into a message starting with »Format«. The
    // messages here are written for a person to read, so they arrive as
    // plain exceptions.
    try {
      await _add();
    } on FormatException catch (e) {
      throw Exception(e.message);
    }
  }

  // ...........................................................................
  Future<void> _add() async {
    final root = _root();
    final target = _target();

    // Read the config before anything is installed: without it there is no
    // place for the layer, and `helix init` is what creates it. A broken
    // config reports itself here rather than after a download.
    if (!_host.existsFile('$root/$dnaConfigPath')) {
      usageException(
        'No $dnaConfigPath in "$root" — run `helix init` '
        '(`gg dna init`) first.',
      );
    }
    final layers = readDnaConfig(_host, root).config.layers;

    final layer = _addDependency(root, target);
    _requireDnaPackage(root, target, layer);
    _addLayer(root, layer, layers);
  }

  // ...........................................................................
  String _root() {
    final option = (argResults!['target'] as String).replaceAll(r'\', '/');
    return option == '.' ? '.' : option;
  }

  // ...........................................................................
  AddTarget _target() {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      usageException('Pass the DNA to add — a package name or a git URL.');
    }
    if (rest.length > 1) {
      usageException('Add one DNA at a time, got: ${rest.join(', ')}.');
    }
    try {
      return AddTarget.parse(rest.single);
    } on FormatException catch (e) {
      usageException(e.message);
    }
  }

  // ...........................................................................
  /// Installs [target] as a dev dependency in the ecosystem it belongs to:
  /// an npm-only name goes to node, everything else to pub when the project
  /// has a `pubspec.yaml` and to node otherwise. Returns the name the
  /// dependency ended up declared under — the name the layers array needs.
  String _addDependency(String root, AddTarget target) {
    final hasPubspec = _host.existsFile('$root/pubspec.yaml');
    final hasPackageJson = _host.existsFile('$root/package.json');

    if (target.isNodeOnlyName && !hasPackageJson) {
      usageException(
        '"${target.name}" is an npm package name, but there is no '
        'package.json in "$root".',
      );
    }
    if (!hasPubspec && !hasPackageJson) {
      usageException(
        'No pubspec.yaml and no package.json in "$root" — run '
        '`helix init` (`gg dna init`) first.',
      );
    }

    return hasPubspec && !target.isNodeOnlyName
        ? _addPubDependency(root, target)
        : _addNodeDependency(root, target);
  }

  // ...........................................................................
  /// Adds [target] to `dev_dependencies`. `dart pub add` is told the
  /// package name even for a git target — and rejects a name the
  /// repository's pubspec does not carry — so the name is authoritative.
  String _addPubDependency(String root, AddTarget target) {
    if (declaresPubDependency(_host, root, target.name)) {
      ggLog(cDetail('✓ Kept existing dev dependency ${target.name}'));
      return target.name;
    }
    final args = target.kind == AddTargetKind.git
        ? ['pub', 'add', target.pubGitDescriptor]
        : pubAddDevArgs(target.name);
    _run(root, pubExecutable(_host, root), args);
    return target.name;
  }

  // ...........................................................................
  /// Adds [target] to `devDependencies` and returns the name it landed
  /// under.
  ///
  /// A git target is installed by URL, and the package manager writes the
  /// name from the repository's own `package.json`: `dna_base.git` becomes
  /// `@tssuite/dna-base`. The layers array needs that name — the engine
  /// looks a layer up under the name a manifest declares, and only a
  /// pnpm lock file would let it fold the two spellings into one identity.
  String _addNodeDependency(String root, AddTarget target) {
    if (target.kind == AddTargetKind.package &&
        declaresNodeDependency(_host, root, target.name)) {
      ggLog(cDetail('✓ Kept existing dev dependency ${target.name}'));
      return target.name;
    }
    final before = _nodeDependencyNames(root);
    final manager = detectNodePackageManager(_host, root);
    final spec = target.kind == AddTargetKind.git
        ? target.nodeGitSpec
        : target.name;
    _run(root, manager.executable, manager.addDevArgs(spec));

    final added = _nodeDependencyNames(root).difference(before);
    if (added.length != 1) return target.name;
    if (added.single != target.name) {
      ggLog(cDetail('${target.raw} is declared as ${added.single}'));
    }
    return added.single;
  }

  // ...........................................................................
  /// Every name `package.json` declares as a dependency.
  Set<String> _nodeDependencyNames(String root) {
    final doc = readPackageJson(_host, root);
    final names = <String>{};
    for (final section in const ['dependencies', 'devDependencies']) {
      final deps = doc?[section];
      if (deps is Map) names.addAll(deps.keys.map((key) => '$key'));
    }
    return names;
  }

  // ...........................................................................
  /// Runs one dependency command. A failure aborts: adding the layer to a
  /// config while the package is not installed would only produce a
  /// failing DNA run later on.
  void _run(String root, String executable, List<String> args) {
    final command = '$executable ${args.join(' ')}';
    final result = _processRun(executable, args, workingDirectory: root);
    if (!result.isSuccess) {
      usageException('$command failed:\n${result.failureOutput}');
    }
    ggLog(cDetail('✓ $command'));
  }

  // ...........................................................................
  /// Insists that what was just installed really is a DNA.
  ///
  /// The dependency is in place at this point, so the layer would be
  /// written next — and a layer that ships no DNA turns every following
  /// DNA run into an error. Reporting it here keeps the config clean and
  /// names the package that has to be fixed.
  void _requireDnaPackage(String root, AddTarget target, String layer) {
    final resolution = PackageResolution.read(_host, root);
    final located = resolution.locate(layer);
    if (located == null) {
      throw FormatException(
        '${target.raw} was installed as "$layer", but it cannot be found '
        'in "$root".\n'
        '  ${resolution.describeFailure(layer)}\n'
        '  Nothing was added to $dnaConfigPath.',
      );
    }
    if (!isDnaPackage(_host, located.root, packageLabel: located.packageName)) {
      throw FormatException(
        '${target.raw} does not ship a DNA: '
        '"${located.packageName}" (${located.root}) has no $dnaConfigPath '
        'declaring "role": "dna" — and a $dnaDirname/ folder alone does not '
        'make a package a DNA layer.\n'
        '  Nothing was added to $dnaConfigPath. Remove the dependency '
        'again if you added it by mistake.',
      );
    }
  }

  // ...........................................................................
  /// Appends [layer] to the `layers` array — the last layer wins, so a
  /// newly added DNA goes to the end. [layers] is what the config declared
  /// before the dependency was installed.
  void _addLayer(String root, String layer, List<String> layers) {
    if (layers.contains(layer)) {
      ggLog(cDetail('✓ Kept existing layer "$layer" in $dnaConfigPath'));
      return;
    }
    final path = '$root/$dnaConfigPath';
    _host.writeString(path, addDnaLayer(_host.readString(path), layer));
    ggLog(cDetail('✓ Added layer "$layer" to $dnaConfigPath'));
  }
}
