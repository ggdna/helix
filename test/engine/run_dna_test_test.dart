// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:helix/helix.dart';
import 'package:helix/src/util/dna_layout.dart';
import 'package:test/test.dart';

void main() {
  const root = '/t';
  final log = <String>[];

  setUp(log.clear);

  /// A consumer with one DNA layer shipping a LICENSE and a doc.
  MemoryDnaHost makeHost({Map<String, String> extra = const {}}) =>
      MemoryDnaHost(
        files: {
          '$root/package.json': '{"devDependencies": {"a-dna": "^1.0.0"}}',
          '$root/dna/_dna.json': '{"version": 1, "layers": ["a-dna"]}',
          '$root/node_modules/a-dna/package.json':
              '{"name": "a-dna", "version": "1.0.0"}',
          '$root/node_modules/a-dna/dna/_dna.json':
              '{"version": 1, "role": "dna"}',
          '$root/node_modules/a-dna/dna/LICENSE': 'MIT\n',
          '$root/node_modules/a-dna/dna/doc/hello.md': '# Hello\n',
          ...extra,
        },
      );

  Future<void> run(MemoryDnaHost host) => runDnaTest(
    targetRoot: root,
    host: host,
    baseDnaRoot: '/no-base',
    log: log.add,
  );

  group('runDnaTest', () {
    test('first run instantiates, commits and passes', () async {
      final host = makeHost();
      await run(host);

      expect(host.existsFile('$root/LICENSE'), isTrue);
      expect(log.any((m) => m.contains('instantiated')), isTrue);
      // Everything generated is committed right away — the developer's
      // working tree stays clean.
      expect(host.commits.single.message, generatedDnaCommitMessage);
      expect(host.commits.single.paths, contains('LICENSE'));
      expect(log, contains('committed as "$generatedDnaCommitMessage"'));

      // The second run has nothing left to do.
      log.clear();
      await run(host);
      expect(host.commits, hasLength(1));
    });

    test('a variable without the dna prefix fails the run', () async {
      final host = makeHost(
        extra: {
          '$root/node_modules/a-dna/dna/_vars.json': '{"projectName": "p"}',
        },
      );
      await expectLater(
        () => run(host),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('projectName'), contains('dnaProjectName')),
          ),
        ),
      );
      // Nothing was written — the run stops while merging the layers.
      expect(host.existsFile('$root/LICENSE'), isFalse);
    });

    test('dot_ escapes in dna/ fail with a rename instruction', () async {
      final host = makeHost(extra: {'$root/dna/dot_vscode/tasks.json': '{}\n'});
      await expectLater(
        () => run(host),
        throwsA(
          isA<Exception>().having(
            (e) => '$e',
            'message',
            allOf(
              contains(invalidDotEscapesMessage),
              contains('dna/dot_vscode'),
              contains('dna/dot-vscode'),
            ),
          ),
        ),
      );
      // Nothing was written — the run stops before instantiating.
      expect(host.existsFile('$root/LICENSE'), isFalse);
    });

    test('dot- escapes and dot_ outside dna/ pass', () async {
      final host = makeHost(
        extra: {
          '$root/node_modules/a-dna/dna/dot-vscode/tasks.json': '{}\n',
          '$root/dot_elsewhere/x.txt': 'x\n',
        },
      );
      await run(host);
      expect(host.existsFile('$root/.vscode/tasks.json'), isTrue);
    });

    test('files stay for a manual commit when git cannot commit', () async {
      final host = makeHost()..commitError = 'no git identity';
      // Not being able to commit is reported, not a failure.
      await run(host);
      expect(host.existsFile('$root/LICENSE'), isTrue);
      expect(log.any((m) => m.contains('Could not commit')), isTrue);
    });

    test('backs up locally changed files and prints where they went', () async {
      final host = makeHost();
      await run(host);
      final generated = host.readString('$root/doc/hello.md');
      host.writeString('$root/doc/hello.md', 'hand edited\n');

      await run(host);

      expect(host.readString('$root/doc/hello.md'), generated);
      final backup = host.files.keys.firstWhere(
        (p) => p.contains(dnaBackupDirPrefix),
      );
      expect(backup, endsWith('/doc/hello.md'));
      expect(backup, isNot(startsWith('$root/')));
      expect(host.readString(backup), 'hand edited\n');
      expect(
        log.map((m) => m.replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '')),
        contains('Local changes of doc/hello.md were backed up to $backup'),
      );
      // The path is highlighted like every other file in the report.
      expect(log.any((m) => m.contains(cCmd(backup))), isTrue);
    });

    test('reports files with uncommitted work and their DNA source', () async {
      final host = makeHost(extra: {'$root/doc/hello.md': '# My notes\n'});
      host.uncommitted.add('doc/hello.md');

      await expectLater(
        () => run(host),
        throwsA(
          isA<Exception>().having(
            (e) => '$e',
            'message',
            allOf(
              contains('invalid changes'),
              contains('Move edits from'),
              contains('a-dna/dna/doc/hello.md'),
            ),
          ),
        ),
      );
      expect(host.readString('$root/doc/hello.md'), '# My notes\n');
    });

    test('fails when LICENSE is missing', () async {
      final host = MemoryDnaHost(
        files: {
          '$root/package.json': '{"devDependencies": {"a-dna": "^1.0.0"}}',
          '$root/node_modules/a-dna/package.json':
              '{"name": "a-dna", "version": "1.0.0"}',
          '$root/node_modules/a-dna/dna/doc/hello.md': '# Hello\n',
        },
      );
      await expectLater(
        () => run(host),
        throwsA(
          isA<Exception>().having(
            (e) => '$e',
            'message',
            contains('LICENSE is missing'),
          ),
        ),
      );
    });

    test('emits warnings and messages through the log', () async {
      final host = makeHost(
        extra: {
          '$root/dna/_dna.json':
              '{"version": 1, "layers": ["a-dna"], "unknownKey": 1}',
        },
      );
      await run(host);
      expect(log.any((m) => m.startsWith('warning: ')), isTrue);
    });

    test('defaults target root and base DNA when not given', () async {
      // The in-memory host keeps this side-effect free: the defaults
      // (current directory, resolved helix package root) are exercised,
      // but nothing is ever read from or written to the real repository.
      final host = MemoryDnaHost();
      await expectLater(
        () => runDnaTest(host: host, log: log.add),
        throwsA(
          isA<Exception>().having(
            (e) => '$e',
            'message',
            contains('LICENSE is missing'),
          ),
        ),
      );
      // Only the in-memory host was touched, never the real repository.
      expect(host.files.keys.every((p) => p.contains('/dna/')), isTrue);
    });
  });

  group('runDnaTest on the real file system', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('helix_run_test_');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('instantiates through the default IoDnaHost', () async {
      // No host injected — this covers the real platform binding. The
      // project is an isolated temp folder, never the repository.
      final target = '${tmp.path}/project';
      final emptyBase = '${tmp.path}/base';
      Directory(emptyBase).createSync(recursive: true);
      File('$target/pubspec.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('name: consumer\n');

      // The temp folder is no git repository, so the generated files
      // stay for a manual commit — reported through the log, not thrown.
      // What fails here is the missing LICENSE.
      await expectLater(
        () => runDnaTest(
          targetRoot: target,
          baseDnaRoot: emptyBase,
          log: log.add,
        ),
        throwsA(
          isA<Exception>().having(
            (e) => '$e',
            'message',
            contains('LICENSE is missing'),
          ),
        ),
      );
      expect(log.any((m) => m.contains('Could not commit')), isTrue);
      expect(File('$target/dna/_generated.json').existsSync(), isTrue);
    });
  });

  group('helixPackageRoot', () {
    test('resolves the installed helix package root', () async {
      final path = await helixPackageRoot();
      expect(path, isNot(contains(r'\')));
      expect(path.endsWith('helix'), isTrue, reason: path);
    });
  });

  group('describeDnaSources', () {
    String plain(String s) => s.replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '');

    test('tells where to move the edits, in one line per file', () {
      expect(
        plain(
          describeDnaSources(
            ['.vscode/settings.json'],
            {'.vscode/settings.json': 'dna/.vscode/settings.json'},
          ),
        ),
        'Move edits from .vscode/settings.json '
        'to dna/.vscode/settings.json.',
      );
    });

    test('colors the action and the files differently', () {
      final report = describeDnaSources(['a.md'], {'a.md': 'dna/a.md'});
      expect(report, contains(cAction('Move edits from')));
      expect(report, contains(cCmd('a.md')));
      expect(report, contains(cCmd('dna/a.md')));
    });

    test('paths without a DNA source are just committed', () {
      expect(
        plain(describeDnaSources(['dna/_generated.json'], const {})),
        'Commit or stash dna/_generated.json.',
      );
    });

    test('renders exactly one line per file', () {
      final report = plain(
        describeDnaSources(['a.md', 'b.md'], {'a.md': 'dna/a.md'}),
      );
      expect(report.split('\n'), hasLength(2));
    });
  });

  group('messages', () {
    test('are single-line headlines', () {
      expect(
        uncommittedTargetsMessage,
        'Generated files carry invalid changes:',
      );
    });
  });
}
