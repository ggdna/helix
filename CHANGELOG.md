# Changelog

## 4.1.2 - 2026-08-12

### Removed

- BREAKING: File-naming conversion at instantiation. DNA files now
instantiate under exactly the name they carry in the layer — no
kebab/snake/camel conversion, and no rewriting of references to renamed
files. The `fileNaming` config key is gone; a `_dna.json` still setting
it now warns as an unknown key. Layers that relied on conversion must
rename their DNA files to the name the target should see.
- BREAKING: The `dot_` dot escape. `dot-` is the only accepted form; the
`dot_` variant only existed for snake_case layers, which the removal of
file-naming conversion makes obsolete. The placed DNA test now rejects a
`dot_`-escaped path in `dna/` before instantiating and reports the
rename to make (`Rename dna/dot_vscode to dna/dot-vscode.`) instead of
silently instantiating a literal `dot_vscode/` folder.
- Remove auto renaming of dna files. Did break links.

## 4.1.1 - 2026-08-12

### Changed

- A `dna/` folder without `dna/_dna.json` is a hard error instead of
silently falling back to `"role": "project"` — that fallback let the
engine treat a hand-authored DNA as generated content.
- Ensure correct naming, Require dna/_dna.json

### Fixed

- The snake_case dot escape `dot_` is decoded like `dot-`, so
`dna/dot_vscode/settings.json` also instantiates to
`.vscode/settings.json`.

## 4.1.0 - 2026-08-09

### Changed

- Increase version
- Publishing dna

## 4.0.1 - 2026-08-08

### Added

- Dotfiles in DNA content are escaped with a `dot-` prefix:
`dna/dot-vscode/settings.json` instantiates to `.vscode/settings.json`.
Without it `dart pub publish` silently drops them.
- Layer resolution goes through the manifests and their lock files
(`pubspec.lock`, `pnpm-lock.yaml`): the lock supplies the ecosystem, the
resolved version and the installed-name index, while
`.dart_tool/package_config.json` and `node_modules/` supply the folder.
- The npm scope is dropped when folding a package name to its layer
identity, so a DNA published to both registries (`@tssuite/dna-base` and
`dna_base`) is one layer, not two. A warning fires when the two copies
carry different `dna/` trees.

### Changed

- Distribute DNA using npm and dart package inheritance
- Set version back to 1

### Changed — breaking

- DNA configuration moved from `.gg/dna.json` to `dna/_dna.json`.
`dart pub publish` drops every path with a leading dot, so a config below
`.gg/` never reached a pub-installed consumer — the layer silently fell
back to defaults. `dna/` is the one folder both ecosystems publish.
- `dna/_dna.json` is hand-authored and the engine only ever reads it.
Everything the engine writes moved to `dna/_generated.json`, which also
absorbed `dna/_instances.json`.
- Layers are declared explicitly in `layers` and referenced by the
package name they are declared under in `pubspec.yaml` / `package.json`.
The old `order` key is gone, and so is the inference from dependency
declaration order — a dependency that is not listed is not a layer.
- Path overrides (`dependencies: { x: { path: … } }`) were removed.
Local checkouts are wired up by gg_localize_refs, which writes
`pubspec_overrides.yaml` / `pnpm-workspace.yaml` and thereby repoints
`.dart_tool/package_config.json` and the `node_modules` symlink.
- A package is a DNA layer only if its `dna/_dna.json` declares
`"role": "dna"`. A `dna/` folder alone no longer qualifies.
- `config.claude.claude_md.include` flattened to `claude.claudeMdInclude`.
- `"version": 1` is required in both files.
- pnpm is the only supported npm package manager; `package-lock.json` and
`yarn.lock` are not read.
- No migration path: `.gg/dna.json`, `dna.yaml` and `dna:` blocks in
`pubspec.yaml` / `package.json` are simply no longer read, and format
version 5 files are rejected.

### Fixed

- `resolvedVersion` read `package.json` even for pub-resolved packages.
A pub tarball ships both manifests, so a pub layer reported the npm
version. The version now comes from the lock file of the ecosystem that
provided the copy, and from the on-disk manifest for localized checkouts.
- A `dna/_generated.json` that exists but cannot be read now throws
instead of being treated as "never instantiated" — the latter made every
instance count as unowned and overwrote hand edits without the
hand-modified check ever firing.
- Fix versions

## 4.0.0 - 2026-08-07

### Added

- Instances: every public file of the merged `dna/` replica (path
segments not starting with `_`) is copied to its project location, with
ownership tracking, adoption of existing files, and removal of files the
DNA no longer produces — including the folders they leave empty
- Inheritance tree: DNAs are declared as dev-dependencies
(npm/pub); parent DNAs are regular dependencies of their child DNA;
helix resolves the tree recursively from `node_modules/` and
`.dart_tool/package_config.json` (diamond dedup, cycle detection)
- JSON overrides: sidecar `X.overrides.json` merges into `X.json` —
objects deep-merge, `null` deletes, `"key!"` replaces outright,
`"key+"` joins arrays (deduplicated); JSONC (comments, trailing
commas) is tolerated
- Variables: `dna/_vars.json` (deep-merged across layers, overridable
via `vars` in `.gg/dna.json`); references `dnaMyVar`, `DnaMyVar`,
`dna_my_var`, `DNA_MY_VAR`, `dna-my-var` are replaced case-adaptively;
non-identifier values verbatim
- File-naming conversion: DNA files are canonical kebab-case and are
converted per target (`pubspec.yaml` → snake_case, `package.json` →
camelCase, configurable via `fileNaming`); references to renamed files
are rewritten in text instances
- `helix init`: places the DNA wrapper test (Dart and/or vitest), a
`.gg/dna.json` skeleton and the `!.gg/dna.json` gitignore exception
- Public engine API: `instantiateDna()` and `runDnaTest()`
(`package:helix/helix.dart`); the engine core is free of `dart:io`
and compilable to WebAssembly (host access via injectable `DnaHost`)
- Per-file guard: an existing file that carries uncommitted work is
never overwritten or deleted — the run names those files and writes
nothing; unrelated dirty files do not block it
- Everything the DNA generates is committed right away as
`#gg: generated DNA` (path-limited, so unrelated changes stay in the
working tree); without a repository or git identity the files are kept
for a manual commit
- Provenance in every failure report: generated files are reported with
the DNA source they are produced from (`edit instead: dna_base/dna/doc/develop.md`), so hand edits go into the DNA instead of
the generated copy (`DnaInstantiationResult.sources`)
- `global.overrides.md` in the src root of any layer: its string blocks
rewrite `{{@tag:…}}` placeholders in every merged `.md` file; file-specific
overrides of the same layer win, heading-form blocks warn
- Warnings (file + line) for leftover pre-4.0 tag notation

### Changed

- BREAKING: `dna/src` is gone — a DNA's `dna/` folder itself mirrors
the project root (public/private via the `_` prefix convention)
- BREAKING: DNA configuration lives only in `.gg/dna.json`; `dna:`
blocks in `pubspec.yaml`/`package.json` and `dna.yaml` are migration
errors
- BREAKING: `helix sync` was replaced by `helix init` — the
instantiation runs inside the placed test on every test run
(hand-modified instances fail, DNA updates are written and committed)
- BREAKING: git layers were removed — declare DNAs as dev-dependencies;
`path:` overrides in `.gg/dna.json` remain for local development
- BREAKING: the bookkeeping is split in two and renamed —
`dna/_dna.json` (format v5: `layers` with `package`/`via`, hashes) and
`dna/_instances.json` (the files the DNA owns); leftover `.dna.json` /
`.instances.json` files are read once, so ownership survives, and then
removed
- BREAKING: the effective variables are no longer duplicated into the
bookkeeping — `dna/_vars.json` is their only home
- BREAKING: `config: claude: skills:` was removed — skills ship as
normal instances at `dna/.claude/skills/<name>`; only the managed
CLAUDE.md block (`claude_md: include:`) remains special
- Base DNA restructured: human documentation at `dna/doc/**`
(conventions, guides — English), skills at `dna/.claude/skills/**`
- BREAKING: every DNA source ships its mergeable DNA under `dna/src` —
the helix base DNA, git layers, and path layers; sources without `dna/src`
are an error with a migration hint
- BREAKING: `<target>/dna/src` is the implicit last layer — it survives the
sync verbatim, is never listed in the config (layer name `src` is
reserved), and replaces `dna/_override`; path layers pointing into
`<target>/dna` are an error
- BREAKING: override files are named `<file>.overrides.md` — the old
`.tag.md` suffix is a hard error with a rename hint
- BREAKING: new tag notation `## [@tag] …` and `{{@tag:default}}`
(comment markers `<!-- @tag -->`); the old notation without `@` is no
longer recognized
- BREAKING: `.dna.json` manifest format v4 (records the implicit src
layer; `--check` reports older manifests as outdated — run `helix sync`)

### Removed

- `helix sync` (including `--check`, `--source`, `--target`), git tag
resolution, the skills mirroring and the staging/backup folders
(`.helix_staging`, `.helix_backup` are no longer created)

## 3.1.1 - 2026-08-07

### Added

- Add .prettierignore and .prettierrc to dna

### Changed

- BREAKING: TypeScript projects instantiate with `kebab-case` file names
— `package.json` no longer defaults to `camelCase` (the value stays
selectable via `fileNaming`); Dart projects keep `snake_case`
- Rework DNA repos
- Provide first DNA, i.e. installation and .vscode settings
- Define dna repos

## 3.1.0 - 2026-08-04

Note: released out of order — this version shipped after 4.0.0 and
contains the rename below on top of the 4.0.0 changes.

### Changed

- Rename .master to .ocean with automatic migration at next start

## 3.0.0 - 2026-07-24

### Added

- `dna: config: claude:` section: `claude_md: include:` maintains a managed
`@`-import block in the target's CLAUDE.md (files stay as-is, folders expand
to their `.md` files); `skills: include:` mirrors skill folders into
`.claude/skills` — only skills helix installed are overwritten or removed,
hand-installed skills are never touched
- `helix sync` creates CLAUDE.md when missing and removes leftover pre-3.0
`helix:conventions` blocks
- `helix sync --check` also verifies the CLAUDE.md block and the installed
skills

### Changed

- BREAKING: layers now live under `dna: dependencies:` — the pre-3.0 syntax
(layer maps directly under `dna:`) is rejected with a migration hint
- BREAKING: `helix sync` is fully non-interactive — the
`install-skills` and `apply-conventions` subcommands, all prompts, and the
`--no-install` flag were removed; everything is driven by the
`dna: config:` block
- BREAKING: `.dna.json` manifest format v3 (adds the `claude` section;
`--check` reports older manifests as outdated — run `helix sync` once)

## 2.1.1 - 2026-07-24

## 2.1.0 - 2026-07-15

### Changed

- Support dna config via dna.yaml and package.json for non-Dart repos
- Harden dna config discovery: require dna block in dna.yaml, tolerate foreign package.json dna fields and undecodable sibling files

## 2.0.0 - 2026-07-15

### Added

- Add init-architecture skill that creates/updates README.architecture.md
- Add dna sync manifest with hash/check support and overlay tracking
- Multi-layer DNA: layers are configured in the target pubspec.yaml `dna:`
block — git layers (optionally pinned via a semver `version:` constraint
resolved against the repo tags), local path layers, and repo-local layers
like `dna/_override` that survive the sync verbatim
- Markdown tag overrides: `### [tag]` sections and `{{tag|default}}` strings
can be overridden per layer via `X.tag.md` files; all markers are rendered
away in the synced output

### Changed

- BREAKING: `helix sync` no longer accepts a positional overlay argument —
configure layers via the `dna:` block in the target pubspec.yaml
- BREAKING: the overlay stored in `.dna.json` is no longer auto-reused
- BREAKING: `.dna.json` manifest format v2 (ordered layer list; `--check`
reports pre-2.0 manifests as outdated)
- Release 2.0.0 docs: changelog, readme, dna config example
- Sync builds the new dna tree in a staging folder and swaps it in via
renames — errors can no longer destroy the existing `dna/` (in particular
in-dna override layers like `dna/_override`); interrupted swaps are
recovered from the backup folder on the next run
- Layers are resolved in parallel (clones, ls-remotes) — also in `--check`
- Prefer stable tags over prereleases in semver resolution
- Doc-comment density rule (max 3 lines before classes, 1 per member) added
to the shipped code conventions
- Use MIT license and shorten package description for pub.dev

### Fixed

- Crash (`RangeError`) when the same section tag appeared on nested headings
- Crash (`TypeError`) in `--check` on structurally malformed `.dna.json`
- Longer code fences now nest shorter ones (CommonMark closing rule), so
fenced markdown examples inside fences stay untouched
- Layer hashes ignore `.git/` and are line-ending agnostic — no more false
`--check` drift after git activity in a layer folder or CRLF checkouts
- A foreign `[tag]` in a replacement heading is replaced instead of
double-prefixed; mixed line endings normalize to the dominant one
- A configured but missing in-dna layer (e.g. `dna/_override` on a fresh
clone — git does not track empty folders) is skipped as empty instead of
failing the sync; `--check` agrees
- Backslash `path:` values in the pubspec work on every platform
- Fix negative hex hash rendering and cwd race between parallel test suites

## 1.1.0 - 2026-05-26

### Added

- Initial boilerplate.
- Add install-skills tests and .gitattributes; refactor for testability
- Add convention docs and apply-conventions command
- Add sync command and refactor install-skills/apply-conventions
- Add install.bat script and ignore .aicode in .gitignore
- Add workflow and commit discipline guides for gg-kidney and rljson
- Add init skill guide for generating project-aware CLAUDE.md

### Changed

- migrate claude/ configs to agents/, update references throughout
- Move dna files to dna folder
