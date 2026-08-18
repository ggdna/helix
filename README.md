# Helix

Helix is the **DNA engine**. The DNA (the guides, scripts, configurations
and agent skills a project inherits) lives in separate **DNA packages**:
`dna_base`, `dna_dart`, `dna-ts`, `ds-dna`, … Each of them ships a `dna/`
folder that mirrors a project root.

Helix resolves the DNA packages a project depends on, merges their `dna/`
folders into one tree and copies the result to its real locations
(`.vscode/settings.json`, `LICENSE`, `doc/`, `.claude/skills/`, …).
These copies are called **instances** — and a placed test guarantees on
every test run that they always match the generated originals.

## Quick start

1. Run `helix init` in your project:

   ```bash
   helix init
   ```

   It runs in a Dart project (`pubspec.yaml`), in a TypeScript project
   (`package.json`) and in an empty folder — there it bootstraps a
   `package.json` with `npm init` first. It then

   - adds the engine as a dev-dependency: `helix` through `dart pub add`
     (`flutter pub add` in a Flutter project) and `@tssuite/helix-js`
     through the package manager the project uses — the `packageManager`
     field of `package.json` decides, otherwise the lock file that is
     there (pnpm, yarn, npm),
   - places `dna/_dna.json`, with `layers` pre-filled from the DNA
     packages you already have installed,
   - places `dna/doc/hello_world.md` — the getting-started doc, itself DNA
     content, so the engine instantiates it to `doc/hello_world.md`,
   - places the wrapper test: `test/dna/dna_test.dart` when the project
     declares `test`, `test/dna/dna.spec.ts` when it declares `vitest`.
     Without a test framework nothing is placed — `helix build` runs the
     same instantiation from the command line.

2. Add the DNA packages you want:

   ```bash
   helix add dna_dart                                  # pub package
   helix add @tssuite/dna-base                         # npm package
   helix add https://github.com/ggsuite/dna_base.git   # git repository
   helix add git@github.com:ggsuite/dna_base.git       # git, ssh
   ```

   Each `helix add` installs the DNA as a dev-dependency and appends its
   package name to `layers` in `dna/_dna.json` — at the end, because the
   last layer wins. The ecosystem follows the name: a scope or a `-` marks
   an npm name (a pub name may contain neither), anything else goes to pub
   when the project has a `pubspec.yaml`. For a git target the repository
   name is the package name — which is how DNA repositories are named.

   Declaring the dependency by hand and listing it under `layers`
   yourself does the same thing.

3. Run your tests — or `helix build`, which performs exactly the same run
   for a project without a test framework. The first run instantiates the
   DNA and commits what it generated as `#gg: generated DNA`. From now on
   every test run keeps the project in sync.

## Distribution: dev-dependencies + inheritance tree

DNAs are normal packages (pnpm, for Dart-reachable DNAs additionally
pub). A DNA declares its **parent DNAs as regular dependencies** — pnpm
and pub therefore install the whole inheritance tree transitively;
Helix clones nothing.

**Resolution.** Layers are named by the package name they are declared
under in `pubspec.yaml`/`package.json`, never by a path. Lock files
(`pubspec.lock`, `pnpm-lock.yaml`) supply the ecosystem, the resolved
version and the list of installed names; `node_modules/` and
`.dart_tool/package_config.json` supply the folder — a lock file pins an
identity, not a location, and reconstructing pub-cache or pnpm-store
paths would mean reimplementing package-manager internals. For local
development nothing DNA-specific is needed: gg_localize_refs writes
`pubspec_overrides.yaml`/`pnpm-workspace.yaml`, and Helix follows the
resolution that produces.

A DNA published to both registries collapses to one layer: the npm scope
is dropped when folding a name to its identity, so `@tssuite/dna-base`,
`dna_base` and `dna-base` are the same layer. node wins when both are
installed; a warning fires when the two copies carry different `dna/`
trees.

**Order**: `layers` is the single source of truth — parents before
children, diamonds deduplicated (first topological position wins), cycles
are errors. **The last layer wins.**

## Configuration: `dna/_dna.json`

The only place DNA configuration lives. It sits inside `dna/` because
that is the one folder both ecosystems publish — `pub` drops every path
with a leading dot, so a config below `.gg/` never reaches a
pub-installed consumer. Helix only ever _reads_ this file; what it
writes goes to `dna/_generated.json`.

A project without a `dna/` folder and without this file is simply not a
DNA project. A `dna/` folder **without** `_dna.json` is a hard error —
the config is what declares whether that folder is hand-authored
(`"role": "dna"`) or Helix-generated, and guessing `project` would let
Helix overwrite a hand-written DNA. Run `helix init` to place it.

```jsonc
{
  "version": 1, // required
  "role": "project", // "dna" for DNA packages themselves
  "layers": ["dna_base", "dna_dart"],
  "vars": { "dnaProjectName": "my_project" },
  "claude": { "claudeMdInclude": ["doc/conventions"] },
}
```

- `role: "project"` (default): `dna/` is fully generated by Helix.
- `role: "dna"`: the repo authors its `dna/` by hand; it is the last
  (winning) layer of its own instantiation and is never overwritten.
  This is also the mark that makes a package a DNA layer at all — a
  `dna/` folder alone does not.
- `layers` lists package names in application order. A dependency that
  is not listed is not a layer.

With `role: "dna"` the repo's own `dna/` is applied unconditionally and
always last — with an empty `layers`, with one layer, with a whole tree
of them, and even when a declared layer is another copy of the same
package. It always contributes its files and always wins a conflict.

## The replica layout

`dna/` mirrors the project root:

| Path in the DNA                       | Instantiated to                |
| ------------------------------------- | ------------------------------ |
| `dna/dot-vscode/settings.json`        | `.vscode/settings.json`        |
| `dna/LICENSE`                         | `LICENSE`                      |
| `dna/doc/develop.md`                  | `doc/develop.md`               |
| `dna/scripts/create-branch.js`        | `scripts/create-branch.js`     |
| `dna/dot-claude/skills/init/SKILL.md` | `.claude/skills/init/SKILL.md` |
| `dna/_vars.json`                      | — (private)                    |

- **Dotfiles are escaped** with a `dot-` prefix. `dart pub publish`
  silently drops every path with a leading dot, so a DNA that ships
  `dna/.vscode/` loses it the moment it is consumed from pub. The escape
  is decoded when instantiating; `dna/` itself keeps it, because that is
  what gets republished. A layer shipping literal dotfiles is warned
  about. `dot-` is the only accepted form: the placed test rejects a
  `dot_`-escaped path in `dna/` before instantiating and names the
  rename (`dna/dot_vscode` → `dna/dot-vscode`).
- **Private**: path segments starting with `_` (e.g. `_vars.json`) stay
  inside `dna/` and are never instantiated.
- **Public**: everything else becomes an instance.
- Consumed by Helix itself: `*.overrides.md`, `*.overrides.json`
  sidecars, plus the two manifests — `dna/_dna.json` (yours) and
  `dna/_generated.json` (Helix's: layers, hashes, and the project files
  the DNA owns). The effective variables are neither: they are
  content and live in `dna/_vars.json`.
- Forbidden instance targets: `.git/**` and `CLAUDE.md` (the latter is
  managed via the `claude` block below).

## The placed test: instantiate + verify in one

Every test run executes Helix (Dart: in-process via the `helix`
dev-dependency; TypeScript: via the npm package `@tssuite/helix-js`,
Helix compiled to WebAssembly with node callbacks injected):

- **Instance changed locally** → the DNA content wins. The local content
  is copied to a fresh folder below the system temp directory (never into
  the project, so it stays out of git and out of the next run) and the
  report prints that path:

  ```text
  Local changes of .vscode/settings.json were backed up to /tmp/helix-dna-backup-a1b2/.vscode/settings.json
  ```

- **DNA updated** (new dependency versions, changed local DNA) → Helix
  rewrites `dna/`, the instances and its bookkeeping and commits
  exactly those files as **`#gg: generated DNA`** — generated content is
  machine-owned and never clutters your working tree. Without a
  repository or a git identity the files stay for a manual commit — the
  run reports them and passes.
- **Everything up to date** → green, no writes.
- **Per-file guard**: every existing file a run would overwrite or
  delete must be committed — except instances the DNA owns, whose local
  content is copied to the backup folder instead. If one of the others carries uncommitted
  work (modified, staged or untracked), the run fails without writing and
  reports each file the same way — `Move edits from <instance> to <DNA
source>.` (headline: _Generated files carry invalid changes:_) Unrelated dirty files never block a run,
  so every overwrite stays recoverable via git.

Existing project files that a DNA also ships are **adopted**
(overwritten — git history is the backup, which is exactly what the
per-file guard enforces). Instances no longer produced by any DNA are
removed, together with folders they leave empty; locally modified ones
are kept with a warning.

## Markdown overrides

Unchanged from 4.0, now across the whole replica: `## [@tag] Heading`
marks a replaceable section, `{{@tag:default}}` a replaceable string. A
higher layer ships `X.overrides.md` next to the same path with
heading-form or `<!-- @tag --> … <!-- @tag -->` blocks;
`global.overrides.md` in the `dna/` root rewrites string placeholders in
all merged `.md` files. Markers survive layer application; the final
render strips them. Content in code fences and inline code is immune.

## JSON overrides

A same-path `X.json` in a later layer replaces the file. A sidecar
`X.overrides.json` merges field-wise:

- objects deep-merge (default), scalars replace
- `null` deletes the key
- `"key!"` **replaces** the value outright (no merge)
- `"key+"` **joins arrays** (append, deduplicated)

```jsonc
// dna_base: dna/dot-vscode/extensions.json
{ "recommendations": ["esbenp.prettier-vscode"] }
// dna_dart: dna/dot-vscode/extensions.overrides.json
{ "recommendations+": ["dart-code.dart-code"] }
// instance: .vscode/extensions.json
{ "recommendations": ["esbenp.prettier-vscode", "dart-code.dart-code"] }
```

JSONC input (comments, trailing commas) is tolerated; structurally
patched files are re-emitted comment-free, untouched files are copied
byte-identical. YAML supports whole-file replacement only —
`X.overrides.yaml` is an error.

## Variables

Defined in `dna/_vars.json` (camelCase keys that **must** start with
`dna`), deep-merged across all layers, finally overridden by `vars` in
the target's `dna/_dna.json`:

```json
{ "dnaCopyrightHolder": "ggsuite", "dnaProjectName": "unnamed" }
```

A key without the `dna` prefix is a hard error: the run fails and names
the rename it expects (`projectName` → `dnaProjectName`). Declaration and
reference are therefore the same name, replaced case-adaptively in every
text file of the merged tree:

| Reference          | Replacement                            |
| ------------------ | -------------------------------------- |
| `dnaProjectName`   | camelCase (`myProject`)                |
| `DnaProjectName`   | PascalCase (`MyProject`) — class names |
| `dna_project_name` | snake_case (`my_project`)              |
| `DNA_PROJECT_NAME` | SCREAMING_SNAKE (`MY_PROJECT`)         |
| `dna-project-name` | kebab-case (`my-project`)              |

Non-identifier values (spaces, sentences — e.g. `"MEGA TARGET"`) are
inserted verbatim for every form. Unknown references stay literal.

**Variables may reference variables.** A value carrying a reference is
expanded before anything else is substituted, in the casing of the form
it is written in:

```json
{ "dnaOrg": "acme", "dnaTitle": "Built by dnaOrg", "dnaLib": "dna_org/lib" }
```

resolves to `dnaTitle = "Built by acme"` and `dnaLib = "acme/lib"`. The
expansion loops until nothing is left to replace, at most 10 times.
Reference cycles are detected up front and reported with the path that
closes them (`Cyclic variable reference: dnaA → dnaB → dnaA.`), as is a
chain deeper than 10 levels.

## File naming

DNA files are instantiated under exactly the name they carry in the DNA
layer — no case conversion happens. Author each file with the name the
target project should see (the dot escape `dot-vscode/` → `.vscode/` is
the only path rewriting Helix performs).

## CLAUDE.md and skills

- Skills are plain instances: `dna/dot-claude/skills/<name>/SKILL.md` →
  `.claude/skills/<name>/SKILL.md`.
- `CLAUDE.md` keeps the managed block: `claude.claudeMdInclude`
  lists files/folders (human documentation!) that get one `@`-import
  line each between `<!-- helix:claude_md:start/end -->`. Content
  outside the block is never touched. All documentation is written for
  humans — the AI consumes the same files.

## Helix API

```dart
import 'package:helix/helix.dart';

await runDnaTest();                  // what the placed test calls
final result = instantiateDna(       // programmatic access
  host: IoDnaHost(),
  targetRoot: '.',
  baseVersion: helixVersion,
);
```

The Helix core is free of `dart:io`/`Process` — all host access goes
through the injectable `DnaHost` interface (`IoDnaHost` for the CLI and
Dart tests, callback-based hosts for the WebAssembly bridge
`@tssuite/helix-js`).
