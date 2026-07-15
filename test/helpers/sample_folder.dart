// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_dna/src/util/copy_directory.dart';
import 'package:path/path.dart' as p;

/// Absolute path to the checked-in `test/sample_folder` fixtures.
///
/// Tests never mutate the fixtures directly — use [copySampleTo] to work on
/// a temp copy (established gg_* convention, see e.g. gg_multi). Relies on
/// `Directory.current` being the repo root: the cwd is process-wide and
/// shared by all parallel suites, so tests must never mutate it — inject a
/// CwdResolver instead.
String sampleRoot() => p.join(Directory.current.path, 'test', 'sample_folder');

/// Copies the sample folder [name] into `<parent>/<name>` and returns the
/// copy. Throws when the sample does not exist.
Directory copySampleTo(String name, Directory parent) {
  final source = Directory(p.join(sampleRoot(), name));
  if (!source.existsSync()) {
    throw ArgumentError('Sample folder not found: ${source.path}');
  }
  final dest = Directory(p.join(parent.path, name));
  copyDirectory(source, dest);
  return dest;
}

/// Initializes a real git repository at [dir] with a single commit containing
/// the current directory content, and creates the annotated [tags] on it.
///
/// Used to exercise the real git code paths (clone, ls-remote) against a
/// local repo without any network access.
Future<void> initGitRepoWithTags(Directory dir, List<String> tags) async {
  await runGit(dir, ['init', '-q']);
  await runGit(dir, ['add', '.']);
  await runGit(dir, ['commit', '-q', '-m', 'init']);
  for (final tag in tags) {
    await runGit(dir, ['tag', '-a', tag, '-m', tag]);
  }
}

/// Runs a git command in [dir] with a fixed test identity. Throws on a
/// non-zero exit code and returns stdout.
Future<String> runGit(Directory dir, List<String> args) async {
  final result = await Process.run(
    'git',
    [
      '-c',
      'user.name=test',
      '-c',
      'user.email=test@example.com',
      ...args,
    ],
    // Explicit working directory: spawning with an inherited cwd is flaky
    // on Windows when the parent process changes or removes its cwd.
    workingDirectory: dir.path,
    runInShell: true,
  );
  if (result.exitCode != 0) {
    throw Exception(
      'git ${args.join(' ')} failed (exit ${result.exitCode}): '
      '${result.stderr}',
    );
  }
  return result.stdout as String;
}
