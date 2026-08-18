// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:helix/src/util/add_target.dart';
import 'package:test/test.dart';

void main() {
  group('AddTarget.parse', () {
    group('package names', () {
      test('takes a pub name as it is', () {
        final target = AddTarget.parse('dna_dart');
        expect(target.kind, AddTargetKind.package);
        expect(target.name, 'dna_dart');
        expect(target.isNodeOnlyName, isFalse);
      });

      test('recognizes a scoped npm name as node-only', () {
        final target = AddTarget.parse('@tssuite/dna-base');
        expect(target.kind, AddTargetKind.package);
        expect(target.name, '@tssuite/dna-base');
        expect(target.isNodeOnlyName, isTrue);
      });

      test('recognizes a dash as node-only — pub forbids it', () {
        expect(AddTarget.parse('dna-ts').isNodeOnlyName, isTrue);
      });

      test('trims what the user typed', () {
        expect(AddTarget.parse('  dna_dart  ').name, 'dna_dart');
      });

      test('rejects an empty target', () {
        expect(() => AddTarget.parse('   '), throwsA(isA<FormatException>()));
      });
    });

    group('git urls', () {
      test('takes the repository name from an https url', () {
        final target = AddTarget.parse('https://github.com/ggsuite/dna_base');
        expect(target.kind, AddTargetKind.git);
        expect(target.name, 'dna_base');
      });

      test('strips a .git suffix and a trailing slash', () {
        expect(
          AddTarget.parse('https://github.com/ggsuite/dna_base.git/').name,
          'dna_base',
        );
      });

      test('drops a #ref fragment', () {
        expect(
          AddTarget.parse('https://github.com/o/dna_base.git#main').name,
          'dna_base',
        );
      });

      test('reads the scp form of ssh urls', () {
        final target = AddTarget.parse('git@github.com:ggsuite/dna_base.git');
        expect(target.kind, AddTargetKind.git);
        expect(target.name, 'dna_base');
      });

      test('reads git:// and ssh:// urls', () {
        expect(
          AddTarget.parse('git://github.com/o/dna_base.git').kind,
          AddTargetKind.git,
        );
        expect(
          AddTarget.parse('ssh://git@github.com/o/dna_base.git').name,
          'dna_base',
        );
      });

      test('reads a plain path ending in .git', () {
        expect(AddTarget.parse('../dna_base.git').name, 'dna_base');
      });

      test('rejects a url without a repository name', () {
        expect(
          () => AddTarget.parse('https://github.com/'),
          throwsA(isA<FormatException>()),
        );
      });

      group('nodeGitSpec', () {
        test('prefixes a protocol url with git+', () {
          expect(
            AddTarget.parse('https://github.com/o/r.git').nodeGitSpec,
            'git+https://github.com/o/r.git',
          );
        });

        test('keeps an already prefixed url', () {
          expect(
            AddTarget.parse('git+https://github.com/o/r.git').nodeGitSpec,
            'git+https://github.com/o/r.git',
          );
        });

        test('turns the scp form into git+ssh', () {
          expect(
            AddTarget.parse('git@github.com:o/r.git').nodeGitSpec,
            'git+ssh://git@github.com/o/r.git',
          );
        });
      });

      test('pubGitDescriptor keeps the format pub expects', () {
        expect(
          AddTarget.parse('https://github.com/o/dna_base.git').pubGitDescriptor,
          'dev:dna_base@{git: https://github.com/o/dna_base.git}',
        );
      });
    });
  });
}
