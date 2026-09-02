// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:typed_data';

/// Injectable host interface: every file-system and git access of the DNA
/// engine goes through this seam, so the engine core stays free of
/// `dart:io`/`Process` and can be compiled to WebAssembly (the JS bridge
/// injects node callbacks instead).
///
/// All paths are posix-separated strings (`/`), absolute or relative to the
/// process working directory — the host implementation maps them to its
/// platform.
abstract class DnaHost {
  /// Whether a file exists at [path].
  bool existsFile(String path);

  /// Whether a directory exists at [path].
  bool existsDir(String path);

  /// [path] with every symlink on it resolved; [path] itself when it
  /// cannot be resolved.
  ///
  /// pnpm installs a package as a symlink into its store, and the
  /// package's own dependencies live in the `node_modules` next to that
  /// store folder — not below the link. Only the resolved path leads to
  /// them, so layer resolution walks from here.
  String realPath(String path) => path;

  /// Reads the file at [path] as bytes.
  Uint8List readBytes(String path);

  /// Reads the file at [path] as UTF-8 text.
  String readString(String path) => utf8.decode(readBytes(path));

  /// Writes [bytes] to [path], creating parent directories.
  void writeBytes(String path, Uint8List bytes);

  /// Writes UTF-8 [content] to [path], creating parent directories.
  void writeString(String path, String content) =>
      writeBytes(path, Uint8List.fromList(utf8.encode(content)));

  /// Deletes the file at [path]; missing files are ignored.
  void deleteFile(String path);

  /// Deletes the directory at [path] recursively; missing dirs are ignored.
  void deleteDir(String path);

  /// Creates the directory at [path] recursively.
  void createDir(String path);

  /// Renames/moves a file or directory from [from] to [to].
  void rename(String from, String to);

  /// Creates a new, empty directory below the system temp folder, its
  /// name starting with [prefix], and returns its absolute posix path.
  /// Used for the backups of locally changed instances — they must not
  /// land in the project (see `instantiateDna`).
  String createTempDir(String prefix);

  /// Lists all files below [dir] recursively as relative posix paths
  /// (files only, no directories, symlinks not followed).
  List<String> listFilesRecursive(String dir);

  /// All paths below [repoRoot] that carry uncommitted work — modified,
  /// staged, deleted or untracked — as posix paths relative to
  /// [repoRoot]. An empty set means everything below [repoRoot] is
  /// committed. Used to protect individual files from being overwritten
  /// (see `instantiateDna`).
  ///
  /// Asynchronous because it starts `git`: under `dart compile wasm` a
  /// process is run through the embedder, which can only answer with a
  /// future.
  Future<Set<String>> uncommittedPaths(String repoRoot);

  /// Commits exactly [paths] (relative to [repoRoot]) with [message],
  /// leaving every other change in the working tree untouched. Throws
  /// when committing is not possible (no repository, no git identity) —
  /// the caller then reports the files for a manual commit instead.
  ///
  /// Asynchronous for the same reason as [uncommittedPaths].
  Future<void> commitPaths(String repoRoot, List<String> paths, String message);
}

// .............................................................................
/// In-memory [DnaHost] for tests and as the reference for callback-based
/// hosts (WASM bridge). Stores files in a flat map keyed by normalized
/// posix path.
class MemoryDnaHost extends DnaHost {
  /// Creates the host, optionally seeded with [files] (path → text), with
  /// [uncommitted] paths (relative to the repo root) and with [links]
  /// (link path → target), which [realPath] follows.
  MemoryDnaHost({
    Map<String, String> files = const {},
    Set<String> uncommitted = const {},
    Map<String, String> links = const {},
  }) : uncommitted = {...uncommitted},
       links = {...links} {
    files.forEach(writeString);
  }

  /// Symlinks: link path → target, followed by [realPath].
  final Map<String, String> links;

  /// The stored files: normalized path → bytes.
  final Map<String, Uint8List> files = {};

  /// What [uncommittedPaths] reports.
  final Set<String> uncommitted;

  /// Commits recorded by [commitPaths], newest last.
  final List<({List<String> paths, String message})> commits = [];

  /// When set, [commitPaths] throws this message — simulates a
  /// repository without git or without a configured identity.
  String? commitError;

  String _norm(String path) {
    final parts = <String>[];
    for (final part in path.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (parts.isNotEmpty) parts.removeLast();
        continue;
      }
      parts.add(part);
    }
    return (path.startsWith('/') ? '/' : '') + parts.join('/');
  }

  @override
  bool existsFile(String path) => files.containsKey(_norm(path));

  @override
  bool existsDir(String path) {
    final prefix = '${_norm(path)}/';
    return files.keys.any((k) => k.startsWith(prefix));
  }

  @override
  String realPath(String path) => links[_norm(path)] ?? super.realPath(path);

  @override
  Uint8List readBytes(String path) {
    final bytes = files[_norm(path)];
    if (bytes == null) {
      throw ArgumentError('MemoryDnaHost: no such file: $path');
    }
    return bytes;
  }

  @override
  void writeBytes(String path, Uint8List bytes) {
    files[_norm(path)] = bytes;
  }

  @override
  void deleteFile(String path) {
    files.remove(_norm(path));
  }

  @override
  void deleteDir(String path) {
    final prefix = '${_norm(path)}/';
    files.removeWhere((k, _) => k.startsWith(prefix));
  }

  @override
  void createDir(String path) {
    // Directories exist implicitly in the flat map.
  }

  @override
  void rename(String from, String to) {
    final fromNorm = _norm(from);
    final toNorm = _norm(to);
    if (files.containsKey(fromNorm)) {
      files[toNorm] = files.remove(fromNorm)!;
      return;
    }
    final prefix = '$fromNorm/';
    final moved = <String, Uint8List>{};
    files.removeWhere((k, v) {
      if (!k.startsWith(prefix)) return false;
      moved['$toNorm/${k.substring(prefix.length)}'] = v;
      return true;
    });
    files.addAll(moved);
  }

  @override
  String createTempDir(String prefix) => '/tmp/$prefix${_tempDirCount++}';

  int _tempDirCount = 0;

  @override
  List<String> listFilesRecursive(String dir) {
    final prefix = '${_norm(dir)}/';
    return files.keys
        .where((k) => k.startsWith(prefix))
        .map((k) => k.substring(prefix.length))
        .toList()
      ..sort();
  }

  @override
  Future<Set<String>> uncommittedPaths(String repoRoot) async => uncommitted;

  @override
  Future<void> commitPaths(
    String repoRoot,
    List<String> paths,
    String message,
  ) async {
    if (commitError != null) throw Exception(commitError);
    commits.add((paths: paths, message: message));
    uncommitted.removeAll(paths);
  }
}
