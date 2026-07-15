// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

/// Markdown tag override engine.
///
/// Source markdown files mark override points with two constructs:
///   - replaceable sections: `### [tag] Überschrift` — the section spans the
///     heading through just before the next heading of the same or a higher
///     level (code-fence aware), or the end of file
///   - replaceable strings: `{{tag|Standardwert}}` (or `{{tag}}` for an
///     empty default)
///
/// Higher DNA layers ship `X.tag.md` files next to `X.md` that carry
/// replacements as a sequence of blocks — see [parseTagFile] for the
/// grammar. [applyTagBlocks] patches a merged target file with such blocks,
/// keeping the markers intact so later layers can re-override the same tags.
/// [renderMarkers] finally strips all markers for the synced output.
library;

/// Suffix identifying tag-override files (`X.tag.md` overrides `X.md`).
const String tagFileSuffix = '.tag.md';

/// One parsed replacement block of a `.tag.md` file.
class TagBlock {
  /// Constructor.
  const TagBlock({required this.tag, required this.content});

  /// The tag this block replaces.
  final String tag;

  /// The replacement content. For heading-form blocks this includes the
  /// heading line itself; for comment-delimited blocks it is the inner text.
  final String content;
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
/// Parses the body of a `.tag.md` file into replacement blocks.
///
/// The file is a sequence of top-level blocks (outside code fences):
///   - comment-delimited: a line `<!-- tag -->` opens a block that the next
///     `<!-- tag -->` line with the same tag closes; other comments inside
///     are content. The single-line form `<!-- tag --> text <!-- tag -->`
///     yields the trimmed inner text.
///   - heading-form: `#… [tag] Titel` opens a block that runs until the next
///     tagged heading, the next top-level comment marker, or the end of
///     file; the heading line is part of the replacement.
///
/// Non-whitespace content outside any block and unclosed comment blocks are
/// reported as warnings.
TagFileParseResult parseTagFile(String content) {
  final doc = _Doc(content);
  final lines = doc.lines;
  final fenced = _fenceMask(lines);
  final blocks = <TagBlock>[];
  final warnings = <String>[];

  String? commentTag;
  String? headingTag;
  var collected = <String>[];
  var lastWasStray = false;

  void closeHeadingBlock() {
    if (headingTag == null) return;
    blocks.add(
      TagBlock(
        tag: headingTag!,
        content: _trimBlankEdges(collected).join('\n'),
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
        if (!lastWasStray) {
          warnings.add(
            'Stray content outside any tag block (line ${i + 1}): "$line".',
          );
        }
        lastWasStray = true;
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
        warnings.add(
          'Ambiguous tag marker line ${i + 1}: "$line" — skipped.',
        );
      }
      lastWasStray = false;
      continue;
    }

    final tagged = _taggedHeadingRe.firstMatch(line);
    if (tagged != null) {
      closeHeadingBlock();
      headingTag = tagged.group(2);
      collected = [line];
      lastWasStray = false;
      continue;
    }

    if (headingTag != null) {
      collected.add(line);
      continue;
    }

    if (line.trim().isEmpty) {
      lastWasStray = false;
      continue;
    }
    if (!lastWasStray) {
      warnings.add(
        'Stray content outside any tag block (line ${i + 1}): "$line".',
      );
    }
    lastWasStray = true;
  }

  if (commentTag != null) {
    warnings.add(
      'Unclosed tag block "<!-- $commentTag -->" — block skipped.',
    );
  }
  closeHeadingBlock();

  return TagFileParseResult(blocks: blocks, warnings: warnings);
}

// .............................................................................
/// Applies [blocks] to [target], the current merged content of an `X.md`.
///
/// The target decides the mechanism per tag:
///   - a `[tag]` heading present → section replacement. The replacement must
///     start with a heading (warned and skipped otherwise); the tag is
///     re-attached to that heading so later layers can re-override it. All
///     occurrences are replaced; the replaced region of each occurrence is
///     bounded by its original heading level.
///   - `{{tag|…}}` placeholders present → string override, implemented as a
///     rewrite to `{{tag|<new value>}}` so later layers can re-override.
///     Placeholders inside code fences or inline code are untouched.
///   - neither → warning.
///
/// [fileLabel] names the target in warnings.
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

    if (regions.isNotEmpty) {
      final replacement = _sectionReplacement(block, warnings, fileLabel);
      if (replacement == null) continue;
      for (final region in regions.reversed) {
        lines.replaceRange(region.start, region.end, [
          ...replacement,
          if (region.end < lines.length) '',
        ]);
      }
      continue;
    }

    // String override: rewrite {{tag|old}} to {{tag|new}}.
    var value = block.content;
    if (value.contains('\n')) {
      warnings.add(
        'Replacement for tag "${block.tag}" in $fileLabel spans multiple '
        'lines — collapsed to a single line.',
      );
      value = value.split('\n').map((line) => line.trim()).join(' ');
    }
    if (value.contains('}}')) {
      warnings.add(
        'Replacement value for tag "${block.tag}" in $fileLabel contains '
        '"}}" — later overrides and rendering may truncate it.',
      );
    }
    final placeholder = _placeholderRe(block.tag);
    var found = false;
    for (var i = 0; i < lines.length; i++) {
      if (fenced[i]) continue;
      lines[i] = _mapOutsideInlineCode(lines[i], (segment) {
        return segment.replaceAllMapped(placeholder, (match) {
          found = true;
          return '{{${block.tag}|$value}}';
        });
      });
    }
    if (!found) {
      warnings.add('Tag "${block.tag}" not found in $fileLabel — skipped.');
    }
  }

  return TagApplyResult(content: doc.render(), warnings: warnings);
}

// .............................................................................
/// Strips all tag markers from [content] for the final synced output:
/// `### [tag] Titel` becomes `### Titel`, `{{tag|wert}}` becomes `wert`,
/// `{{tag}}` becomes the empty string.
///
/// Markers inside code fences or inline code are preserved so documentation
/// can show the syntax literally. The function is idempotent.
String renderMarkers(String content) {
  final doc = _Doc(content);
  final lines = doc.lines;
  final fenced = _fenceMask(lines);

  for (var i = 0; i < lines.length; i++) {
    if (fenced[i]) continue;
    var line = lines[i];
    final tagged = _taggedHeadingRe.firstMatch(line);
    if (tagged != null) {
      final rest = tagged.group(3)!.trim();
      line = rest.isEmpty ? tagged.group(1)! : '${tagged.group(1)!} $rest';
    }
    line = _mapOutsideInlineCode(line, (segment) {
      return segment.replaceAllMapped(
        _anyPlaceholderRe,
        (match) => match.group(2) ?? '',
      );
    });
    lines[i] = line;
  }

  return doc.render();
}

// =============================================================================
// Private
// =============================================================================

final RegExp _taggedHeadingRe =
    RegExp(r'^(#{1,6})[ \t]+\[([A-Za-z0-9_-]+)\][ \t]*(.*)$');
final RegExp _headingRe = RegExp(r'^(#{1,6})(?:[ \t]+(.*))?$');
final RegExp _commentMarkerRe = RegExp(r'<!--\s*([A-Za-z0-9_-]+)\s*-->');
final RegExp _anyPlaceholderRe =
    RegExp(r'\{\{([A-Za-z0-9_-]+)(?:\|(.*?))?\}\}');
final RegExp _fenceRe = RegExp(r'^\s{0,3}(`{3,}|~{3,})');
final RegExp _inlineCodeRe = RegExp(r'`[^`]*`');

RegExp _placeholderRe(String tag) =>
    RegExp(r'\{\{' + RegExp.escape(tag) + r'(?:\|(.*?))?\}\}');

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

  /// The line ending the majority of lines use. Mixed files get normalized
  /// to their dominant ending on render.
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
/// Returns a mask marking every line that belongs to a code fence (including
/// the fence delimiter lines themselves).
///
/// Follows the CommonMark closing rule: a fence only closes on a run of the
/// same character that is at least as long as the opener — so a 3-backtick
/// line inside a 4-backtick fence is content, which lets documentation nest
/// literal fenced examples.
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
/// Validates and prepares the section replacement of [block]: must start
/// with a heading; the block's tag occupies the heading's marker slot — a
/// missing tag is attached, a foreign tag is replaced. Returns `null` (with
/// a warning) for invalid replacements.
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
        ? '$hashes [${block.tag}]'
        : '$hashes [${block.tag}] $rest';
  } else if (tagged.group(2) != block.tag) {
    final rest = tagged.group(3)!.trim();
    lines[0] = rest.isEmpty
        ? '${tagged.group(1)} [${block.tag}]'
        : '${tagged.group(1)} [${block.tag}] $rest';
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
