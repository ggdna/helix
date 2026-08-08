// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:typed_data';

import 'package:gg_hash/gg_hash.dart';

import 'dna_fs.dart';
import 'dna_layout.dart';

// .............................................................................
/// Whether the relative posix path [rel] counts as dna content — the
/// configuration, the engine's own bookkeeping and `.git/` never do, so
/// hashing and copying agree on scope.
///
/// Excluding both manifests here is what keeps them out of a consumer's
/// `dna/`: a layer ships them, and without the exclusion they would be
/// merged in and then immediately overwritten again, run after run.
bool isDnaContent(String rel) =>
    rel != dnaConfigFilename &&
    rel != dnaGeneratedFilename &&
    rel != '.git' &&
    !rel.startsWith('.git/');

// .............................................................................
/// Stable [fnv1] hash of a single file's [bytes], EOL-normalized so CRLF
/// checkouts don't produce false drift.
String hashFileBytes(Uint8List bytes) => toHex64(fnv1(normalizeEol(bytes)));

// .............................................................................
/// Stable [fnv1] hash over paths and bytes of all dna content files below
/// [dir] (via [host]) — sorted, EOL-normalized, `null` if [dir] is missing.
String? hashTree(DnaHost host, String dir) {
  if (!host.existsDir(dir) && !host.existsFile(dir)) return null;
  final entries = host.listFilesRecursive(dir).where(isDnaContent).toList()
    ..sort();
  final perFile = <int>[];
  for (final rel in entries) {
    perFile.add(fnv1(utf8.encode(rel)));
    perFile.add(fnv1(normalizeEol(host.readBytes('$dir/$rel'))));
  }
  return toHex64(fnv1(perFile));
}

// .............................................................................
/// Replaces every `\r\n` byte pair with `\n`.
Uint8List normalizeEol(Uint8List bytes) {
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
  final hi = (value >> 32) & 0xFFFFFFFF;
  final lo = value & 0xFFFFFFFF;
  return '0x${hi.toRadixString(16).padLeft(8, '0')}'
      '${lo.toRadixString(16).padLeft(8, '0')}';
}
