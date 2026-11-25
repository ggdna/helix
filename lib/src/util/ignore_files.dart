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

/// The suffix every ignore file name ends with.
const String ignoreFileSuffix = 'ignore';

/// The file `dart pub publish` reads instead of `.gitignore`.
const String pubignoreFileName = '.pubignore';

/// The file whose lines a root `.pubignore` starts with.
const String gitignoreFileName = '.gitignore';

// .............................................................................
/// Whether the DNA path [relPosix] is an ignore file: its name — after the
/// `dot-` escape is decoded — starts with a dot and ends with `ignore`,
/// e.g. `dot-pubignore` or `doc/dot-prettierignore`.
bool isIgnoreFile(String relPosix) {
  final name = decodeDotSegments(relPosix).split('/').last;
  return name.startsWith('.') &&
      name.length > ignoreFileSuffix.length + 1 &&
      name.endsWith(ignoreFileSuffix);
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
/// keeps it. Comments and blank lines stay where they are; a section left
/// without a pattern of its own is dropped entirely. The result is empty
/// when no section adds a pattern, and ends with a newline otherwise.
String mergeIgnoreSections(Iterable<IgnoreSection> sections) {
  final seen = <String>{};
  final blocks = <String>[];

  for (final section in sections) {
    final kept = <String>[];
    var addsPattern = false;
    for (final line in section.text.replaceAll('\r\n', '\n').split('\n')) {
      final pattern = line.trim();
      if (pattern.isEmpty || pattern.startsWith('#')) {
        kept.add(line);
        continue;
      }
      if (!seen.add(pattern)) continue;
      kept.add(line);
      addsPattern = true;
    }
    if (!addsPattern) continue;

    while (kept.first.trim().isEmpty) {
      kept.removeAt(0);
    }
    while (kept.last.trim().isEmpty) {
      kept.removeLast();
    }
    blocks.add(['# ${section.name}', ...kept].join('\n'));
  }

  return blocks.isEmpty ? '' : '${blocks.join('\n\n')}\n';
}
