// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';

/// Sets [values] in the JSONC [text] of a `dna/_vars.json` and returns the
/// new text; a `null` [text] — no file yet — yields a fresh one.
///
/// The edit is textual for the same reason as `addDnaLayer`: the file is
/// hand-authored, and decoding plus re-encoding would drop its comments.
/// A key that is there with the deletion marker `null` gets the value in
/// place; every other key is appended as the last entry. Keys that
/// already carry a value are the caller's to leave out.
String addDnaVars(String? text, Map<String, String> values) {
  if (text == null) {
    final entries = [for (final e in values.entries) _entry(e.key, e.value)];
    return '{\n${entries.join(',\n')}\n}\n';
  }

  var result = text;
  final appended = <String>[];
  for (final e in values.entries) {
    final replaced = _replaceNull(result, e.key, e.value);
    if (replaced == null) {
      appended.add(_entry(e.key, e.value));
    } else {
      result = replaced;
    }
  }
  if (appended.isEmpty) return result;

  final code = _scan(result);
  final open = code.structural.indexWhere((i) => result[i] == '{');
  final close = code.structural.lastIndexWhere((i) => result[i] == '}');
  if (open < 0 || close < 0 || code.structural[close] < code.structural[open]) {
    throw const FormatException(
      'The DNA variables file does not contain a JSON object.',
    );
  }
  final openAt = code.structural[open];
  final closeAt = code.structural[close];

  var body = result.substring(openAt + 1, closeAt).trimRight();
  // The comma goes right behind the last entry — after a trailing
  // `// comment` it would be commented out.
  final last = _scan(body).lastCode;
  if (last >= 0 && body[last] != ',') {
    body = '${body.substring(0, last + 1)},${body.substring(last + 1)}';
  }
  return '${result.substring(0, openAt + 1)}$body\n'
      '${appended.join(',\n')}\n'
      '${result.substring(closeAt)}';
}

// .............................................................................
String _entry(String key, String value) =>
    '  ${jsonEncode(key)}: ${jsonEncode(value)}';

// .............................................................................
/// [text] with `"key": null` set to [value], or `null` when the key is not
/// there with the deletion marker outside a comment.
String? _replaceNull(String text, String key, String value) {
  final pattern = RegExp('${RegExp.escape(jsonEncode(key))}\\s*:\\s*null\\b');
  final code = _scan(text).code;
  for (final match in pattern.allMatches(text)) {
    if (!code[match.start]) continue;
    final nullAt = match.end - 'null'.length;
    return text.replaceRange(nullAt, match.end, jsonEncode(value));
  }
  return null;
}

// .............................................................................
/// Scans [text] once: [code] marks every character outside a `//` or
/// `/* */` comment, [structural] lists those also outside a string, and
/// [lastCode] is the last non-whitespace code character (`-1` for none).
({List<bool> code, List<int> structural, int lastCode}) _scan(String text) {
  final code = List<bool>.filled(text.length, false);
  final structural = <int>[];
  var lastCode = -1;
  var inString = false;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (inString) {
      code[i] = true;
      lastCode = i;
      if (char == r'\' && i + 1 < text.length) {
        code[++i] = true;
        lastCode = i;
      } else if (char == '"') {
        inString = false;
      }
      continue;
    }
    if (text.startsWith('//', i)) {
      final end = text.indexOf('\n', i);
      i = end < 0 ? text.length : end;
      continue;
    }
    if (text.startsWith('/*', i)) {
      final end = text.indexOf('*/', i + 2);
      i = end < 0 ? text.length : end + 1;
      continue;
    }
    code[i] = true;
    if (char.trim().isEmpty) continue;
    lastCode = i;
    if (char == '"') {
      inString = true;
    } else {
      structural.add(i);
    }
  }
  return (code: code, structural: structural, lastCode: lastCode);
}
