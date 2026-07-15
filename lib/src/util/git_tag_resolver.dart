// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:pub_semver/pub_semver.dart';

/// Result of resolving a semver constraint against the tags of a git repo.
class ResolvedTag {
  /// Constructor.
  const ResolvedTag({
    required this.version,
    required this.tag,
    required this.sha,
  });

  /// The normalized semver version, e.g. `1.4.0`.
  final Version version;

  /// The original tag name (e.g. `v1.4.0`), used for `git clone --branch`.
  final String tag;

  /// The commit SHA the tag points at (peeled for annotated tags).
  final String sha;
}

/// Picks the highest tag of [tags] (name -> SHA, `v` prefix and plain both
/// accepted, plain wins ties, non-semver ignored) that satisfies
/// [constraint]; `null` when none does.
ResolvedTag? resolveTagForConstraint(
  Map<String, String> tags,
  VersionConstraint constraint,
) {
  ResolvedTag? best;
  for (final entry in tags.entries) {
    final version = _parseTagVersion(entry.key);
    if (version == null || !constraint.allows(version)) continue;
    final candidate = ResolvedTag(
      version: version,
      tag: entry.key,
      sha: entry.value,
    );
    if (best == null ||
        version > best.version ||
        (version == best.version &&
            best.tag.startsWith('v') &&
            !candidate.tag.startsWith('v'))) {
      best = candidate;
    }
  }
  return best;
}

/// Returns the semver versions of [tags], sorted ascending, for messages.
List<Version> semverVersionsOf(Iterable<String> tags) {
  final versions = <Version>[
    for (final tag in tags)
      if (_parseTagVersion(tag) case final Version version) version,
  ]..sort();
  return versions;
}

/// Parses `git ls-remote --tags` output into tag name -> commit SHA, with
/// peeled `^{}` SHAs of annotated tags winning over the tag-object SHA.
Map<String, String> parseLsRemoteTags(String output) {
  final tags = <String, String>{};
  final peeled = <String, String>{};
  for (final line in output.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length < 2) continue;
    final sha = parts[0];
    final ref = parts[1];
    const prefix = 'refs/tags/';
    if (!ref.startsWith(prefix)) continue;
    var name = ref.substring(prefix.length);
    if (name.endsWith('^{}')) {
      name = name.substring(0, name.length - 3);
      peeled[name] = sha;
    } else {
      tags[name] = sha;
    }
  }
  return {
    for (final entry in tags.entries)
      entry.key: peeled[entry.key] ?? entry.value,
  };
}

// ...........................................................................
Version? _parseTagVersion(String tag) {
  final raw = tag.startsWith('v') ? tag.substring(1) : tag;
  try {
    return Version.parse(raw);
  } on FormatException {
    return null;
  }
}
