// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:typed_data';

import 'package:gg_dna/src/engine/instantiate.dart';
import 'package:gg_dna/src/util/dna_fs.dart';
import 'package:gg_dna/src/util/dna_manifest.dart';
import 'package:test/test.dart';

void main() {
  const root = '/t';

  /// Builds a target with base-dna and dna-dart installed via npm and a
  /// pubspec (Dart project → snake_case naming).
  MemoryDnaHost makeHost({Map<String, String> extra = const {}}) =>
      MemoryDnaHost(
        files: {
          '$root/pubspec.yaml': 'name: consumer\n'
              'dev_dependencies:\n  dna_dart: ^1.0.0\n',
          '$root/package.json': '{"devDependencies": '
              '{"dna-dart": "^1.0.0"}}',
          // base-dna (installed transitively) ..........................
          '$root/node_modules/base-dna/package.json':
              '{"name": "base-dna", "version": "1.0.0"}',
          '$root/node_modules/base-dna/dna/_vars.json':
              '{"copyrightHolder": "ggsuite", "projectName": "unnamed"}',
          '$root/node_modules/base-dna/dna/LICENSE':
              'MIT (c) dnaCopyrightHolder\n',
          '$root/node_modules/base-dna/dna/doc/develop.md': '''
# Develop

Package manager: {{@pm:npm}}.

## [@update] Update dependencies

Run {{@pm:npm}} update.
''',
          '$root/node_modules/base-dna/dna/.vscode/settings.json': '''
{
  // base settings
  "editor.rulers": [80],
  "files.trimTrailingWhitespace": true
}
''',
          '$root/node_modules/base-dna/dna/.vscode/extensions.json':
              '{"recommendations": ["esbenp.prettier-vscode"]}\n',
          // dna-dart ...................................................
          '$root/node_modules/dna-dart/package.json':
              '{"name": "dna-dart", "version": "1.0.0", '
                  '"dependencies": {"base-dna": "^1.0.0"}}',
          '$root/node_modules/dna-dart/dna/doc/develop.overrides.md': '''
## [@update] Update dependencies

Run dart pub upgrade.

<!-- @pm --> dart pub <!-- @pm -->
''',
          '$root/node_modules/dna-dart/dna/.vscode/settings.overrides.json':
              '{"dart.showTodos": false}',
          '$root/node_modules/dna-dart/dna/.vscode/extensions.overrides.json':
              '{"recommendations+": ["dart-code.dart-code"]}',
          '$root/node_modules/dna-dart/dna/test/dna/dna-test.dart':
              '// dnaProjectName test wrapper\n',
          ...extra,
        },
      );

  group('instantiateDna — end to end', () {
    test('merges layers, renders, substitutes, instantiates', () {
      final host = makeHost(
        extra: {
          '$root/.gg/dna.json': '{"vars": {"projectName": "my_project"}}',
        },
      );
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '5.0.0',
      );
      expect(r.modifiedInstances, isEmpty);
      expect(r.blocked, isFalse);
      expect(r.updated, isNotEmpty);

      // dna/ is generated: markers rendered, overrides applied.
      final develop = host.readString('$root/dna/doc/develop.md');
      expect(develop, contains('Run dart pub upgrade.'));
      expect(develop, contains('Package manager: dart pub.'));
      expect(develop, isNot(contains('[@update]')));
      expect(develop, isNot(contains('{{@pm')));

      // Instance: doc/develop.md (public).
      expect(host.existsFile('$root/doc/develop.md'), isTrue);

      // JSON deep merge + array join.
      final settings = host.readString('$root/.vscode/settings.json');
      expect(settings, contains('"editor.rulers"'));
      expect(settings, contains('"dart.showTodos": false'));
      final extensions = host.readString('$root/.vscode/extensions.json');
      expect(extensions, contains('esbenp.prettier-vscode'));
      expect(extensions, contains('dart-code.dart-code'));

      // Variables: verbatim value, config var wins, naming converted.
      expect(
        host.readString('$root/LICENSE'),
        contains('MIT (c) ggsuite'),
      );
      expect(host.existsFile('$root/test/dna/dna_test.dart'), isTrue);
      expect(
        host.readString('$root/test/dna/dna_test.dart'),
        contains('myProject test wrapper'),
      );

      // Private files stay in dna/.
      expect(host.existsFile('$root/_vars.json'), isFalse);
      expect(host.existsFile('$root/dna/_vars.json'), isTrue);
      expect(
        host.readString('$root/dna/_vars.json'),
        contains('"projectName": "my_project"'),
      );

      // Sidecars are consumed.
      expect(
        host.existsFile('$root/dna/.vscode/settings.overrides.json'),
        isFalse,
      );
      expect(
        host.existsFile('$root/.vscode/settings.overrides.json'),
        isFalse,
      );

      // Manifest v5 with recursive layer info.
      final manifest = DnaManifest.read(host, root)!;
      expect(manifest.layers.map((l) => l.name).toList(), [
        'base-dna',
        'dna-dart',
      ]);
      expect(manifest.layers.first.via, 'dna-dart');
      expect(
        manifest.instances.map((i) => i.path),
        contains('.vscode/settings.json'),
      );
      expect(manifest.vars!['projectName'], 'my_project');
      expect(manifest.hash, isNotNull);

      // Second run is a no-op.
      final second = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '5.0.0',
      );
      expect(second.upToDate, isTrue);
    });

    test('golden update: DNA change rewrites instances and reports once', () {
      final host = makeHost();
      instantiateDna(host: host, targetRoot: root, baseVersion: '5.0.0');

      host.writeString(
        '$root/node_modules/base-dna/dna/.vscode/extensions.json',
        '{"recommendations": ["esbenp.prettier-vscode", "new.extension"]}\n',
      );
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '5.0.0',
      );
      expect(r.updated, contains('.vscode/extensions.json'));
      expect(
        host.readString('$root/.vscode/extensions.json'),
        contains('new.extension'),
      );
      final third = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '5.0.0',
      );
      expect(third.upToDate, isTrue);
    });

    test('hand-modified instances fail without any writes', () {
      final host = makeHost();
      instantiateDna(host: host, targetRoot: root, baseVersion: '5.0.0');

      host.writeString('$root/.vscode/settings.json', '{"hacked": true}');
      final before = Map.of(host.files);
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '5.0.0',
      );
      expect(r.modifiedInstances, ['.vscode/settings.json']);
      expect(r.updated, isEmpty);
      expect(host.files, before);
      // The report names the DNA file to edit instead — here the sidecar
      // of the last contributing layer.
      expect(
        r.sources['.vscode/settings.json'],
        'dna-dart/dna/.vscode/settings.overrides.json',
      );
    });

    test('sources name the DNA file behind every reported path', () {
      final host = makeHost();
      instantiateDna(host: host, targetRoot: root, baseVersion: '5.0.0');

      // A plain file comes from the layer that shipped it last …
      host.writeString('$root/LICENSE', 'hand edited\n');
      // … a generated dna/ file from the same source.
      host.writeString('$root/dna/doc/develop.md', 'hand edited\n');
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '5.0.0',
      );
      expect(r.sources['LICENSE'], 'base-dna/dna/LICENSE');
      expect(
        r.modifiedInstances,
        contains('LICENSE'),
      );

      // Markdown overrides win over the base file they patch.
      final fresh = makeHost();
      instantiateDna(host: fresh, targetRoot: root, baseVersion: '5.0.0');
      fresh.writeString('$root/doc/develop.md', 'hand edited\n');
      final r2 = instantiateDna(
        host: fresh,
        targetRoot: root,
        baseVersion: '5.0.0',
      );
      expect(
        r2.sources['doc/develop.md'],
        'dna-dart/dna/doc/develop.overrides.md',
      );
    });

    test('sources name the package as installed, not the identity', () {
      final host = MemoryDnaHost(
        files: {
          '$root/pubspec.yaml': 'name: consumer\n'
              'dev_dependencies:\n  base_dna: ^1.0.0\n',
          '$root/.dart_tool/package_config.json': '{"packages": [ '
              '{"name": "base_dna", "rootUri": "../../cache/base_dna"}]}',
          '/cache/base_dna/pubspec.yaml': 'name: base_dna\nversion: 1.0.0\n',
          '/cache/base_dna/dna/LICENSE': 'MIT\n',
        },
      );
      instantiateDna(host: host, targetRoot: root, baseVersion: '5.0.0');
      host.writeString('$root/LICENSE', 'hand edited\n');
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '5.0.0',
      );
      expect(r.sources['LICENSE'], 'base_dna/dna/LICENSE');
    });

    test('path overrides are shown as the local folder to open', () {
      final host = MemoryDnaHost(
        files: {
          '$root/pubspec.yaml': 'name: consumer\n',
          '$root/.gg/dna.json': '{"order": ["local-dna"], "dependencies": '
              '{"local-dna": {"path": "../local-dna"}}}',
          '$root/../local-dna/dna/LICENSE': 'MIT\n',
        },
      );
      instantiateDna(host: host, targetRoot: root, baseVersion: '5.0.0');
      host.writeString('$root/LICENSE', 'hand edited\n');
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '5.0.0',
      );
      expect(r.sources['LICENSE'], '../local-dna/dna/LICENSE');
    });

    test('a hand-fix moved into the DNA heals the modified state', () {
      final host = makeHost();
      instantiateDna(host: host, targetRoot: root, baseVersion: '5.0.0');

      // User edits the instance by hand → fail.
      host.writeString('$root/LICENSE', 'MIT (c) ggsuite — edited\n');
      final failed = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '5.0.0',
      );
      expect(failed.modifiedInstances, ['LICENSE']);

      // User moves the change into the DNA source instead.
      host.writeString(
        '$root/node_modules/base-dna/dna/LICENSE',
        'MIT (c) dnaCopyrightHolder — edited\n',
      );
      final healed = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '5.0.0',
      );
      expect(healed.modifiedInstances, isEmpty);
      expect(healed.updated, isNotEmpty);
    });

    test('unrelated dirty files never block the run', () {
      final host = makeHost(
        extra: {'$root/lib/my_code.dart': 'void main() {}'},
      );
      host.uncommitted.addAll(['lib/my_code.dart', 'README.md']);
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '5.0.0',
      );
      expect(r.blocked, isFalse);
      expect(r.updated, isNotEmpty);
      expect(host.existsFile('$root/LICENSE'), isTrue);
    });

    test('an uncommitted file that would be overwritten blocks', () {
      final host = makeHost();
      instantiateDna(host: host, targetRoot: root, baseVersion: '5.0.0');

      // The DNA changes and the target instance is dirty at the same time.
      host.writeString(
        '$root/node_modules/base-dna/dna/LICENSE',
        'MIT (c) dnaCopyrightHolder — new\n',
      );
      host.uncommitted.add('LICENSE');
      final before = Map.of(host.files);
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '5.0.0',
      );
      expect(r.blocked, isTrue);
      expect(r.uncommittedTargets, ['LICENSE']);
      expect(r.updated, isEmpty);
      expect(host.files, before);
      expect(r.messages, contains(uncommittedTargetsMessage));
      expect(r.sources['LICENSE'], 'base-dna/dna/LICENSE');
    });

    test('an uncommitted file that is only created does not block', () {
      // The instance does not exist yet — nothing can be lost.
      final host = makeHost();
      host.uncommitted.add('LICENSE');
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '5.0.0',
      );
      expect(r.blocked, isFalse);
      expect(host.existsFile('$root/LICENSE'), isTrue);
    });

    test('an untracked existing file is protected from adoption', () {
      final host = makeHost(
        extra: {'$root/.vscode/settings.json': '{"mine": true}'},
      );
      host.uncommitted.add('.vscode/settings.json');
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '5.0.0',
      );
      expect(r.uncommittedTargets, ['.vscode/settings.json']);
      expect(host.readString('$root/.vscode/settings.json'), '{"mine": true}');
    });

    test('the guard is skipped when everything is up to date', () {
      final host = makeHost();
      instantiateDna(host: host, targetRoot: root, baseVersion: '5.0.0');
      host.uncommitted.addAll(['LICENSE', '.vscode/settings.json']);
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '5.0.0',
      );
      expect(r.upToDate, isTrue);
    });

    test('adopts existing project files (git is the backup)', () {
      final host = makeHost(
        extra: {'$root/.vscode/settings.json': '{"mine": true}'},
      );
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '5.0.0',
      );
      expect(
        r.messages.any((m) => m.contains('adopted .vscode/settings.json')),
        isTrue,
      );
      expect(
        host.readString('$root/.vscode/settings.json'),
        isNot(contains('mine')),
      );
    });

    test('removes owned instances no longer produced, keeps modified ones', () {
      final host = makeHost();
      instantiateDna(host: host, targetRoot: root, baseVersion: '5.0.0');

      // The DNA stops shipping the extensions file.
      host.deleteFile(
        '$root/node_modules/base-dna/dna/.vscode/extensions.json',
      );
      host.deleteFile(
        '$root/node_modules/dna-dart/dna/.vscode/extensions.overrides.json',
      );
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '5.0.0',
      );
      expect(host.existsFile('$root/.vscode/extensions.json'), isFalse);
      expect(
        r.updated.any((u) => u.contains('.vscode/extensions.json')),
        isTrue,
      );

      // Same situation, but the user modified the instance → kept.
      final host2 = makeHost();
      instantiateDna(host: host2, targetRoot: root, baseVersion: '5.0.0');
      host2.writeString('$root/.vscode/extensions.json', '{"mine": 1}');
      host2.deleteFile(
        '$root/node_modules/base-dna/dna/.vscode/extensions.json',
      );
      host2.deleteFile(
        '$root/node_modules/dna-dart/dna/.vscode/extensions.overrides.json',
      );
      final r2 = instantiateDna(
        host: host2,
        targetRoot: root,
        baseVersion: '5.0.0',
      );
      expect(host2.existsFile('$root/.vscode/extensions.json'), isTrue);
      expect(
        r2.warnings.any((w) => w.contains('remove manually')),
        isTrue,
      );
    });

    test('role dna: own dna/ is the last layer and never overwritten', () {
      final host = MemoryDnaHost(
        files: {
          '$root/package.json': '{"name": "dna-dart", "version": "1.0.0", '
              '"dependencies": {"base-dna": "^1.0.0"}}',
          '$root/.gg/dna.json': '{"role": "dna"}',
          '$root/node_modules/base-dna/package.json':
              '{"name": "base-dna", "version": "1.0.0"}',
          '$root/node_modules/base-dna/dna/doc/develop.md': '# Base\n',
          '$root/node_modules/base-dna/dna/LICENSE': 'MIT\n',
          '$root/dna/doc/develop.md': '# Own version\n',
          '$root/dna/.vscode/settings.json': '{"a": 1}\n',
        },
      );
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '5.0.0',
      );
      expect(r.modifiedInstances, isEmpty);

      // Own dna/ untouched (authored), own content wins in instances.
      expect(host.readString('$root/dna/doc/develop.md'), '# Own version\n');
      expect(host.readString('$root/doc/develop.md'), '# Own version\n');
      expect(host.existsFile('$root/.vscode/settings.json'), isTrue);
      expect(host.existsFile('$root/LICENSE'), isTrue);

      final manifest = DnaManifest.read(host, root)!;
      expect(manifest.hash, isNull);
      expect(manifest.layers.map((l) => l.name), contains('self'));

      final second = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '5.0.0',
      );
      expect(second.upToDate, isTrue);
    });

    test('camelCase naming for package.json-only projects', () {
      final host = MemoryDnaHost(
        files: {
          '$root/package.json': '{"devDependencies": {"dna-ts": "^1.0.0"}}',
          '$root/node_modules/dna-ts/package.json':
              '{"name": "dna-ts", "version": "1.0.0"}',
          '$root/node_modules/dna-ts/dna/test/dna/my-spec-helper.ts':
              '// helper\n',
        },
      );
      instantiateDna(host: host, targetRoot: root, baseVersion: '5.0.0');
      expect(
        host.existsFile('$root/test/dna/mySpecHelper.ts'),
        isTrue,
      );
    });

    test('renamed references are rewritten in instances only', () {
      final host = MemoryDnaHost(
        files: {
          '$root/pubspec.yaml': 'name: x\n',
          '$root/package.json': '{"devDependencies": {"a-dna": "1"}}',
          '$root/node_modules/a-dna/package.json':
              '{"name": "a-dna", "version": "1.0.0"}',
          '$root/node_modules/a-dna/dna/scripts/create-branch.js':
              'console.log("hi");\n',
          '$root/node_modules/a-dna/dna/doc/develop.md':
              'Run node scripts/create-branch.js\n',
        },
      );
      instantiateDna(host: host, targetRoot: root, baseVersion: '5.0.0');
      expect(host.existsFile('$root/scripts/create_branch.js'), isTrue);
      expect(
        host.readString('$root/doc/develop.md'),
        'Run node scripts/create_branch.js\n',
      );
      // dna/ originals keep canonical names and references.
      expect(host.existsFile('$root/dna/scripts/create-branch.js'), isTrue);
      expect(
        host.readString('$root/dna/doc/develop.md'),
        'Run node scripts/create-branch.js\n',
      );
    });

    test('writes the managed CLAUDE.md block from projected instances', () {
      final host = makeHost(
        extra: {
          '$root/.gg/dna.json': '{"config": {"claude": '
              '{"claude_md": {"include": ["doc"]}}}}',
          '$root/CLAUDE.md': '# My project\n',
        },
      );
      instantiateDna(host: host, targetRoot: root, baseVersion: '5.0.0');
      final claude = host.readString('$root/CLAUDE.md');
      expect(claude, contains('# My project'));
      expect(claude, contains('@doc/develop.md'));
      expect(claude, contains('<!-- gg_dna:claude_md:start -->'));
    });

    test('yaml overrides and legacy .tag.md files are hard errors', () {
      final yamlHost = makeHost(
        extra: {
          '$root/node_modules/dna-dart/dna/a.overrides.yaml': 'x: 1',
        },
      );
      expect(
        () => instantiateDna(
          host: yamlHost,
          targetRoot: root,
          baseVersion: '5.0.0',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('YAML overrides'),
          ),
        ),
      );

      final tagHost = makeHost(
        extra: {'$root/node_modules/dna-dart/dna/doc/x.tag.md': 'x'},
      );
      expect(
        () => instantiateDna(
          host: tagHost,
          targetRoot: root,
          baseVersion: '5.0.0',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('.tag.md'),
          ),
        ),
      );
    });

    test('override without target logs a skip message', () {
      final host = makeHost(
        extra: {
          '$root/node_modules/dna-dart/dna/doc/missing.overrides.md':
              '<!-- @x --> y <!-- @x -->',
        },
      );
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '5.0.0',
      );
      expect(
        r.messages.any((m) => m.contains('has no target file')),
        isTrue,
      );
    });

    test('forbidden instance targets are skipped with a warning', () {
      final host = makeHost(
        extra: {
          '$root/node_modules/dna-dart/dna/CLAUDE.md': '# no\n',
          '$root/node_modules/dna-dart/dna/.git/config': 'x\n',
        },
      );
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '5.0.0',
      );
      // `.git/**` never even enters the merge (it is not dna content),
      // CLAUDE.md is dropped at instance planning time.
      expect(
        r.warnings.where((w) => w.contains('forbidden')).single,
        contains('CLAUDE.md'),
      );
      expect(host.existsFile('$root/CLAUDE.md'), isFalse);
      expect(host.existsFile('$root/dna/.git/config'), isFalse);
    });

    test('instance name collisions are a hard error', () {
      final host = makeHost(
        extra: {
          '$root/node_modules/dna-dart/dna/doc/my-note.md': 'a\n',
          '$root/node_modules/dna-dart/dna/doc/my_note.md': 'b\n',
        },
      );
      expect(
        () => instantiateDna(
          host: host,
          targetRoot: root,
          baseVersion: '5.0.0',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Instance collision'),
          ),
        ),
      );
    });

    test('a deleted instance is restored, an identical one adopted', () {
      final host = makeHost();
      instantiateDna(host: host, targetRoot: root, baseVersion: '5.0.0');

      host.deleteFile('$root/LICENSE');
      final restored = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '5.0.0',
      );
      expect(
        restored.messages.any((m) => m.contains('restored missing LICENSE')),
        isTrue,
      );

      // A foreign file that already equals the DNA output is adopted
      // silently — no write, just a log line.
      final fresh = makeHost(
        extra: {'$root/LICENSE': 'MIT (c) ggsuite\n'},
      );
      final adopted = instantiateDna(
        host: fresh,
        targetRoot: root,
        baseVersion: '5.0.0',
      );
      expect(
        adopted.messages.any(
          (m) => m.contains('adopted LICENSE (already up to date)'),
        ),
        isTrue,
      );
    });

    test('global.overrides.md rewrites string tags across all files', () {
      final host = makeHost(
        extra: {
          '$root/node_modules/base-dna/dna/doc/other.md':
              'Manager: {{@pm:npm}}\n',
          '$root/node_modules/dna-dart/dna/global.overrides.md':
              '<!-- @pm --> dart pub <!-- @pm -->\n',
        },
      );
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '5.0.0',
      );
      expect(host.readString('$root/doc/other.md'), 'Manager: dart pub\n');
      expect(r.warnings.where((w) => w.contains('global')), isEmpty);
    });

    test('global overrides warn about heading blocks and dead tags', () {
      final host = makeHost(
        extra: {
          '$root/node_modules/dna-dart/dna/global.overrides.md': '''
## [@section] A heading block

Not allowed globally.

<!-- @unused --> nothing matches <!-- @unused -->
''',
          // A nested global override file is ignored with a warning.
          '$root/node_modules/dna-dart/dna/doc/global.overrides.md':
              '<!-- @x --> y <!-- @x -->\n',
        },
      );
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '5.0.0',
      );
      expect(
        r.warnings.any((w) => w.contains('heading-form block')),
        isTrue,
      );
      expect(
        r.warnings.any((w) => w.contains('"unused" matches nothing')),
        isTrue,
      );
      expect(
        r.warnings.any((w) => w.contains('only supported at')),
        isTrue,
      );
    });

    test('json overrides without a target log a skip message', () {
      final host = makeHost(
        extra: {
          '$root/node_modules/dna-dart/dna/.vscode/missing.overrides.json':
              '{"a": 1}',
        },
      );
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '5.0.0',
      );
      expect(
        r.messages.any(
          (m) =>
              m.contains('missing.overrides.json') &&
              m.contains('has no target file'),
        ),
        isTrue,
      );
    });

    test('binary and non-utf8 files are copied byte-identical', () {
      final host = makeHost();
      final binary = Uint8List.fromList([0x89, 0x50, 0x00, 0x01, 0xFF]);
      final latin1 = Uint8List.fromList([0xE4, 0xF6, 0xFC]);
      host.writeBytes(
        '$root/node_modules/dna-dart/dna/doc/logo.png',
        binary,
      );
      host.writeBytes(
        '$root/node_modules/dna-dart/dna/doc/legacy.txt',
        latin1,
      );
      instantiateDna(host: host, targetRoot: root, baseVersion: '5.0.0');
      expect(host.readBytes('$root/doc/logo.png'), binary);
      expect(host.readBytes('$root/doc/legacy.txt'), latin1);
    });

    test('base DNA of gg_dna itself is layer 0', () {
      final host = makeHost(
        extra: {
          '/gg/dna/doc/base-doc.md': '# From gg_dna base\n',
        },
      );
      instantiateDna(
        host: host,
        targetRoot: root,
        baseDnaRoot: '/gg',
        baseVersion: '5.0.0',
      );
      expect(host.existsFile('$root/dna/doc/base-doc.md'), isTrue);
      expect(host.existsFile('$root/doc/base_doc.md'), isTrue);
      final manifest = DnaManifest.read(host, root)!;
      expect(manifest.layers.first.name, 'base');
      expect(manifest.baseHash, isNotNull);
    });
  });
}
