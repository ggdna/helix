// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

/// Name of the replica folder every DNA layer ships.
const String dnaDirname = 'dna';

/// Format version of both `dna/_dna.json` and `dna/_generated.json`.
const int dnaFormatVersion = 6;

/// Filename of the hand-authored DNA configuration inside `<target>/dna/`
/// — the only place DNA configuration lives. Private per the `_`
/// convention, so it is never instantiated, and the engine only ever
/// reads it.
const String dnaConfigFilename = '_dna.json';

/// Filename of the engine-owned bookkeeping inside `<target>/dna/`:
/// resolved layers, hashes and the DNA-owned instances. Rewritten on
/// every run, never edited by hand.
const String dnaGeneratedFilename = '_generated.json';

/// Prefix that escapes a leading dot in DNA content: `dot-vscode` becomes
/// `.vscode` when instantiated.
const String dotPrefix = 'dot-';

// .............................................................................
/// Whether [relPosix] is private per the `_` convention: any path segment
/// starting with `_` stays inside `dna/` and is never instantiated.
bool isPrivatePath(String relPosix) =>
    relPosix.split('/').any((s) => s.startsWith('_'));

// .............................................................................
/// Decodes the `dot-` escape of [relPosix]: `dot-vscode/settings.json`
/// becomes `.vscode/settings.json`.
///
/// DNA layers ship dotfiles escaped because `dart pub publish` silently
/// drops every path with a leading dot — a pub-installed layer would
/// otherwise lose `.vscode/`, `.claude/` and friends. `dna/` itself keeps
/// the escaped form, because that is what gets republished.
String decodeDotSegments(String relPosix) => relPosix
    .split('/')
    .map(
      (s) => s.startsWith(dotPrefix) ? '.${s.substring(dotPrefix.length)}' : s,
    )
    .join('/');

// .............................................................................
/// Whether instantiating to [relPosix] is forbidden: git internals and the
/// managed `CLAUDE.md` (which mixes project-owned content with the managed
/// block).
bool isForbiddenInstanceTarget(String relPosix) =>
    relPosix == '.git' ||
    relPosix.startsWith('.git/') ||
    relPosix == 'CLAUDE.md';

// .............................................................................
/// The file naming standard instances are converted to.
enum FileNaming {
  /// `my_file.dart` — Dart projects.
  snakeCase,

  /// `myFile.ts` — TypeScript projects.
  camelCase,

  /// `my-file.md` — canonical DNA form.
  kebabCase,

  /// No conversion.
  keep,
}

// .............................................................................
/// Parses the `fileNaming` config value; `null` when [value] is `null`,
/// throws [FormatException] on unknown values.
FileNaming? parseFileNaming(String? value) {
  switch (value) {
    case null:
      return null;
    case 'snake_case':
      return FileNaming.snakeCase;
    case 'camelCase':
      return FileNaming.camelCase;
    case 'kebab-case':
      return FileNaming.kebabCase;
    case 'keep':
      return FileNaming.keep;
    default:
      throw FormatException(
        'fileNaming must be one of snake_case, camelCase, kebab-case, '
        'keep — got "$value".',
      );
  }
}

// .............................................................................
/// Converts one path segment to [naming]. Only the part before the first
/// dot is converted (`dna-test.dart` → `dna_test.dart`, `.spec.ts` and
/// `.code-snippets` survive) and only for purely lowercase names — names
/// with uppercase letters (`LICENSE`, `README.md`) and dotfiles stay
/// untouched.
String convertSegmentNaming(String segment, FileNaming naming) {
  if (segment.startsWith('.')) return segment;
  final dot = segment.indexOf('.');
  final base = dot < 0 ? segment : segment.substring(0, dot);
  final ext = dot < 0 ? '' : segment.substring(dot);
  if (base.contains(RegExp('[A-Z]'))) return segment;
  if (!base.contains(RegExp('[a-z]'))) return segment;
  final words = base.split(RegExp('[-_]+')).where((w) => w.isNotEmpty).toList();
  if (words.length < 2) return segment;
  final String converted;
  switch (naming) {
    case FileNaming.snakeCase:
      converted = words.join('_');
    case FileNaming.camelCase:
      converted = words.first +
          words.skip(1).map((w) => w[0].toUpperCase() + w.substring(1)).join();
    case FileNaming.kebabCase:
      converted = words.join('-');
    case FileNaming.keep:
      converted = base;
  }
  return '$converted$ext';
}

// .............................................................................
/// Converts every segment of the relative posix path [relPosix] to
/// [naming] via [convertSegmentNaming]. Paths rooted in a dot-folder
/// (`.claude/`, `.vscode/`, `.github/`, …) keep their canonical names —
/// they are tool configuration, not ecosystem source, and e.g. skill
/// folder names must stay identical across all projects.
String convertPathNaming(String relPosix, FileNaming naming) {
  if (naming == FileNaming.keep) return relPosix;
  if (relPosix.startsWith('.')) return relPosix;
  return relPosix
      .split('/')
      .map((s) => convertSegmentNaming(s, naming))
      .join('/');
}

// .............................................................................
/// Rewrites references to renamed files in a text instance: every key of
/// [renames] (old segment name) is replaced literally by its value, longest
/// keys first.
String rewriteRenamedReferences(String content, Map<String, String> renames) {
  if (renames.isEmpty) return content;
  var result = content;
  final keys = renames.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final key in keys) {
    result = result.replaceAll(key, renames[key]!);
  }
  return result;
}

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
