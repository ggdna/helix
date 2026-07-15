// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:gg_hash/gg_hash.dart';
import 'package:path/path.dart' as p;

/// Filename that holds the sync manifest inside `<target>/dna/`.
const String dnaManifestFilename = '.dna.json';

// .............................................................................
/// Whether the relative posix path [rel] counts as dna content — the root
/// manifest and `.git/` never do, so hashing and copying agree on scope.
bool isDnaContent(String rel) =>
    rel != dnaManifestFilename && rel != '.git' && !rel.startsWith('.git/');

// .............................................................................
/// Stable [fnv1] hash over paths and bytes of all dna content files in
/// [dir] — sorted, EOL-normalized (`\r\n` == `\n`), `null` if [dir] is
/// missing. Only content per [isDnaContent] enters the hash.
String? hashDnaDirectory(Directory dir) {
  if (!dir.existsSync()) return null;
  final base = dir.absolute.path;
  final entries = <(String, File)>[];
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final rel = p.relative(entity.path, from: base).replaceAll('\\', '/');
    if (!isDnaContent(rel)) continue;
    entries.add((rel, entity));
  }
  entries.sort((a, b) => a.$1.compareTo(b.$1));

  final perFile = <int>[];
  for (final (rel, file) in entries) {
    final pathHash = fnv1(utf8.encode(rel));
    final contentHash = fnv1(_normalizeEol(file.readAsBytesSync()));
    perFile.add(pathHash);
    perFile.add(contentHash);
  }
  final folded = fnv1(perFile);
  return toHex64(folded);
}

// .............................................................................
/// Replaces every `\r\n` byte pair with `\n` ([fnv1] hashes [Uint8List]
/// chunked, so both paths must return the same representation).
Uint8List _normalizeEol(Uint8List bytes) {
  if (!bytes.contains(13)) return bytes;
  final result = <int>[];
  for (var i = 0; i < bytes.length; i++) {
    if (bytes[i] == 13 && i + 1 < bytes.length && bytes[i + 1] == 10) {
      continue;
    }
    result.add(bytes[i]);
  }
  return Uint8List.fromList(result);
}

// .............................................................................
/// Formats [value] as unsigned 64-bit hex (`0x` + 16 digits, never signed).
String toHex64(int value) {
  // toRadixString renders high-bit values with a minus sign — format the
  // two 32-bit halves separately instead.
  final hi = (value >> 32) & 0xFFFFFFFF;
  final lo = value & 0xFFFFFFFF;
  return '0x${hi.toRadixString(16).padLeft(8, '0')}'
      '${lo.toRadixString(16).padLeft(8, '0')}';
}
