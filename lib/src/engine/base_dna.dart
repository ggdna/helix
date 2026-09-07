// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import '../util/dna_fs.dart';
import '../util/dna_layout.dart';
import '../util/dna_vars.dart';

/// The base DNA the engine carries itself — layer 0 of every project,
/// below whatever that project declares.
///
/// Kept here as source rather than read from the installed package folder:
/// resolving that folder needs `dart:isolate`, which `dart compile wasm`
/// does not support, so a DNA run inside a WebAssembly build could not
/// find it. Embedded, the engine carries its own base wherever it runs.
///
/// The constants are the source and `dna/` is what consumers get:
/// `test/engine/base_dna_test.dart` repairs the folder from [baseDnaFiles]
/// the way `test/helix_version_test.dart` repairs the version literal.

// .............................................................................
/// Every file the base DNA ships, keyed by its path below `dna/`.
///
/// `_generated.json` is deliberately absent: it is the engine's own
/// bookkeeping, excluded from a layer's content by `isDnaContent` and
/// never read from a layer.
///
/// Both entries are private — a leading `_` never becomes an instance —
/// so layer 0 contributes configuration, not files: a project that
/// declares no layer of its own gets no instances from the base.
const Map<String, String> baseDnaFiles = {
  dnaConfigFilename: baseDnaConfig,
  dnaVarsFilename: baseDnaVars,
};

/// Content of the base DNA's `_dna.json`.
const String baseDnaConfig =
    '''
{
  // The base DNA the engine carries itself: it is applied to every project
  // as layer 0, below whatever that project declares.
  "version": $dnaFormatVersion,

  // No parents — this is the bottom of every tree.
  "layers": []
}
''';

/// Content of the base DNA's `_vars.json` — the base declares none.
const String baseDnaVars = '{}\n';

// .............................................................................
/// Writes [baseDnaFiles] into a fresh temp folder through [host] and
/// returns that folder — the `baseDnaRoot` the engine reads layer 0 from.
///
/// The caller owns the folder and deletes it when the run is over.
String materializeBaseDna(DnaHost host) {
  final root = host.createTempDir('helix_base_dna_');
  baseDnaFiles.forEach((rel, content) {
    host.writeString('$root/$dnaDirname/$rel', content);
  });
  return root;
}
