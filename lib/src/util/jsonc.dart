// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';

/// Parses [source] as JSON with VS-Code-style extras: `//` line comments,
/// `/* */` block comments and trailing commas. Comments and trailing commas
/// are blanked out (offsets preserved), then the result is decoded with
/// [jsonDecode]. Throws a [FormatException] prefixed with [sourceLabel] on
/// invalid input.
Object? parseJsonc(String source, {String? sourceLabel}) {
  final cleaned = stripJsonComments(source);
  try {
    return jsonDecode(cleaned);
  } on FormatException catch (e) {
    final label = sourceLabel == null ? '' : '$sourceLabel: ';
    throw FormatException('${label}invalid JSON: ${e.message}', e.source);
  }
}

// .............................................................................
/// Replaces `//` and `/* */` comments outside strings with spaces and removes
/// trailing commas before `}` or `]` — character offsets stay stable so error
/// positions from [jsonDecode] still point at the original [source].
String stripJsonComments(String source) {
  final chars = source.codeUnits.toList();
  const space = 0x20;
  const quote = 0x22;
  const backslash = 0x5C;
  const slash = 0x2F;
  const star = 0x2A;
  const comma = 0x2C;
  const closeBrace = 0x7D;
  const closeBracket = 0x5D;
  const newline = 0x0A;
  const carriageReturn = 0x0D;

  var inString = false;
  var inLineComment = false;
  var inBlockComment = false;

  for (var i = 0; i < chars.length; i++) {
    final c = chars[i];
    if (inString) {
      if (c == backslash) {
        i++;
      } else if (c == quote) {
        inString = false;
      }
      continue;
    }
    if (inLineComment) {
      if (c == newline || c == carriageReturn) {
        inLineComment = false;
      } else {
        chars[i] = space;
      }
      continue;
    }
    if (inBlockComment) {
      if (c == star && i + 1 < chars.length && chars[i + 1] == slash) {
        chars[i] = space;
        chars[i + 1] = space;
        i++;
        inBlockComment = false;
      } else if (c != newline && c != carriageReturn) {
        chars[i] = space;
      }
      continue;
    }
    if (c == quote) {
      inString = true;
      continue;
    }
    if (c == slash && i + 1 < chars.length) {
      final next = chars[i + 1];
      if (next == slash) {
        chars[i] = space;
        chars[i + 1] = space;
        i++;
        inLineComment = true;
        continue;
      }
      if (next == star) {
        chars[i] = space;
        chars[i + 1] = space;
        i++;
        inBlockComment = true;
        continue;
      }
    }
    if (c == comma) {
      // Blank the comma when the next relevant character closes a
      // collection — that is a trailing comma jsonDecode rejects.
      var j = i + 1;
      var isTrailing = false;
      var scanLine = false;
      var scanBlock = false;
      while (j < chars.length) {
        final n = chars[j];
        if (scanLine) {
          if (n == newline || n == carriageReturn) scanLine = false;
          j++;
          continue;
        }
        if (scanBlock) {
          if (n == star && j + 1 < chars.length && chars[j + 1] == slash) {
            scanBlock = false;
            j++;
          }
          j++;
          continue;
        }
        if (n == space || n == 0x09 || n == newline || n == carriageReturn) {
          j++;
          continue;
        }
        if (n == slash && j + 1 < chars.length) {
          if (chars[j + 1] == slash) {
            scanLine = true;
            j += 2;
            continue;
          }
          if (chars[j + 1] == star) {
            scanBlock = true;
            j += 2;
            continue;
          }
        }
        isTrailing = n == closeBrace || n == closeBracket;
        break;
      }
      if (isTrailing) chars[i] = space;
    }
  }
  return String.fromCharCodes(chars);
}
