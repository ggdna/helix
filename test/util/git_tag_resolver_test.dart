// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_dna/src/util/git_tag_resolver.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

import '../helpers/sample_folder.dart';

void main() {
  group('resolveTagForConstraint', () {
    test('picks the highest satisfying tag', () {
      final resolved = resolveTagForConstraint(
        {'1.4.0': 'a', '1.5.2': 'b', '2.0.0': 'c'},
        VersionConstraint.parse('^1.4.0'),
      );
      expect(resolved!.tag, '1.5.2');
      expect(resolved.version, Version.parse('1.5.2'));
      expect(resolved.sha, 'b');
    });

    test('accepts v-prefixed tags and keeps the original tag name', () {
      final resolved = resolveTagForConstraint(
        {'v1.4.0': 'a', 'v1.5.0': 'b'},
        VersionConstraint.parse('^1.4.0'),
      );
      expect(resolved!.tag, 'v1.5.0');
      expect(resolved.version, Version.parse('1.5.0'));
    });

    test('resolves exact constraints', () {
      final resolved = resolveTagForConstraint(
        {'1.4.0': 'a', '1.5.0': 'b'},
        VersionConstraint.parse('1.4.0'),
      );
      expect(resolved!.tag, '1.4.0');
    });

    test('ignores non-semver tags', () {
      final resolved = resolveTagForConstraint(
        {'latest': 'a', 'release-candidate': 'b', '1.4.0': 'c'},
        VersionConstraint.parse('any'),
      );
      expect(resolved!.tag, '1.4.0');
    });

    test('returns null when nothing satisfies or the map is empty', () {
      expect(
        resolveTagForConstraint(
          {'1.0.0': 'a'},
          VersionConstraint.parse('^2.0.0'),
        ),
        isNull,
      );
      expect(
        resolveTagForConstraint({}, VersionConstraint.parse('any')),
        isNull,
      );
    });

    test('prefers stable versions over higher prereleases (pub semantics)', () {
      final resolved = resolveTagForConstraint(
        {'1.4.0': 'a', '1.5.0-beta.1': 'b'},
        VersionConstraint.parse('^1.4.0'),
      );
      expect(resolved!.tag, '1.4.0');

      // A prerelease is used when nothing stable satisfies.
      final onlyPre = resolveTagForConstraint(
        {'1.5.0-beta.1': 'b', '1.5.0-beta.2': 'c'},
        VersionConstraint.parse('^1.4.0'),
      );
      expect(onlyPre!.tag, '1.5.0-beta.2');

      // Constraints targeting a prerelease resolve to it.
      final targeted = resolveTagForConstraint(
        {'1.4.0': 'a', '2.0.0-beta.1': 'b'},
        VersionConstraint.parse('^2.0.0-beta'),
      );
      expect(targeted!.tag, '2.0.0-beta.1');
    });

    test('supports range constraints', () {
      final resolved = resolveTagForConstraint(
        {'1.4.0': 'a', '1.5.0': 'b', '2.0.0': 'c'},
        VersionConstraint.parse('>=1.0.0 <1.5.0'),
      );
      expect(resolved!.tag, '1.4.0');
    });

    test('prefers the plain name when v-prefixed duplicate exists', () {
      for (final tags in [
        {'v1.4.0': 'a', '1.4.0': 'b'},
        {'1.4.0': 'b', 'v1.4.0': 'a'},
      ]) {
        final resolved = resolveTagForConstraint(
          tags,
          VersionConstraint.parse('1.4.0'),
        );
        expect(resolved!.tag, '1.4.0');
      }
    });
  });

  group('semverVersionsOf', () {
    test('returns sorted semver versions, skipping non-semver tags', () {
      final versions = semverVersionsOf(['v2.0.0', 'latest', '1.4.0']);
      expect(versions, [Version.parse('1.4.0'), Version.parse('2.0.0')]);
    });
  });

  group('parseLsRemoteTags', () {
    test('prefers peeled SHAs for annotated tags', () {
      final tags = parseLsRemoteTags(
        'aaa\trefs/tags/1.4.0\n'
        'bbb\trefs/tags/1.4.0^{}\n'
        'ccc\trefs/tags/1.5.0\n',
      );
      expect(tags, {'1.4.0': 'bbb', '1.5.0': 'ccc'});
    });

    test('ignores non-tag refs and blank lines', () {
      final tags = parseLsRemoteTags(
        'aaa\tHEAD\n'
        '\n'
        'bbb\trefs/heads/main\n'
        'ccc\trefs/tags/v1.0.0\n',
      );
      expect(tags, {'v1.0.0': 'ccc'});
    });

    test('parses the output of a real local git repository', () async {
      final tmp = Directory.systemTemp.createTempSync('git_tag_resolver_');
      try {
        final repo = copySampleTo('dna_company', tmp);
        await initGitRepoWithTags(repo, ['1.4.0', 'v1.5.0', 'latest']);

        final output = await runGit(repo, ['ls-remote', '--tags', repo.path]);
        final tags = parseLsRemoteTags(output);

        // Annotated tags: peeled entries must collapse into one SHA per tag.
        expect(tags.keys.toSet(), {'1.4.0', 'v1.5.0', 'latest'});
        final headSha = (await runGit(repo, ['rev-parse', 'HEAD'])).trim();
        expect(tags['1.4.0'], headSha);
        expect(tags['v1.5.0'], headSha);

        final resolved = resolveTagForConstraint(
          tags,
          VersionConstraint.parse('^1.4.0'),
        );
        expect(resolved!.tag, 'v1.5.0');
        expect(resolved.sha, headSha);
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });
  });
}
