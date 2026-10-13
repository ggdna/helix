// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dna_config.dart';
import 'dna_layout.dart';
import 'dna_vars.dart';
import 'layer_graph.dart';
import 'package_resolution.dart';

// .............................................................................
/// One layer as the `mustOverride` check sees it.
class MustOverrideLayer {
  /// Creates the layer.
  const MustOverrideLayer({
    required this.name,
    required this.varsFile,
    this.parents = const [],
    this.mustOverride = const {},
    this.ownVars = const {},
  });

  /// Canonical layer identity — what the [parents] of other layers name.
  final String name;

  /// The `_vars.json` of this layer as a developer opens it — where a
  /// missing value has to go.
  final String varsFile;

  /// Canonical names of the layer's own parents.
  final List<String> parents;

  /// The flags of the layer's own `dna/_dna.json`.
  final Map<String, bool> mustOverride;

  /// Variables the layer's own `_vars.json` gives a value (`null`, the
  /// deletion marker, is no value).
  final Set<String> ownVars;
}

// .............................................................................
/// A layer that does not set a variable it is required to set.
class MustOverrideViolation {
  /// Creates the violation.
  const MustOverrideViolation({
    required this.layer,
    required this.variable,
    required this.requiredBy,
  });

  /// The layer that misses the value.
  final MustOverrideLayer layer;

  /// The variable without a value.
  final String variable;

  /// Name of the layer whose `mustOverride: true` is in effect.
  final String requiredBy;
}

// .............................................................................
/// Checks [layers] — parents before children — against the `mustOverride`
/// flags they declare.
///
/// A layer inherits the flags of its parents; when any parent passes on
/// `true`, the layer must give the variable a value in its own
/// `_vars.json`. A flag the layer declares itself takes effect for its
/// children only: `true` passes the duty on even where it was lifted,
/// `false` lifts it. The declaring layer is never bound by its own flag.
List<MustOverrideViolation> mustOverrideViolations(
  List<MustOverrideLayer> layers,
) {
  // Per layer: variable → name of the layer whose `true` its children
  // inherit.
  final passedOn = <String, Map<String, String>>{};
  final violations = <MustOverrideViolation>[];

  for (final layer in layers) {
    final inherited = <String, String>{};
    for (final parent in layer.parents) {
      passedOn[parent]?.forEach((variable, requiredBy) {
        inherited.putIfAbsent(variable, () => requiredBy);
      });
    }

    for (final entry in inherited.entries) {
      if (layer.ownVars.contains(entry.key)) continue;
      violations.add(
        MustOverrideViolation(
          layer: layer,
          variable: entry.key,
          requiredBy: entry.value,
        ),
      );
    }

    final own = Map<String, String>.of(inherited);
    layer.mustOverride.forEach((variable, flag) {
      if (flag) {
        own[variable] = layer.name;
      } else {
        own.remove(variable);
      }
    });
    passedOn[layer.name] = own;
  }
  return violations;
}

// .............................................................................
/// Name of the project's own layer in the check — always the last one.
const String mustOverrideSelf = 'self';

/// The resolved [layers] and the project itself, as [mustOverrideViolations]
/// takes them: [varsFileOf] names a layer's `_vars.json` the way a
/// developer opens it, [ownVarsOf] says what a layer (or
/// [mustOverrideSelf]) sets itself. [includeSelf] `false` leaves the
/// project out — a workspace is exempt.
List<MustOverrideLayer> mustOverrideLayers({
  required List<ResolvedLayer> layers,
  required DnaConfig config,
  required String Function(ResolvedLayer layer) varsFileOf,
  required Set<String> Function(String name) ownVarsOf,
  bool includeSelf = true,
}) => [
  for (final layer in layers)
    MustOverrideLayer(
      name: layer.name,
      varsFile: varsFileOf(layer),
      parents: layer.parents,
      mustOverride: layer.mustOverride,
      ownVars: ownVarsOf(layer.name),
    ),
  if (includeSelf)
    MustOverrideLayer(
      name: mustOverrideSelf,
      varsFile: '$dnaDirname/$dnaVarsFilename',
      parents: [for (final l in config.layers) canonicalPackageName(l)],
      mustOverride: config.mustOverride,
      ownVars: ownVarsOf(mustOverrideSelf),
    ),
];
