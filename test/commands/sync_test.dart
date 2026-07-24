// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:gg_dna/src/commands/sync.dart';
import 'package:gg_dna/src/util/claude_md.dart';
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

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sync_test_');
    pkgRoot = Directory(p.join(tmp.path, 'pkg'))..createSync();
    pkgDna = Directory(p.join(pkgRoot.path, 'dna', 'src'))
      ..createSync(recursive: true);
    target = Directory(p.join(tmp.path, 'target'))..createSync();
    messages = <String>[];
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

  Sync makeCmd({
    GitCloner? gitCloner,
    GitRevParse? gitRevParse,
    GitLsRemote? gitLsRemote,
    GitLsRemoteTags? gitLsRemoteTags,
  }) =>
      Sync(
        ggLog: messages.add,
        packageRootResolver: () async => pkgRoot.path,
        gitCloner: gitCloner,
        gitRevParse: gitRevParse,
        gitLsRemote: gitLsRemote,
        gitLsRemoteTags: gitLsRemoteTags,
      );

  CommandRunner<dynamic> makeRunner(Sync cmd) =>
      CommandRunner<dynamic>('test', 'test')..addCommand(cmd);

  Future<void> runSync(
    Sync cmd, {
    List<String> extra = const [],
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

    test('mirrors source dna/ into <target>/dna', () async {
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
        '## [@s] Alt\n\nWert: {{@v:standard}}\n',
      );
      writeFile(
        p.join(pkgDna.path, 'guides', 'a.overrides.md'),
        '## [@s] Neu\n\nInhalt.\n',
      );

      await runSync(makeCmd());

      expect(
        File(p.join(target.path, 'dna', 'guides', 'a.md')).readAsStringSync(),
        '## Neu\n\nInhalt.\n',
      );
      // Tag files are consumed, never copied.
      expect(
        File(p.join(target.path, 'dna', 'guides', 'a.overrides.md'))
            .existsSync(),
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
        '  dependencies:\n'
        '    orphan:\n'
        '      path: ../nowhere\n',
      );
      writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'A');

      await runSync(makeCmd());

      expect(messages.any((m) => m.contains('ignored')), isTrue);
    });

    // =========================================================================
    group('path layers', () {
      test('merges layers in order — later layers win', () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'BASE');
        writeFile(
          p.join(tmp.path, 'layer1', 'dna', 'src', 'guides', 'a.md'),
          'ONE',
        );
        writeFile(
          p.join(tmp.path, 'layer1', 'dna', 'src', 'guides', 'one.md'),
          '1',
        );
        writeFile(
          p.join(tmp.path, 'layer2', 'dna', 'src', 'guides', 'a.md'),
          'TWO',
        );
        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - one\n'
          '    - two\n'
          '  dependencies:\n'
          '    one:\n'
          '      path: ../layer1\n'
          '    two:\n'
          '      path: ../layer2\n',
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

      test('throws when a path layer has no dna/src folder', () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'BASE');
        writeFile(p.join(tmp.path, 'direct', 'guides', 'a.md'), 'DIRECT');
        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - direct\n'
          '  dependencies:\n'
          '    direct:\n'
          '      path: ../direct\n',
        );

        await expectLater(
          runSync(makeCmd()),
          throwsA(
            isA<Exception>().having(
              (e) => '$e',
              'message',
              contains('does not contain a dna/src folder'),
            ),
          ),
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
          '  dependencies:\n'
          '    missing:\n'
          '      path: ../missing\n',
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
          '  dependencies:\n'
          '    f:\n'
          '      path: ../afile.txt\n',
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

      test('throws when a layer points into <target>/dna', () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'A');
        writeFile(p.join(target.path, 'dna', 'guides', 'a.md'), 'A');
        for (final path in ['dna', 'dna/_override']) {
          writePubspec(
            'dna:\n'
            '  order:\n'
            '    - self\n'
            '  dependencies:\n'
            '    self:\n'
            '      path: $path\n',
          );

          await expectLater(
            runSync(makeCmd()),
            throwsA(
              isA<Exception>().having(
                (e) => '$e',
                'message',
                allOf(
                  contains('no longer supported'),
                  contains('dna/src'),
                ),
              ),
            ),
          );
        }
      });

      test('skips .git folders and layer manifests when copying', () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'BASE');
        final layerSrc = Directory(p.join(tmp.path, 'layer', 'dna', 'src'));
        writeFile(p.join(layerSrc.path, 'guides', 'a.md'), 'LAYER');
        writeFile(p.join(layerSrc.path, '.git', 'config'), 'git stuff');
        writeFile(p.join(layerSrc.path, '.dna.json'), '{"version": 2}');
        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - layer\n'
          '  dependencies:\n'
          '    layer:\n'
          '      path: ../layer\n',
        );

        await runSync(makeCmd());

        expect(
          Directory(p.join(target.path, 'dna', '.git')).existsSync(),
          isFalse,
        );
        // The layer's own manifest is not copied; the sync writes a fresh
        // one after the merge. The implicit src layer is recorded last.
        final manifest = DnaManifest.read(
          Directory(p.join(target.path, 'dna')),
        );
        expect(manifest!.layers.map((l) => l.name), ['layer', 'src']);
        expect(manifest.layers.last.path, 'dna/src');
      });

      test(
          'a missing <target>/dna/src is skipped as empty '
          '(fresh clones: git does not track empty folders)', () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'Wert: {{@s:x}}\n');

        await runSync(makeCmd());

        expect(
          File(p.join(target.path, 'dna', 'guides', 'a.md')).existsSync(),
          isTrue,
        );

        // The immediate check agrees with the sync.
        messages.clear();
        await runSync(makeCmd(), extra: ['--check']);
        expect(messages.last, contains('up to date'));

        // Creating dna/src later is reported as a layer change …
        writeFile(
          p.join(target.path, 'dna', 'src', 'guides', 'a.overrides.md'),
          '<!-- @s --> neu <!-- @s -->\n',
        );
        messages.clear();
        await expectLater(
          runSync(makeCmd(), extra: ['--check']),
          throwsA(isA<Exception>()),
        );
        expect(
          messages.any((m) => m.contains('layer "src"')),
          isTrue,
        );

        // … and the next sync picks it up.
        await runSync(makeCmd());
        expect(
          File(p.join(target.path, 'dna', 'guides', 'a.md')).readAsStringSync(),
          'Wert: neu\n',
        );
        messages.clear();
        await runSync(makeCmd(), extra: ['--check']);
        expect(messages.last, contains('up to date'));
      });

      test('a later full-file override resets earlier tag patches', () async {
        writeFile(
          p.join(pkgDna.path, 'guides', 'a.md'),
          '## [@s] Basis\n\nx\n',
        );
        writeFile(
          p.join(tmp.path, 'layer1', 'dna', 'src', 'guides', 'a.overrides.md'),
          '## [@s] Gepatcht\n\ny\n',
        );
        writeFile(
          p.join(tmp.path, 'layer2', 'dna', 'src', 'guides', 'a.md'),
          '# Komplett neu\n',
        );
        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - one\n'
          '    - two\n'
          '  dependencies:\n'
          '    one:\n'
          '      path: ../layer1\n'
          '    two:\n'
          '      path: ../layer2\n',
        );

        await runSync(makeCmd());

        // The full file of the later layer wins over the earlier patch.
        expect(
          File(p.join(target.path, 'dna', 'guides', 'a.md')).readAsStringSync(),
          '# Komplett neu\n',
        );
      });

      test('dna/src is applied implicitly as the very last layer', () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'BASE');
        writeFile(
          p.join(tmp.path, 'layer1', 'dna', 'src', 'guides', 'a.md'),
          'ONE',
        );
        writeFile(
          p.join(target.path, 'dna', 'src', 'guides', 'a.md'),
          'SRC',
        );
        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - one\n'
          '  dependencies:\n'
          '    one:\n'
          '      path: ../layer1\n',
        );

        await runSync(makeCmd());

        // The implicit src layer wins over all configured layers.
        expect(
          File(p.join(target.path, 'dna', 'guides', 'a.md')).readAsStringSync(),
          'SRC',
        );
        expect(
          messages.any((m) => m.contains('Applied layer "src"')),
          isTrue,
        );
        // The layer source survived verbatim.
        expect(
          File(p.join(target.path, 'dna', 'src', 'guides', 'a.md'))
              .readAsStringSync(),
          'SRC',
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
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), '## [@s] Alt\n\nx\n');
        // Simulate a sync that was killed between the two swap renames:
        // dna/ is gone, the old tree (with the user's src layer) lives in
        // the backup folder.
        writeFile(
          p.join(
            target.path,
            '.gg_dna_backup',
            'src',
            'guides',
            'a.overrides.md',
          ),
          '## [@s] Neu\n\nInhalt.\n',
        );

        await runSync(makeCmd());

        expect(messages.any((m) => m.contains('Recovering')), isTrue);
        expect(
          File(p.join(target.path, 'dna', 'guides', 'a.md')).readAsStringSync(),
          '## Neu\n\nInhalt.\n',
        );
        expect(
          File(
            p.join(target.path, 'dna', 'src', 'guides', 'a.overrides.md'),
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
        const tagFile = '## [@s] Neu\n';
        writeFile(
          p.join(target.path, 'dna', 'src', 'guides', 'a.overrides.md'),
          tagFile,
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
            p.join(target.path, 'dna', 'src', 'guides', 'a.overrides.md'),
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
          'dna/src survives the wipe verbatim and does not inherit '
          'base content', () async {
        writeFile(
          p.join(pkgDna.path, 'guides', 'a.md'),
          '## [@s] Alt\n\nAlter Inhalt.\n',
        );
        // The base ships junk below src that must NOT leak into the
        // restored layer source.
        writeFile(p.join(pkgDna.path, 'src', 'junk.md'), 'junk');
        const tagFile = '<!-- @s -->\n## Neu\n\nNeuer Inhalt.\n<!-- @s -->\n';
        writeFile(
          p.join(target.path, 'dna', 'src', 'guides', 'a.overrides.md'),
          tagFile,
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
            p.join(target.path, 'dna', 'src', 'guides', 'a.overrides.md'),
          ).readAsStringSync(),
          tagFile,
        );
        expect(
          File(p.join(target.path, 'dna', 'src', 'junk.md')).existsSync(),
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
          '  dependencies:\n'
          '    company:\n'
          '      git: https://example.com/company.git\n',
        );

        await runSync(
          makeCmd(
            gitCloner: clonerWriting(
              {'dna/src/guides/a.md': 'COMPANY'},
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
        expect(manifest!.layers.first.commit, 'abc123');
        expect(manifest.layers.first.resolvedVersion, isNull);
      });

      test('expands gg_* shorthands in the git field', () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'BASE');
        final urls = <String>[];
        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - company\n'
          '  dependencies:\n'
          '    company:\n'
          '      git: gg_dna_company\n',
        );

        await runSync(
          makeCmd(
            gitCloner: clonerWriting({'dna/src/guides/a.md': 'X'}, urls: urls),
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
          '  dependencies:\n'
          '    company:\n'
          '      git: https://example.com/company.git\n'
          '      version: ^1.4.0\n',
        );

        await runSync(
          makeCmd(
            gitCloner: clonerWriting({'dna/src/guides/a.md': 'X'}, refs: refs),
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
        final layer = manifest!.layers.first;
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
          '  dependencies:\n'
          '    company:\n'
          '      git: https://example.com/company.git\n'
          '      version: ^3.0.0\n',
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
          '  dependencies:\n'
          '    company:\n'
          '      git: https://example.com/company.git\n'
          '      version: ^1.0.0\n',
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
          '  dependencies:\n'
          '    company:\n'
          '      git: https://example.com/company.git\n',
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
              contains('does not contain a dna/src folder'),
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
          '  dependencies:\n'
          '    company:\n'
          '      git: https://example.com/company.git\n'
          '    missing:\n'
          '      path: ../missing\n',
        );

        await expectLater(
          runSync(
            makeCmd(
              gitCloner: clonerWriting({'dna/src/x.md': 'X'}, dests: dests),
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
          p.join(layer.path, 'dna', 'src', 'guides', 'none.overrides.md'),
          '<!-- @x --> y <!-- @x -->\n',
        );
        // Parse warning (stray content) + apply warning (unknown tag).
        writeFile(
          p.join(layer.path, 'dna', 'src', 'guides', 'a.overrides.md'),
          'Streuner\n\n<!-- @missing --> y <!-- @missing -->\n',
        );
        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - layer\n'
          '  dependencies:\n'
          '    layer:\n'
          '      path: ../layer\n',
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

      test('a pre-4.0 .tag.md file is a hard error with a rename hint',
          () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), '# A\n');
        writeFile(
          p.join(target.path, 'dna', 'src', 'guides', 'a.tag.md'),
          '<!-- @s --> x <!-- @s -->\n',
        );

        await expectLater(
          runSync(makeCmd()),
          throwsA(
            isA<Exception>().having(
              (e) => '$e',
              'message',
              allOf(contains('.tag.md'), contains('.overrides.md')),
            ),
          ),
        );
      });

      test('warns about leftover pre-4.0 notation in merged files', () async {
        writeFile(
          p.join(pkgDna.path, 'guides', 'a.md'),
          '## [alt] Abschnitt\n\nWert: {{alt|standard}}\n',
        );
        // Legacy notation inside an overrides file warns too.
        writeFile(
          p.join(target.path, 'dna', 'src', 'guides', 'a.overrides.md'),
          '<!-- @s --> {{alt|x}} <!-- @s -->\n',
        );

        await runSync(makeCmd());

        expect(
          messages.any(
            (m) =>
                m.contains('a.overrides.md') && m.contains('legacy string tag'),
          ),
          isTrue,
        );

        expect(
          messages.any(
            (m) => m.contains('guides/a.md') && m.contains('legacy section'),
          ),
          isTrue,
        );
        expect(
          messages.any((m) => m.contains('legacy string tag')),
          isTrue,
        );
        // Old notation stays literal in the output.
        expect(
          File(p.join(target.path, 'dna', 'guides', 'a.md')).readAsStringSync(),
          '## [alt] Abschnitt\n\nWert: {{alt|standard}}\n',
        );
      });
    });

    // =========================================================================
    group('global.overrides.md', () {
      test('rewrites string tags in every file of the merged tree', () async {
        writeFile(
          p.join(pkgDna.path, 'guides', 'a.md'),
          'A: {{@tone:neutral}}\n',
        );
        writeFile(
          p.join(pkgDna.path, 'agents', 'b.md'),
          'B: {{@tone:neutral}}\n',
        );
        writeFile(
          p.join(target.path, 'dna', 'src', 'global.overrides.md'),
          '<!-- @tone --> förmlich <!-- @tone -->\n',
        );

        await runSync(makeCmd());

        expect(
          File(p.join(target.path, 'dna', 'guides', 'a.md')).readAsStringSync(),
          'A: förmlich\n',
        );
        expect(
          File(p.join(target.path, 'dna', 'agents', 'b.md')).readAsStringSync(),
          'B: förmlich\n',
        );
        // The global overrides file is consumed, not copied — but the src
        // source survives verbatim.
        expect(
          File(p.join(target.path, 'dna', 'global.overrides.md')).existsSync(),
          isFalse,
        );
        expect(
          File(p.join(target.path, 'dna', 'src', 'global.overrides.md'))
              .existsSync(),
          isTrue,
        );

        // The immediate check agrees with the sync.
        messages.clear();
        await runSync(makeCmd(), extra: ['--check']);
        expect(messages.last, contains('up to date'));
      });

      test('file-specific overrides of the same layer win over global',
          () async {
        writeFile(
          p.join(pkgDna.path, 'guides', 'a.md'),
          'A: {{@tone:neutral}}\n',
        );
        writeFile(
          p.join(pkgDna.path, 'guides', 'b.md'),
          'B: {{@tone:neutral}}\n',
        );
        final src = p.join(target.path, 'dna', 'src');
        writeFile(
          p.join(src, 'global.overrides.md'),
          '<!-- @tone --> global <!-- @tone -->\n',
        );
        writeFile(
          p.join(src, 'guides', 'a.overrides.md'),
          '<!-- @tone --> spezifisch <!-- @tone -->\n',
        );

        await runSync(makeCmd());

        expect(
          File(p.join(target.path, 'dna', 'guides', 'a.md')).readAsStringSync(),
          'A: spezifisch\n',
        );
        expect(
          File(p.join(target.path, 'dna', 'guides', 'b.md')).readAsStringSync(),
          'B: global\n',
        );
      });

      test('a later layer global override wins over an earlier one', () async {
        writeFile(
          p.join(pkgDna.path, 'guides', 'a.md'),
          'A: {{@tone:neutral}}\n',
        );
        writeFile(
          p.join(tmp.path, 'layer1', 'dna', 'src', 'global.overrides.md'),
          '<!-- @tone --> eins <!-- @tone -->\n',
        );
        writeFile(
          p.join(target.path, 'dna', 'src', 'global.overrides.md'),
          '<!-- @tone --> zwei <!-- @tone -->\n',
        );
        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - one\n'
          '  dependencies:\n'
          '    one:\n'
          '      path: ../layer1\n',
        );

        await runSync(makeCmd());

        expect(
          File(p.join(target.path, 'dna', 'guides', 'a.md')).readAsStringSync(),
          'A: zwei\n',
        );
      });

      test('warns about heading-form blocks, unknown tags, and global.md',
          () async {
        writeFile(
          p.join(pkgDna.path, 'guides', 'a.md'),
          'A: {{@tone:neutral}}\n',
        );
        writeFile(p.join(pkgDna.path, 'global.md'), '# Reserved\n');
        writeFile(
          p.join(target.path, 'dna', 'src', 'global.overrides.md'),
          '## [@section] Nicht erlaubt\n'
          '\n'
          'Inhalt.\n'
          '\n'
          '<!-- @tone -->\n'
          'zeile1\n'
          'zeile2\n'
          '<!-- @tone -->\n'
          '<!-- @nowhere --> x <!-- @nowhere -->\n'
          '<!-- @legacy --> {{alt|y}} <!-- @legacy -->\n'
          '<!-- @broken --> kaputt}} <!-- @broken -->\n'
          'Streuner\n',
        );

        await runSync(makeCmd());

        expect(
          messages.any((m) => m.contains('heading-form block')),
          isTrue,
        );
        expect(
          messages.any(
            (m) =>
                m.contains(r'global.overrides.md') &&
                m.contains('legacy string tag'),
          ),
          isTrue,
        );
        expect(
          messages.any(
            (m) =>
                m.contains(r'global.overrides.md') &&
                m.contains('Stray content'),
          ),
          isTrue,
        );
        expect(
          messages.any((m) => m.contains('spans multiple lines')),
          isTrue,
        );
        expect(
          messages.any((m) => m.contains('"}}"')),
          isTrue,
        );
        expect(
          messages.any(
            (m) => m.contains('"nowhere"') && m.contains('not found in any'),
          ),
          isTrue,
        );
        expect(
          messages.any((m) => m.contains('global.md is a reserved name')),
          isTrue,
        );
        expect(
          File(p.join(target.path, 'dna', 'guides', 'a.md')).readAsStringSync(),
          'A: zeile1 zeile2\n',
        );
        // The reserved file is still copied.
        expect(
          File(p.join(target.path, 'dna', 'global.md')).existsSync(),
          isTrue,
        );
      });
    });

    // =========================================================================
    group('sample workspace end-to-end (real git)', () {
      late Directory companyRepo;

      /// Builds the three-layer sample workspace: base_pkg as base DNA,
      /// dna_company as a real local git repo with tags, dna_project as a
      /// path layer, and the target repo with its implicit dna/src layer.
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

        // Section overridden by dna/src (implicit highest layer), string
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
          '### [@example] So bleibt ein Beispiel erhalten\n'
          '{{@example:unberührt}}\n'
          '```\n',
        );

        // Full-file override: the later path layer wins.
        expect(
          File(p.join(target.path, 'dna', 'guides', 'company.md'))
              .readAsStringSync(),
          startsWith('# Company Guide (Projekt)'),
        );

        // The implicit src layer source survived verbatim.
        expect(
          File(
            p.join(
              target.path,
              'dna',
              'src',
              'guides',
              'coding.overrides.md',
            ),
          ).readAsStringSync(),
          contains('<!-- @greeting -->'),
        );

        // No consumed .overrides.md files outside the override source.
        final tagFiles = Directory(p.join(target.path, 'dna'))
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.overrides.md'))
            .map((f) => p.relative(f.path, from: target.path))
            .map((f) => f.replaceAll('\\', '/'))
            .toList();
        expect(tagFiles, ['dna/src/guides/coding.overrides.md']);

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
        expect(manifest.layers[2].name, 'src');
        expect(manifest.layers[2].path, 'dna/src');

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

        // A local edit of the src layer triggers both the local and
        // the layer problem.
        writeFile(
          p.join(target.path, 'dna', 'src', 'guides', 'coding.overrides.md'),
          '<!-- @greeting -->\n## Anders\n<!-- @greeting -->\n',
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
            (m) => m.contains('layer "src"'),
          ),
          isTrue,
        );
      });
    });

    // =========================================================================
    group('non-Dart config sources (dna.yaml / package.json)', () {
      const expectedCoding = '# Coding Guide\n'
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
          '### [@example] So bleibt ein Beispiel erhalten\n'
          '{{@example:unberührt}}\n'
          '```\n';

      test('syncs a TypeScript repo configured via package.json', () async {
        copyDirectory(Directory(p.join(sampleRoot(), 'base_pkg')), pkgRoot);
        copySampleTo('dna_project', tmp);
        copyDirectory(Directory(p.join(sampleRoot(), 'target_ts')), target);

        await runSync(makeCmd());

        expect(
          File(p.join(target.path, 'dna', 'guides', 'coding.md'))
              .readAsStringSync(),
          expectedCoding,
        );
        expect(
          File(
            p.join(target.path, 'dna', 'src', 'guides', 'coding.overrides.md'),
          ).existsSync(),
          isTrue,
        );

        final manifest = DnaManifest.read(
          Directory(p.join(target.path, 'dna')),
        );
        expect(
          manifest!.layers.map((l) => l.name),
          ['dna_project', 'src'],
        );

        messages.clear();
        await runSync(makeCmd(), extra: ['--check']);
        expect(messages.last, contains('up to date'));
      });

      test('syncs a repo configured via dna.yaml and detects config drift',
          () async {
        copyDirectory(Directory(p.join(sampleRoot(), 'base_pkg')), pkgRoot);
        copyDirectory(Directory(p.join(sampleRoot(), 'target_yaml')), target);

        await runSync(makeCmd());

        expect(
          File(p.join(target.path, 'dna', 'guides', 'coding.md'))
              .readAsStringSync(),
          expectedCoding,
        );

        messages.clear();
        await runSync(makeCmd(), extra: ['--check']);
        expect(messages.last, contains('up to date'));

        // Changing the dna.yaml config drifts against the manifest.
        writeFile(
          p.join(target.path, 'dna.yaml'),
          'dna:\n'
          '  order:\n'
          '    - other\n'
          '  dependencies:\n'
          '    other:\n'
          '      path: ../other\n',
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

      test('throws when dna is configured in more than one file', () async {
        copyDirectory(Directory(p.join(sampleRoot(), 'base_pkg')), pkgRoot);
        copyDirectory(Directory(p.join(sampleRoot(), 'target_yaml')), target);
        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - dna_other\n'
          '  dependencies:\n'
          '    dna_other:\n'
          '      path: ../somewhere\n',
        );

        await expectLater(
          runSync(makeCmd()),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              contains('more than one file'),
            ),
          ),
        );
        // Atomicity: the failed sync leaves no dna folder behind.
        expect(
          Directory(p.join(target.path, 'dna', 'guides')).existsSync(),
          isFalse,
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

      test('throws when .dna.json is missing or has a pre-4.0 format',
          () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'A');
        writeFile(p.join(target.path, 'dna', 'guides', 'a.md'), 'A');

        await expectLater(
          runSync(makeCmd(), extra: ['--check']),
          throwsA(isA<Exception>()),
        );
        expect(
          messages.any((m) => m.contains('missing or pre-4.0 format')),
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
          messages.any((m) => m.contains('missing or pre-4.0 format')),
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
        writeFile(p.join(tmp.path, 'layerA', 'dna', 'src', 'x.md'), 'X');
        writeFile(p.join(tmp.path, 'layerB', 'dna', 'src', 'x.md'), 'X');
        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - a\n'
          '  dependencies:\n'
          '    a:\n'
          '      path: ../layerA\n',
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
          'dna:\n  order:\n    - a\n  dependencies:\n    a:\n'
          '      path: ../layerB\n',
        );
        // Name changed.
        await expectDrift(
          'dna:\n  order:\n    - b\n  dependencies:\n    b:\n'
          '      path: ../layerA\n',
        );
        // Layer removed.
        await expectDrift('dna:\n  order: []\n');
        // Switched from path to git.
        await expectDrift(
          'dna:\n  order:\n    - a\n  dependencies:\n    a:\n'
          '      git: https://example.com/a.git\n',
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
          '  dependencies:\n'
          '    c:\n'
          '      git: https://example.com/c.git\n'
          '      version: ^1.0.0\n',
        );
        await runSync(
          makeCmd(
            gitCloner: clonerWriting({'dna/src/x.md': 'X'}),
            gitLsRemoteTags: (url) async => {'1.0.0': 'sha1'},
          ),
        );

        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - c\n'
          '  dependencies:\n'
          '    c:\n'
          '      git: https://example.com/c.git\n'
          '      version: ^2.0.0\n',
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
          '  dependencies:\n'
          '    c:\n'
          '      git: https://example.com/c.git\n'
          '      version: ^1.0.0\n',
        );
        await runSync(
          makeCmd(
            gitCloner: clonerWriting({'dna/src/x.md': 'X'}),
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
          '  dependencies:\n'
          '    c:\n'
          '      git: https://example.com/c.git\n',
        );
        await runSync(
          makeCmd(
            gitCloner: clonerWriting({'dna/src/x.md': 'X'}),
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
        writeFile(p.join(tmp.path, 'layerA', 'dna', 'src', 'x.md'), 'X');
        writePubspec(
          'dna:\n'
          '  order:\n'
          '    - a\n'
          '  dependencies:\n'
          '    a:\n'
          '      path: ../layerA\n',
        );
        await runSync(makeCmd());

        // Layer changed.
        writeFile(p.join(tmp.path, 'layerA', 'dna', 'src', 'x.md'), 'X2');
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
    group('config: claude:', () {
      const claudeConfig = '  config:\n'
          '    claude:\n'
          '      claude_md:\n'
          '        include:\n'
          '          - dna/agents/conventions\n'
          '          - project_structure.md\n'
          '      skills:\n'
          '        include:\n'
          '          - dna/agents/skills\n';

      void writeClaudeSources() {
        writeFile(
          p.join(pkgDna.path, 'agents', 'conventions', 'code-conventions.md'),
          '# code',
        );
        final skillsSrc = Directory(p.join(pkgDna.path, 'agents', 'skills'))
          ..createSync(recursive: true);
        writeSkillIn(skillsSrc, 'new-project');
        writeSkillIn(skillsSrc, 'simplify');
        writeFile(p.join(target.path, 'project_structure.md'), '# structure');
      }

      test('writes the CLAUDE.md block and installs skills from the config',
          () async {
        writeClaudeSources();
        writePubspec('dna:\n  order: []\n$claudeConfig');

        await runSync(makeCmd());

        final claudeMd =
            File(p.join(target.path, 'CLAUDE.md')).readAsStringSync();
        expect(claudeMd, contains(claudeMdStartMarker));
        expect(
          claudeMd,
          contains('@dna/agents/conventions/code-conventions.md'),
        );
        expect(claudeMd, contains('@project_structure.md'));

        final claudeSkills =
            Directory(p.join(target.path, '.claude', 'skills'));
        expect(
          File(p.join(claudeSkills.path, 'new-project', 'SKILL.md'))
              .existsSync(),
          isTrue,
        );
        expect(
          File(p.join(claudeSkills.path, 'simplify', 'SKILL.md')).existsSync(),
          isTrue,
        );

        final manifest = DnaManifest.read(
          Directory(p.join(target.path, 'dna')),
        );
        expect(
          manifest!.claude.installedSkills,
          ['new-project', 'simplify'],
        );
        expect(
          manifest.claude.claudeMdInclude,
          ['dna/agents/conventions', 'project_structure.md'],
        );

        // The claude phase keeps --check green.
        messages.clear();
        await runSync(makeCmd(), extra: ['--check']);
        expect(messages.last, contains('up to date'));
      });

      test('keeps hand-written CLAUDE.md content around the block', () async {
        writeClaudeSources();
        writeFile(
          p.join(target.path, 'CLAUDE.md'),
          '# Mine\n\nKeep me.\n',
        );
        writePubspec('dna:\n  order: []\n$claudeConfig');

        await runSync(makeCmd());

        final claudeMd =
            File(p.join(target.path, 'CLAUDE.md')).readAsStringSync();
        expect(claudeMd, startsWith('# Mine\n\nKeep me.\n'));
        expect(claudeMd, contains('@project_structure.md'));
      });

      test('removes skills that are no longer configured, keeps foreign ones',
          () async {
        writeClaudeSources();
        writePubspec('dna:\n  order: []\n$claudeConfig');
        await runSync(makeCmd());

        // A hand-installed skill appears next to the managed ones.
        writeFile(
          p.join(target.path, '.claude', 'skills', 'mine', 'SKILL.md'),
          '# mine',
        );

        // The skills section disappears from the config.
        writePubspec(
          'dna:\n'
          '  order: []\n'
          '  config:\n'
          '    claude:\n'
          '      claude_md:\n'
          '        include:\n'
          '          - project_structure.md\n',
        );
        await runSync(makeCmd());

        expect(
          Directory(p.join(target.path, '.claude', 'skills', 'new-project'))
              .existsSync(),
          isFalse,
        );
        expect(
          Directory(p.join(target.path, '.claude', 'skills', 'simplify'))
              .existsSync(),
          isFalse,
        );
        expect(
          File(p.join(target.path, '.claude', 'skills', 'mine', 'SKILL.md'))
              .existsSync(),
          isTrue,
        );
        expect(
          messages.any((m) => m.contains('removed skill new-project')),
          isTrue,
        );

        final manifest = DnaManifest.read(
          Directory(p.join(target.path, 'dna')),
        );
        expect(manifest!.claude.installedSkills, isEmpty);
      });

      test('never overwrites a hand-installed skill with the same name',
          () async {
        writeClaudeSources();
        writeFile(
          p.join(target.path, '.claude', 'skills', 'simplify', 'SKILL.md'),
          '# handmade',
        );
        writePubspec('dna:\n  order: []\n$claudeConfig');

        await runSync(makeCmd());

        expect(
          File(p.join(target.path, '.claude', 'skills', 'simplify', 'SKILL.md'))
              .readAsStringSync(),
          '# handmade',
        );
        expect(
          messages.any((m) => m.contains('not installed by gg_dna')),
          isTrue,
        );
        final manifest = DnaManifest.read(
          Directory(p.join(target.path, 'dna')),
        );
        expect(manifest!.claude.installedSkills, ['new-project']);
      });

      test('without config: claude: neither CLAUDE.md nor .claude appear',
          () async {
        writeClaudeSources();
        writePubspec('dna:\n  order: []\n');

        await runSync(makeCmd());

        expect(File(p.join(target.path, 'CLAUDE.md')).existsSync(), isFalse);
        expect(
          Directory(p.join(target.path, '.claude')).existsSync(),
          isFalse,
        );
      });

      test('throws when a claude_md include is missing after the sync',
          () async {
        writeFile(p.join(pkgDna.path, 'guides', 'a.md'), 'A');
        writePubspec(
          'dna:\n'
          '  order: []\n'
          '  config:\n'
          '    claude:\n'
          '      claude_md:\n'
          '        include:\n'
          '          - does-not-exist.md\n',
        );

        await expectLater(
          runSync(makeCmd()),
          throwsA(
            isA<Exception>().having(
              (e) => '$e',
              'message',
              contains('does-not-exist.md'),
            ),
          ),
        );
      });

      test('--check detects claude config drift, block and skill drift',
          () async {
        writeClaudeSources();
        writePubspec('dna:\n  order: []\n$claudeConfig');
        await runSync(makeCmd());

        // 1) Config drift: include list changed after the sync.
        writePubspec(
          'dna:\n'
          '  order: []\n'
          '  config:\n'
          '    claude:\n'
          '      claude_md:\n'
          '        include:\n'
          '          - project_structure.md\n',
        );
        messages.clear();
        await expectLater(
          runSync(makeCmd(), extra: ['--check']),
          throwsA(isA<Exception>()),
        );
        expect(
          messages.any((m) => m.contains('claude config changed')),
          isTrue,
        );

        // Restore the config for the remaining checks.
        writePubspec('dna:\n  order: []\n$claudeConfig');

        // 2) Someone edited the managed block.
        final claudeMdFile = File(p.join(target.path, 'CLAUDE.md'));
        final original = claudeMdFile.readAsStringSync();
        claudeMdFile.writeAsStringSync(
          original.replaceAll('@project_structure.md', '@tampered.md'),
        );
        messages.clear();
        await expectLater(
          runSync(makeCmd(), extra: ['--check']),
          throwsA(isA<Exception>()),
        );
        expect(
          messages.any((m) => m.contains('CLAUDE.md block out of date')),
          isTrue,
        );
        claudeMdFile.writeAsStringSync(original);

        // 3) CLAUDE.md deleted entirely.
        claudeMdFile.deleteSync();
        messages.clear();
        await expectLater(
          runSync(makeCmd(), extra: ['--check']),
          throwsA(isA<Exception>()),
        );
        expect(messages.any((m) => m.contains('missing')), isTrue);
        claudeMdFile.writeAsStringSync(original);

        // 4) An owned skill was modified locally.
        final skillFile = File(
          p.join(target.path, '.claude', 'skills', 'simplify', 'SKILL.md'),
        );
        skillFile.writeAsStringSync('# tampered');
        messages.clear();
        await expectLater(
          runSync(makeCmd(), extra: ['--check']),
          throwsA(isA<Exception>()),
        );
        expect(
          messages.any((m) => m.contains('skill "simplify" is out of date')),
          isTrue,
        );

        // 5) An owned skill was deleted locally.
        skillFile.parent.deleteSync(recursive: true);
        messages.clear();
        await expectLater(
          runSync(makeCmd(), extra: ['--check']),
          throwsA(isA<Exception>()),
        );
        expect(
          messages.any((m) => m.contains('skill "simplify" is not installed')),
          isTrue,
        );

        // A fresh sync heals everything.
        await runSync(makeCmd());
        messages.clear();
        await runSync(makeCmd(), extra: ['--check']);
        expect(messages.last, contains('up to date'));

        // 6) A claude_md include vanished after the sync.
        File(p.join(target.path, 'project_structure.md')).deleteSync();
        messages.clear();
        await expectLater(
          runSync(makeCmd(), extra: ['--check']),
          throwsA(isA<Exception>()),
        );
        expect(
          messages.any((m) => m.contains('CLAUDE.md check failed')),
          isTrue,
        );
        writeFile(p.join(target.path, 'project_structure.md'), '# structure');

        // 7) One skill source vanished — its installed copy is an orphan.
        Directory(p.join(target.path, 'dna', 'agents', 'skills', 'simplify'))
            .deleteSync(recursive: true);
        messages.clear();
        await expectLater(
          runSync(makeCmd(), extra: ['--check']),
          throwsA(isA<Exception>()),
        );
        expect(
          messages.any(
            (m) => m.contains(
              'skill "simplify" is no longer configured but still installed',
            ),
          ),
          isTrue,
        );

        // 8) The whole skills source inside dna/ vanished.
        Directory(p.join(target.path, 'dna', 'agents', 'skills'))
            .deleteSync(recursive: true);
        messages.clear();
        await expectLater(
          runSync(makeCmd(), extra: ['--check']),
          throwsA(isA<Exception>()),
        );
        expect(
          messages.any((m) => m.contains('skills check failed')),
          isTrue,
        );
      });

      test('replaces a pre-3.0 conventions block in CLAUDE.md', () async {
        writeClaudeSources();
        writeFile(
          p.join(target.path, 'CLAUDE.md'),
          '# Mine\n'
          '\n'
          '$legacyConventionsStartMarker v=2026-01-01 -->\n'
          '@.claude/conventions/code-conventions.md\n'
          '$legacyConventionsEndMarker\n',
        );
        writePubspec('dna:\n  order: []\n$claudeConfig');

        await runSync(makeCmd());

        final claudeMd =
            File(p.join(target.path, 'CLAUDE.md')).readAsStringSync();
        expect(claudeMd, isNot(contains('gg_dna:conventions')));
        expect(claudeMd, contains(claudeMdStartMarker));
        expect(claudeMd, startsWith('# Mine\n'));
      });
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
