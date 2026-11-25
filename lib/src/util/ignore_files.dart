// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

/// Ignore files (`.gitignore`, `.pubignore`, `.npmignore`,
/// `.prettierignore`, …) are not replaced layer by layer like other DNA
/// files: every layer adds the lines for the files it ships itself, and the
/// project receives the union of all of them.
library;

import 'dna_layout.dart';
import 'dna_tree_hash.dart';

/// The file `dart pub publish` reads instead of `.gitignore`.
const String pubignoreFileName = '.pubignore';

/// The file whose lines a root `.pubignore` starts with.
const String gitignoreFileName = '.gitignore';

// .............................................................................
/// Whether the DNA path [relPosix] is an ignore file: its name — after the
/// `dot-` escape is decoded — starts with a dot and ends with `ignore`,
/// e.g. `dot-pubignore` or `doc/dot-prettierignore`.
bool isIgnoreFile(String relPosix) {
  final name = decodeDotSegments(relPosix.split('/').last);
  return name.length > '.ignore'.length &&
      name.startsWith('.') &&
      name.endsWith('ignore');
}

// .............................................................................
/// One contribution to an ignore file: the [text] a source named [name]
/// ships.
typedef IgnoreSection = ({String name, String text});

// .............................................................................
/// Joins [sections] into one ignore file, in the given order.
///
/// Each section starts with a `# <name>` line. A pattern that an earlier
/// section already holds is left out, so the first section to name a path
/// keeps it — unless a line of the other kind (pattern or `!`-negation) came
/// in between: the last matching line wins in an ignore file, so such a
/// repetition still changes what is ignored.
/// Comments and blank lines stay where they are; a section left without a
/// pattern of its own is dropped entirely. The result is empty when no
/// section adds a pattern, and ends with a newline otherwise.
String mergeIgnoreSections(Iterable<IgnoreSection> sections) {
  final ignored = <String>{};
  final negated = <String>{};
  final blocks = <String>[];

  for (final section in sections) {
    final kept = <String>[];
    var addsPattern = false;
    for (final line in normalizeEolText(section.text).split('\n')) {
      final pattern = _patternOf(line);
      if (pattern.isEmpty || pattern.startsWith('#')) {
        kept.add(line);
        continue;
      }
      // A negation may undo the patterns before it and a pattern the
      // negations before it, so a repetition only counts as one while no
      // line of the other kind came in between.
      final negation = pattern.startsWith('!');
      final (same, other) = negation ? (negated, ignored) : (ignored, negated);
      if (!same.add(pattern)) continue;
      other.clear();
      kept.add(line);
      addsPattern = true;
    }
    if (!addsPattern) continue;

    bool filled(String line) => line.trim().isNotEmpty;
    final body = kept.sublist(
      kept.indexWhere(filled),
      kept.lastIndexWhere(filled) + 1,
    );
    blocks.add(['# ${section.name}', ...body].join('\n'));
  }

  return blocks.isEmpty ? '' : '${blocks.join('\n\n')}\n';
}

// .............................................................................
/// The pattern [line] stands for: without the line break and the trailing
/// whitespace git ignores, but with leading and escaped (`\ `) trailing
/// whitespace, which belong to the pattern.
String _patternOf(String line) =>
    line.replaceFirst(_unescapedTrailingSpace, '');

final RegExp _unescapedTrailingSpace = RegExp(r'(?<!\\)[ \t\r]+$');
