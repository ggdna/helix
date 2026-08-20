// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_console_colors/gg_console_colors.dart';

import '../helix_version.dart';
import '../util/dna_fs.dart';
import '../util/dna_fs_io.dart';
import '../util/dna_layout.dart';
import 'base_dna.dart';
import 'instantiate.dart';

/// Entry point for the placed DNA test (`test/dna/dna_test.dart` imports
/// helix as dev-dependency and calls this). Runs one instantiation over
/// the current project and throws when the project is not in a clean,
/// up-to-date DNA state:
///
/// - a `dot_`-escaped path in `dna/` → fails before instantiating, naming
///   the `dot-` rename
/// - locally changed instances → the local content is copied to a
///   system-temp folder and the DNA content is written
/// - DNA updates → writes them and commits them; without a repository or
///   a git identity they stay for a manual commit (a warning, not a
///   failure)
/// - a file to be overwritten carries uncommitted work → fails without
///   writing (unrelated dirty files do not block)
/// - missing LICENSE → fails
Future<void> runDnaTest({
  String? targetRoot,
  DnaHost? host,
  String? baseDnaRoot,
  void Function(String message)? log,
}) async {
  final effectiveHost = host ?? IoDnaHost();
  final root = (targetRoot ?? Directory.current.path).replaceAll(r'\', '/');
  // A caller-supplied base wins; otherwise the engine writes the base DNA
  // it carries and cleans it up again below.
  final base = baseDnaRoot ?? materializeBaseDna(effectiveHost);
  final emit = log ?? print; // coverage:ignore-line

  try {
    await _runDnaTest(host: effectiveHost, root: root, base: base, emit: emit);
  } finally {
    if (baseDnaRoot == null) effectiveHost.deleteDir(base);
  }
}

// .............................................................................
/// The body of [runDnaTest], with the base DNA already in place.
Future<void> _runDnaTest({
  required DnaHost host,
  required String root,
  required String base,
  required void Function(String message) emit,
}) async {
  final effectiveHost = host;

  final invalidEscapes = invalidDotEscapes(effectiveHost, root);
  if (invalidEscapes.isNotEmpty) {
    throw Exception(
      '\n${cError(invalidDotEscapesMessage)}\n'
      '${describeInvalidDotEscapes(invalidEscapes)}',
    );
  }

  final result = await instantiateDna(
    host: effectiveHost,
    targetRoot: root,
    baseDnaRoot: base,
    baseVersion: helixVersion,
  );

  for (final warning in result.warnings) {
    emit('warning: $warning');
  }
  for (final message in result.messages) {
    emit(message);
  }

  for (final path in result.backedUp) {
    emit(
      '${cAction('Local changes of')} ${cCmd(path)} '
      '${cAction('were backed up to')} '
      '${cCmd('${result.backupDir}/$path')}',
    );
  }
  if (result.blocked) {
    throw Exception(
      '\n${cError(uncommittedTargetsMessage)}\n'
      '${describeDnaSources(result.uncommittedTargets, result.sources)}',
    );
  }
  if (!effectiveHost.existsFile('$root/LICENSE')) {
    throw Exception(
      'LICENSE is missing — ship it via a DNA layer or add it manually.',
    );
  }
}

// .............................................................................
/// Signature of [runDnaTest] — the seam that lets the commands calling it
/// be tested without a project on disk.
typedef DnaTestRunner = Future<void> Function({
  String? targetRoot,
  DnaHost? host,
  String? baseDnaRoot,
  void Function(String message)? log,
});

// .............................................................................
/// Colors of the DNA report — the problem in [cError], files in [cCmd],
/// what to do in [cAction], what happened in [cDetail].
String cError(Object message) => red(message);

/// Color of a file path or command in the DNA report.
String cCmd(Object message) => blue(message);

/// Color of an instruction in the DNA report.
String cAction(Object message) => yellow(message);

/// Color of a step that was carried out — the details a reader skims past
/// on the way to the instruction.
String cDetail(Object message) => darkGray(message);

// .............................................................................
/// The paths below `<root>/dna/` that escape a leading dot with `dot_`
/// instead of `dot-`, project-relative. Only `dot-` is decoded, so these
/// would instantiate as literal `dot_…` folders.
List<String> invalidDotEscapes(DnaHost host, String root) {
  final dnaRoot = '$root/$dnaDirname';
  if (!host.existsDir(dnaRoot)) return const [];
  final hits = <String>{};
  // Paths come back relative to `dnaRoot` from both hosts.
  for (final rel in host.listFilesRecursive(dnaRoot)) {
    final segment = invalidDotSegment(rel.replaceAll(r'\', '/'));
    if (segment != null) hits.add(segment);
  }
  return hits.toList()..sort();
}

// .............................................................................
/// Renders one instruction per invalid dot escape: rename it to `dot-`.
String describeInvalidDotEscapes(List<String> segments) => segments
    .map((segment) {
      final fixed = '$dotPrefix${segment.substring(invalidDotPrefix.length)}';
      return '${cAction('Rename')} ${cCmd('$dnaDirname/$segment')} '
          '${cAction('to')} ${cCmd('$dnaDirname/$fixed')}.';
    })
    .join('\n');

// .............................................................................
/// Renders one instruction per reported path: move the edits from the
/// generated file to the DNA file it is produced from.
String describeDnaSources(List<String> paths, Map<String, String> sources) =>
    paths
        .map((path) {
          final source = sources[path];
          return source == null
              ? '${cAction('Commit or stash')} ${cCmd(path)}.'
              : '${cAction('Move edits from')} ${cCmd(path)} '
                    '${cAction('to')} ${cCmd(source)}.';
        })
        .join('\n');
