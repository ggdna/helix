// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_log/gg_log.dart';

import '../util/dna_config.dart';
import '../util/dna_fs.dart';
import '../util/dna_layout.dart';
import '../util/dna_must_override.dart';
import '../util/dna_vars.dart';
import '../util/dna_vars_edit.dart';
import '../util/jsonc.dart';
import '../util/layer_graph.dart';
import '../util/package_resolution.dart';
import '../util/text_prompt.dart';

/// Path of the project's own variables file relative to its root.
const String dnaVarsPath = '$dnaDirname/$dnaVarsFilename';

// .............................................................................
/// A variable the project has to set itself.
class MissingProjectVar {
  /// Creates the entry.
  const MissingProjectVar({
    required this.variable,
    required this.requiredBy,
    this.fromConfigVars,
  });

  /// The variable without a value in the project's `dna/_vars.json`.
  final String variable;

  /// Name of the layer whose `mustOverride: true` asks for it.
  final String requiredBy;

  /// The value the project already gives it in the `vars` of
  /// `dna/_dna.json` — its own choice, which only has to move. `null` when
  /// there is none: a value inherited from the layers is never offered,
  /// it is exactly what `mustOverride` asks to replace.
  final String? fromConfigVars;
}

// .............................................................................
/// The variables the layers of [targetRoot] mark `mustOverride` and the
/// project's own `dna/_vars.json` does not set yet.
///
/// Throws a [FormatException] when the project's `dna/_vars.json` cannot
/// be parsed — counting its values as missing would ask again for what it
/// may well set, and append to a file that is broken already.
List<MissingProjectVar> missingProjectVars(DnaHost host, String targetRoot) {
  final config = readDnaConfig(host, targetRoot).config;
  final graph = expandLayerGraph(
    host: host,
    targetRoot: targetRoot,
    config: config,
    resolution: PackageResolution.read(host, targetRoot),
  );

  final ownVars = <String>{};
  final path = '$targetRoot/$dnaVarsPath';
  if (host.existsFile(path)) {
    final text = host.readString(path);
    parseJsonc(text, sourceLabel: dnaVarsPath);
    for (final e in parseDnaVarEntries(
      text,
      sourceLabel: dnaVarsPath,
    ).entries.entries) {
      if (e.value != null) ownVars.add(e.key);
    }
  }

  final violations = mustOverrideViolations(
    mustOverrideLayers(
      layers: graph.layers,
      config: config,
      varsFileOf: (layer) => '${layer.package}/$dnaVarsPath',
      // Only the project's own duties matter here.
      ownVarsOf: (name) => name == mustOverrideSelf ? ownVars : const {},
    ),
  );

  return [
    for (final v in violations)
      if (v.layer.name == mustOverrideSelf)
        MissingProjectVar(
          variable: v.variable,
          requiredBy: v.requiredBy,
          fromConfigVars: config.vars[v.variable] as String?,
        ),
  ];
}

// .............................................................................
/// Asks for every variable of [missingProjectVars] and appends the answers
/// to the project's `dna/_vars.json`. Without anybody to ask, it names the
/// variables to set by hand instead — the next DNA run fails until they
/// are.
///
/// Asking never makes `init` or `add` fail where they did not fail
/// before: a config, layer tree or variables file that cannot be read or
/// written is left to the build, which reports it with its full context.
Future<void> askMustOverrides({
  required DnaHost host,
  required String targetRoot,
  required TextPrompt prompt,
  required GgLog ggLog,
}) async {
  final List<MissingProjectVar> missing;
  try {
    missing = missingProjectVars(host, targetRoot);
  } on Exception {
    return;
  }
  if (missing.isEmpty) return;

  final names = missing.map((m) => m.variable).join(', ');
  final answers = <String, String>{};
  try {
    for (final m in missing) {
      answers[m.variable] = await prompt(
        prompt: '${m.variable} (required by ${m.requiredBy})',
        defaultValue: m.fromConfigVars,
      );
    }
  } on PromptUnavailableException catch (e) {
    ggLog(
      '! Set $names in $dnaVarsPath — the layers require it and it cannot '
      'be asked for (${e.reason}).',
    );
    return;
  }

  final path = '$targetRoot/$dnaVarsPath';
  try {
    final text = host.existsFile(path) ? host.readString(path) : null;
    host.writeString(path, addDnaVars(text, answers));
  } on Exception catch (e) {
    ggLog('! Set $names in $dnaVarsPath — writing it failed ($e).');
    return;
  }
  ggLog('✓ Set ${answers.keys.join(', ')} in $dnaVarsPath');
}
