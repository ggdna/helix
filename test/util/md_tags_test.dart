// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:helix/src/util/md_tags.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../helpers/sample_folder.dart';

String _sample(String name) =>
    File(p.join(sampleRoot(), 'md_tags', name)).readAsStringSync();

void main() {
  group('parseTagFile', () {
    test('parses the sample overrides file with all block forms', () {
      final result = parseTagFile(_sample('source.overrides.md'));

      expect(result.warnings, isEmpty);
      expect(
        result.blocks.map((b) => b.tag),
        ['setup', 'package_manager', 'usage', 'project_name'],
      );

      expect(
        result.blocks[0].content,
        '## [@setup] Setup (überschrieben)\n'
        '\n'
        'Nutze die Firmen-Toolchain.\n'
        '\n'
        '#### Tieferer Unterschritt\n'
        '\n'
        'Auch Teil der Ersetzung.',
      );
      expect(result.blocks[0].isHeadingForm, isTrue);
      expect(result.blocks[1].content, 'pnpm');
      expect(result.blocks[1].isHeadingForm, isFalse);
      expect(
        result.blocks[2].content,
        '## Verwendung\n\nStarte mit `run`.',
      );
      expect(result.blocks[3].content, 'Acme-Projekt');
    });

    test('parses the single-line comment form', () {
      final result = parseTagFile('<!-- @t --> Wert <!-- @t -->\n');
      expect(result.blocks.single.tag, 't');
      expect(result.blocks.single.content, 'Wert');
      expect(result.blocks.single.isHeadingForm, isFalse);
      expect(result.warnings, isEmpty);
    });

    test('warns about unclosed comment blocks and skips them', () {
      final result = parseTagFile('<!-- @t -->\nInhalt\n');
      expect(result.blocks, isEmpty);
      expect(result.warnings.single, contains('Unclosed'));
    });

    test('warns about stray content outside blocks', () {
      final result = parseTagFile(
        'Streuner\n'
        'noch einer\n'
        '\n'
        '<!-- @t --> ok <!-- @t -->\n',
      );
      expect(result.blocks, hasLength(1));
      // All stray lines are collapsed into a single warning.
      expect(result.warnings.single, contains('Stray content'));
      expect(result.warnings.single, contains('lines 1, 2'));
    });

    test('plain comments without @ are not markers', () {
      final result = parseTagFile(
        '<!-- kein marker -->\n'
        '<!-- @t --> ok <!-- @t -->\n',
      );
      expect(result.blocks.single.tag, 't');
      // The plain comment counts as stray content.
      expect(result.warnings.single, contains('Stray content'));
    });

    test('markers inside code fences are content, not delimiters', () {
      final result = parseTagFile(
        '<!-- @t -->\n'
        '```\n'
        '<!-- @t -->\n'
        '```\n'
        '<!-- @t -->\n',
      );
      expect(result.blocks.single.tag, 't');
      expect(result.blocks.single.content, '```\n<!-- @t -->\n```');
      expect(result.warnings, isEmpty);
    });

    test('foreign comment markers inside a block are content', () {
      final result = parseTagFile(
        '<!-- @t -->\n'
        '<!-- @other -->\n'
        '<!-- @t -->\n',
      );
      expect(result.blocks.single.content, '<!-- @other -->');
    });

    test('a tagged heading ends the previous heading block', () {
      final result = parseTagFile(
        '## [@a] A\nInhalt A\n\n## [@b] B\nInhalt B\n',
      );
      expect(result.blocks.map((b) => b.tag), ['a', 'b']);
      expect(result.blocks[0].content, '## [@a] A\nInhalt A');
      expect(result.blocks[1].content, '## [@b] B\nInhalt B');
      expect(result.blocks[0].isHeadingForm, isTrue);
      expect(result.blocks[1].isHeadingForm, isTrue);
    });

    test('tolerates CRLF input', () {
      final result = parseTagFile('<!-- @t --> Wert <!-- @t -->\r\n');
      expect(result.blocks.single.content, 'Wert');

      final heading = parseTagFile('## [@a] A\r\nInhalt\r\n');
      expect(heading.blocks.single.content, '## [@a] A\nInhalt');
    });

    test('warns about ambiguous marker lines', () {
      final result = parseTagFile('<!-- @t --> hängender Text\n');
      expect(result.blocks, isEmpty);
      expect(result.warnings.single, contains('Ambiguous'));
    });

    test('tolerates a UTF-8 BOM before the first marker', () {
      final result = parseTagFile('﻿<!-- @t --> Wert <!-- @t -->\n');
      expect(result.blocks.single.content, 'Wert');
      expect(result.warnings, isEmpty);
    });

    test('handles empty input', () {
      final result = parseTagFile('');
      expect(result.blocks, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test('warns about stray fenced content outside blocks', () {
      final result = parseTagFile('```\ncode\n```\n');
      expect(result.blocks, isEmpty);
      expect(result.warnings.single, contains('Stray content'));
    });
  });

  group('applyTagBlocks', () {
    test('applies the sample overrides to the sample source (golden)', () {
      final blocks = parseTagFile(_sample('source.overrides.md')).blocks;
      final result = applyTagBlocks(
        _sample('source.md'),
        blocks,
        fileLabel: 'source.md',
      );
      expect(result.warnings, isEmpty);
      expect(result.content, _sample('applied.expected.md'));
    });

    test('replaces a section reaching until the end of file', () {
      final result = applyTagBlocks(
        '## [@a] Alt\n\nAlter Inhalt.\n',
        const [TagBlock(tag: 'a', content: '## [@a] Neu\n\nNeuer Inhalt.')],
        fileLabel: 'x.md',
      );
      expect(result.content, '## [@a] Neu\n\nNeuer Inhalt.\n');
    });

    test('replaces all occurrences of a tagged section', () {
      final result = applyTagBlocks(
        '## [@a] Eins\nx\n\n## Mitte\n\n## [@a] Zwei\ny\n',
        const [TagBlock(tag: 'a', content: '## [@a] Neu\nz')],
        fileLabel: 'x.md',
      );
      expect(
        result.content,
        '## [@a] Neu\nz\n\n## Mitte\n\n## [@a] Neu\nz\n',
      );
    });

    test('a higher-level heading ends the section', () {
      final result = applyTagBlocks(
        '### [@a] Tief\nx\n\n## Höher\ny\n',
        const [TagBlock(tag: 'a', content: '### [@a] Neu\nz')],
        fileLabel: 'x.md',
      );
      expect(result.content, '### [@a] Neu\nz\n\n## Höher\ny\n');
    });

    test('nested same-tag headings do not crash — outer section wins', () {
      final result = applyTagBlocks(
        '## [@x] Outer\n\ntext\n\n### [@x] Inner\n\nmore text\n\nlong tail\n',
        const [TagBlock(tag: 'x', content: '## [@x] Neu')],
        fileLabel: 'x.md',
      );
      expect(result.content, '## [@x] Neu\n');
      expect(result.warnings, isEmpty);
    });

    test('replaces a foreign tag in the replacement heading', () {
      final result = applyTagBlocks(
        '## [@setup] Alt\nx\n',
        const [TagBlock(tag: 'setup', content: '## [@greeting] Neu\nz')],
        fileLabel: 'x.md',
      );
      expect(result.content, '## [@setup] Neu\nz\n');

      // Also for foreign-tagged headings without a title text.
      final bare = applyTagBlocks(
        '## [@setup] Alt\nx\n',
        const [TagBlock(tag: 'setup', content: '## [@greeting]\nz')],
        fileLabel: 'x.md',
      );
      expect(bare.content, '## [@setup]\nz\n');
    });

    test('re-attaches the tag when the replacement heading lacks it', () {
      final result = applyTagBlocks(
        '## [@a] Alt\nx\n',
        const [TagBlock(tag: 'a', content: '# Neu\nz')],
        fileLabel: 'x.md',
      );
      expect(result.content, '# [@a] Neu\nz\n');

      // Also for headings without a title text.
      final bare = applyTagBlocks(
        '## [@a] Alt\nx\n',
        const [TagBlock(tag: 'a', content: '##\nz')],
        fileLabel: 'x.md',
      );
      expect(bare.content, '## [@a]\nz\n');
    });

    test('warns and skips when the replacement has no heading', () {
      const source = '## [@a] Alt\nx\n';
      for (final content in ['nur Text', '']) {
        final result = applyTagBlocks(
          source,
          [TagBlock(tag: 'a', content: content)],
          fileLabel: 'x.md',
        );
        expect(result.content, source);
        expect(
          result.warnings.single,
          contains('must start with a heading'),
        );
      }
    });

    test('tagged headings inside fences are no occurrences', () {
      const source = '```\n## [@a] Fenced\n```\n';
      final result = applyTagBlocks(
        source,
        const [TagBlock(tag: 'a', content: '## [@a] Neu')],
        fileLabel: 'x.md',
      );
      expect(result.content, source);
      expect(result.warnings.single, contains('not found'));
    });

    test('rewrites placeholders with empty defaults', () {
      final result = applyTagBlocks(
        'Wert: {{@a}}\n',
        const [TagBlock(tag: 'a', content: 'neu')],
        fileLabel: 'x.md',
      );
      expect(result.content, 'Wert: {{@a:neu}}\n');
    });

    test('splits tag and default at the first colon', () {
      final rendered = renderMarkers('{{@a:x:y}}\n');
      expect(rendered, 'x:y\n');
    });

    test('old-notation placeholders are not rewritten', () {
      final result = applyTagBlocks(
        '{{a|alt}}\n',
        const [TagBlock(tag: 'a', content: 'neu')],
        fileLabel: 'x.md',
      );
      expect(result.content, '{{a|alt}}\n');
      expect(result.warnings.single, contains('not found'));
    });

    test('warns when a replacement value contains }}', () {
      final result = applyTagBlocks(
        '{{@a:alt}}\n',
        const [TagBlock(tag: 'a', content: 'kaputt}}')],
        fileLabel: 'x.md',
      );
      expect(result.warnings.single, contains('"}}"'));
    });

    test('collapses multi-line string replacements with a warning', () {
      final result = applyTagBlocks(
        '{{@a:alt}}\n',
        const [TagBlock(tag: 'a', content: 'zeile1\nzeile2')],
        fileLabel: 'x.md',
      );
      expect(result.content, '{{@a:zeile1 zeile2}}\n');
      expect(result.warnings.single, contains('multiple'));
    });

    test('warns about unknown tags', () {
      final result = applyTagBlocks(
        'kein Marker\n',
        const [TagBlock(tag: 'missing', content: 'x')],
        fileLabel: 'y.md',
      );
      expect(result.content, 'kein Marker\n');
      expect(result.warnings.single, contains('"missing"'));
      expect(result.warnings.single, contains('y.md'));
    });

    test('preserves CRLF line endings', () {
      final result = applyTagBlocks(
        '## [@a] Alt\r\nx\r\n',
        const [TagBlock(tag: 'a', content: '## [@a] Neu\nz')],
        fileLabel: 'x.md',
      );
      expect(result.content, '## [@a] Neu\r\nz\r\n');
    });
  });

  group('applyGlobalStringBlocks', () {
    test('rewrites matching placeholders and records found tags', () {
      final foundTags = <String>{};
      final result = applyGlobalStringBlocks(
        'A {{@tone:nett}} B {{@other:x}}\n',
        const [
          TagBlock(tag: 'tone', content: 'förmlich'),
          TagBlock(tag: 'missing', content: 'x'),
        ],
        foundTags: foundTags,
      );
      expect(result, 'A {{@tone:förmlich}} B {{@other:x}}\n');
      expect(foundTags, {'tone'});
    });

    test('collapses multi-line values silently', () {
      final foundTags = <String>{};
      final result = applyGlobalStringBlocks(
        '{{@a:alt}}\n',
        const [TagBlock(tag: 'a', content: 'zeile1\nzeile2')],
        foundTags: foundTags,
      );
      expect(result, '{{@a:zeile1 zeile2}}\n');
    });

    test('skips fenced and inline code', () {
      final foundTags = <String>{};
      const source = '```\n{{@a:x}}\n```\n`{{@a:y}}`\n{{@a:z}}\n';
      final result = applyGlobalStringBlocks(
        source,
        const [TagBlock(tag: 'a', content: 'neu')],
        foundTags: foundTags,
      );
      expect(result, '```\n{{@a:x}}\n```\n`{{@a:y}}`\n{{@a:neu}}\n');
    });
  });

  group('detectLegacyMarkers', () {
    test('reports legacy headings and placeholders with line numbers', () {
      final findings = detectLegacyMarkers(
        '# Titel\n'
        '## [alt] Abschnitt\n'
        'Wert: {{alt|standard}}\n'
        '## [@neu] Abschnitt\n'
        'Wert: {{@neu:standard}}\n',
      );
      expect(findings, hasLength(2));
      expect(findings[0], contains('line 2'));
      expect(findings[0], contains('[@tag]'));
      expect(findings[1], contains('line 3'));
      expect(findings[1], contains('{{@tag:default}}'));
    });

    test('skips fenced and inline code', () {
      final findings = detectLegacyMarkers(
        '```\n## [alt] X\n{{alt|x}}\n```\n`{{alt|y}}`\n',
      );
      expect(findings, isEmpty);
    });

    test('plain links and braces are not legacy markers', () {
      final findings = detectLegacyMarkers(
        'Ein [Link](https://example.com) und {{kein_tag}} bleiben.\n',
      );
      expect(findings, isEmpty);
    });
  });

  group('renderMarkers', () {
    test('renders the applied sample to clean markdown (golden)', () {
      final rendered = renderMarkers(_sample('applied.expected.md'));
      expect(rendered, _sample('rendered.expected.md'));
    });

    test('is idempotent', () {
      final once = renderMarkers(_sample('applied.expected.md'));
      expect(renderMarkers(once), once);
    });

    test('renders {{@tag}} to the empty string', () {
      expect(renderMarkers('a{{@x}}b\n'), 'ab\n');
    });

    test('keeps old-notation markers literal', () {
      const source = '## [a] T\n{{b|c}}\n';
      expect(renderMarkers(source), source);
    });

    test('strips tags from headings without titles', () {
      expect(renderMarkers('## [@a]\n'), '##\n');
    });

    test('keeps markers inside fences and inline code', () {
      const source = '```\n## [@a] X\n{{@b:c}}\n```\n`{{@d:e}}`\n';
      expect(renderMarkers(source), source);
    });

    test('longer fences nest shorter ones (CommonMark closing rule)', () {
      const source = '````markdown\n```\n{{@a:x}}\n```\n````\n';
      expect(renderMarkers(source), source);

      // A tilde run inside a backtick fence is content, not a closer.
      const mixed = '```\n~~~\n{{@a:x}}\n```\n';
      expect(renderMarkers(mixed), mixed);
    });

    test('preserves CRLF line endings', () {
      expect(
        renderMarkers('## [@a] T\r\n{{@b:c}}\r\n'),
        '## T\r\nc\r\n',
      );
    });

    test('normalizes mixed line endings to the dominant one', () {
      expect(renderMarkers('{{@a:x}}\r\nb\nc\nd\n'), 'x\nb\nc\nd\n');
      expect(renderMarkers('{{@a:x}}\r\nb\r\nc\n'), 'x\r\nb\r\nc\r\n');
    });
  });
}
