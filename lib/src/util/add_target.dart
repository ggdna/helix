// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

/// What kind of reference `helix add` was given.
enum AddTargetKind {
  /// A git repository — `https://…`, `git@…`, `ssh://…` or a `.git` path.
  git,

  /// A package name from a registry (npm or pub).
  package,
}

// .............................................................................
/// A parsed `helix add` target: what to install, and under which name the
/// layer appears in `dna/_dna.json`.
class AddTarget {
  /// Creates the target.
  const AddTarget({required this.kind, required this.raw, required this.name});

  /// Parses [raw] — a git URL or a package name.
  factory AddTarget.parse(String raw) {
    final target = raw.trim();
    if (target.isEmpty) {
      throw const FormatException(
        'Nothing to add — pass a git URL or a '
        'package name.',
      );
    }
    if (!_isGitUrl(target)) {
      return AddTarget(kind: AddTargetKind.package, raw: target, name: target);
    }
    return AddTarget(
      kind: AddTargetKind.git,
      raw: target,
      name: _repositoryName(target),
    );
  }

  /// The kind of reference.
  final AddTargetKind kind;

  /// The reference as the user wrote it.
  final String raw;

  /// The package name: what the user typed for a registry package, the
  /// repository name for a git target. DNA repositories are named after
  /// their package, and the name is what the `layers` array holds.
  final String name;

  /// Whether [name] can only be an npm name: a scope or a `-`, neither of
  /// which a pub package name may contain.
  bool get isNodeOnlyName => name.startsWith('@') || name.contains('-');

  /// How npm, pnpm and yarn want this git target spelled: they need a
  /// protocol, so the scp form `git@host:org/repo.git` becomes
  /// `git+ssh://git@host/org/repo.git`.
  String get nodeGitSpec {
    final scp = RegExp(r'^([^@/]+)@([^:/]+):(.+)$').firstMatch(raw);
    if (scp != null && !raw.contains('://')) {
      return 'git+ssh://${scp.group(1)}@${scp.group(2)}/${scp.group(3)}';
    }
    return raw.startsWith('git+') ? raw : 'git+$raw';
  }

  /// The `dart pub add` descriptor of this git target. The space after
  /// `git:` is part of the format pub expects.
  String get pubGitDescriptor => 'dev:$name@{git: $raw}';

  // ...........................................................................
  static bool _isGitUrl(String target) =>
      target.startsWith('https://') ||
      target.startsWith('http://') ||
      target.startsWith('git://') ||
      target.startsWith('git+') ||
      target.startsWith('ssh://') ||
      target.endsWith('.git') ||
      RegExp(r'^[^@/\s]+@[^:/\s]+:').hasMatch(target);

  static String _repositoryName(String url) {
    var path = url;
    final hash = path.indexOf('#');
    if (hash >= 0) path = path.substring(0, hash);
    path = path.replaceAll(r'\', '/');

    // Drop scheme and host — what remains is the repository path, and a
    // url without one has no name to derive.
    final scheme = path.indexOf('://');
    if (scheme >= 0) {
      final afterHost = path.indexOf('/', scheme + 3);
      path = afterHost < 0 ? '' : path.substring(afterHost + 1);
    } else {
      final colon = path.indexOf(':');
      if (colon >= 0) path = path.substring(colon + 1);
    }

    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    var name = path.substring(path.lastIndexOf('/') + 1);
    if (name.endsWith('.git')) {
      name = name.substring(0, name.length - '.git'.length);
    }
    if (name.isEmpty) {
      throw FormatException('No repository name in "$url".');
    }
    return name;
  }
}
