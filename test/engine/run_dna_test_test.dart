// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_dna/gg_dna.dart';
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
          '$root/node_modules/a-dna/package.json':
              '{"name": "a-dna", "version": "1.0.0"}',
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

    test('files stay for a manual commit when git cannot commit', () async {
      final host = makeHost()..commitError = 'no git identity';
      await expectLater(
        () => run(host),
        throwsA(
          isA<Exception>().having(
            (e) => '$e',
            'message',
            allOf(contains('need a commit'), contains('LICENSE')),
          ),
        ),
      );
      expect(host.existsFile('$root/LICENSE'), isTrue);
      expect(log.any((m) => m.contains('Could not commit')), isTrue);
    });

    test('reports hand-modified files with their DNA source', () async {
      final host = makeHost();
      await run(host);
      host.writeString('$root/doc/hello.md', 'hand edited\n');

      await expectLater(
        () => run(host),
        throwsA(
          isA<Exception>().having(
            (e) => '$e',
            'message',
            allOf(
              contains('modified by hand'),
              contains('Move edits from'),
              contains('doc/hello.md'),
              contains('a-dna/dna/doc/hello.md'),
            ),
          ),
        ),
      );
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
        extra: {'$root/.gg/dna.json': '{"unknownKey": 1}'},
      );
      await run(host);
      expect(log.any((m) => m.startsWith('warning: ')), isTrue);
    });

    test('defaults target root and base DNA when not given', () async {
      // The in-memory host keeps this side-effect free: the defaults
      // (current directory, resolved gg_dna package root) are exercised,
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
      tmp = Directory.systemTemp.createTempSync('gg_dna_run_test_');
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
      // stay for a manual commit.
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
            contains('need a commit'),
          ),
        ),
      );
      expect(File('$target/dna/_dna.json').existsSync(), isTrue);
    });
  });

  group('ggDnaPackageRoot', () {
    test('resolves the installed gg_dna package root', () async {
      final path = await ggDnaPackageRoot();
      expect(path, isNot(contains(r'\')));
      expect(path.endsWith('gg_dna'), isTrue, reason: path);
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
      expect(cError(modifiedInstancesMessage), isNot(report));
    });

    test('paths without a DNA source are just committed', () {
      expect(
        plain(describeDnaSources(['dna/_dna.json'], const {})),
        'Commit or stash dna/_dna.json.',
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
      expect(modifiedInstancesMessage, 'Generated files modified by hand:');
      expect(
        uncommittedTargetsMessage,
        'Generated files carry invalid changes:',
      );
    });
  });
}
