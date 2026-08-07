// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dna_fs.dart';

/// Marker that opens the managed CLAUDE.md block.
const String claudeMdStartMarker = '<!-- gg_dna:claude_md:start -->';

/// Marker that closes the managed CLAUDE.md block.
const String claudeMdEndMarker = '<!-- gg_dna:claude_md:end -->';

/// Start marker of the pre-3.0 conventions block — removed on sight so
/// migrated repos do not carry two gg_dna blocks.
const String legacyConventionsStartMarker = '<!-- gg_dna:conventions:start';

/// End marker of the pre-3.0 conventions block.
const String legacyConventionsEndMarker = '<!-- gg_dna:conventions:end -->';

// .............................................................................
/// Expands the `claude_md: include:` entries to the files that get one
/// `@`-import line each. Entries are matched against [projectedFiles]
/// (the files the instantiation is about to produce) first, then against
/// the file system via [host]: files stay as-is, folders expand to all
/// their `.md` files (sorted). Missing entries throw — an instantiation
/// must never generate broken `@`-imports.
List<String> expandClaudeMdIncludes({
  required DnaHost host,
  required String targetRoot,
  required List<String> include,
  Set<String> projectedFiles = const {},
}) {
  final result = <String>[];
  for (final entry in include) {
    final rel = entry.replaceAll(r'\', '/');
    if (projectedFiles.contains(rel)) {
      result.add(rel);
      continue;
    }
    final folderMatches = projectedFiles
        .where((f) => f.startsWith('$rel/') && f.toLowerCase().endsWith('.md'))
        .toList()
      ..sort();
    if (folderMatches.isNotEmpty) {
      result.addAll(folderMatches);
      continue;
    }
    final path = '$targetRoot/$rel';
    if (host.existsFile(path)) {
      result.add(rel);
      continue;
    }
    if (host.existsDir(path)) {
      final files = host
          .listFilesRecursive(path)
          .where((f) => f.toLowerCase().endsWith('.md'))
          .map((f) => '$rel/$f')
          .toList()
        ..sort();
      result.addAll(files);
      continue;
    }
    throw Exception('claude_md include does not exist: "$entry"');
  }
  return result;
}

// .............................................................................
/// Builds the managed block: one `@`-import line per path between the
/// markers. Claude Code expands each import at session start (relative
/// paths resolve relative to the CLAUDE.md, max four hops deep).
String buildClaudeMdBlock(Iterable<String> importPaths) => [
      claudeMdStartMarker,
      ...importPaths.map((path) => '@$path'),
      claudeMdEndMarker,
    ].join('\n');

// .............................................................................
/// Replaces the managed block in [content] with [block], or appends it
/// when no block exists yet. A leftover pre-3.0 conventions block is
/// removed. Throws when a start marker has no matching end marker.
String upsertClaudeMdBlock(String content, String block) {
  final cleaned = _removeLegacyBlock(content);
  final start = cleaned.indexOf(claudeMdStartMarker);
  if (start == -1) {
    final trimmed = cleaned.trimRight();
    if (trimmed.isEmpty) {
      return '$block\n';
    }
    return '$trimmed\n\n$block\n';
  }
  final endIdx = cleaned.indexOf(claudeMdEndMarker, start);
  if (endIdx == -1) {
    throw StateError(
      'Found "$claudeMdStartMarker" without matching '
      '"$claudeMdEndMarker" in CLAUDE.md.',
    );
  }
  final before = cleaned.substring(0, start);
  final after = cleaned.substring(endIdx + claudeMdEndMarker.length);
  return '$before$block$after';
}

// .............................................................................
/// The updated content of `<targetRoot>/CLAUDE.md` for [importPaths], or
/// `null` when the file already carries exactly this block.
String? updatedClaudeMd(
  DnaHost host,
  String targetRoot,
  Iterable<String> importPaths,
) {
  final path = '$targetRoot/CLAUDE.md';
  final existing = host.existsFile(path) ? host.readString(path) : '';
  final updated =
      upsertClaudeMdBlock(existing, buildClaudeMdBlock(importPaths));
  return existing == updated ? null : updated;
}

// .............................................................................
String _removeLegacyBlock(String content) {
  final start = content.indexOf(legacyConventionsStartMarker);
  if (start == -1) return content;
  final endIdx = content.indexOf(legacyConventionsEndMarker, start);
  if (endIdx == -1) return content;
  var end = endIdx + legacyConventionsEndMarker.length;
  // Also swallow the newline(s) directly after the removed block.
  while (
      end < content.length && (content[end] == '\n' || content[end] == '\r')) {
    end++;
  }
  return content.substring(0, start) + content.substring(end);
}
