// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:path/path.dart' as p;

import 'dna_fs.dart';

/// The root of the git work tree [dir] lies in — its own folder or the
/// nearest parent holding a `.git`, the way git itself looks for it —
/// or `null` outside any repository. `.git` is a folder in a repository
/// and a file in a worktree or submodule. Symlinks on [dir] are resolved
/// first, so the result is an absolute posix path.
String? findGitRoot(DnaHost host, String dir) {
  var current = host.realPath(dir);
  while (true) {
    if (host.existsDir('$current/.git') || host.existsFile('$current/.git')) {
      return current;
    }
    // The platform context: only it knows `C:/` as a root on Windows.
    final parent = p.dirname(current);
    if (parent == current) return null;
    current = parent;
  }
}

// .............................................................................
/// The folder `build` and `add` work on when `--target` is left at its
/// default: the root of the repository [workingDir] lies in, so running
/// them from `lib/src` treats the whole project. [workingDir] itself when
/// it is the repository root already or lies in no repository at all.
String projectRoot(DnaHost host, String workingDir) {
  final gitRoot = findGitRoot(host, workingDir);
  if (gitRoot == null || gitRoot == host.realPath(workingDir)) {
    return workingDir;
  }
  return gitRoot;
}

// .............................................................................
/// The folder a command works on: [target] as passed with `--target`,
/// posix-separated, or the [projectRoot] of [workingDir] when there is
/// none. [onMoved] receives that root when it is not [workingDir] — the
/// command tells the user where it went.
String resolveTarget(
  DnaHost host,
  String? target,
  String workingDir, {
  void Function(String root)? onMoved,
}) {
  if (target != null) return target.replaceAll(r'\', '/');
  final root = projectRoot(host, workingDir);
  if (root != workingDir) onMoved?.call(root);
  return root;
}
