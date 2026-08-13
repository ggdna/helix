// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:helix/src/engine/instantiate.dart';
import 'package:helix/src/util/dna_config.dart';
import 'package:helix/src/util/dna_fs.dart';
import 'package:helix/src/util/dna_fs_io.dart';
import 'package:helix/src/util/dna_layout.dart';
import 'package:helix/src/util/dna_manifest.dart';
import 'package:test/test.dart';

void main() {
  const root = '/t';

  /// A `dna/_dna.json` of a DNA package with [layers] as its parents.
  String layerConfig([List<String> layers = const []]) =>
      '{"version": $dnaFormatVersion, "role": "dna", '
      '"layers": [${layers.map((l) => '"$l"').join(', ')}]}';

  /// Builds a target with dna-base and dna-dart installed via npm and a
  /// pubspec.
  MemoryDnaHost makeHost({Map<String, String> extra = const {}}) =>
      MemoryDnaHost(
        files: {
          '$root/pubspec.yaml': 'name: consumer\n'
              'dev_dependencies:\n  dna_dart: ^1.0.0\n',
          '$root/package.json': '{"devDependencies": '
              '{"dna-dart": "^1.0.0"}}',
          '$root/$dnaConfigPath':
              '{"version": $dnaFormatVersion, "layers": ["dna-dart"]}',
          // dna-base (installed transitively) ..........................
          '$root/node_modules/dna-base/package.json':
              '{"name": "dna-base", "version": "1.0.0"}',
          '$root/node_modules/dna-base/$dnaConfigPath': layerConfig(),
          '$root/node_modules/dna-base/dna/_vars.json':
              '{"dnaCopyrightHolder": "ggsuite", "dnaProjectName": "unnamed"}',
          '$root/node_modules/dna-base/dna/LICENSE':
              'MIT (c) dnaCopyrightHolder\n',
          '$root/node_modules/dna-base/dna/doc/develop.md': '''
# Develop

Package manager: {{@pm:npm}}.

## [@update] Update dependencies

Run {{@pm:npm}} update.
''',
          '$root/node_modules/dna-base/dna/dot-vscode/settings.json': '''
{
  // base settings
  "editor.rulers": [80],
  "files.trimTrailingWhitespace": true
}
''',
          '$root/node_modules/dna-base/dna/dot-vscode/extensions.json':
              '{"recommendations": ["esbenp.prettier-vscode"]}\n',
          // dna-dart ...................................................
          '$root/node_modules/dna-dart/package.json':
              '{"name": "dna-dart", "version": "1.0.0", '
                  '"dependencies": {"dna-base": "^1.0.0"}}',
          '$root/node_modules/dna-dart/$dnaConfigPath': layerConfig([
            'dna-base',
          ]),
          '$root/node_modules/dna-dart/dna/doc/develop.overrides.md': '''
## [@update] Update dependencies

Run dart pub upgrade.

<!-- @pm --> dart pub <!-- @pm -->
''',
          '$root/node_modules/dna-dart/dna/dot-vscode/settings.overrides.json':
              '{"dart.showTodos": false}',
          '$root/node_modules/dna-dart/dna/dot-vscode/extensions.overrides.json':
              '{"recommendations+": ["dart-code.dart-code"]}',
          '$root/node_modules/dna-dart/dna/test/dna/dna-test.dart':
              '// dnaProjectName test wrapper\n',
          ...extra,
        },
      );

  group('instantiateDna on the real file system', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('helix_prune_test_');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('a folder emptied by the DNA is removed as well', () {
      final host = IoDnaHost(git: (_, __) => '');
      final project = '${tmp.path}/project';
      final layer = '$project/node_modules/a-dna';
      host
        ..writeString('$layer/package.json', '{"name": "a-dna"}')
        ..writeString('$layer/$dnaConfigPath', layerConfig())
        ..writeString('$layer/dna/doc/keep.md', '# keep\n')
        ..writeString('$layer/dna/doc/guides/doomed.md', '# doomed\n')
        ..writeString('$project/pubspec.yaml', 'name: consumer\n')
        ..writeString(
          '$project/$dnaConfigPath',
          '{"version": $dnaFormatVersion, "layers": ["a-dna"]}',
        );

      instantiateDna(
        host: host,
        targetRoot: project,
        baseVersion: '4.0.0',
      );
      expect(Directory('$project/doc/guides').existsSync(), isTrue);

      // The DNA drops the only file of that folder …
      host.deleteFile('$layer/dna/doc/guides/doomed.md');
      final r = instantiateDna(
        host: host,
        targetRoot: project,
        baseVersion: '4.0.0',
      );

      // … so neither the instance nor its now empty folder survive —
      // in the project and in the generated dna/ replica.
      expect(File('$project/doc/guides/doomed.md').existsSync(), isFalse);
      expect(Directory('$project/doc/guides').existsSync(), isFalse);
      expect(Directory('$project/dna/doc/guides').existsSync(), isFalse);
      // Folders that still hold files stay.
      expect(File('$project/doc/keep.md').existsSync(), isTrue);
      expect(Directory('$project/doc').existsSync(), isTrue);
      expect(
        r.messages.any((m) => m.contains('removed empty folder doc/guides')),
        isTrue,
        reason: r.messages.join('\n'),
      );
    });

    test('the backup lands in a real system-temp folder', () {
      final host = IoDnaHost(git: (_, __) => '');
      final project = '${tmp.path}/project';
      final layer = '$project/node_modules/a-dna';
      host
        ..writeString('$layer/package.json', '{"name": "a-dna"}')
        ..writeString('$layer/$dnaConfigPath', layerConfig())
        ..writeString('$layer/dna/doc/keep.md', '# keep\n')
        ..writeString('$project/pubspec.yaml', 'name: consumer\n')
        ..writeString(
          '$project/$dnaConfigPath',
          '{"version": $dnaFormatVersion, "layers": ["a-dna"]}',
        );
      instantiateDna(host: host, targetRoot: project, baseVersion: '4.0.0');

      host.writeString('$project/doc/keep.md', '# edited by hand\n');
      final r = instantiateDna(
        host: host,
        targetRoot: project,
        baseVersion: '4.0.0',
      );

      expect(r.backedUp, ['doc/keep.md']);
      final backup = File('${r.backupDir}/doc/keep.md');
      addTearDown(() => Directory(r.backupDir!).deleteSync(recursive: true));
      expect(backup.readAsStringSync(), '# edited by hand\n');
      expect(File('$project/doc/keep.md').readAsStringSync(), '# keep\n');
      // Outside the project, below the system temp folder.
      expect(r.backupDir, isNot(contains(project)));
      expect(
        r.backupDir,
        startsWith(
          Directory.systemTemp.absolute.path.replaceAll(r'\', '/'),
        ),
      );
    });
  });

  group('instantiateDna — end to end', () {
    test('merges layers, renders, substitutes, instantiates', () {
      final host = makeHost(
        extra: {
          '$root/$dnaConfigPath': '{"version": $dnaFormatVersion, '
              '"layers": ["dna-dart"], '
              '"vars": {"dnaProjectName": "my_project"}}',
        },
      );
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '4.0.0',
      );
      expect(r.backedUp, isEmpty);
      expect(r.backupDir, isNull);
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

      // Variables: verbatim value, config var wins.
      expect(
        host.readString('$root/LICENSE'),
        contains('MIT (c) ggsuite'),
      );
      expect(host.existsFile('$root/test/dna/dna-test.dart'), isTrue);
      expect(
        host.readString('$root/test/dna/dna-test.dart'),
        contains('myProject test wrapper'),
      );

      // Private files stay in dna/.
      expect(host.existsFile('$root/_vars.json'), isFalse);
      expect(host.existsFile('$root/dna/_vars.json'), isTrue);
      expect(
        host.readString('$root/dna/_vars.json'),
        contains('"dnaProjectName": "my_project"'),
      );

      // Sidecars are consumed.
      expect(
        host.existsFile('$root/dna/dot-vscode/settings.overrides.json'),
        isFalse,
      );
      expect(
        host.existsFile('$root/.vscode/settings.overrides.json'),
        isFalse,
      );

      // Manifest v5 with recursive layer info.
      final manifest = DnaManifest.read(host, root)!;
      expect(manifest.layers.map((l) => l.name).toList(), [
        'dna-base',
        'dna-dart',
      ]);
      expect(manifest.layers.first.via, 'dna-dart');
      expect(
        manifest.instances.map((i) => i.path),
        contains('.vscode/settings.json'),
      );
      expect(manifest.hash, isNotNull);

      // Second run is a no-op.
      final second = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '4.0.0',
      );
      expect(second.upToDate, isTrue);
    });

    test('golden update: DNA change rewrites instances and reports once', () {
      final host = makeHost();
      instantiateDna(host: host, targetRoot: root, baseVersion: '4.0.0');

      host.writeString(
        '$root/node_modules/dna-base/dna/dot-vscode/extensions.json',
        '{"recommendations": ["esbenp.prettier-vscode", "new.extension"]}\n',
      );
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '4.0.0',
      );
      expect(r.updated, contains('.vscode/extensions.json'));
      expect(
        host.readString('$root/.vscode/extensions.json'),
        contains('new.extension'),
      );
      final third = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '4.0.0',
      );
      expect(third.upToDate, isTrue);
    });

    test('locally changed instances are backed up and overwritten', () {
      final host = makeHost();
      instantiateDna(host: host, targetRoot: root, baseVersion: '4.0.0');
      final generated = host.readString('$root/.vscode/settings.json');

      host.writeString('$root/.vscode/settings.json', '{"hacked": true}');
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '4.0.0',
      );
      expect(r.backedUp, ['.vscode/settings.json']);
      expect(r.updated, contains('.vscode/settings.json'));
      // The DNA content wins, the local content survives in system temp.
      expect(host.readString('$root/.vscode/settings.json'), generated);
      expect(r.backupDir, contains(dnaBackupDirPrefix));
      expect(
        host.readString('${r.backupDir}/.vscode/settings.json'),
        '{"hacked": true}',
      );
      // Outside the project — nothing to commit, nothing the next run
      // sees.
      expect(r.backupDir, isNot(startsWith('$root/')));
      expect(r.updated.any((u) => u.contains(dnaBackupDirPrefix)), isFalse);
      // The report names the DNA file to edit instead — here the sidecar
      // of the last contributing layer.
      expect(
        r.sources['.vscode/settings.json'],
        'dna-dart/dna/dot-vscode/settings.overrides.json',
      );
    });

    test('sources name the DNA file behind every reported path', () {
      final host = makeHost();
      instantiateDna(host: host, targetRoot: root, baseVersion: '4.0.0');

      // A plain file comes from the layer that shipped it last …
      host.writeString('$root/LICENSE', 'hand edited\n');
      // … a generated dna/ file from the same source.
      host.writeString('$root/dna/doc/develop.md', 'hand edited\n');
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '4.0.0',
      );
      expect(r.sources['LICENSE'], 'dna-base/dna/LICENSE');
      expect(r.backedUp, contains('LICENSE'));

      // Markdown overrides win over the base file they patch.
      final fresh = makeHost();
      instantiateDna(host: fresh, targetRoot: root, baseVersion: '4.0.0');
      fresh.writeString('$root/doc/develop.md', 'hand edited\n');
      final r2 = instantiateDna(
        host: fresh,
        targetRoot: root,
        baseVersion: '4.0.0',
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
              'dev_dependencies:\n  dna_base: ^1.0.0\n',
          '$root/$dnaConfigPath':
              '{"version": $dnaFormatVersion, "layers": ["dna-base"]}',
          '$root/.dart_tool/package_config.json': '{"packages": [ '
              '{"name": "dna_base", "rootUri": "../../cache/dna_base"}]}',
          '/cache/dna_base/pubspec.yaml': 'name: dna_base\nversion: 1.0.0\n',
          '/cache/dna_base/$dnaConfigPath': layerConfig(),
          '/cache/dna_base/dna/LICENSE': 'MIT\n',
        },
      );
      instantiateDna(host: host, targetRoot: root, baseVersion: '4.0.0');
      host.writeString('$root/LICENSE', 'hand edited\n');
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '4.0.0',
      );
      expect(r.sources['LICENSE'], 'dna_base/dna/LICENSE');
    });

    test('a localized layer is shown as the folder to open', () {
      // The real workspace shape: target and layer are siblings under the
      // ticket root, two org folders apart. gg_localize_refs points
      // package_config.json at the checkout, and the report has to name
      // that folder — relative to the target — not the package.
      const target = '/w/ds_cdm/ds-dna';
      final host = MemoryDnaHost(
        files: {
          '$target/pubspec.yaml': 'name: consumer\n',
          '$target/$dnaConfigPath':
              '{"version": $dnaFormatVersion, "layers": ["local_dna"]}',
          '$target/pubspec.lock': '''
packages:
  local_dna:
    dependency: "direct main"
    description:
      path: "../../ggsuite/local-dna"
      relative: true
    source: path
    version: "1.0.0"
''',
          '$target/.dart_tool/package_config.json': '{"packages": [ '
              '{"name": "local_dna", '
              '"rootUri": "../../../ggsuite/local-dna"}]}',
          '/w/ggsuite/local-dna/$dnaConfigPath': layerConfig(),
          '/w/ggsuite/local-dna/dna/LICENSE': 'MIT\n',
        },
      );
      instantiateDna(host: host, targetRoot: target, baseVersion: '4.0.0');
      host.writeString('$target/LICENSE', 'hand edited\n');
      final r = instantiateDna(
        host: host,
        targetRoot: target,
        baseVersion: '4.0.0',
      );
      expect(r.sources['LICENSE'], '../../ggsuite/local-dna/dna/LICENSE');
    });

    test('a layer outside the target tree keeps its absolute folder', () {
      final host = MemoryDnaHost(
        files: {
          '$root/pubspec.yaml': 'name: consumer\n',
          '$root/$dnaConfigPath':
              '{"version": $dnaFormatVersion, "layers": ["local_dna"]}',
          '$root/.dart_tool/package_config.json': '{"packages": [ '
              '{"name": "local_dna", "rootUri": "file:///elsewhere/dna"}]}',
          '$root/pubspec.lock': '''
packages:
  local_dna:
    dependency: "direct main"
    description:
      path: "/elsewhere/dna"
      relative: false
    source: path
    version: "1.0.0"
''',
          '/elsewhere/dna/$dnaConfigPath': layerConfig(),
          '/elsewhere/dna/dna/LICENSE': 'MIT\n',
        },
      );
      instantiateDna(host: host, targetRoot: root, baseVersion: '4.0.0');
      host.writeString('$root/LICENSE', 'hand edited\n');
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '4.0.0',
      );
      expect(r.sources['LICENSE'], '../elsewhere/dna/dna/LICENSE');
    });

    test('a hand-fix moved into the DNA becomes the generated content', () {
      final host = makeHost();
      instantiateDna(host: host, targetRoot: root, baseVersion: '4.0.0');

      // User edits the instance by hand → backed up and overwritten.
      host.writeString('$root/LICENSE', 'MIT (c) ggsuite — edited\n');
      final overwritten = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '4.0.0',
      );
      expect(overwritten.backedUp, ['LICENSE']);
      expect(
        host.readString('${overwritten.backupDir}/LICENSE'),
        'MIT (c) ggsuite — edited\n',
      );

      // User moves the change into the DNA source instead.
      host.writeString(
        '$root/node_modules/dna-base/dna/LICENSE',
        'MIT (c) dnaCopyrightHolder — edited\n',
      );
      final healed = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '4.0.0',
      );
      expect(healed.backedUp, isEmpty);
      expect(healed.updated, isNotEmpty);
    });

    test('commits everything it generated, path-limited', () {
      final host = makeHost();
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '4.0.0',
      );
      expect(r.committed, isTrue);
      expect(r.upToDate, isTrue);
      expect(host.commits.single.message, generatedDnaCommitMessage);
      expect(host.commits.single.paths, contains('LICENSE'));
      // Decorated report entries never reach git.
      expect(
        host.commits.single.paths.any((p) => p.contains('(removed)')),
        isFalse,
      );
      expect(
        r.messages,
        contains('committed as "$generatedDnaCommitMessage"'),
      );
    });

    test('keeps the files when committing is impossible', () {
      final host = makeHost()..commitError = 'not a git repository';
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '4.0.0',
      );
      expect(r.committed, isFalse);
      expect(r.upToDate, isFalse);
      expect(r.updated, isNotEmpty);
      expect(host.existsFile('$root/LICENSE'), isTrue);
      expect(
        r.warnings.any((w) => w.contains('Could not commit')),
        isTrue,
      );
    });

    test('the config is read, the bookkeeping written, side by side', () {
      final host = makeHost();
      final before = host.readString('$root/$dnaConfigPath');

      instantiateDna(host: host, targetRoot: root, baseVersion: '4.0.0');
      instantiateDna(host: host, targetRoot: root, baseVersion: '4.0.0');

      // The developer's file is untouched after two runs …
      expect(host.readString('$root/$dnaConfigPath'), before);
      // … and the engine's file sits beside it, carrying the instances
      // but never the variables.
      expect(host.existsFile('$root/$dnaGeneratedPath'), isTrue);
      final generated = jsonDecode(host.readString('$root/$dnaGeneratedPath'))
          as Map<String, dynamic>;
      expect(generated['instances'], isNotEmpty);
      expect(generated.containsKey('vars'), isFalse);
      expect(
        host.readString('$root/dna/_vars.json'),
        contains('dnaCopyrightHolder'),
      );
    });

    test('a layer does not leak its own manifests into the consumer', () {
      final host = makeHost(
        extra: {
          '$root/node_modules/dna-dart/$dnaGeneratedPath':
              '{"version": $dnaFormatVersion, "layers": [], '
                  '"baseVersion": "5.0.0", "instances": []}',
        },
      );
      instantiateDna(host: host, targetRoot: root, baseVersion: '4.0.0');
      // The consumer's own bookkeeping, not the layer's: a leak would
      // make every run report changes forever.
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '4.0.0',
      );
      expect(r.upToDate, isTrue, reason: r.updated.join('\n'));
      // The bookkeeping is the consumer's own, not the layer's copy.
      final generated = jsonDecode(host.readString('$root/$dnaGeneratedPath'))
          as Map<String, dynamic>;
      expect(generated['layers'], isNotEmpty);
      expect(generated['instances'], isNotEmpty);
    });

    test('unrelated dirty files never block the run', () {
      final host = makeHost(
        extra: {'$root/lib/my_code.dart': 'void main() {}'},
      );
      host.uncommitted.addAll(['lib/my_code.dart', 'README.md']);
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '4.0.0',
      );
      expect(r.blocked, isFalse);
      expect(r.updated, isNotEmpty);
      expect(host.existsFile('$root/LICENSE'), isTrue);
    });

    test('an uncommitted file that would be overwritten blocks', () {
      final host = makeHost();
      instantiateDna(host: host, targetRoot: root, baseVersion: '4.0.0');

      // The DNA changes and the target instance is dirty at the same time.
      host.writeString(
        '$root/node_modules/dna-base/dna/LICENSE',
        'MIT (c) dnaCopyrightHolder — new\n',
      );
      host.uncommitted.add('LICENSE');
      final before = Map.of(host.files);
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '4.0.0',
      );
      expect(r.blocked, isTrue);
      expect(r.uncommittedTargets, ['LICENSE']);
      expect(r.updated, isEmpty);
      expect(host.files, before);
      expect(r.messages, contains(uncommittedTargetsMessage));
      expect(r.sources['LICENSE'], 'dna-base/dna/LICENSE');
    });

    test('an uncommitted file that is only created does not block', () {
      // The instance does not exist yet — nothing can be lost.
      final host = makeHost();
      host.uncommitted.add('LICENSE');
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '4.0.0',
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
        baseVersion: '4.0.0',
      );
      expect(r.uncommittedTargets, ['.vscode/settings.json']);
      expect(host.readString('$root/.vscode/settings.json'), '{"mine": true}');
    });

    test('the guard is skipped when everything is up to date', () {
      final host = makeHost();
      instantiateDna(host: host, targetRoot: root, baseVersion: '4.0.0');
      host.uncommitted.addAll(['LICENSE', '.vscode/settings.json']);
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '4.0.0',
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
        baseVersion: '4.0.0',
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
      instantiateDna(host: host, targetRoot: root, baseVersion: '4.0.0');

      // The DNA stops shipping the extensions file.
      host.deleteFile(
        '$root/node_modules/dna-base/dna/dot-vscode/extensions.json',
      );
      host.deleteFile(
        '$root/node_modules/dna-dart/dna/dot-vscode/extensions.overrides.json',
      );
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '4.0.0',
      );
      expect(host.existsFile('$root/.vscode/extensions.json'), isFalse);
      expect(
        r.updated.any((u) => u.contains('.vscode/extensions.json')),
        isTrue,
      );

      // Same situation, but the user modified the instance → kept.
      final host2 = makeHost();
      instantiateDna(host: host2, targetRoot: root, baseVersion: '4.0.0');
      host2.writeString('$root/.vscode/extensions.json', '{"mine": 1}');
      host2.deleteFile(
        '$root/node_modules/dna-base/dna/dot-vscode/extensions.json',
      );
      host2.deleteFile(
        '$root/node_modules/dna-dart/dna/dot-vscode/extensions.overrides.json',
      );
      final r2 = instantiateDna(
        host: host2,
        targetRoot: root,
        baseVersion: '4.0.0',
      );
      expect(host2.existsFile('$root/.vscode/extensions.json'), isTrue);
      expect(
        r2.warnings.any((w) => w.contains('remove manually')),
        isTrue,
      );
    });

    test('role dna: own dna/ is synced whatever layers are declared', () {
      // Two declared layers, a chain (dna-dart -> dna-base), each shipping
      // the same paths as the target. The own dna/ still wins every
      // conflict and still contributes its exclusive files.
      final host = MemoryDnaHost(
        files: {
          '$root/package.json': '{"name": "leaf-dna", "version": "1.0.0", '
              '"dependencies": {"dna-dart": "^1.0.0", "dna-base": "^1.0.0"}}',
          '$root/$dnaConfigPath': layerConfig(['dna-base', 'dna-dart']),
          '$root/node_modules/dna-base/package.json':
              '{"name": "dna-base", "version": "1.0.0"}',
          '$root/node_modules/dna-base/$dnaConfigPath': layerConfig(),
          '$root/node_modules/dna-base/dna/doc/develop.md': '# Base\n',
          '$root/node_modules/dna-dart/package.json':
              '{"name": "dna-dart", "version": "1.0.0", '
                  '"dependencies": {"dna-base": "^1.0.0"}}',
          '$root/node_modules/dna-dart/$dnaConfigPath':
              layerConfig(['dna-base']),
          '$root/node_modules/dna-dart/dna/doc/develop.md': '# Dart\n',
          '$root/dna/doc/develop.md': '# Own version\n',
          '$root/dna/doc/only-here.md': '# Only in the own DNA\n',
        },
      );
      instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '4.0.0',
      );

      // Applied last: the own file wins over both layers …
      expect(host.readString('$root/doc/develop.md'), '# Own version\n');
      // … and a file no layer ships is instantiated all the same.
      expect(
        host.readString('$root/doc/only-here.md'),
        '# Only in the own DNA\n',
      );

      // The ordering the win depends on, asserted directly.
      final manifest = DnaManifest.read(host, root)!;
      expect(
        manifest.layers.map((l) => l.name),
        ['dna-base', 'dna-dart', 'self'],
      );
    });

    test('role dna: own dna/ is the last layer and never overwritten', () {
      final host = MemoryDnaHost(
        files: {
          '$root/package.json': '{"name": "dna-dart", "version": "1.0.0", '
              '"dependencies": {"dna-base": "^1.0.0"}}',
          '$root/$dnaConfigPath': layerConfig(['dna-base']),
          '$root/node_modules/dna-base/package.json':
              '{"name": "dna-base", "version": "1.0.0"}',
          '$root/node_modules/dna-base/$dnaConfigPath': layerConfig(),
          '$root/node_modules/dna-base/dna/doc/develop.md': '# Base\n',
          '$root/node_modules/dna-base/dna/LICENSE': 'MIT\n',
          '$root/dna/doc/develop.md': '# Own version\n',
          '$root/dna/dot-vscode/settings.json': '{"a": 1}\n',
        },
      );
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '4.0.0',
      );
      expect(r.backedUp, isEmpty);

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
        baseVersion: '4.0.0',
      );
      expect(second.upToDate, isTrue);
      // The hand-authored config survives inside the hand-authored dna/.
      expect(
        host.readString('$root/$dnaConfigPath'),
        layerConfig(['dna-base']),
      );
    });

    test('dot- escapes become dotfiles in the project, not in dna/', () {
      final host = makeHost(
        extra: {
          '$root/node_modules/dna-dart/dna/dot-claude/skills/init/SKILL.md':
              '# init\n',
        },
      );
      instantiateDna(host: host, targetRoot: root, baseVersion: '4.0.0');

      // The instance carries the real dotfile name …
      expect(
        host.existsFile('$root/.claude/skills/init/SKILL.md'),
        isTrue,
      );
      // … while the replica keeps the escape, so it survives republishing
      // through pub, which drops every path with a leading dot.
      expect(
        host.existsFile('$root/dna/dot-claude/skills/init/SKILL.md'),
        isTrue,
      );
      expect(
        host.existsFile('$root/dna/.claude/skills/init/SKILL.md'),
        isFalse,
      );
    });

    test('a layer shipping literal dotfiles is warned about', () {
      final host = makeHost(
        extra: {'$root/node_modules/dna-dart/dna/.prettierrc': '{}\n'},
      );
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '4.0.0',
      );
      expect(
        r.warnings.any(
          (w) =>
              w.contains('.prettierrc') &&
              w.contains('dart pub publish drops them'),
        ),
        isTrue,
        reason: r.warnings.join('\n'),
      );
      // Still instantiated — the warning is advice, not a rejection.
      expect(host.existsFile('$root/.prettierrc'), isTrue);
    });

    test('an escaped and a literal dotfile colliding is a hard error', () {
      final host = makeHost(
        extra: {
          '$root/node_modules/dna-dart/dna/.prettierrc': '{"a": 1}\n',
          '$root/node_modules/dna-dart/dna/dot-prettierrc': '{"b": 2}\n',
        },
      );
      expect(
        () => instantiateDna(
          host: host,
          targetRoot: root,
          baseVersion: '4.0.0',
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

    test('names are instantiated verbatim for package.json-only projects', () {
      final host = MemoryDnaHost(
        files: {
          '$root/package.json': '{"devDependencies": {"dna-ts": "^1.0.0"}}',
          '$root/$dnaConfigPath':
              '{"version": $dnaFormatVersion, "layers": ["dna-ts"]}',
          '$root/node_modules/dna-ts/package.json':
              '{"name": "dna-ts", "version": "1.0.0"}',
          '$root/node_modules/dna-ts/$dnaConfigPath': layerConfig(),
          '$root/node_modules/dna-ts/dna/test/dna/my-spec-helper.ts':
              '// helper\n',
        },
      );
      instantiateDna(host: host, targetRoot: root, baseVersion: '4.0.0');
      expect(
        host.existsFile('$root/test/dna/my-spec-helper.ts'),
        isTrue,
      );
    });

    test('writes the managed CLAUDE.md block from projected instances', () {
      final host = makeHost(
        extra: {
          '$root/$dnaConfigPath': '{"version": $dnaFormatVersion, '
              '"layers": ["dna-dart"], '
              '"claude": {"claudeMdInclude": ["doc"]}}',
          '$root/CLAUDE.md': '# My project\n',
        },
      );
      instantiateDna(host: host, targetRoot: root, baseVersion: '4.0.0');
      final claude = host.readString('$root/CLAUDE.md');
      expect(claude, contains('# My project'));
      expect(claude, contains('@doc/develop.md'));
      expect(claude, contains('<!-- helix:claude_md:start -->'));
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
          baseVersion: '4.0.0',
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
          baseVersion: '4.0.0',
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
        baseVersion: '4.0.0',
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
        baseVersion: '4.0.0',
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
          '$root/node_modules/dna-dart/dna/dot-vscode/tasks.json': '{}\n',
          '$root/node_modules/dna-dart/dna/.vscode/tasks.json': '{}\n',
        },
      );
      expect(
        () => instantiateDna(
          host: host,
          targetRoot: root,
          baseVersion: '4.0.0',
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
      instantiateDna(host: host, targetRoot: root, baseVersion: '4.0.0');

      host.deleteFile('$root/LICENSE');
      final restored = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '4.0.0',
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
        baseVersion: '4.0.0',
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
          '$root/node_modules/dna-base/dna/doc/other.md':
              'Manager: {{@pm:npm}}\n',
          '$root/node_modules/dna-dart/dna/global.overrides.md':
              '<!-- @pm --> dart pub <!-- @pm -->\n',
        },
      );
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '4.0.0',
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
        baseVersion: '4.0.0',
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
          '$root/node_modules/dna-dart/dna/dot-vscode/missing.overrides.json':
              '{"a": 1}',
        },
      );
      final r = instantiateDna(
        host: host,
        targetRoot: root,
        baseVersion: '4.0.0',
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
      instantiateDna(host: host, targetRoot: root, baseVersion: '4.0.0');
      expect(host.readBytes('$root/doc/logo.png'), binary);
      expect(host.readBytes('$root/doc/legacy.txt'), latin1);
    });

    test('base DNA of helix itself is layer 0', () {
      final host = makeHost(
        extra: {
          '/gg/dna/doc/base-doc.md': '# From helix base\n',
        },
      );
      instantiateDna(
        host: host,
        targetRoot: root,
        baseDnaRoot: '/gg',
        baseVersion: '4.0.0',
      );
      expect(host.existsFile('$root/dna/doc/base-doc.md'), isTrue);
      expect(host.existsFile('$root/doc/base-doc.md'), isTrue);
      // The engine's built-in base DNA points at the repo's dna/ folder,
      // never at a helix package path.
      host.writeString('$root/doc/base-doc.md', 'hand edited\n');
      final modified = instantiateDna(
        host: host,
        targetRoot: root,
        baseDnaRoot: '/gg',
        baseVersion: '4.0.0',
      );
      expect(modified.sources['doc/base-doc.md'], 'dna/doc/base-doc.md');
      final manifest = DnaManifest.read(host, root)!;
      expect(manifest.layers.first.name, 'base');
      expect(manifest.baseHash, isNotNull);
    });
  });
}
