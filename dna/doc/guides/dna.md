# The DNA System

The DNA system keeps a family of repositories consistent: shared
conventions, Claude skills, scripts, and configuration are written
**once** in DNA packages and **instantiated** into every consuming
project. This guide explains the system (gg_dna 5.x) for human
developers.

Two things are easy to confuse:

- **`gg_dna` is the engine** — the tool that resolves, merges and
  instantiates DNA. It carries no project conventions of its own.
- **The DNA is the content** — it lives in the DNA packages
  (`base_dna`, `dna_dart`, `dna-ts`, `ds-dna`, …). That is where you
  edit anything you want your projects to inherit.

## What a DNA Is

A DNA package is a normal pub/npm package that ships a `dna/` folder. That
folder is a **replica of a project root**: `dna/doc/conventions/…` lands
at `doc/conventions/…`, `dna/.claude/skills/review/SKILL.md` lands at
`.claude/skills/review/SKILL.md`, `dna/scripts/…` lands at `scripts/…`.

Every repository plays one of two roles, declared in `.gg/dna.json` — the
only place DNA configuration lives:

- **`"role": "dna"`** — a DNA repository. Its `dna/` folder is authored by
  hand and never overwritten. It is also applied to the repo itself as the
  top layer, so a DNA repo eats its own dog food.
- **`"role": "project"`** (default) — a consumer. Its `dna/` folder is
  fully generated. Never edit it.

## Layers and Inheritance

Projects consume DNAs as **dev-dependencies** (pub/npm). A DNA can itself
depend on a parent DNA as a regular dependency. gg_dna expands this into
an inheritance tree and merges the `dna/` replicas bottom-up:

1. the base DNA shipped with gg_dna itself (always the lowest layer),
2. the DNA dev-dependencies, parents before children, in declaration
   order (overridable via `"order"` in `.gg/dna.json`),
3. in a `role: dna` repo: the repo's own `dna/` folder as the top layer.

Later layers win on path collisions; diamond dependencies are merged only
once. For local development, `.gg/dna.json` can point a layer at a
checkout instead of the published package:

```jsonc
{ "dependencies": { "base_dna": { "path": "../base_dna" } } }
```

## Public vs. Private: the `_` Convention

Every file of the merged replica whose path contains **no segment starting
with `_`** is public and is copied to its project location as an
**instance**. Paths with a leading-underscore segment (`dna/_vars.json`,
`dna/_drafts/…`) stay inside `dna/`. Override sidecars (`*.overrides.md`,
`*.overrides.json`, `global.overrides.md`) are consumed by the engine and
never instantiated.

## Instances and the Placed Test

`gg_dna init` is the only CLI command. It places a wrapper test (Dart:
`test/dna/dna_test.dart`, TypeScript: `test/dna/dna.spec.ts`), a
`.gg/dna.json` skeleton, and a `!.gg/dna.json` gitignore exception. From
then on **every test run instantiates the DNA**: merge all layers, apply
overrides, substitute variables, convert file naming, and reconcile the
result with the project.

Outcomes (golden-update semantics):

| Situation | Result |
|---|---|
| Everything up to date | Test passes |
| The DNA produced updates | Files are written; the test fails once with "review & commit" |
| An instance was edited by hand | Test fails, nothing is written |
| A file to be overwritten has uncommitted changes | Test fails without writing |
| `LICENSE` missing | Test fails |

Two rules follow from this:

- **Per-file guard**: gg_dna never overwrites a file that carries
  uncommitted work — it names those files and writes nothing, so every
  DNA change appears as a reviewable diff on top of a commit. Dirty files
  the DNA does not touch are ignored: you can keep working while the DNA
  updates.
- **Instances belong to the DNA**: to change one, edit the DNA layer that
  owns it (or `dna/` in a `role: dna` repo) — the next test run
  propagates the change. When a generated file was edited by hand, the
  test names the DNA source file to edit instead, for example
  `edit instead: base_dna/dna/doc/develop.md`.

Getting started in a consumer:

```bash
dart pub add --dev gg_dna     # declare the DNA(s) as dev-dependencies
dart run gg_dna init          # place the test + config skeleton
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

Layers define variables in `dna/_vars.json` — camelCase keys **without**
prefix:

```json
{ "projectName": "my-project", "orgName": "acme" }
```

Variable files merge across layers (`null` deletes an inherited
variable); a project can override values via `"vars"` in `.gg/dna.json`.
In DNA content, variables are referenced **with the `dna` prefix**, and
each reference form renders the value in its own casing:

| Reference | Renders as (value `my-project`) |
|---|---|
| `dnaProjectName` | `myProject` |
| `DnaProjectName` | `MyProject` |
| `dna_project_name` | `my_project` |
| `DNA_PROJECT_NAME` | `MY_PROJECT` |
| `dna-project-name` | `my-project` |

Values that are not identifier-like (sentences, spaces) are inserted
verbatim in all forms. Unknown references stay literal.

## File-Naming Conversion

DNA files use **canonical kebab-case** names (`code-conventions.md`). At
instantiation, names are converted to the target's standard:

- `pubspec.yaml` present → snake_case (`code_conventions.md`)
- `package.json` present → camelCase (`codeConventions.md`)
- configurable via `"fileNaming"` in `.gg/dna.json`
  (`snake_case`, `camelCase`, `kebab-case`, `keep`)

Names containing uppercase letters (`README.md`, `SKILL.md`, `LICENSE`)
and dotfiles are never converted. References to renamed files inside text
instances are rewritten automatically.

## Configuration Reference (`.gg/dna.json`)

```jsonc
{
  "role": "project",            // "dna" for DNA repositories
  "order": ["base_dna"],        // layer order; default: dev-dependency order
  "vars": { "projectName": "my-project" },
  "fileNaming": "snake_case",   // camelCase | kebab-case | keep
  "dependencies": { "base_dna": { "path": "../base_dna" } },
  "config": {
    "claude": { "claude_md": { "include": ["doc/conventions"] } }
  }
}
```

All keys are optional. `config.claude.claude_md.include` maintains a
managed block of `@` imports in the project's `CLAUDE.md` (folders expand
to their `.md` files) between `<!-- gg_dna:claude_md:start -->` and
`<!-- gg_dna:claude_md:end -->`. `CLAUDE.md` itself is never a DNA
instance — only that block is managed; everything outside it belongs to
the project.

## What the Base DNA Ships

The gg_dna package itself carries the lowest layer:

- `doc/conventions/` — code, test, and documentation conventions,
- `doc/guides/` — this guide and a Claude Code quick start,
- `.claude/skills/` — the `init`, `new-project`, `new-ticket`, and
  `review` skills,
- `scripts/` — a placeholder for helper scripts of higher layers.

Organization DNAs layer their specifics (license headers, tooling
commands, org-specific guides) on top via the override mechanisms above.
