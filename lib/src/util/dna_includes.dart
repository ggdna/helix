// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

/// Splices the full content of one merged DNA file into another, so the
/// reader needs no separate instance file to see it — the mechanism a
/// `--workspace` build relies on to keep documentation readable once
/// `doc/` itself is no longer instantiated. One level only: content
/// spliced in is not itself scanned for further markers or `@`-imports,
/// which matches every known use so far.
library;

import 'dart:convert';
import 'dart:typed_data';

/// One line `<!-- helix:include:<path> -->`, capturing `<path>`. Always
/// resolved, in every build — the marker exists only where a DNA author
/// chose it over a plain instance file.
final RegExp includeMarkerRe = RegExp(r'^<!--\s*helix:include:(.+?)\s*-->$');

/// One line `@<path>` — Claude Code's own import syntax. Resolved only in
/// `--workspace` builds, where the imported path is never written as its
/// own file and the plain `@`-line would otherwise point nowhere.
final RegExp atImportRe = RegExp(r'^@(\S+)$');

// .............................................................................
/// Replaces every include marker in [text] with the content [merged] holds
/// at that path; with [inlineAtImports] a lone `@path` line is replaced the
/// same way. [selfLabel] names [text] for the error message. A referenced
/// path missing from [merged] throws — the DNA must never ship a marker
/// that resolves to nothing, the same rule `expandClaudeMdIncludes` already
/// follows for `@`-imports.
String resolveIncludes(
  String text,
  Map<String, Uint8List> merged, {
  required String selfLabel,
  bool inlineAtImports = false,
}) {
  final lines = text.split('\n');
  final result = <String>[];
  for (final line in lines) {
    final trimmed = line.trim();
    final markerMatch = includeMarkerRe.firstMatch(trimmed);
    final atMatch = inlineAtImports ? atImportRe.firstMatch(trimmed) : null;
    final match = markerMatch ?? atMatch;
    if (match == null) {
      result.add(line);
      continue;
    }
    final rel = match.group(1)!;
    final bytes = merged[rel];
    if (bytes == null) {
      throw Exception('"$selfLabel" includes "$rel", which does not exist.');
    }
    result.add(utf8.decode(bytes));
  }
  return result.join('\n');
}
