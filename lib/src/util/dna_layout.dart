// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

/// Name of the replica folder every DNA layer ships.
const String dnaDirname = 'dna';

/// Format version of both `dna/_dna.json` and `dna/_generated.json`.
const int dnaFormatVersion = 1;

/// Filename of the hand-authored DNA configuration inside `<target>/dna/`
/// — the only place DNA configuration lives. Private per the `_`
/// convention, so it is never instantiated, and the engine only ever
/// reads it.
const String dnaConfigFilename = '_dna.json';

/// Filename of the engine-owned bookkeeping inside `<target>/dna/`:
/// resolved layers, hashes and the DNA-owned instances. Rewritten on
/// every run, never edited by hand.
const String dnaGeneratedFilename = '_generated.json';

/// Name prefix of the system-temp folder an instantiation puts the
/// backups in when it overwrites generated files that were changed
/// locally. Outside the project on purpose: the backup is a safety net,
/// not project content, and must not show up in git or in the DNA state.
const String dnaBackupDirPrefix = 'helix-dna-backup-';

/// Prefix that escapes a leading dot in DNA content: `dot-vscode` becomes
/// `.vscode` when instantiated. The only accepted form — `dot_` is not an
/// escape and instantiates verbatim.
const String dotPrefix = 'dot-';

// .............................................................................
/// Whether [relPosix] is private per the `_` convention: any path segment
/// starting with `_` stays inside `dna/` and is never instantiated.
bool isPrivatePath(String relPosix) =>
    relPosix.split('/').any((s) => s.startsWith('_'));

// .............................................................................
/// Decodes the dot escape of [relPosix]: `dot-vscode/settings.json`
/// becomes `.vscode/settings.json`.
///
/// DNA layers ship dotfiles escaped because `dart pub publish` silently
/// drops every path with a leading dot — a pub-installed layer would
/// otherwise lose `.vscode/`, `.claude/` and friends. `dna/` itself keeps
/// the escaped form, because that is what gets republished.
String decodeDotSegments(String relPosix) =>
    relPosix.split('/').map(_decodeDotSegment).join('/');

String _decodeDotSegment(String segment) => segment.startsWith(dotPrefix)
    ? '.${segment.substring(dotPrefix.length)}'
    : segment;

// .............................................................................
/// The misspelled dot escape: `dot_vscode` instead of `dot-vscode`.
const String invalidDotPrefix = 'dot_';

/// The first `dot_`-escaped segment of [relPosix], or `null` when there is
/// none. Only `dot-` is decoded, so such a path would instantiate as a
/// literal `dot_…` folder — the placed DNA test rejects it.
String? invalidDotSegment(String relPosix) {
  for (final segment in relPosix.split('/')) {
    if (segment.startsWith(invalidDotPrefix)) return segment;
  }
  return null;
}

// .............................................................................
/// Whether instantiating to [relPosix] is forbidden: git internals and the
/// managed `CLAUDE.md` (which mixes project-owned content with the managed
/// block).
bool isForbiddenInstanceTarget(String relPosix) =>
    relPosix == '.git' ||
    relPosix.startsWith('.git/') ||
    relPosix == 'CLAUDE.md';

// .............................................................................
/// All ancestor folders of [paths], deepest first — the candidates to
/// prune after their files were deleted. The paths themselves and the
/// root (empty string) are not part of the result.
List<String> ancestorDirs(Iterable<String> paths) {
  final dirs = <String>{};
  for (final path in paths) {
    final parts = path.split('/')..removeLast();
    while (parts.isNotEmpty) {
      dirs.add(parts.join('/'));
      parts.removeLast();
    }
  }
  return dirs.toList()
    ..sort((a, b) {
      final byDepth = b.split('/').length.compareTo(a.split('/').length);
      return byDepth != 0 ? byDepth : a.compareTo(b);
    });
}
