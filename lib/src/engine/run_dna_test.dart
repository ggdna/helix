// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';
import 'dart:isolate';

import 'package:gg_console_colors/gg_console_colors.dart';

import '../helix_version.dart';
import '../util/dna_fs.dart';
import '../util/dna_fs_io.dart';
import '../util/dna_layout.dart';
import 'instantiate.dart';

/// Entry point for the placed DNA test (`test/dna/dna_test.dart` imports
/// helix as dev-dependency and calls this). Runs one instantiation over
/// the current project and throws when the project is not in a clean,
/// up-to-date DNA state:
///
/// - a `dot_`-escaped path in `dna/` → fails before instantiating, naming
///   the `dot-` rename
/// - hand-modified instances → fails, files stay untouched
/// - DNA updates → writes them and fails once ("review & commit")
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
  final base = baseDnaRoot ?? await helixPackageRoot();
  final emit = log ?? print; // coverage:ignore-line

  final invalidEscapes = invalidDotEscapes(effectiveHost, root);
  if (invalidEscapes.isNotEmpty) {
    throw Exception(
      '\n${cError(invalidDotEscapesMessage)}\n'
      '${describeInvalidDotEscapes(invalidEscapes)}',
    );
  }

  final result = instantiateDna(
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

  if (result.modifiedInstances.isNotEmpty) {
    throw Exception(
      '\n${cError(modifiedInstancesMessage)}\n'
      '${describeDnaSources(result.modifiedInstances, result.sources)}',
    );
  }
  if (result.blocked) {
    throw Exception(
      '\n${cError(uncommittedTargetsMessage)}\n'
      '${describeDnaSources(result.uncommittedTargets, result.sources)}',
    );
  }
  if (result.updated.isNotEmpty && !result.committed) {
    final lines = result.updated
        .map((path) => '${cAction('Commit')} ${cCmd(path)}.')
        .join('\n');
    throw Exception('\n${cError(needsCommitMessage)}\n$lines');
  }
  if (!effectiveHost.existsFile('$root/LICENSE')) {
    throw Exception(
      'LICENSE is missing — ship it via a DNA layer or add it manually.',
    );
  }
}

// .............................................................................
/// Colors of the DNA report — the problem in [cError], files in [cCmd],
/// what to do in [cAction].
String cError(Object message) => red(message);

/// Color of a file path or command in the DNA report.
String cCmd(Object message) => blue(message);

/// Color of an instruction in the DNA report.
String cAction(Object message) => yellow(message);

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
String describeInvalidDotEscapes(List<String> segments) =>
    segments.map((segment) {
      final fixed = '$dotPrefix${segment.substring(invalidDotPrefix.length)}';
      return '${cAction('Rename')} ${cCmd('$dnaDirname/$segment')} '
          '${cAction('to')} ${cCmd('$dnaDirname/$fixed')}.';
    }).join('\n');

// .............................................................................
/// Renders one instruction per reported path: move the edits from the
/// generated file to the DNA file it is produced from.
String describeDnaSources(
  List<String> paths,
  Map<String, String> sources,
) =>
    paths.map((path) {
      final source = sources[path];
      return source == null
          ? '${cAction('Commit or stash')} ${cCmd(path)}.'
          : '${cAction('Move edits from')} ${cCmd(path)} '
              '${cAction('to')} ${cCmd(source)}.';
    }).join('\n');

// .............................................................................
/// Resolves the root folder of the installed helix package (its own
/// `dna/` folder is the implicit base layer).
Future<String> helixPackageRoot() async {
  final uri = await Isolate.resolvePackageUri(
    Uri.parse('package:helix/helix.dart'),
  );
  if (uri == null) {
    // coverage:ignore-start
    throw Exception(
      'Cannot resolve the helix package root — pass baseDnaRoot '
      'explicitly.',
    );
    // coverage:ignore-end
  }
  return File(uri.toFilePath()).parent.parent.path.replaceAll(r'\', '/');
}
