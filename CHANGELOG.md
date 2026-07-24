# Changelog

## [3.0.0] - 2026-07-24

### Added

- `dna: config: claude:` section: `claude_md: include:` maintains a managed
`@`-import block in the target's CLAUDE.md (files stay as-is, folders expand
to their `.md` files); `skills: include:` mirrors skill folders into
`.claude/skills` — only skills gg_dna installed are overwritten or removed,
hand-installed skills are never touched
- `gg_dna sync` creates CLAUDE.md when missing and removes leftover pre-3.0
`gg_dna:conventions` blocks
- `gg_dna sync --check` also verifies the CLAUDE.md block and the installed
skills

### Changed

- BREAKING: layers now live under `dna: dependencies:` — the pre-3.0 syntax
(layer maps directly under `dna:`) is rejected with a migration hint
- BREAKING: `gg_dna sync` is fully non-interactive — the
`install-skills` and `apply-conventions` subcommands, all prompts, and the
`--no-install` flag were removed; everything is driven by the
`dna: config:` block
- BREAKING: `.dna.json` manifest format v3 (adds the `claude` section;
`--check` reports older manifests as outdated — run `gg_dna sync` once)

### Migration from 2.x

1. Move the layer maps into a `dependencies:` block under `dna:`.
2. Add the desired CLAUDE.md includes and skill folders to
   `dna: config: claude:`.
3. Run `gg_dna sync` once — the legacy conventions block in CLAUDE.md is
   replaced; `.claude/conventions/` copies are no longer used and can be
   deleted.

## [2.1.0] - 2026-07-15

### Changed

- Support dna config via dna.yaml and package.json for non-Dart repos
- Harden dna config discovery: require dna block in dna.yaml, tolerate foreign package.json dna fields and undecodable sibling files

## [2.0.0] - 2026-07-15

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

- BREAKING: `gg_dna sync` no longer accepts a positional overlay argument —
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

## [1.1.0] - 2026-05-26

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

[2.1.0]: https://github.com/ggsuite/gg_dna/compare/2.0.0...2.1.0
[2.0.0]: https://github.com/ggsuite/gg_dna/compare/1.1.0...2.0.0
[1.1.0]: https://github.com/ggsuite/gg_dna/tag/%tag
