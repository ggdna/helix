// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:helix/src/util/dna_config.dart';
import 'package:helix/src/util/dna_must_override.dart';
import 'package:helix/src/util/layer_graph.dart';
import 'package:helix/src/util/package_resolution.dart';
import 'package:test/test.dart';

void main() {
  MustOverrideLayer layer(
    String name, {
    List<String> parents = const [],
    Map<String, bool> mustOverride = const {},
    Set<String> ownVars = const {},
  }) => MustOverrideLayer(
    name: name,
    varsFile: '$name/dna/_vars.json',
    parents: parents,
    mustOverride: mustOverride,
    ownVars: ownVars,
  );

  /// `layer: variable (requiredBy)` per violation, for compact asserts.
  List<String> check(List<MustOverrideLayer> layers) => [
    for (final v in mustOverrideViolations(layers))
      '${v.layer.name}: ${v.variable} (${v.requiredBy})',
  ];

  group('mustOverrideViolations', () {
    test('no flags, no violations', () {
      expect(
        check([
          layer('a'),
          layer('b', parents: ['a']),
        ]),
        isEmpty,
      );
    });

    test('the declaring layer itself is not bound', () {
      expect(
        check([
          layer('a', mustOverride: {'dnaX': true}),
        ]),
        isEmpty,
      );
    });

    test('every layer below a true must set the value', () {
      expect(
        check([
          layer('a', mustOverride: {'dnaX': true}),
          layer('b', parents: ['a']),
          layer('c', parents: ['b'], ownVars: {'dnaX'}),
          layer('d', parents: ['c']),
        ]),
        ['b: dnaX (a)', 'd: dnaX (a)'],
      );
    });

    test('false lifts the duty for the layers below, not for itself', () {
      expect(
        check([
          layer('a', mustOverride: {'dnaX': true}),
          layer('b', parents: ['a'], mustOverride: {'dnaX': false}),
          layer('c', parents: ['b']),
        ]),
        ['b: dnaX (a)'],
      );
    });

    test('a true below a false imposes the duty again', () {
      expect(
        check([
          layer('a', mustOverride: {'dnaX': true}),
          layer(
            'b',
            parents: ['a'],
            mustOverride: {'dnaX': false},
            ownVars: {'dnaX'},
          ),
          layer('c', parents: ['b'], mustOverride: {'dnaX': true}),
          layer('d', parents: ['c']),
        ]),
        ['d: dnaX (c)'],
      );
    });

    test('a repeated true names the nearest declaring layer', () {
      expect(
        check([
          layer('a', mustOverride: {'dnaX': true}),
          layer(
            'b',
            parents: ['a'],
            mustOverride: {'dnaX': true},
            ownVars: {'dnaX'},
          ),
          layer('c', parents: ['b']),
        ]),
        ['c: dnaX (b)'],
      );
    });

    test('one parent passing on true is enough', () {
      expect(
        check([
          layer('a', mustOverride: {'dnaX': true}),
          layer(
            'lifted',
            parents: ['a'],
            mustOverride: {'dnaX': false},
            ownVars: {'dnaX'},
          ),
          layer('kept', parents: ['a'], ownVars: {'dnaX'}),
          layer('child', parents: ['lifted', 'kept']),
        ]),
        ['child: dnaX (a)'],
      );
    });

    test('a sibling layer does not count for the duty', () {
      // The value reaches the merge through `sibling`, but `child` is
      // the one bound by `a`.
      expect(
        check([
          layer('a', mustOverride: {'dnaX': true}),
          layer('sibling', ownVars: {'dnaX'}),
          layer('child', parents: ['sibling', 'a']),
        ]),
        ['child: dnaX (a)'],
      );
    });

    test('false without an inherited duty changes nothing', () {
      expect(
        check([
          layer('a', mustOverride: {'dnaX': false}),
          layer('b', parents: ['a']),
        ]),
        isEmpty,
      );
    });

    test('unknown parents are skipped', () {
      expect(
        check([
          layer('b', parents: ['missing']),
        ]),
        isEmpty,
      );
    });

    test('a violation carries the layer and its vars file', () {
      final v = mustOverrideViolations([
        layer('a', mustOverride: {'dnaX': true}),
        layer('b', parents: ['a']),
      ]).single;
      expect(v.layer.varsFile, 'b/dna/_vars.json');
      expect(v.variable, 'dnaX');
      expect(v.requiredBy, 'a');
    });
  });

  group('mustOverrideLayers', () {
    const guides = ResolvedLayer(
      name: 'dna-guides',
      root: '/n/dna-guides',
      package: '@ggdna/dna-guides',
      ecosystem: PackageEcosystem.node,
      source: PackageSource.registry,
      mustOverride: {'dnaX': true},
    );
    const config = DnaConfig(
      layers: ['@ggdna/dna-guides'],
      mustOverride: {'dnaY': false},
    );

    List<MustOverrideLayer> build({bool includeSelf = true}) =>
        mustOverrideLayers(
          layers: [guides],
          config: config,
          varsFileOf: (layer) => '${layer.package}/dna/_vars.json',
          ownVarsOf: (name) => {'$name-var'},
          includeSelf: includeSelf,
        );

    test('lists the layers, then the project with canonical parents', () {
      final layers = build();
      expect(layers.map((l) => l.name), ['dna-guides', mustOverrideSelf]);
      expect(layers.first.varsFile, '@ggdna/dna-guides/dna/_vars.json');
      expect(layers.first.mustOverride, {'dnaX': true});
      expect(layers.first.ownVars, {'dna-guides-var'});
      expect(layers.last.varsFile, 'dna/_vars.json');
      expect(layers.last.parents, ['dna-guides']);
      expect(layers.last.mustOverride, {'dnaY': false});
      expect(layers.last.ownVars, {'$mustOverrideSelf-var'});
    });

    test('leaves the project out on request', () {
      expect(build(includeSelf: false).map((l) => l.name), ['dna-guides']);
    });
  });
}
