# The DNA System

The DNA system keeps a family of repositories consistent: shared
conventions, Claude skills, scripts, and configuration are written
**once** in DNA packages and **instantiated** into every consuming
project. This guide explains the system (Helix 5.x) for human
developers.

Two things are easy to confuse:

- **Helix is the engine** — the tool that resolves, merges and
  instantiates DNA. It ships no `dna/` folder and therefore no
  conventions of its own.
- **The DNA is the content** — it lives in the DNA packages
  (`dna_base`, `dna_dart`, `dna-ts`, `ds-dna`, …). That is where you
  edit anything you want your projects to inherit.

## What a DNA Is

A DNA package is a normal pub/npm package that ships a `dna/` folder. That
folder is a **replica of a project root**: `dna/doc/conventions/…` lands
at `doc/conventions/…`, `dna/dot-claude/skills/review/SKILL.md` lands at
`.claude/skills/review/SKILL.md`, `dna/scripts/…` lands at `scripts/…`.

Dotfiles are escaped with a `dot-` prefix, because `dart pub publish`
silently drops every path with a leading dot — an unescaped
`dna/.vscode/` never reaches a consumer that installs the DNA from pub.

Every repository plays one of two roles, declared in `dna/_dna.json` — the
only place DNA configuration lives. It sits inside `dna/` for the same
reason: that is the one folder both ecosystems publish.

- **`"role": "dna"`** — a DNA repository. Its `dna/` folder is authored by
  hand and never overwritten. It is also applied to the repo itself as the
  top layer, so a DNA repo eats its own dog food. This declaration is what
  makes a package usable as a layer; a `dna/` folder alone does not.
- **`"role": "project"`** (default) — a consumer. Its `dna/` folder is
  fully generated. Never edit it — except `dna/_dna.json`, which is yours.

## Layers and Inheritance

Projects consume DNAs as dependencies (pub/npm). A DNA declares its own
parents the same way. Helix expands this into an inheritance tree and
merges the `dna/` replicas bottom-up:

1. the layers listed in `"layers"`, parents before children — a layer's
   parents come from its own `dna/_dna.json`,
2. in a `role: dna` repo: the repo's own `dna/` folder as the top layer.

Helix itself ships no `dna/` folder, so it contributes no layer: every
file a project receives comes from a DNA package it declares. What a
project inherits is therefore fully described by its `"layers"`.

Later layers win on path collisions; diamond dependencies are merged only
once. Layers are named by the **package name** they are declared under in
`pubspec.yaml`/`package.json` — never by a path:

```jsonc
{ "version": 1, "layers": ["dna_base"] }
```

A DNA published to both registries is one layer, not two: the npm scope is
dropped when folding a name to its identity, so `@tssuite/dna-base` and
`dna_base` mean the same thing.

For local development nothing DNA-specific is needed — `gg_localize_refs`
points `pubspec_overrides.yaml`/`pnpm-workspace.yaml` at the sibling
checkouts, and Helix follows whatever the package manager resolved.

## Public vs. Private: the `_` Convention

Every file of the merged replica whose path contains **no segment starting
with `_`** is public and is copied to its project location as an
**instance**. Paths with a leading-underscore segment (`dna/_vars.json`,
`dna/_drafts/…`) stay inside `dna/`. Override sidecars (`*.overrides.md`,
`*.overrides.json`, `global.overrides.md`) are consumed by Helix and
never instantiated.

## Instances and the Placed Test

`helix init` is the only CLI command. It places a wrapper test (Dart:
`test/dna/dna_test.dart`, TypeScript: `test/dna/dna.spec.ts`) and a
`dna/_dna.json` skeleton with `layers` pre-filled from the DNA packages
you have installed. From then on **every test run instantiates the DNA**: merge all layers, apply
overrides, substitute variables, convert file naming, and reconcile the
result with the project.

Outcomes (golden-update semantics):

| Situation | Result |
|---|---|
| Everything up to date | Test passes |
| The DNA produced updates | Files are written and committed as `#gg: generated DNA` |
| An instance was edited by hand | Test fails, nothing is written |
| A file to be overwritten carries invalid changes | Test fails without writing |
| `LICENSE` missing | Test fails |

Two rules follow from this:

- **Per-file guard**: Helix never overwrites a file that carries
  uncommitted work — it names those files and writes nothing, so every
  DNA change appears as a reviewable diff on top of a commit. Dirty files
  the DNA does not touch are ignored: you can keep working while the DNA
  updates.
- **Instances belong to the DNA**: to change one, edit the DNA layer that
  owns it (or `dna/` in a `role: dna` repo) — the next test run
  propagates the change. When a generated file was edited by hand, the
  test names both files:

  ```text
  Generated files modified by hand:
  Move edits from doc/develop.md to dna_base/dna/doc/develop.md.
  ```

Getting started in a consumer:

```bash
dart pub add --dev helix     # declare the DNA(s) as dev-dependencies
dart run helix init          # place the test + config skeleton
git add -A && git commit -m "Add DNA"
dart test                     # first run instantiates → "review & commit"
git add -A && git commit -m "Instantiate DNA"
dart test                     # green
```

## Overrides

Higher layers can patch files of lower layers instead of replacing them.

### Markdown: `X.overrides.md`

A sidecar `guide.overrides.md` patches `guide.md`. The target file offers
two kinds of anchors:

- **Tagged sections** — a heading like `## [@setup] Setup` marks the whole
  section (up to the next heading of the same or higher level) as
  replaceable.
- **Tagged strings** — a placeholder like `{{@packageManager:npm}}` marks
  an inline value; `npm` is the default.

The overrides file contains only replacement blocks:

```markdown
## [@setup] Setup (company edition)

Use the company toolchain.

<!-- @packageManager --> pnpm <!-- @packageManager -->
```

A heading-form block replaces the whole tagged section. A
comment-delimited block (`<!-- @tag --> … <!-- @tag -->`, multi-line or
single-line) rewrites a string tag. Markers survive from layer to layer —
so even higher layers can override again — and are stripped from the final
instances. Fenced and inline code are never touched, so documentation can
show the syntax literally.

A `global.overrides.md` at a layer's `dna/` root rewrites string tags
across **all** files of lower layers (string form only).

### JSON: `X.overrides.json`

A sidecar `settings.overrides.json` merges into `settings.json`:

- objects deep-merge, scalars replace,
- `"key": null` deletes the key,
- `"key!": …` replaces the value outright (no merge),
- `"key+": […]` appends to an array (deduplicated),
- arrays without a suffix replace.

JSONC (comments, trailing commas) is tolerated in DNA JSON files.

## Variables

Layers define variables in `dna/_vars.json` — camelCase keys that
**must** start with `dna`; a key without the prefix fails the placed test
with the rename it expects:

```json
{ "dnaProjectName": "my-project", "dnaOrgName": "acme" }
```

Variable files merge across layers (`null` deletes an inherited
variable); a project can override values via `"vars"` in `dna/_dna.json`,
under the same prefixed keys. In DNA content, variables are referenced by
the very same name, and each reference form renders the value in its own
casing:

| Reference | Renders as (value `my-project`) |
|---|---|
| `dnaProjectName` | `myProject` |
| `DnaProjectName` | `MyProject` |
| `dna_project_name` | `my_project` |
| `DNA_PROJECT_NAME` | `MY_PROJECT` |
| `dna-project-name` | `my-project` |

Values that are not identifier-like (sentences, spaces) are inserted
verbatim in all forms. Unknown references stay literal.

A value may itself reference other variables — in any of the five forms:

```json
{ "dnaOrg": "acme", "dnaTitle": "Built by dnaOrg" }
```

`dnaTitle` becomes `Built by acme`. Helix loops over the values until no
reference to a known variable is left, at most 10 passes. Two setups are
rejected before instantiation starts: a cycle (`dnaA` → `dnaB` → `dnaA`,
including a variable referencing itself), reported with the path that
closes it, and a chain reaching deeper than 10 levels.

## File-Naming Conversion

DNA files use **canonical kebab-case** names (`code-conventions.md`). At
instantiation, names are converted to the target's standard:

- `pubspec.yaml` present → snake_case (`code_conventions.md`)
- `package.json` present → kebab-case (`code-conventions.md`)
- configurable via `"fileNaming"` in `dna/_dna.json`
  (`snake_case`, `camelCase`, `kebab-case`, `keep`)

Names containing uppercase letters (`README.md`, `SKILL.md`, `LICENSE`)
and dotfiles are never converted. References to renamed files inside text
instances are rewritten automatically.

## Configuration Reference (`dna/_dna.json`)

```jsonc
{
  "version": 1,                 // required
  "role": "project",            // "dna" for DNA repositories
  "layers": ["dna_base"],       // package names, in application order
  "vars": { "dnaProjectName": "my-project" },
  "fileNaming": "snake_case",   // camelCase | kebab-case | keep
  "claude": { "claudeMdInclude": ["doc/conventions"] }
}
```

Only `version` is required. `claude.claudeMdInclude` maintains a managed
block of `@` imports in the project's `CLAUDE.md` (folders expand to their
`.md` files) between `<!-- helix:claude_md:start -->` and
`<!-- helix:claude_md:end -->`. `CLAUDE.md` itself is never a DNA
instance — only that block is managed; everything outside it belongs to
the project.

Helix writes nothing into this file. Its own bookkeeping — the
resolved layers, their versions and hashes, and the list of instances it
owns — goes to `dna/_generated.json`, which is machine-owned and should
never be edited by hand.

## Where the Content Lives

Helix ships no content. The lowest layer of a typical setup is
`dna_base`, which carries what every repository of the family shares:

- `doc/conventions/` — code, test, and documentation conventions,
- `doc/guides/` — this guide and a Claude Code quick start,
- `.claude/skills/` — the `init`, `new-project`, `new-ticket`, and
  `review` skills,
- `scripts/` — a placeholder for helper scripts of higher layers.

Language and organization DNAs layer their specifics (license headers,
tooling commands, org-specific guides) on top via the override mechanisms
above. To change any of it, edit the DNA package — never the instance,
and never Helix.
