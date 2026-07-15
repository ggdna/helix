// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_dna/src/commands/apply_conventions.dart';
import 'package:gg_dna/src/commands/sync.dart';
import 'package:gg_dna/src/util/copy_directory.dart';
import 'package:gg_dna/src/util/dna_manifest.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/sample_folder.dart';

void main() {
  late Directory tmp;
  late Directory pkgRoot;
  late Directory pkgDna;
  late Directory target;
  late List<String> messages;
  late List<String> selectorPrompts;
  late Map<String, bool> selectorAnswers;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sync_test_');
    pkgRoot = Directory(p.join(tmp.path, 'pkg'))..createSync();
    pkgDna = Directory(p.join(pkgRoot.path, 'dna'))..createSync();
    target = Directory(p.join(tmp.path, 'target'))..createSync();
    messages = <String>[];
    selectorPrompts = <String>[];
    selectorAnswers = <String, bool>{};
  });

  tearDown(() {
    if (tmp.existsSync()) {
      tmp.deleteSync(recursive: true);
    }
  });

  // ---------------------------------------------------------------------------
  void writeFile(String path, String content) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  void writePubspec(String dnaBlock) {
    writeFile(
      p.join(target.path, 'pubspec.yaml'),
      'name: target_repo\nversion: 0.1.0\n$dnaBlock',
    );
  }

  bool selector(String prompt) {
    selectorPrompts.add(prompt);
    for (final entry in selectorAnswers.entries) {
      if (prompt.contains(entry.key)) return entry.value;
    }
    return false;
  }

  Sync makeCmd({
    GitCloner? gitCloner,
    GitRevParse? gitRevParse,
    GitLsRemote? gitLsRemote,
    GitLsRemoteTags? gitLsRemoteTags,
  }) =>
      Sync(
        ggLog: messages.add,
        packageRootResolver: () async => pkgRoot.path,
        selector: selector,
        gitCloner: gitCloner,
        gitRevParse: gitRevParse,
        gitLsRemote: gitLsRemote,
        gitLsRemoteTags: gitLsRemoteTags,
      );

  CommandRunner<dynamic> makeRunner(Sync cmd) =>
      CommandRunner<dynamic>('test', 'test')..addCommand(cmd);

  Future<void> runSync(
    Sync cmd, {
    List<String> extra = const ['--no-install'],
  }) =>
      makeRunner(cmd).run(['sync', '--target', target.path, ...extra]);

  void writeSkillIn(Directory parent, String name) {
    final dir = Directory(p.join(parent.path, name))..createSync();
    File(p.join(dir.path, 'SKILL.md')).writeAsStringSync('# $name');
  }

  /// A stub cloner that writes [files] (relative paths with `/`) into the
  /// clone destination and records the received urls and refs.
  GitCloner clonerWriting(
    Map<String, String> files, {
    List<String>? urls,
    List<String?>? refs,
    List<Directory>? dests,
  }) =>
      (String url, Directory dest, {String? ref}) async {
        urls?.add(url);
        refs?.add(ref);
        dests?.add(dest);
        for (final entry in files.entries) {
          writeFile(p.join(dest.path, entry.key), entry.value);
        }
      };

  // ===========================================================================
  group('Sync', () {
    test('throws when source dna folder does not exist', () async {
      final cmd = makeCmd();
      await expectLater(
        makeRunner(cmd).run([
          'sync',
          '--source',
          p.join(tmp.path, 'missing'),
          '--target',
          target.path,
          '--no-install',
        ]),
        throwsA(isA<UsageException>()),
      );
    });

    test('rejects positional overlay arguments with a migration hint',
        () async {
      final cmd = makeCmd();
      await expectLater(
        makeRunner(cmd).run([
          'sync',
          '--target',
          target.path,
          '--no-install',
          'gg_some_overlay',
        ]),
        throwsA(
          isA<UsageException>().having(
            (e) => e.message,
            'message',
            contains('removed in gg_dna 2.0'),
          ),
        ),
      );
    });

    test('mirrors source dna/ into <target>/dna and skips install', () async {
      writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'A');
      writeFile(p.join(pkgDna.path, 'scripts', 'run.sh'), 'echo hi');
      writeFile(p.join(pkgDna.path, 'agents', 'sub', 'b.md'), 'B');

      await runSync(makeCmd());

      expect(
        File(p.join(target.path, 'dna', 'guides', 'a.md')).readAsStringSync(),
        'A',
      );
      expect(
        File(p.join(target.path, 'dna', 'scripts', 'run.sh'))
            .readAsStringSync(),
        'echo hi',
      );
      expect(
        File(p.join(target.path, 'dna', 'agents', 'sub', 'b.md'))
            .readAsStringSync(),
        'B',
      );
      expect(messages.any((m) => m.contains('Synced')), isTrue);
      expect(
        messages.any((m) => m.contains('No dna: config')),
        isTrue,
      );
      expect(selectorPrompts, isEmpty);
    });

    test('a pubspec without dna key results in a base-only sync', () async {
      writePubspec('');
      writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'A');

      await runSync(makeCmd());

      expect(messages.any((m) => m.contains('No dna: config')), isTrue);
      expect(
        File(p.join(target.path, 'dna', 'guides', 'a.md')).existsSync(),
        isTrue,
      );
    });

    test('replaces stale files in an existing target dna/', () async {
      writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'A-new');
      writeFile(p.join(target.path, 'dna', 'guides', 'a.md'), 'A-old');
      writeFile(p.join(target.path, 'dna', 'guides', 'gone.md'), 'gone');

      await runSync(makeCmd());

      expect(
        File(p.join(target.path, 'dna', 'guides', 'a.md')).readAsStringSync(),
        'A-new',
      );
      expect(
        File(p.join(target.path, 'dna', 'guides', 'gone.md')).existsSync(),
        isFalse,
      );
    });

    test('renders markers of the base dna and applies base tag files',
        () async {
      writeFile(
        p.join(pkgDna.path, 'guides', 'a.md'),
        '## [s] Alt\n\nWert: {{v|standard}}\n',
      );
      writeFile(
        p.join(pkgDna.path, 'guides', 'a.tag.md'),
        '## [s] Neu\n\nInhalt.\n',
      );

      await runSync(makeCmd());

      expect(
        File(p.join(target.path, 'dna', 'guides', 'a.md')).readAsStringSync(),
        '## Neu\n\nInhalt.\n',
      );
      // Tag files are consumed, never copied.
      expect(
        File(p.join(target.path, 'dna', 'guides', 'a.tag.md')).existsSync(),
        isFalse,
      );
    });

    test('throws a UsageException on an invalid dna config', () async {
      writePubspec('dna: 42\n');
      writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'A');

      await expectLater(
        runSync(makeCmd()),
        throwsA(
          isA<UsageException>().having(
            (e) => e.message,
            'message',
            contains('must be a map'),
          ),
        ),
      );
    });

    test('logs config warnings about orphaned layer configs', () async {
      writePubspec(
        'dna:\n'
        '  orphan:\n'
        '    path: ../nowhere\n',
      );
      writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'A');

      await runSync(makeCmd());

      expect(messages.any((m) => m.contains('ignored')), isTrue);
    });

    // =========================================================================
    group('path layers', () {
      test('merges layers in order — later layers win', () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'BASE');
        writeFile(p.join(tmp.path, 'layer1', 'dna', 'guides', 'a.md'), 'ONE');
        writeFile(p.join(tmp.path, 'layer1', 'dna', 'guides', 'one.md'), '1');
        writeFile(p.join(tmp.path, 'layer2', 'dna', 'guides', 'a.md'), 'TWO');
        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - one\n'
          '    - two\n'
          '  one:\n'
          '    path: ../layer1\n'
          '  two:\n'
          '    path: ../layer2\n',
        );

        await runSync(makeCmd());

        expect(
          File(p.join(target.path, 'dna', 'guides', 'a.md')).readAsStringSync(),
          'TWO',
        );
        expect(
          File(p.join(target.path, 'dna', 'guides', 'one.md'))
              .readAsStringSync(),
          '1',
        );
        expect(
          messages.any((m) => m.contains('Applied layer "one"')),
          isTrue,
        );
        expect(
          messages.any((m) => m.contains('Applied layer "two"')),
          isTrue,
        );
      });

      test('supports direct-content layers without a dna/ subfolder', () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'BASE');
        writeFile(p.join(tmp.path, 'direct', 'guides', 'a.md'), 'DIRECT');
        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - direct\n'
          '  direct:\n'
          '    path: ../direct\n',
        );

        await runSync(makeCmd());

        expect(
          File(p.join(target.path, 'dna', 'guides', 'a.md')).readAsStringSync(),
          'DIRECT',
        );
      });

      test(
          'throws when a layer path does not exist and leaves the target '
          'untouched', () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'A');
        await runSync(makeCmd());

        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - missing\n'
          '  missing:\n'
          '    path: ../missing\n',
        );
        await expectLater(
          runSync(makeCmd()),
          throwsA(
            isA<Exception>().having(
              (e) => '$e',
              'message',
              contains('does not exist'),
            ),
          ),
        );
        // Atomicity: the previously synced content is still there.
        expect(
          File(p.join(target.path, 'dna', 'guides', 'a.md')).existsSync(),
          isTrue,
        );
      });

      test('throws a clear error when a layer path is a file', () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'A');
        writeFile(p.join(tmp.path, 'afile.txt'), 'ich bin eine datei');
        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - f\n'
          '  f:\n'
          '    path: ../afile.txt\n',
        );

        await expectLater(
          runSync(makeCmd()),
          throwsA(
            isA<Exception>().having(
              (e) => '$e',
              'message',
              contains('is a file, not a folder'),
            ),
          ),
        );
      });

      test('throws when a layer points at <target>/dna itself', () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'A');
        writeFile(p.join(target.path, 'dna', 'guides', 'a.md'), 'A');
        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - self\n'
          '  self:\n'
          '    path: dna\n',
        );

        await expectLater(
          runSync(makeCmd()),
          throwsA(
            isA<Exception>().having(
              (e) => '$e',
              'message',
              contains('must not point at'),
            ),
          ),
        );
      });

      test('skips .git folders and layer manifests when copying', () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'BASE');
        final layer = Directory(p.join(tmp.path, 'layer'));
        writeFile(p.join(layer.path, 'guides', 'a.md'), 'LAYER');
        writeFile(p.join(layer.path, '.git', 'config'), 'git stuff');
        writeFile(p.join(layer.path, '.dna.json'), '{"version": 2}');
        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - layer\n'
          '  layer:\n'
          '    path: ../layer\n',
        );

        await runSync(makeCmd());

        expect(
          Directory(p.join(target.path, 'dna', '.git')).existsSync(),
          isFalse,
        );
        // The layer's own manifest is not copied; the sync writes a fresh
        // one after the merge.
        final manifest = DnaManifest.read(
          Directory(p.join(target.path, 'dna')),
        );
        expect(manifest!.layers.single.name, 'layer');
      });

      test(
          'a configured but missing in-dna layer is skipped as empty '
          '(fresh clones: git does not track empty folders)', () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'A');
        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - repo\n'
          '  repo:\n'
          '    path: dna/_override\n',
        );

        await runSync(makeCmd());

        expect(
          messages.any((m) => m.contains('does not exist yet')),
          isTrue,
        );
        expect(
          File(p.join(target.path, 'dna', 'guides', 'a.md')).existsSync(),
          isTrue,
        );

        // The immediate check agrees with the sync.
        messages.clear();
        await runSync(makeCmd(), extra: ['--check']);
        expect(messages.last, contains('up to date'));

        // Creating the override later is reported as layer change …
        writeFile(
          p.join(target.path, 'dna', '_override', 'guides', 'a.tag.md'),
          '<!-- s --> x <!-- s -->\n',
        );
        messages.clear();
        await expectLater(
          runSync(makeCmd(), extra: ['--check']),
          throwsA(isA<Exception>()),
        );
        expect(
          messages.any((m) => m.contains('layer "repo" has changed')),
          isTrue,
        );

        // … and the next sync picks it up.
        await runSync(makeCmd());
        messages.clear();
        await runSync(makeCmd(), extra: ['--check']);
        expect(messages.last, contains('up to date'));
      });

      test('a later full-file override resets earlier tag patches', () async {
        writeFile(
          p.join(pkgDna.path, 'guides', 'a.md'),
          '## [s] Basis\n\nx\n',
        );
        writeFile(
          p.join(tmp.path, 'layer1', 'dna', 'guides', 'a.tag.md'),
          '## [s] Gepatcht\n\ny\n',
        );
        writeFile(
          p.join(tmp.path, 'layer2', 'dna', 'guides', 'a.md'),
          '# Komplett neu\n',
        );
        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - one\n'
          '    - two\n'
          '  one:\n'
          '    path: ../layer1\n'
          '  two:\n'
          '    path: ../layer2\n',
        );

        await runSync(makeCmd());

        // The full file of the later layer wins over the earlier patch.
        expect(
          File(p.join(target.path, 'dna', 'guides', 'a.md')).readAsStringSync(),
          '# Komplett neu\n',
        );
      });

      test('in-dna layers may use a repo-style dna/ subfolder', () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'BASE');
        writeFile(
          p.join(target.path, 'dna', '_override', 'dna', 'guides', 'a.md'),
          'OVERRIDE',
        );
        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - repo\n'
          '  repo:\n'
          '    path: dna/_override\n',
        );

        await runSync(makeCmd());

        expect(
          File(p.join(target.path, 'dna', 'guides', 'a.md')).readAsStringSync(),
          'OVERRIDE',
        );
        // The layer source survived verbatim.
        expect(
          File(
            p.join(target.path, 'dna', '_override', 'dna', 'guides', 'a.md'),
          ).existsSync(),
          isTrue,
        );
      });

      test('removes stale staging and backup folders of interrupted syncs',
          () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'A');
        writeFile(p.join(target.path, 'dna', 'guides', 'old.md'), 'old');
        writeFile(p.join(target.path, '.gg_dna_staging', 'junk.md'), 'junk');
        writeFile(p.join(target.path, '.gg_dna_backup', 'junk.md'), 'junk');

        await runSync(makeCmd());

        expect(
          Directory(p.join(target.path, '.gg_dna_staging')).existsSync(),
          isFalse,
        );
        expect(
          Directory(p.join(target.path, '.gg_dna_backup')).existsSync(),
          isFalse,
        );
        expect(
          File(p.join(target.path, 'dna', 'guides', 'a.md')).existsSync(),
          isTrue,
        );
        expect(
          File(p.join(target.path, 'dna', 'guides', 'old.md')).existsSync(),
          isFalse,
        );
      });

      test('recovers the dna backup of an interrupted swap', () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), '## [s] Alt\n\nx\n');
        // Simulate a sync that was killed between the two swap renames:
        // dna/ is gone, the old tree (with the user's override layer)
        // lives in the backup folder.
        writeFile(
          p.join(
            target.path,
            '.gg_dna_backup',
            '_override',
            'guides',
            'a.tag.md',
          ),
          '## [s] Neu\n\nInhalt.\n',
        );
        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - repo\n'
          '  repo:\n'
          '    path: dna/_override\n',
        );

        await runSync(makeCmd());

        expect(messages.any((m) => m.contains('Recovering')), isTrue);
        expect(
          File(p.join(target.path, 'dna', 'guides', 'a.md')).readAsStringSync(),
          '## Neu\n\nInhalt.\n',
        );
        expect(
          File(
            p.join(target.path, 'dna', '_override', 'guides', 'a.tag.md'),
          ).existsSync(),
          isTrue,
        );
        expect(
          Directory(p.join(target.path, '.gg_dna_backup')).existsSync(),
          isFalse,
        );
      });

      test('a failure while building leaves the target untouched', () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'A');
        const tagFile = '## [s] Neu\n';
        writeFile(
          p.join(target.path, 'dna', '_override', 'guides', 'a.tag.md'),
          tagFile,
        );
        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - repo\n'
          '  repo:\n'
          '    path: dna/_override\n',
        );
        await runSync(makeCmd());
        final before = File(p.join(target.path, 'dna', 'guides', 'a.md'))
            .readAsStringSync();

        // A base .md with invalid UTF-8 makes the render pass throw —
        // after the staging tree was already populated.
        File(p.join(pkgDna.path, 'guides', 'bad.md'))
            .writeAsBytesSync([0xC3, 0x28]);
        await expectLater(
          runSync(makeCmd()),
          throwsA(isA<Exception>()),
        );

        // Target untouched, override source intact, no leftovers.
        expect(
          File(p.join(target.path, 'dna', 'guides', 'a.md')).readAsStringSync(),
          before,
        );
        expect(
          File(
            p.join(target.path, 'dna', '_override', 'guides', 'a.tag.md'),
          ).readAsStringSync(),
          tagFile,
        );
        expect(
          File(p.join(target.path, 'dna', 'guides', 'bad.md')).existsSync(),
          isFalse,
        );
        expect(
          Directory(p.join(target.path, '.gg_dna_staging')).existsSync(),
          isFalse,
        );
        expect(
          Directory(p.join(target.path, '.gg_dna_backup')).existsSync(),
          isFalse,
        );
      });

      test(
          'in-dna layers survive the wipe verbatim and do not inherit '
          'base content', () async {
        writeFile(
          p.join(pkgDna.path, 'guides', 'a.md'),
          '## [s] Alt\n\nAlter Inhalt.\n',
        );
        // The base ships junk below _override that must NOT leak into the
        // restored layer source.
        writeFile(p.join(pkgDna.path, '_override', 'junk.md'), 'junk');
        const tagFile = '<!-- s -->\n## Neu\n\nNeuer Inhalt.\n<!-- s -->\n';
        writeFile(
          p.join(target.path, 'dna', '_override', 'guides', 'a.tag.md'),
          tagFile,
        );
        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - repo\n'
          '  repo:\n'
          '    path: dna/_override\n',
        );

        await runSync(makeCmd());

        // Merged output is patched and rendered.
        expect(
          File(p.join(target.path, 'dna', 'guides', 'a.md')).readAsStringSync(),
          '## Neu\n\nNeuer Inhalt.\n',
        );
        // The layer source survived verbatim — markers intact, no junk.
        expect(
          File(
            p.join(target.path, 'dna', '_override', 'guides', 'a.tag.md'),
          ).readAsStringSync(),
          tagFile,
        );
        expect(
          File(p.join(target.path, 'dna', '_override', 'junk.md')).existsSync(),
          isFalse,
        );

        // The manifest hash was computed after the restore: an immediate
        // --check passes.
        messages.clear();
        await runSync(makeCmd(), extra: ['--check']);
        expect(messages.last, contains('up to date'));
      });
    });

    // =========================================================================
    group('git layers (stubbed)', () {
      test('clones unconstrained layers at HEAD and records the commit',
          () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'BASE');
        final urls = <String>[];
        final refs = <String?>[];
        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - company\n'
          '  company:\n'
          '    git: https://example.com/company.git\n',
        );

        await runSync(
          makeCmd(
            gitCloner: clonerWriting(
              {'dna/guides/a.md': 'COMPANY'},
              urls: urls,
              refs: refs,
            ),
            gitRevParse: (dir) async => 'abc123',
          ),
        );

        expect(urls, ['https://example.com/company.git']);
        expect(refs, [null]);
        expect(
          File(p.join(target.path, 'dna', 'guides', 'a.md')).readAsStringSync(),
          'COMPANY',
        );
        final manifest = DnaManifest.read(
          Directory(p.join(target.path, 'dna')),
        );
        expect(manifest!.layers.single.commit, 'abc123');
        expect(manifest.layers.single.resolvedVersion, isNull);
      });

      test('expands gg_* shorthands in the git field', () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'BASE');
        final urls = <String>[];
        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - company\n'
          '  company:\n'
          '    git: gg_dna_company\n',
        );

        await runSync(
          makeCmd(
            gitCloner: clonerWriting({'dna/guides/a.md': 'X'}, urls: urls),
            gitRevParse: (dir) async => 'abc123',
          ),
        );

        expect(urls, ['https://github.com/ggsuite/gg_dna_company.git']);
        expect(
          messages.any((m) => m.contains('Resolved shorthand')),
          isTrue,
        );
      });

      test('resolves version constraints against tags and clones the tag',
          () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'BASE');
        final refs = <String?>[];
        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - company\n'
          '  company:\n'
          '    git: https://example.com/company.git\n'
          '    version: ^1.4.0\n',
        );

        await runSync(
          makeCmd(
            gitCloner: clonerWriting({'dna/guides/a.md': 'X'}, refs: refs),
            gitLsRemoteTags: (url) async => {
              '1.4.0': 'sha140',
              'v1.5.0': 'sha150',
              '2.0.0': 'sha200',
            },
          ),
        );

        expect(refs, ['v1.5.0']);
        expect(messages.any((m) => m.contains('^1.4.0')), isTrue);
        final manifest = DnaManifest.read(
          Directory(p.join(target.path, 'dna')),
        );
        final layer = manifest!.layers.single;
        expect(layer.resolvedVersion, '1.5.0');
        expect(layer.resolvedTag, 'v1.5.0');
        expect(layer.commit, 'sha150');
        expect(layer.versionConstraint, '^1.4.0');
      });

      test('throws when no tag satisfies the constraint — target untouched',
          () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'A');
        await runSync(makeCmd());
        final before =
            File(p.join(target.path, 'dna', 'guides', 'a.md')).existsSync();

        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - company\n'
          '  company:\n'
          '    git: https://example.com/company.git\n'
          '    version: ^3.0.0\n',
        );
        await expectLater(
          runSync(
            makeCmd(
              gitCloner: clonerWriting(const {}),
              gitLsRemoteTags: (url) async => {'1.4.0': 'sha140'},
            ),
          ),
          throwsA(
            isA<Exception>().having(
              (e) => '$e',
              'message',
              allOf(contains('no tag satisfies'), contains('1.4.0')),
            ),
          ),
        );

        expect(before, isTrue);
        expect(
          File(p.join(target.path, 'dna', 'guides', 'a.md')).existsSync(),
          isTrue,
        );
      });

      test('throws when tags cannot be listed', () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'A');
        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - company\n'
          '  company:\n'
          '    git: https://example.com/company.git\n'
          '    version: ^1.0.0\n',
        );

        await expectLater(
          runSync(
            makeCmd(
              gitCloner: clonerWriting(const {}),
              gitLsRemoteTags: (url) async => null,
            ),
          ),
          throwsA(
            isA<Exception>().having(
              (e) => '$e',
              'message',
              contains('cannot list tags'),
            ),
          ),
        );
      });

      test('throws when the clone has no dna/ folder and cleans up', () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'A');
        final dests = <Directory>[];
        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - company\n'
          '  company:\n'
          '    git: https://example.com/company.git\n',
        );

        await expectLater(
          runSync(
            makeCmd(
              gitCloner: clonerWriting({'readme.md': 'X'}, dests: dests),
              gitRevParse: (dir) async => 'abc123',
            ),
          ),
          throwsA(
            isA<Exception>().having(
              (e) => '$e',
              'message',
              contains('does not contain a dna/ folder'),
            ),
          ),
        );
        expect(dests.single.existsSync(), isFalse);
      });

      test('cleans up cloned layers when a later layer fails', () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'A');
        final dests = <Directory>[];
        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - company\n'
          '    - missing\n'
          '  company:\n'
          '    git: https://example.com/company.git\n'
          '  missing:\n'
          '    path: ../missing\n',
        );

        await expectLater(
          runSync(
            makeCmd(
              gitCloner: clonerWriting({'dna/x.md': 'X'}, dests: dests),
              gitRevParse: (dir) async => 'abc123',
            ),
          ),
          throwsA(isA<Exception>()),
        );
        expect(dests.single.existsSync(), isFalse);
      });
    });

    // =========================================================================
    group('tag override warnings', () {
      test('logs when a tag file has no target and forwards engine warnings',
          () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), '# A\n');
        final layer = Directory(p.join(tmp.path, 'layer'));
        // No guides/none.md exists anywhere.
        writeFile(
          p.join(layer.path, 'dna', 'guides', 'none.tag.md'),
          '<!-- x --> y <!-- x -->\n',
        );
        // Parse warning (stray content) + apply warning (unknown tag).
        writeFile(
          p.join(layer.path, 'dna', 'guides', 'a.tag.md'),
          'Streuner\n\n<!-- missing --> y <!-- missing -->\n',
        );
        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - layer\n'
          '  layer:\n'
          '    path: ../layer\n',
        );

        await runSync(makeCmd());

        expect(
          messages.any((m) => m.contains('no target file')),
          isTrue,
        );
        expect(
          messages.any((m) => m.contains('Stray content')),
          isTrue,
        );
        expect(
          messages.any((m) => m.contains('"missing" not found')),
          isTrue,
        );
      });
    });

    // =========================================================================
    group('sample workspace end-to-end (real git)', () {
      late Directory companyRepo;

      /// Builds the three-layer sample workspace: base_pkg as base DNA,
      /// dna_company as a real local git repo with tags, dna_project as a
      /// path layer, and the target repo with its dna/_override layer.
      Future<void> setUpSampleWorkspace() async {
        copyDirectory(
          Directory(p.join(sampleRoot(), 'base_pkg')),
          pkgRoot,
        );
        companyRepo = copySampleTo('dna_company', tmp);
        await initGitRepoWithTags(companyRepo, ['1.4.0', 'v1.5.0', 'latest']);
        copySampleTo('dna_project', tmp);
        copyDirectory(
          Directory(p.join(sampleRoot(), 'target')),
          target,
        );

        // Point the git layer at the local repo.
        final pubspec = File(p.join(target.path, 'pubspec.yaml'));
        pubspec.writeAsStringSync(
          pubspec.readAsStringSync().replaceAll(
                'https://github.com/acme/dna_company.git',
                companyRepo.path,
              ),
        );
      }

      test('merges all three layers, renders markers, and passes --check',
          () async {
        await setUpSampleWorkspace();

        // Real git: no cloner/lsRemoteTags stubs.
        await runSync(makeCmd());

        // Section overridden by dna/_override (highest layer), string
        // overridden by dna_project, both rendered.
        expect(
          File(p.join(target.path, 'dna', 'guides', 'coding.md'))
              .readAsStringSync(),
          '# Coding Guide\n'
          '\n'
          '## Repo-Begrüßung\n'
          '\n'
          'Dieses Repo grüßt besonders.\n'
          '\n'
          '## Werkzeuge\n'
          '\n'
          'Nutze pnpm für Dependencies.\n'
          '\n'
          '### Beispiel\n'
          '\n'
          '```markdown\n'
          '### [example] So bleibt ein Beispiel erhalten\n'
          '{{example|unberührt}}\n'
          '```\n',
        );

        // Full-file override: the later path layer wins.
        expect(
          File(p.join(target.path, 'dna', 'guides', 'company.md'))
              .readAsStringSync(),
          startsWith('# Company Guide (Projekt)'),
        );

        // The in-dna layer source survived verbatim.
        expect(
          File(
            p.join(
              target.path,
              'dna',
              '_override',
              'guides',
              'coding.tag.md',
            ),
          ).readAsStringSync(),
          contains('<!-- greeting -->'),
        );

        // No consumed .tag.md files outside the override source.
        final tagFiles = Directory(p.join(target.path, 'dna'))
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.tag.md'))
            .map((f) => p.relative(f.path, from: target.path))
            .map((f) => f.replaceAll('\\', '/'))
            .toList();
        expect(tagFiles, ['dna/_override/guides/coding.tag.md']);

        // Manifest: resolved version, tag, and commit of the git layer.
        final headSha =
            (await runGit(companyRepo, ['rev-parse', 'HEAD'])).trim();
        final manifest = DnaManifest.read(
          Directory(p.join(target.path, 'dna')),
        );
        expect(manifest!.baseVersion, '0.0.1');
        expect(manifest.layers, hasLength(3));
        expect(manifest.layers[0].name, 'dna_company');
        expect(manifest.layers[0].resolvedVersion, '1.5.0');
        expect(manifest.layers[0].resolvedTag, 'v1.5.0');
        expect(manifest.layers[0].commit, headSha);
        expect(manifest.layers[1].name, 'dna_project');
        expect(manifest.layers[1].hash, isNotNull);
        expect(manifest.layers[2].name, 'dna_repo');
        expect(manifest.layers[2].path, 'dna/_override');

        // Immediate --check passes (hash computed after restore).
        messages.clear();
        await runSync(makeCmd(), extra: ['--check']);
        expect(messages.last, contains('up to date'));
      });

      test('--check detects new matching tags and local override edits',
          () async {
        await setUpSampleWorkspace();
        await runSync(makeCmd());

        // A new matching tag appears in the company repo.
        await runGit(companyRepo, ['tag', '-a', '1.6.0', '-m', '1.6.0']);
        messages.clear();
        await expectLater(
          runSync(makeCmd(), extra: ['--check']),
          throwsA(isA<Exception>()),
        );
        expect(
          messages.any((m) => m.contains('new matching version')),
          isTrue,
        );

        // Re-sync picks 1.6.0 up and is green again.
        await runSync(makeCmd());
        final manifest = DnaManifest.read(
          Directory(p.join(target.path, 'dna')),
        );
        expect(manifest!.layers[0].resolvedVersion, '1.6.0');

        // A local edit of the override layer triggers both the local and
        // the layer problem.
        writeFile(
          p.join(target.path, 'dna', '_override', 'guides', 'coding.tag.md'),
          '<!-- greeting -->\n## Anders\n<!-- greeting -->\n',
        );
        messages.clear();
        await expectLater(
          runSync(makeCmd(), extra: ['--check']),
          throwsA(isA<Exception>()),
        );
        expect(
          messages.any((m) => m.contains('local files modified')),
          isTrue,
        );
        expect(
          messages.any(
            (m) => m.contains('layer "dna_repo" has changed'),
          ),
          isTrue,
        );
      });
    });

    // =========================================================================
    group('--check', () {
      test('passes when target/dna matches source', () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'A');
        await runSync(makeCmd());
        messages.clear();

        await runSync(makeCmd(), extra: ['--check']);
        expect(messages.last, contains('up to date'));
      });

      test('throws when target/dna is missing', () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'A');

        await expectLater(
          runSync(makeCmd(), extra: ['--check']),
          throwsA(isA<Exception>()),
        );
        expect(messages.any((m) => m.contains('missing')), isTrue);
      });

      test('throws when .dna.json is missing or has a pre-2.0 format',
          () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'A');
        writeFile(p.join(target.path, 'dna', 'guides', 'a.md'), 'A');

        await expectLater(
          runSync(makeCmd(), extra: ['--check']),
          throwsA(isA<Exception>()),
        );
        expect(
          messages.any((m) => m.contains('missing or pre-2.0 format')),
          isTrue,
        );

        // A gg_dna 1.x manifest is rejected the same way.
        writeFile(
          p.join(target.path, 'dna', '.dna.json'),
          jsonEncode({'overlay': 'gg_foo', 'hash': '0x01'}),
        );
        messages.clear();
        await expectLater(
          runSync(makeCmd(), extra: ['--check']),
          throwsA(isA<Exception>()),
        );
        expect(
          messages.any((m) => m.contains('missing or pre-2.0 format')),
          isTrue,
        );
      });

      test('throws when a local file was modified after sync', () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'A');
        await runSync(makeCmd());
        writeFile(p.join(target.path, 'dna', 'guides', 'a.md'), 'A-modified');

        await expectLater(
          runSync(makeCmd(), extra: ['--check']),
          throwsA(isA<Exception>()),
        );
        expect(
          messages.any((m) => m.contains('local files modified')),
          isTrue,
        );
      });

      test('throws when the base source has new content', () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'A');
        await runSync(makeCmd());
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'A-new');

        await expectLater(
          runSync(makeCmd(), extra: ['--check']),
          throwsA(isA<Exception>()),
        );
        expect(
          messages.any((m) => m.contains('base source has changed')),
          isTrue,
        );
      });

      test('detects dna config drift against the manifest', () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'A');
        writeFile(p.join(tmp.path, 'layerA', 'dna', 'x.md'), 'X');
        writeFile(p.join(tmp.path, 'layerB', 'dna', 'x.md'), 'X');
        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - a\n'
          '  a:\n'
          '    path: ../layerA\n',
        );
        await runSync(makeCmd());

        Future<void> expectDrift(String dnaBlock) async {
          writePubspec(dnaBlock);
          messages.clear();
          await expectLater(
            runSync(makeCmd(), extra: ['--check']),
            throwsA(isA<Exception>()),
          );
          expect(
            messages.any((m) => m.contains('changed since last sync')),
            isTrue,
          );
        }

        // Path changed.
        await expectDrift(
          'dna:\n  order:\n    - a\n  a:\n    path: ../layerB\n',
        );
        // Name changed.
        await expectDrift(
          'dna:\n  order:\n    - b\n  b:\n    path: ../layerA\n',
        );
        // Layer removed.
        await expectDrift('dna:\n  order: []\n');
        // Switched from path to git.
        await expectDrift(
          'dna:\n  order:\n    - a\n  a:\n'
          '    git: https://example.com/a.git\n',
        );
        // Constraint added on the git variant needs a matching manifest —
        // covered by the version-constraint drift below.

        // Config removed entirely while the manifest still has layers.
        writeFile(
          p.join(target.path, 'pubspec.yaml'),
          'name: target_repo\nversion: 0.1.0\n',
        );
        messages.clear();
        await expectLater(
          runSync(makeCmd(), extra: ['--check']),
          throwsA(isA<Exception>()),
        );
        expect(
          messages.any((m) => m.contains('changed since last sync')),
          isTrue,
        );
      });

      test('detects version constraint drift', () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'A');
        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - c\n'
          '  c:\n'
          '    git: https://example.com/c.git\n'
          '    version: ^1.0.0\n',
        );
        await runSync(
          makeCmd(
            gitCloner: clonerWriting({'dna/x.md': 'X'}),
            gitLsRemoteTags: (url) async => {'1.0.0': 'sha1'},
          ),
        );

        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - c\n'
          '  c:\n'
          '    git: https://example.com/c.git\n'
          '    version: ^2.0.0\n',
        );
        messages.clear();
        await expectLater(
          runSync(
            makeCmd(gitLsRemoteTags: (url) async => {'1.0.0': 'sha1'}),
            extra: ['--check'],
          ),
          throwsA(isA<Exception>()),
        );
        expect(
          messages.any((m) => m.contains('changed since last sync')),
          isTrue,
        );
      });

      test('checks constrained git layers against fresh tags', () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'A');
        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - c\n'
          '  c:\n'
          '    git: https://example.com/c.git\n'
          '    version: ^1.0.0\n',
        );
        await runSync(
          makeCmd(
            gitCloner: clonerWriting({'dna/x.md': 'X'}),
            gitLsRemoteTags: (url) async => {'1.0.0': 'sha1'},
          ),
        );

        // Unchanged tags: up to date.
        messages.clear();
        await runSync(
          makeCmd(gitLsRemoteTags: (url) async => {'1.0.0': 'sha1'}),
          extra: ['--check'],
        );
        expect(messages.last, contains('up to date'));

        // A higher matching tag appeared.
        messages.clear();
        await expectLater(
          runSync(
            makeCmd(
              gitLsRemoteTags: (url) async =>
                  {'1.0.0': 'sha1', '1.1.0': 'sha2'},
            ),
            extra: ['--check'],
          ),
          throwsA(isA<Exception>()),
        );
        expect(
          messages.any((m) => m.contains('new matching version')),
          isTrue,
        );

        // Tags cannot be listed anymore.
        messages.clear();
        await expectLater(
          runSync(
            makeCmd(gitLsRemoteTags: (url) async => null),
            extra: ['--check'],
          ),
          throwsA(isA<Exception>()),
        );
        expect(
          messages.any((m) => m.contains('cannot list tags')),
          isTrue,
        );

        // No tag satisfies the constraint anymore.
        messages.clear();
        await expectLater(
          runSync(
            makeCmd(gitLsRemoteTags: (url) async => {'0.9.0': 'sha0'}),
            extra: ['--check'],
          ),
          throwsA(isA<Exception>()),
        );
        expect(
          messages.any((m) => m.contains('no tag satisfies')),
          isTrue,
        );
      });

      test('checks unconstrained git layers against remote HEAD', () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'A');
        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - c\n'
          '  c:\n'
          '    git: https://example.com/c.git\n',
        );
        await runSync(
          makeCmd(
            gitCloner: clonerWriting({'dna/x.md': 'X'}),
            gitRevParse: (dir) async => 'abc123',
          ),
        );

        // HEAD unchanged: up to date.
        messages.clear();
        await runSync(
          makeCmd(gitLsRemote: (url) async => 'abc123'),
          extra: ['--check'],
        );
        expect(messages.last, contains('up to date'));

        // HEAD moved.
        messages.clear();
        await expectLater(
          runSync(
            makeCmd(gitLsRemote: (url) async => 'def456'),
            extra: ['--check'],
          ),
          throwsA(isA<Exception>()),
        );
        expect(
          messages.any((m) => m.contains('has new commits')),
          isTrue,
        );

        // Remote unreachable.
        messages.clear();
        await expectLater(
          runSync(
            makeCmd(gitLsRemote: (url) async => null),
            extra: ['--check'],
          ),
          throwsA(isA<Exception>()),
        );
        expect(
          messages.any((m) => m.contains('cannot resolve remote HEAD')),
          isTrue,
        );
      });

      test('checks path layers by re-hashing', () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'A');
        writeFile(p.join(tmp.path, 'layerA', 'dna', 'x.md'), 'X');
        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - a\n'
          '  a:\n'
          '    path: ../layerA\n',
        );
        await runSync(makeCmd());

        // Layer changed.
        writeFile(p.join(tmp.path, 'layerA', 'dna', 'x.md'), 'X2');
        messages.clear();
        await expectLater(
          runSync(makeCmd(), extra: ['--check']),
          throwsA(isA<Exception>()),
        );
        expect(
          messages.any((m) => m.contains('layer "a" has changed')),
          isTrue,
        );

        // Layer path gone.
        Directory(p.join(tmp.path, 'layerA')).deleteSync(recursive: true);
        messages.clear();
        await expectLater(
          runSync(makeCmd(), extra: ['--check']),
          throwsA(isA<Exception>()),
        );
        expect(
          messages.any((m) => m.contains('path no longer exists')),
          isTrue,
        );
      });
    });

    // =========================================================================
    test('prompts per skill and installs only the selected ones', () async {
      final skillsSrc = Directory(p.join(pkgDna.path, 'agents', 'skills'))
        ..createSync(recursive: true);
      writeSkillIn(skillsSrc, 'new-project');
      writeSkillIn(skillsSrc, 'new-ticket');
      writeSkillIn(skillsSrc, 'simplify');

      selectorAnswers['/new-project?'] = true;
      selectorAnswers['/new-ticket?'] = false;
      selectorAnswers['/simplify?'] = true;

      await runSync(makeCmd(), extra: []);

      expect(
        Directory(p.join(target.path, 'dna', 'agents', 'skills', 'new-project'))
            .existsSync(),
        isTrue,
      );

      final claudeSkills = Directory(p.join(target.path, '.claude', 'skills'));
      expect(
        File(p.join(claudeSkills.path, 'new-project', 'SKILL.md')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(claudeSkills.path, 'simplify', 'SKILL.md')).existsSync(),
        isTrue,
      );
      expect(
        Directory(p.join(claudeSkills.path, 'new-ticket')).existsSync(),
        isFalse,
      );

      expect(
        selectorPrompts.where((p) => p.contains('/new-project?')).length,
        1,
      );
      expect(
        selectorPrompts.where((p) => p.contains('/new-ticket?')).length,
        1,
      );
      expect(
        selectorPrompts.where((p) => p.contains('/simplify?')).length,
        1,
      );
    });

    test('prompts per convention and applies only the selected ones', () async {
      final convSrc = Directory(
        p.join(pkgDna.path, 'agents', 'conventions'),
      )..createSync(recursive: true);
      File(p.join(convSrc.path, 'code-conventions.md'))
          .writeAsStringSync('# code');
      File(p.join(convSrc.path, 'test-conventions.md'))
          .writeAsStringSync('# test');

      selectorAnswers['code-conventions.md'] = true;
      selectorAnswers['test-conventions.md'] = false;

      await runSync(makeCmd(), extra: []);

      final destDir = Directory(p.join(target.path, '.claude', 'conventions'));
      expect(
        File(p.join(destDir.path, 'code-conventions.md')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(destDir.path, 'test-conventions.md')).existsSync(),
        isFalse,
      );

      final claudeMd =
          File(p.join(target.path, 'CLAUDE.md')).readAsStringSync();
      expect(
        claudeMd,
        contains('@.claude/conventions/code-conventions.md'),
      );
      expect(
        claudeMd.contains('@.claude/conventions/test-conventions.md'),
        isFalse,
      );
      expect(claudeMd, contains(ApplyConventions.startMarker));
    });

    test('logs "no skills selected" when user says no to every prompt',
        () async {
      final skillsSrc = Directory(p.join(pkgDna.path, 'agents', 'skills'))
        ..createSync(recursive: true);
      writeSkillIn(skillsSrc, 'alpha');

      await runSync(makeCmd(), extra: []);

      expect(
        messages.any((m) => m.contains('no skills selected')),
        isTrue,
      );
      expect(
        Directory(p.join(target.path, '.claude', 'skills')).existsSync(),
        isFalse,
      );
    });

    test('logs "no conventions selected" when user says no to every prompt',
        () async {
      final convSrc = Directory(p.join(pkgDna.path, 'agents', 'conventions'))
        ..createSync(recursive: true);
      File(p.join(convSrc.path, 'code-conventions.md'))
          .writeAsStringSync('# code');

      await runSync(makeCmd(), extra: []);

      expect(
        messages.any((m) => m.contains('no conventions selected')),
        isTrue,
      );
      expect(
        File(p.join(target.path, 'CLAUDE.md')).existsSync(),
        isFalse,
      );
    });

    test('--no-install skips both prompt phases', () async {
      final skillsSrc = Directory(p.join(pkgDna.path, 'agents', 'skills'))
        ..createSync(recursive: true);
      writeSkillIn(skillsSrc, 'alpha');
      final convSrc = Directory(p.join(pkgDna.path, 'agents', 'conventions'))
        ..createSync(recursive: true);
      File(p.join(convSrc.path, 'code-conventions.md'))
          .writeAsStringSync('# code');

      await runSync(makeCmd());

      expect(selectorPrompts, isEmpty);
      expect(
        Directory(p.join(target.path, '.claude')).existsSync(),
        isFalse,
      );
    });

    // =========================================================================
    group('expandShorthand', () {
      test('expands bare gg_* names to the ggsuite github URL', () {
        expect(
          Sync.expandShorthand('gg_dna_ggsuite'),
          'https://github.com/ggsuite/gg_dna_ggsuite.git',
        );
      });

      test('strips a trailing .git before building the URL', () {
        expect(
          Sync.expandShorthand('gg_dna_ggsuite.git'),
          'https://github.com/ggsuite/gg_dna_ggsuite.git',
        );
      });

      test('rejects anything that is not a bare gg_* name', () {
        expect(Sync.expandShorthand('dna_repo'), isNull);
        expect(Sync.expandShorthand('gg_foo/bar'), isNull);
        expect(Sync.expandShorthand('git@github.com:ggsuite/gg_x.git'), isNull);
        expect(Sync.expandShorthand('https://example.com/gg_x.git'), isNull);
        expect(Sync.expandShorthand('C:\\repos\\gg_x'), isNull);
      });
    });
  });
}
