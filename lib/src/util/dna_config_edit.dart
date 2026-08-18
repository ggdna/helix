// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

/// Inserts [layer] as the last entry of the `layers` array in the JSONC
/// [text] of a `dna/_dna.json` and returns the new text.
///
/// The edit is textual on purpose: the config is hand-authored, and
/// decoding plus re-encoding would drop its comments. The insertion
/// follows the formatting that is already there — appended inline in a
/// one-line array, on its own line in a multi-line one — and a config
/// without a `layers` array gets one after the opening brace.
///
/// The last layer wins, which is why a new one goes to the end.
String addDnaLayer(String text, String layer) {
  final entry = '"$layer"';
  final array = _layersArray(text);
  if (array == null) return _insertLayersKey(text, entry);

  final inner = text.substring(array.open + 1, array.close);
  final String replacement;
  if (inner.trim().isEmpty) {
    replacement = entry;
  } else if (!inner.contains('\n')) {
    final body = inner.trimRight();
    final separator = body.endsWith(',') ? ' ' : ', ';
    replacement = '$body$separator$entry';
  } else {
    // Keep the indentation of the last entry, and its trailing whitespace
    // — that is what carries the closing bracket's own line.
    final body = inner.trimRight();
    final trailing = inner.substring(body.length);
    final lastLine = body.substring(body.lastIndexOf('\n') + 1);
    final indent = RegExp(r'^\s*').firstMatch(lastLine)!.group(0)!;
    final separator = body.endsWith(',') ? '' : ',';
    replacement = '$body$separator\n$indent$entry$trailing';
  }

  return text.replaceRange(array.open + 1, array.close, replacement);
}

// .............................................................................
/// Position of the `layers` array in [text], or `null` when there is none.
({int open, int close})? _layersArray(String text) {
  final key = RegExp(r'"layers"\s*:\s*\[').firstMatch(text);
  if (key == null) return null;
  final open = key.end - 1;
  var depth = 0;
  var inString = false;
  for (var i = open; i < text.length; i++) {
    final char = text[i];
    if (inString) {
      if (char == r'\') {
        i++;
      } else if (char == '"') {
        inString = false;
      }
      continue;
    }
    switch (char) {
      case '"':
        inString = true;
      case '[':
        depth++;
      case ']':
        depth--;
        if (depth == 0) return (open: open, close: i);
    }
  }
  throw const FormatException(
    'The "layers" array of the DNA config is not closed.',
  );
}

// .............................................................................
/// Adds a whole `layers` key to a config that has none, right after the
/// opening brace of the root object.
String _insertLayersKey(String text, String entry) {
  final brace = text.indexOf('{');
  if (brace < 0) {
    throw const FormatException(
      'The DNA config does not contain a JSON object.',
    );
  }
  final rest = text.substring(brace + 1);
  // An empty object needs no comma, anything else does.
  final needsComma =
      rest.trimLeft().isNotEmpty && !rest.trimLeft().startsWith('}');
  return '${text.substring(0, brace + 1)}\n'
      '  "layers": [$entry]${needsComma ? ',' : ''}'
      '$rest';
}
