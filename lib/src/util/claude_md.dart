// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:path/path.dart' as p;

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
/// `@`-import line each: files stay as-is, folders expand to all their
/// `.md` files (recursive, sorted). Paths are relative to [targetRoot]
/// and returned posix-style. Missing entries throw — a sync must never
/// generate broken `@`-imports.
List<String> expandClaudeMdIncludes(String targetRoot, List<String> include) {
  final result = <String>[];
  for (final entry in include) {
    final rel = entry.replaceAll('\\', '/');
    final path = p.normalize(p.join(targetRoot, rel));
    if (FileSystemEntity.isFileSync(path)) {
      result.add(_relPosix(path, targetRoot));
      continue;
    }
    final dir = Directory(path);
    if (!dir.existsSync()) {
      throw Exception(
        'claude_md include does not exist: "$entry" '
        '(resolved to $path)',
      );
    }
    final files = <String>[];
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.md')) {
        files.add(_relPosix(entity.path, targetRoot));
      }
    }
    files.sort();
    result.addAll(files);
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
/// Upserts the managed block for [importPaths] into `<targetRoot>/CLAUDE.md`,
/// creating the file when it does not exist. Returns `true` when the file
/// changed.
bool writeClaudeMd(String targetRoot, Iterable<String> importPaths) {
  final file = File(p.join(targetRoot, 'CLAUDE.md'));
  final existing = file.existsSync() ? file.readAsStringSync() : '';
  final updated =
      upsertClaudeMdBlock(existing, buildClaudeMdBlock(importPaths));
  if (existing == updated) return false;
  file.writeAsStringSync(updated);
  return true;
}

// .............................................................................
String _relPosix(String path, String from) =>
    p.relative(path, from: from).replaceAll('\\', '/');

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
