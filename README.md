# Helix

Helix is the **DNA engine**. The DNA (the guides, scripts, configurations
and agent skills a project inherits) lives in separate **DNA packages**:
`dna_guides`, `dna_dart`, `dna-ts`, `ds-dna`, … Each of them ships a `dna/`
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
   (`package.json`) and in an empty folder — there it asks whether the
   project is Dart or TypeScript and bootstraps a `pubspec.yaml` or a
   `package.json` (with `npm init`) first. Pass `--language dart` or
   `--language typescript` to skip the question, which headless runs
   have to. It then

   - adds the engine as a dev-dependency: `helix` through `dart pub add`
     (`flutter pub add` in a Flutter project) and `@tssuite/helix-js`
     through the package manager the project uses — the `packageManager`
     field of `package.json` decides, otherwise the lock file that is
     there (pnpm, yarn, npm),
   - places `dna/_dna.json`, with `layers` pre-filled from the DNA
     packages you already have installed,
   - places the DNA check: `test/dna/dna_test.dart` in a Dart project
     (a `pubspec.yaml`) that declares `test` or `flutter_test`,
     `test/dna/dna.spec.ts` in a TypeScript project that declares
     `vitest`. An existing check is replaced. Without a test framework
     nothing is placed.

2. Add the DNA packages you want:

   ```bash
   helix add dna_dart                                  # pub package
   helix add @ggdna/dna-guides                         # npm package
   helix add https://github.com/ggdna/dna_guides.git   # git repository
   helix add git@github.com:ggdna/dna_guides.git       # git, ssh
   ```

   Each `helix add` installs the DNA as a dev-dependency, appends its
   package name to `layers` in `dna/_dna.json` — at the end, because the
   last layer wins — and then builds: the same run `helix build` performs,
   so the project is in sync when the command returns.

   The ecosystem follows the name: a scope or a `-` marks an npm name (a
   pub name may contain neither), anything else goes to pub when the
   project has a `pubspec.yaml`. For a git target the repository name is
   the package name — which is how DNA repositories are named. A package
   that ships no DNA (no `dna/_dna.json`) is refused, and nothing is
   written to `layers`.

   Declaring the dependency by hand and listing it under `layers`
   yourself does the same thing — followed by `helix build`.

3. Run `helix build`. It instantiates the DNA and commits what it
   generated as `#gg: generated DNA`. From now on every test run checks
   that the generated files are unchanged — the check writes nothing.

4. Later, `helix upgrade` brings the project to the installed layers:
   it places the newest DNA check — the Dart check in a Dart project, the
   vitest check in a TypeScript project, removing a check of the other
   language that helix placed — and then runs `helix build`.

   `helix build` and `helix add` work on the root of the repository the
   current folder lies in, so they can be run from any subfolder. Outside
   a repository they use the current folder; `--target` names another
   folder explicitly.

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
is dropped when folding a name to its identity, so `@ggdna/dna-guides`,
`dna_guides` and `dna-guides` are the same layer. node wins when both are
installed; a warning fires when the two copies carry different `dna/`
trees.

**Order**: `layers` is the single source of truth — parents before
children, diamonds deduplicated (first topological position wins), cycles
are errors. **The last layer wins** — except for `dna/CLAUDE.md`, of which
every layer keeps its own (see [CLAUDE.md and skills](#claudemd-and-skills)).

## Configuration: `dna/_dna.json`

The only place DNA configuration lives. It sits inside `dna/` because
that is the one folder both ecosystems publish — `pub` drops every path
with a leading dot, so a config below `.gg/` never reaches a
pub-installed consumer. Helix only ever _reads_ this file; what it
writes goes to `dna/_generated.json`.

A project without a `dna/` folder and without this file is simply not a
DNA project. A `dna/` folder **without** `_dna.json` is a hard error —
the config is what names the layers that folder builds on. Run
`helix init` to place it.

```jsonc
{
  "version": 1, // required
  "layers": ["dna_guides", "dna_dart"],
  "vars": { "dnaProjectName": "my_project" },
  "mustOverride": { "dnaProjectName": true },
  "claude": { "claudeMdInclude": ["doc/conventions"] },
}
```

- `layers` lists package names in application order. A dependency that
  is not listed is not a layer.
- `mustOverride` names variables the layers below must set themselves
  and needs `"version": 2` (see [Variables](#variables)).

`dna/` is always hand-authored source. Helix never writes into it — the
merged result is instantiated into the project root and nowhere else.
Every package carrying a `dna/_dna.json` can therefore be used as a
layer; no flag permits or forbids it, the consumer decides by listing it.

The repo's own `dna/` is applied unconditionally and always last — with
an empty `layers`, with one layer, with a whole tree of them, and even
when a declared layer is another copy of the same package. It always
contributes its files and always wins a conflict.

A `"role"` left over from earlier versions is ignored; Helix reminds you
to remove it from your own config and stays silent about the configs of
your layers.

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
- Forbidden instance targets: `.git/**`. A `dna/CLAUDE.md` does not
  instantiate to the project's `CLAUDE.md`: it becomes
  `.claude/CLAUDE_<layer>.md`, imported by the managed block of the
  project's `CLAUDE.md` (see below).

## The placed check: verify, write nothing

Every test run checks the DNA with `checkDna` (Dart: in-process via the
`helix` dev-dependency; TypeScript: via the npm package
`@tssuite/helix-js`, Helix compiled to WebAssembly). It plans the same
run as `helix build` and writes, backs up and commits nothing:

- **Generated file changed or deleted by hand** → fails, naming the DNA
  file the edit belongs in and the `git checkout` that restores it
  (headline: _Generated DNA files were changed or deleted by hand:_).
  This covers every instance, the managed block of `CLAUDE.md` and
  `dna/_generated.json` itself
- **DNA updates outstanding** (a newer helix, a changed layer, a changed
  `dna/` or `dna/_dna.json`) → reported with `gg dna build`, passes
- **`dot_` escape in `dna/`** → fails with the `dot-` rename

How it tells the two apart: `dna/_generated.json` records the helix
version, the content hash of every layer and of `dna/_dna.json`, and the
hash of every instance and of the managed `CLAUDE.md` block. While helix,
the layers and the configuration hash as recorded, the DNA is unchanged —
the project must then match the DNA output exactly, and any difference
was made by hand, even one whose hash was edited into the manifest too.
After a DNA update, a file still matching its recorded hash is an update
to apply; one that no longer does was changed by hand.

The check is placed only where it can run: the project declares the engine
(`helix`, or `@tssuite/helix-js`) and its test framework (`test` or
`flutter_test`, or `vitest`). Where the engine is gone, a check helix
placed is removed again.

## The build: instantiate + verify in one

`helix build`, `helix add` and `helix upgrade` run the instantiation
(`runDnaTest`):

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

Across the whole replica: `## @tag Heading` marks a replaceable section.
A higher layer ships `X.overrides.md` next to the same path with
heading-form or `<!-- @tag --> … <!-- @tag -->` blocks. Markers survive
layer application; the final render strips them. Content in code fences
and inline code is immune.

There are no string placeholders — a single value that differs per
project is a variable in `dna/_vars.json`, not a marker. The retired
notations (`## [@tag] …` and `{{@tag:default}}`) are still detected and
reported, so nothing changes meaning silently.

## JSON overrides

A same-path `X.json` in a later layer replaces the file. A sidecar
`X.overrides.json` merges field-wise:

- objects deep-merge (default), scalars replace
- `null` deletes the key
- `"key!"` **replaces** the value outright (no merge)
- `"key+"` **joins arrays** (append, deduplicated)

```jsonc
// dna_guides: dna/dot-vscode/extensions.json
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

## Ignore files

A file whose name starts with a dot and ends with `ignore` is never
replaced by a later layer: Helix joins the lines of every layer into one
file, one `# <layer>` section per layer in layer order, the own `dna/`
last. A pattern an earlier section already holds is left out.

`dna/dot-pubignore` of a layer `dna_readme` and of a layer `dna_scripts`
listed after it:

```gitignore
/doc/guides/
/doc/templates/
/scripts/
```

```gitignore
/doc/guides/
/scripts/
```

The project's `.pubignore`:

```gitignore
# .gitignore
.dart_tool/
coverage

# dna_readme
/doc/guides/
/doc/templates/
/scripts/
```

`dna_scripts` adds nothing new, so it gets no section.

A root `.pubignore` starts with the project's `.gitignore`: `dart pub
publish` reads the `.pubignore` instead of the `.gitignore`, so without it
everything git ignores would be published. Never list `/dna/` — a package
used as a layer is read from its published `dna/` folder.

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

### Values a layer must set: `mustOverride`

A layer marks variables whose value every layer below it has to set
explicitly — in `dna/_dna.json`, next to `layers`. The flags need format
version 2:

```jsonc
{
  "version": 2,
  "layers": [],
  "mustOverride": { "dnaGitQuickCheckPipelineName": true },
}
```

- `true`: every child layer (a layer listing this one in its `layers`)
  and the project must give the variable a value in its **own**
  `dna/_vars.json`. `vars` in `dna/_dna.json` and `null` do not count; a
  value that only reaches the merge through a sibling layer does not
  either.
- A layer that does not mention the variable inherits the flag of its
  parents — one parent passing on `true` is enough.
- `false` lifts the duty for the layers below. The layer that writes
  `false` is itself still bound by what it inherits.
- The declaring layer is never bound by its own flag, so its own placed
  test needs no value.
- A `--workspace` build exempts the workspace itself (its `dna/` is a
  throwaway scaffold); its layers are still checked.

A missing value fails the run before anything is written, naming the
file to fix and the layer that asks for it:

```text
Variables marked mustOverride have no value:
  dna/_vars.json must set "dnaGitQuickCheckPipelineName" (mustOverride of dna-scripts)
```

`helix init` and `helix add` ask for every value the layers require and
the project does not set yet, and write the answers into
`dna/_vars.json` — comments stay. The inherited value is never offered:
it is exactly what has to be replaced. Only a value the project already
gives in the `vars` of `dna/_dna.json` is offered as the default. A
`--workspace` add and a `--quiet` init ask nothing; without a terminal
they name the variables to set by hand instead.

**Compatibility.** Configs with `"version": 1` stay valid and are read
as before; only a config using `mustOverride` needs `"version": 2`, and
`mustOverride` in a version 1 config is an error. The version is what
enforces a current engine: a helix (or gg) that predates the flags
rejects a version 2 config instead of ignoring them silently — in a
consumer as much as in the layer itself, since every layer's config
is read. A `helix: ^1.12.0` in a layer's `pubspec.yaml` covers only
its own placed test: helix is a dev dependency there, and dev
dependencies do not reach the consumers.

## File naming

DNA files are instantiated under exactly the name they carry in the DNA
layer — no case conversion happens. Author each file with the name the
target project should see (the dot escape `dot-vscode/` → `.vscode/` is
the only path rewriting Helix performs).

## CLAUDE.md and skills

- Skills are plain instances: `dna/dot-claude/skills/<name>/SKILL.md` →
  `.claude/skills/<name>/SKILL.md`.
- Every layer that ships a `dna/CLAUDE.md` gets its own instance
  `.claude/CLAUDE_<layer>.md`, named after the bare package name with
  `-` turned into `_` (`@ggdna/dna-gg` → `.claude/CLAUDE_dna_gg.md`);
  the own `dna/` is filed under the project's package name. A topic
  layer therefore cannot wipe out the instructions of another; an empty
  file or a text an earlier layer already ships is not repeated. The
  file is rendered and substituted like every other DNA file, and its
  relative `@`-imports get a `../`, since Claude Code resolves them
  relative to `.claude/`. `CLAUDE.overrides.md` patches a tagged section
  in every layer file that carries it. A layer that drops out takes its
  file along.
- `CLAUDE.md` keeps the managed block between
  `<!-- helix:claude_md:start/end -->`. Content outside the block is
  never touched. The block holds only `@`-import lines, in this order:
  - one per `.claude/CLAUDE_<layer>.md`, in layer order, the own `dna/`
    last. Once no layer ships one any more, the next run empties the
    block again.
  - one per file of `claude.claudeMdInclude` (files or folders of human
    documentation!).

  ```markdown
  <!-- helix:claude_md:start -->

  @.claude/CLAUDE_dna_gg.md
  @.claude/CLAUDE_dna_dart.md

  <!-- helix:claude_md:end -->
  ```

  All documentation is written for humans — the AI consumes the same
  files.

## Helix API

```dart
import 'package:helix/helix.dart';

await checkDna();                    // what the placed check calls
await runDnaTest();                  // what helix build runs
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
