// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

/// Markdown tag override engine: sections marked `### @tag Titel` are
/// replaced via `X.overrides.md` files of higher DNA layers
/// ([parseTagFile] + [applyTagBlocks], markers stay re-overridable);
/// [renderMarkers] strips the markers for the output. Per-value
/// substitution is the job of the dna variables in `dna/_vars.json`.
/// The full syntax is documented in the README.
library;

/// Suffix identifying override files (`X.overrides.md` overrides `X.md`).
const String overridesFileSuffix = '.overrides.md';

/// The pre-4.0 override suffix — hitting one is a hard error with a
/// rename hint, never a silent skip.
const String legacyOverridesFileSuffix = '.tag.md';

/// One parsed replacement block of a `.overrides.md` file.
class TagBlock {
  /// Constructor.
  const TagBlock({
    required this.tag,
    required this.content,
    this.isHeadingForm = false,
  });

  /// The tag this block replaces.
  final String tag;

  /// The replacement content (heading-form blocks include their heading).
  final String content;

  /// Whether the block was written as `#… @tag Titel` (vs. comment
  /// markers) — global overrides reject heading-form blocks.
  final bool isHeadingForm;
}

/// Result of [parseTagFile].
class TagFileParseResult {
  /// Constructor.
  const TagFileParseResult({required this.blocks, required this.warnings});

  /// The parsed blocks, in file order.
  final List<TagBlock> blocks;

  /// Non-fatal findings (stray content, unclosed blocks, …).
  final List<String> warnings;
}

/// Result of [applyTagBlocks].
class TagApplyResult {
  /// Constructor.
  const TagApplyResult({required this.content, required this.warnings});

  /// The patched target content.
  final String content;

  /// Non-fatal findings (unknown tags, invalid replacements, …).
  final List<String> warnings;
}

// .............................................................................
/// Parses a `.overrides.md` body into its comment-delimited
/// (`<!-- @tag -->` … `<!-- @tag -->`, also single-line) and heading-form
/// (`#… @tag Titel` up to the next block) replacement blocks; stray
/// content warns.
TagFileParseResult parseTagFile(String content) {
  final doc = _Doc(content);
  final lines = doc.lines;
  final fenced = _fenceMask(lines);
  final blocks = <TagBlock>[];
  final warnings = <String>[];

  String? commentTag;
  String? headingTag;
  var collected = <String>[];
  final strayLines = <int>[];

  void closeHeadingBlock() {
    if (headingTag == null) return;
    blocks.add(
      TagBlock(
        tag: headingTag!,
        content: _trimBlankEdges(collected).join('\n'),
        isHeadingForm: true,
      ),
    );
    headingTag = null;
    collected = [];
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];

    // Fenced lines are always content — a `<!-- tag -->` or `### [tag]`
    // inside a code fence never opens or closes a block.
    if (fenced[i]) {
      if (commentTag != null || headingTag != null) {
        collected.add(line);
      } else if (line.trim().isNotEmpty) {
        strayLines.add(i + 1);
      }
      continue;
    }

    // Inside a comment-delimited block only the same-tag marker closes.
    if (commentTag != null) {
      final marker = _commentMarkerRe.firstMatch(line);
      if (marker != null &&
          marker.group(1) == commentTag &&
          line.trim() == marker.group(0)) {
        blocks.add(
          TagBlock(
            tag: commentTag,
            content: _trimBlankEdges(collected).join('\n'),
          ),
        );
        commentTag = null;
        collected = [];
      } else {
        collected.add(line);
      }
      continue;
    }

    final markers = _commentMarkerRe.allMatches(line).toList();
    if (markers.isNotEmpty) {
      closeHeadingBlock();
      final first = markers.first;
      if (markers.length == 2 &&
          markers[1].group(1) == first.group(1) &&
          line.substring(0, first.start).trim().isEmpty &&
          line.substring(markers[1].end).trim().isEmpty) {
        // Single-line form: <!-- tag --> text <!-- tag -->
        blocks.add(
          TagBlock(
            tag: first.group(1)!,
            content: line.substring(first.end, markers[1].start).trim(),
          ),
        );
      } else if (markers.length == 1 && line.trim() == first.group(0)) {
        commentTag = first.group(1);
      } else {
        warnings.add('Ambiguous tag marker line ${i + 1}: "$line" — skipped.');
      }
      continue;
    }

    final tagged = _taggedHeadingRe.firstMatch(line);
    if (tagged != null) {
      closeHeadingBlock();
      headingTag = tagged.group(2);
      collected = [line];
      continue;
    }

    if (headingTag != null) {
      collected.add(line);
      continue;
    }

    if (line.trim().isNotEmpty) {
      strayLines.add(i + 1);
    }
  }

  if (commentTag != null) {
    warnings.add('Unclosed tag block "<!-- $commentTag -->" — block skipped.');
  }
  closeHeadingBlock();
  if (strayLines.isNotEmpty) {
    warnings.add(
      'Stray content outside any tag block '
      '(line${strayLines.length > 1 ? 's' : ''} ${strayLines.join(', ')}).',
    );
  }

  return TagFileParseResult(blocks: blocks, warnings: warnings);
}

// .............................................................................
/// Applies [blocks] to [target] — an `@tag` heading there marks the
/// section a block replaces; the marker stays re-overridable for later
/// layers. A tag that matches nothing warns via [fileLabel].
TagApplyResult applyTagBlocks(
  String target,
  List<TagBlock> blocks, {
  required String fileLabel,
}) {
  final doc = _Doc(target);
  final warnings = <String>[];

  for (final block in blocks) {
    final lines = doc.lines;
    final fenced = _fenceMask(lines);

    // Collect all tagged-section occurrences with their boundaries before
    // mutating anything — the replacement re-attaches the same tag, so a
    // rescan after mutation would find the freshly inserted heading again.
    // A same-tag heading nested inside an already collected region (deeper
    // level) is skipped: it is part of the outer section and gets replaced
    // with it — collecting it would create overlapping regions and corrupt
    // the reverse replacement below.
    final regions = <({int start, int end})>[];
    for (var i = 0; i < lines.length; i++) {
      if (fenced[i]) continue;
      if (regions.isNotEmpty && i < regions.last.end) continue;
      final tagged = _taggedHeadingRe.firstMatch(lines[i]);
      if (tagged == null || tagged.group(2) != block.tag) continue;
      final level = tagged.group(1)!.length;
      var end = i + 1;
      while (end < lines.length) {
        if (!fenced[end]) {
          final heading = _headingRe.firstMatch(lines[end]);
          if (heading != null && heading.group(1)!.length <= level) break;
        }
        end++;
      }
      regions.add((start: i, end: end));
    }

    if (regions.isEmpty) {
      warnings.add('Tag "${block.tag}" not found in $fileLabel — skipped.');
      continue;
    }

    final replacement = _sectionReplacement(block, warnings, fileLabel);
    if (replacement == null) continue;
    for (final region in regions.reversed) {
      lines.replaceRange(region.start, region.end, [
        ...replacement,
        if (region.end < lines.length) '',
      ]);
    }
  }

  return TagApplyResult(content: doc.render(), warnings: warnings);
}

// .............................................................................
/// Strips all markers for the synced output (`### @tag T` -> `### T`);
/// fenced and inline code stay untouched so documentation can show the
/// syntax literally. Idempotent.
String renderMarkers(String content) {
  final doc = _Doc(content);
  final lines = doc.lines;
  final fenced = _fenceMask(lines);

  for (var i = 0; i < lines.length; i++) {
    if (fenced[i]) continue;
    var line = lines[i];
    final tagged = _taggedHeadingRe.firstMatch(line);
    if (tagged != null) {
      final rest = (tagged.group(3) ?? '').trim();
      line = rest.isEmpty ? tagged.group(1)! : '${tagged.group(1)!} $rest';
    }
    lines[i] = line;
  }

  return doc.render();
}

// .............................................................................
/// Reports lines of [content] that still use the pre-4.0 notation —
/// unambiguous patterns only (`## [tag] …` headings and `{{tag|…}}`
/// placeholders); fenced and inline code are skipped. Returns one
/// message per finding, prefixed with the 1-based line number.
List<String> detectLegacyMarkers(String content) {
  final doc = _Doc(content);
  final lines = doc.lines;
  final fenced = _fenceMask(lines);
  final findings = <String>[];

  for (var i = 0; i < lines.length; i++) {
    if (fenced[i]) continue;
    final line = lines[i];
    if (_legacyHeadingRe.hasMatch(line)) {
      findings.add(
        'line ${i + 1}: bracketed section tag — '
        'use "@tag" instead of "[@tag]".',
      );
    }
    var legacyPlaceholder = false;
    _mapOutsideInlineCode(line, (segment) {
      if (_legacyPlaceholderRe.hasMatch(segment)) legacyPlaceholder = true;
      return segment;
    });
    if (legacyPlaceholder) {
      findings.add(
        'line ${i + 1}: string placeholder — these are gone; define a '
        'dna variable in dna/_vars.json instead.',
      );
    }
  }

  return findings;
}

// =============================================================================
// Private
// =============================================================================

final RegExp _taggedHeadingRe = RegExp(
  r'^(#{1,6})[ \t]+@([A-Za-z0-9_-]+)(?:[ \t]+(.*))?$',
);
final RegExp _headingRe = RegExp(r'^(#{1,6})(?:[ \t]+(.*))?$');
final RegExp _commentMarkerRe = RegExp(r'<!--\s*@([A-Za-z0-9_-]+)\s*-->');
final RegExp _fenceRe = RegExp(r'^\s{0,3}(`{3,}|~{3,})');
final RegExp _inlineCodeRe = RegExp(r'`[^`]*`');

/// Retired notations, detected for warnings only: bracketed section
/// headings (`## [@tag] …` and the pre-4.0 `## [tag] …`) and the string
/// placeholders `{{@tag:…}}` / `{{tag|…}}`.
final RegExp _legacyHeadingRe = RegExp(
  r'^#{1,6}[ \t]+\[@?[A-Za-z0-9_-]+\][ \t]*',
);
final RegExp _legacyPlaceholderRe = RegExp(r'\{\{@?[A-Za-z0-9_-]+[:|]');

// .............................................................................
/// Splits [content] into logical lines while remembering the dominant line
/// ending and trailing-newline state, so [render] can reproduce them. Layer
/// sources on user machines may be CRLF even though this repo is LF-only.
class _Doc {
  _Doc(String content)
    : eol = _dominantEol(content),
      endsWithNewline = content.endsWith('\n') {
    final raw = content.split('\n');
    if (content.endsWith('\n')) raw.removeLast();
    lines.addAll([
      for (final line in raw)
        line.endsWith('\r') ? line.substring(0, line.length - 1) : line,
    ]);
  }

  /// The majority line ending; mixed files normalize to it on render.
  static String _dominantEol(String content) {
    final crlf = '\r\n'.allMatches(content).length;
    final lf = '\n'.allMatches(content).length - crlf;
    return crlf > lf ? '\r\n' : '\n';
  }

  final List<String> lines = [];
  final String eol;
  final bool endsWithNewline;

  String render() => lines.join(eol) + (endsWithNewline ? eol : '');
}

// .............................................................................
/// Masks all code-fence lines (CommonMark: closers need the same character
/// and at least the opener's length, so longer fences nest shorter ones).
List<bool> _fenceMask(List<String> lines) {
  final mask = List<bool>.filled(lines.length, false);
  String? fence;
  for (var i = 0; i < lines.length; i++) {
    final match = _fenceRe.firstMatch(lines[i]);
    if (match != null) {
      final delimiter = match.group(1)!;
      mask[i] = true;
      if (fence == null) {
        fence = delimiter;
      } else if (delimiter[0] == fence[0] && delimiter.length >= fence.length) {
        fence = null;
      }
      continue;
    }
    mask[i] = fence != null;
  }
  return mask;
}

// .............................................................................
/// Prepares [block] as section replacement: must start with a heading whose
/// marker slot receives the block's tag; `null` plus warning otherwise.
List<String>? _sectionReplacement(
  TagBlock block,
  List<String> warnings,
  String fileLabel,
) {
  final lines = _trimBlankEdges(_Doc(block.content).lines);
  final heading = lines.isEmpty ? null : _headingRe.firstMatch(lines.first);
  if (heading == null) {
    warnings.add(
      'Section replacement for tag "${block.tag}" in $fileLabel must start '
      'with a heading — skipped.',
    );
    return null;
  }
  final tagged = _taggedHeadingRe.firstMatch(lines.first);
  if (tagged == null) {
    final hashes = heading.group(1)!;
    final rest = (heading.group(2) ?? '').trim();
    lines[0] = rest.isEmpty
        ? '$hashes @${block.tag}'
        : '$hashes @${block.tag} $rest';
  } else if (tagged.group(2) != block.tag) {
    final rest = (tagged.group(3) ?? '').trim();
    lines[0] = rest.isEmpty
        ? '${tagged.group(1)} @${block.tag}'
        : '${tagged.group(1)} @${block.tag} $rest';
  }
  return lines;
}

// .............................................................................
/// Removes leading and trailing whitespace-only lines.
List<String> _trimBlankEdges(List<String> lines) {
  var start = 0;
  var end = lines.length;
  while (start < end && lines[start].trim().isEmpty) {
    start++;
  }
  while (end > start && lines[end - 1].trim().isEmpty) {
    end--;
  }
  return lines.sublist(start, end);
}

// .............................................................................
/// Applies [transform] to the parts of [line] outside `inline code` spans.
String _mapOutsideInlineCode(
  String line,
  String Function(String segment) transform,
) {
  final buffer = StringBuffer();
  var index = 0;
  for (final match in _inlineCodeRe.allMatches(line)) {
    buffer.write(transform(line.substring(index, match.start)));
    buffer.write(match.group(0));
    index = match.end;
  }
  buffer.write(transform(line.substring(index)));
  return buffer.toString();
}
