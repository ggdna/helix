// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';
import 'dart:typed_data';

import 'package:gg_process/gg_process.dart';
import 'package:path/path.dart' as p;

import 'dna_fs.dart';

/// Runs a git command in [workingDirectory] and returns its stdout —
/// injectable for tests.
typedef GitRunner = Future<String> Function(
  String workingDirectory,
  List<String> args,
);

/// [DnaHost] backed by `dart:io` and the local `git` binary. This file is
/// the only place binding the engine to the real platform — the engine
/// core itself must not import `dart:io`.
///
/// The file operations go through `dart:io` directly: they are covered by
/// `IOOverrides`, which a WebAssembly embedder installs. Starting `git` is
/// not, so it goes through `package:gg_process` instead.
class IoDnaHost extends DnaHost {
  /// Creates the host; [git] can be stubbed in tests.
  IoDnaHost({GitRunner? git}) : _git = git ?? _defaultGit;

  final GitRunner _git;

  // coverage:ignore-start
  static Future<String> _defaultGit(
    String workingDirectory,
    List<String> args,
  ) async {
    final result = await ggRunProcess(
      'git',
      args,
      workingDirectory: workingDirectory,
    );
    if (result.exitCode != 0) {
      throw Exception(
        'git ${args.join(' ')} failed in $workingDirectory: '
        '${result.stderr}',
      );
    }
    return result.stdout as String;
  }
  // coverage:ignore-end

  @override
  bool existsFile(String path) => File(path).existsSync();

  @override
  bool existsDir(String path) => Directory(path).existsSync();

  @override
  Uint8List readBytes(String path) => File(path).readAsBytesSync();

  @override
  void writeBytes(String path, Uint8List bytes) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
  }

  @override
  void deleteFile(String path) {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  }

  @override
  void deleteDir(String path) {
    final dir = Directory(path);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  @override
  void createDir(String path) => Directory(path).createSync(recursive: true);

  @override
  void rename(String from, String to) {
    if (Directory(from).existsSync()) {
      Directory(from).renameSync(to);
    } else {
      File(from).renameSync(to);
    }
  }

  @override
  String createTempDir(String prefix) => Directory.systemTemp
      .createTempSync(prefix)
      .absolute
      .path
      .replaceAll(r'\', '/');

  @override
  List<String> listFilesRecursive(String dir) {
    final root = Directory(dir);
    if (!root.existsSync()) return [];
    final base = root.absolute.path;
    final result = <String>[];
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      result.add(
        p.relative(entity.absolute.path, from: base).replaceAll('\\', '/'),
      );
    }
    return result..sort();
  }

  @override
  Future<Set<String>> uncommittedPaths(String repoRoot) async {
    // `git status` prints repo-root-relative paths — strip the prefix of
    // [repoRoot] inside the repository so the result is relative to it.
    final prefix = (await _git(repoRoot, [
      'rev-parse',
      '--show-prefix',
    ])).trim();
    // `-uall` lists untracked files individually (git would otherwise
    // collapse whole untracked folders into one `dir/` entry).
    final status = await _git(repoRoot, [
      '-c',
      'core.quotepath=false',
      'status',
      '--porcelain',
      '-uall',
    ]);
    return parseGitStatusPaths(status, prefix: prefix);
  }

  @override
  Future<void> commitPaths(
    String repoRoot,
    List<String> paths,
    String message,
  ) async {
    if (paths.isEmpty) return;
    // `-A --` stages content, additions and deletions of exactly these
    // paths; the path-limited commit leaves everything else untouched,
    // including whatever else is already staged.
    await _git(repoRoot, ['add', '-A', '--', ...paths]);
    // Restoring a locally changed instance can put back exactly what HEAD
    // has — then there is nothing to commit and `git commit` would exit
    // non-zero. That is a success, not a failure to report.
    final staged = await _git(repoRoot, [
      'diff',
      '--cached',
      '--name-only',
      '--',
      ...paths,
    ]);
    if (staged.trim().isEmpty) return;
    await _git(repoRoot, ['commit', '-m', message, '--', ...paths]);
  }
}

// .............................................................................
/// Parses `git status --porcelain` [output] into paths relative to the
/// folder identified by [prefix] (the repo-root-relative path of that
/// folder, as printed by `git rev-parse --show-prefix`). Rename entries
/// contribute both their old and their new path.
Set<String> parseGitStatusPaths(String output, {String prefix = ''}) {
  final result = <String>{};
  for (final line in output.split('\n')) {
    if (line.length < 4) continue;
    final entry = line.substring(3);
    final paths = entry.contains(' -> ') ? entry.split(' -> ') : [entry];
    for (final raw in paths) {
      var path = raw.trim().replaceAll(r'\', '/');
      if (path.startsWith('"') && path.endsWith('"') && path.length > 1) {
        path = path.substring(1, path.length - 1);
      }
      if (path.isEmpty) continue;
      if (prefix.isEmpty) {
        result.add(path);
      } else if (path.startsWith(prefix)) {
        result.add(path.substring(prefix.length));
      }
    }
  }
  return result;
}
