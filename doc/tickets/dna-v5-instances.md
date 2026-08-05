# gg_dna 5.0 — replica layout, instances, dev-dependency distribution

Decision log of the v5 redesign (ticket "dna", 2026-08-05). Supersedes
the 4.0 design documented in `dna_src_and_overrides_md.md` where they
conflict.

## Decisions

1. **No `dna/src`** — a DNA's `dna/` folder itself mirrors the project
   root. Public entries are copied to their project locations
   ("instances"), private entries (leading `_`, e.g. `_vars.json`) stay
   inside `dna/`.
2. **Instances must always match the generated originals.** A placed
   test verifies this on every run; hand-edited instances fail with the
   hint to edit the owning DNA instead.
3. **Inheritance tree** — DNA packages are published to the registry
   of the ecosystems that consume them: `base_dna` is a hybrid
   (pub.dev + npm), `dna_dart` is pub.dev only, `dna-ts` npm only.
   Package and repository names match (`base_dna`, `dna_dart`). Consumers declare DNAs as dev-dependencies; parent DNAs
   are regular dependencies of their child, so npm/pub resolve the tree
   transitively. gg_dna reads installed packages instead of cloning;
   the last override wins.
4. **Default order** = the declaration order of DNA dev-dependencies in
   `package.json`/`pubspec.yaml`; `.gg/dna.json` `order` overrides.
5. **Configuration only in `.gg/dna.json`** — never in
   `pubspec.yaml`/`package.json`/`dna.yaml`.
6. **`gg_dna init` replaces `gg_dna sync`** — init only places the
   wrapper test (+ config skeleton + gitignore exception); the
   instantiation runs inside the test via the gg_dna library (Dart
   in-process; TypeScript via `@tssuite/gg-dna`, the engine compiled to
   WebAssembly with fs/git callbacks injected — project
   `gg_dna-js-bridge`, derived from `gg-bridge-dart-typescript`).
7. **JSON overrides** via sidecar `X.overrides.json`: deep-merge by
   default, `null` deletes, `"key!"` replaces, `"key+"` joins arrays.
8. **Variables** in `dna/_vars.json`, referenced case-adaptively as
   `dnaMyVar` / `DnaMyVar` / `dna_my_var` / `DNA_MY_VAR` /
   `dna-my-var`; non-identifier values verbatim.
9. **File naming** — canonical kebab-case in DNAs, converted per target
   (Dart snake_case, TS camelCase); references rewritten in instances.
10. **Per-file guard** — a run never overwrites or deletes an existing
    file that carries uncommitted work (modified, staged or untracked);
    it names those files and writes nothing. Unrelated dirty files do
    not block a run. Adoption/overwrite is therefore always recoverable
    without forcing a fully clean tree (revised from the original
    clean-tree guard on the user's request).
11. **Skills are instances** (`dna/.claude/skills/**`); the old
    `config: claude: skills:` mirroring is gone. `CLAUDE.md` keeps the
    managed `claude_md` block.
12. **Documentation is written for humans**; the AI consumes the same
    files (conventions/guides live at `dna/doc/**` → `doc/**`,
    referenced from CLAUDE.md via `@`-imports).
13. **Language**: DNA content is English; legacy German docs are
    translated during migration.
14. **`gg_dna_ggsuite` is retired** — general DNA docs moved into
    gg_dna's base DNA, org-specific content moves to `base_dna`.

## Engine architecture

- Core (`lib/src/engine/instantiate.dart` + utils) is free of
  `dart:io`/`Process`; all host access goes through `DnaHost`
  (`lib/src/util/dna_fs.dart`). `IoDnaHost` binds to `dart:io` + git;
  `MemoryDnaHost` serves tests and mirrors the callback host of the
  WASM bridge.
- The merge happens in memory (no staging folders on disk anymore);
  golden-update semantics decide between fail/write/no-op, the manifest
  `dna/.dna.json` (format v5) records layers (`package`,
  `resolvedVersion`, `via`), instances (path + hash) and the effective
  variables.
