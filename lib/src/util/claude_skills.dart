// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:path/path.dart' as p;

import 'copy_directory.dart';

/// Destination of installed skills, relative to the target root.
const String claudeSkillsRel = '.claude/skills';

/// Result of [syncClaudeSkills]: what is installed now (goes into the
/// manifest), what was removed, and non-fatal findings.
typedef ClaudeSkillsResult = ({
  List<String> installed,
  List<String> removed,
  List<String> warnings,
});

// .............................................................................
/// Lists all subdirectories of [source] that contain a `SKILL.md` file,
/// sorted alphabetically by name.
List<Directory> discoverSkills(Directory source) {
  final result = <Directory>[];
  for (final entity in source.listSync()) {
    if (entity is Directory &&
        File(p.join(entity.path, 'SKILL.md')).existsSync()) {
      result.add(entity);
    }
  }
  result.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
  return result;
}

// .............................................................................
/// Mirrors the skills of the `skills: include:` folders into
/// `<targetRoot>/.claude/skills` — without prompting:
///
/// * skills gg_dna installed before ([previouslyInstalled], from the
///   manifest) are overwritten or — when no longer configured — removed;
/// * hand-installed skills (present on disk but not in the manifest) are
///   never touched: a name collision yields a warning, not an overwrite;
/// * include folders that do not exist throw — the config points at
///   something the sync did not produce.
///
/// On duplicate skill names across include folders the later folder wins.
ClaudeSkillsResult syncClaudeSkills({
  required String targetRoot,
  required List<String> include,
  required List<String> previouslyInstalled,
}) {
  final warnings = <String>[];

  // Discover the configured skills; later includes win on collisions.
  final sources = <String, Directory>{};
  for (final entry in include) {
    final rel = entry.replaceAll('\\', '/');
    final dir = Directory(p.normalize(p.join(targetRoot, rel)));
    if (!dir.existsSync()) {
      throw Exception(
        'skills include does not exist: "$entry" (resolved to ${dir.path})',
      );
    }
    for (final skill in discoverSkills(dir)) {
      sources[p.basename(skill.path)] = skill;
    }
  }

  final destRoot = Directory(p.join(targetRoot, claudeSkillsRel));
  final installed = <String>[];
  final removed = <String>[];

  for (final name in sources.keys.toList()..sort()) {
    final targetDir = Directory(p.join(destRoot.path, name));
    final ownedByGgDna = previouslyInstalled.contains(name);
    if (targetDir.existsSync() && !ownedByGgDna) {
      warnings.add(
        'skill "$name" already exists in $claudeSkillsRel but was not '
        'installed by gg_dna — left untouched.',
      );
      continue;
    }
    if (targetDir.existsSync()) {
      targetDir.deleteSync(recursive: true);
    }
    copyDirectory(sources[name]!, targetDir);
    installed.add(name);
  }

  // Remove skills gg_dna installed earlier that are no longer configured.
  for (final name in previouslyInstalled) {
    if (sources.containsKey(name)) continue;
    final targetDir = Directory(p.join(destRoot.path, name));
    if (targetDir.existsSync()) {
      targetDir.deleteSync(recursive: true);
    }
    removed.add(name);
  }

  return (installed: installed, removed: removed, warnings: warnings);
}
