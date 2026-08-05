// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import 'jsonc.dart';

/// Filename of the variables file inside a layer's `dna/` replica —
/// private per the `_` convention, deep-merged across layers.
const String dnaVarsFilename = '_vars.json';

/// Key pattern for variable names: camelCase without the `dna` prefix.
final RegExp dnaVarKeyRe = RegExp(r'^[a-z][a-zA-Z0-9]*$');

// .............................................................................
/// Parses a `_vars.json` [jsonContent] into raw entries. Values are coerced
/// to strings (numbers, booleans); `null` survives as a deletion marker for
/// [mergeDnaVarEntries]. Invalid keys or nested values are skipped with a
/// warning (prefixed with [sourceLabel]).
({Map<String, Object?> entries, List<String> warnings}) parseDnaVarEntries(
  String jsonContent, {
  required String sourceLabel,
}) {
  final warnings = <String>[];
  final Object? decoded;
  try {
    decoded = parseJsonc(jsonContent, sourceLabel: sourceLabel);
  } on FormatException catch (e) {
    warnings.add(e.message);
    return (entries: <String, Object?>{}, warnings: warnings);
  }
  if (decoded is! Map<String, dynamic>) {
    warnings.add('$sourceLabel: expected a JSON object — ignored.');
    return (entries: <String, Object?>{}, warnings: warnings);
  }
  final validated = validateDnaVarEntries(decoded, sourceLabel: sourceLabel);
  warnings.addAll(validated.warnings);
  return (entries: validated.entries, warnings: warnings);
}

// .............................................................................
/// Validates an already-decoded variables map (see [parseDnaVarEntries]).
({Map<String, Object?> entries, List<String> warnings}) validateDnaVarEntries(
  Map<String, dynamic> decoded, {
  required String sourceLabel,
}) {
  final warnings = <String>[];
  final entries = <String, Object?>{};
  for (final entry in decoded.entries) {
    final key = entry.key;
    if (!dnaVarKeyRe.hasMatch(key)) {
      warnings.add(
        '$sourceLabel: key "$key" is not camelCase without prefix — '
        'skipped.',
      );
      continue;
    }
    if (RegExp('^dna[A-Z]').hasMatch(key)) {
      warnings.add(
        '$sourceLabel: key "$key" starts with "dna" — variables are '
        'defined without the prefix and referenced with it.',
      );
    }
    final value = entry.value;
    if (value == null) {
      entries[key] = null;
    } else if (value is String) {
      entries[key] = value;
    } else if (value is num || value is bool) {
      entries[key] = '$value';
    } else {
      warnings.add(
        '$sourceLabel: value of "$key" must be string, number, bool or '
        'null — skipped.',
      );
    }
  }
  return (entries: entries, warnings: warnings);
}

// .............................................................................
/// Merges [later] over [base]: `null` deletes the key, everything else
/// replaces it.
Map<String, Object?> mergeDnaVarEntries(
  Map<String, Object?> base,
  Map<String, Object?> later,
) {
  final result = Map<String, Object?>.of(base);
  for (final entry in later.entries) {
    if (entry.value == null) {
      result.remove(entry.key);
    } else {
      result[entry.key] = entry.value;
    }
  }
  return result;
}

// .............................................................................
/// The effective variable set used for substitution.
class DnaVars {
  /// Creates the variable set from canonical camelCase [values].
  const DnaVars({this.values = const {}});

  /// Builds the set from merged raw [entries], dropping deletion markers.
  factory DnaVars.fromEntries(Map<String, Object?> entries) => DnaVars(
        values: {
          for (final e in entries.entries)
            if (e.value != null) e.key: e.value! as String,
        },
      );

  /// Canonical camelCase variable names without prefix → values.
  final Map<String, String> values;

  /// JSON-encodable representation (canonical key order as inserted).
  Map<String, dynamic> toJson() => Map<String, dynamic>.of(values);
}

// .............................................................................
/// The five reference forms a variable can be written in.
enum DnaVarForm {
  /// `dnaProjectName` → value in camelCase.
  camel,

  /// `DnaProjectName` → value in PascalCase.
  pascal,

  /// `dna_project_name` → value in snake_case.
  snake,

  /// `DNA_PROJECT_NAME` → value in SCREAMING_SNAKE_CASE.
  screaming,

  /// `dna-project-name` → value in kebab-case.
  kebab,
}

// .............................................................................
/// Replaces all `dna`-prefixed references to [vars] in [content],
/// case-adaptively per reference form. Longer variable names win over
/// shorter ones; unknown references stay literal.
String substituteDnaVars(String content, DnaVars vars) {
  if (vars.values.isEmpty) return content;
  if (!RegExp('dna', caseSensitive: false).hasMatch(content)) return content;

  var result = content;
  final keys = vars.values.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final key in keys) {
    final words = splitIntoWords(key);
    final value = vars.values[key]!;
    for (final form in DnaVarForm.values) {
      final pattern = _referencePattern(words, form);
      final replacement = renderValue(value, form);
      result = result.replaceAll(pattern, replacement);
    }
  }
  return result;
}

// .............................................................................
RegExp _referencePattern(List<String> words, DnaVarForm form) {
  switch (form) {
    case DnaVarForm.camel:
      final ref = 'dna${words.map(_capitalize).join()}';
      return RegExp('(?<![A-Za-z0-9])$ref(?![a-z0-9])');
    case DnaVarForm.pascal:
      final ref = 'Dna${words.map(_capitalize).join()}';
      return RegExp('(?<![A-Za-z0-9])$ref(?![a-z0-9])');
    case DnaVarForm.snake:
      final ref = 'dna_${words.join('_')}';
      return RegExp('(?<![A-Za-z0-9])$ref(?![A-Za-z0-9])');
    case DnaVarForm.screaming:
      final ref = 'DNA_${words.map((w) => w.toUpperCase()).join('_')}';
      return RegExp('(?<![A-Za-z0-9])$ref(?![A-Za-z0-9])');
    case DnaVarForm.kebab:
      final ref = 'dna-${words.join('-')}';
      return RegExp('(?<![A-Za-z0-9])$ref(?![A-Za-z0-9])');
  }
}

// .............................................................................
/// Whether [value] can be re-cased: a single identifier-like token
/// (letters, digits, `_`/`-` separators, starts with a letter, no spaces
/// or newlines). Everything else is inserted verbatim.
bool isCaseConvertible(String value) =>
    RegExp(r'^[A-Za-z][A-Za-z0-9]*([_-][A-Za-z0-9]+)*$').hasMatch(value);

// .............................................................................
/// Renders [value] in the casing of [form]; non-convertible values are
/// returned verbatim.
String renderValue(String value, DnaVarForm form) {
  if (!isCaseConvertible(value)) return value;
  final words = splitIntoWords(value);
  switch (form) {
    case DnaVarForm.camel:
      return words.first + words.skip(1).map(_capitalize).join();
    case DnaVarForm.pascal:
      return words.map(_capitalize).join();
    case DnaVarForm.snake:
      return words.join('_');
    case DnaVarForm.screaming:
      return words.map((w) => w.toUpperCase()).join('_');
    case DnaVarForm.kebab:
      return words.join('-');
  }
}

// .............................................................................
/// Splits an identifier into lowercase words: separators `_`/`-` and
/// camelCase humps both delimit (`ggTemplate_project` → gg, template,
/// project).
List<String> splitIntoWords(String identifier) {
  final words = <String>[];
  for (final part in identifier.split(RegExp('[_-]+'))) {
    if (part.isEmpty) continue;
    final buffer = StringBuffer();
    for (var i = 0; i < part.length; i++) {
      final char = part[i];
      final isUpper = char.toUpperCase() == char && char.toLowerCase() != char;
      if (isUpper && buffer.isNotEmpty) {
        words.add(buffer.toString().toLowerCase());
        buffer.clear();
      }
      buffer.write(char);
    }
    if (buffer.isNotEmpty) words.add(buffer.toString().toLowerCase());
  }
  return words.isEmpty ? [identifier.toLowerCase()] : words;
}

String _capitalize(String word) =>
    word.isEmpty ? word : word[0].toUpperCase() + word.substring(1);

// .............................................................................
/// Git's binary heuristic: a NUL byte within the first 8000 bytes.
bool looksBinary(Uint8List bytes) {
  final end = bytes.length < 8000 ? bytes.length : 8000;
  for (var i = 0; i < end; i++) {
    if (bytes[i] == 0) return true;
  }
  return false;
}
