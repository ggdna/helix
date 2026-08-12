# Documentation Conventions

Documentation is **functional**, not "pretty". Every piece of
documentation has a clear goal: API understanding, reproducibility,
traceability of changes. This file is the generic base shipped with
`gg_dna`; organization-specific tooling notes (CI workflows, commit
wrappers) belong in a higher DNA layer.

## 1. Doc Comments in Code (`///`)

See `code_conventions.md` §7 (including the density guidance: at most 3
lines before classes, one line per member by default). In addition:

- **What, not how.** "Returns the list value at index `[i]`" — not "Loops
  through internal data and returns the i-th".
- **Consistent tense**: 3rd-person indicative ("Updates the state.",
  "Throws when ..."); no "Will update", no imperative "Update the state.".
- **Parameters**: mention them in the summary line with `[name]`
  references (`/// Runs [task] and prints its success or error state.`);
  switch to the `- [name]` bullet syntax of `code_conventions.md` §7 when
  their behavior needs real explanation.
- **Examples and longer explanations** belong in the README or a library
  header; a fenced `dart` block in a doc comment only when the call is not
  obvious from signature + description.
- **Throw behavior** is part of the contract — make it explicit when
  relevant: `Throws a [StateError] when closed.`

## 2. README.md

Mandatory structure (in this order):

````markdown
# <PackageName>

<1–3 sentences: What does this package do? Which problem does it solve?>

## Features (or: ## Description / ## Classes depending on the package)

- **<Feature>**: <short explanation>
- ...

## Usage / Example Usage

```dart
import 'package:<pkg>/<pkg>.dart';

void main() async {
  // Minimal example that runs without modification
}
```

## Features and bugs

Please file feature requests and bugs at [GitHub](https://github.com/<org>/<pkg>).
````

Optional and common:

- **`## State`** with a CI badge of the project's main workflow.
- **`## Classes`** as a table for multi-class packages:

  ```markdown
  | Class            | Description                          |
  | :--------------- | :----------------------------------- |
  | `FooList`        | Create lists of ordinary value types |
  ```

- **`## How It Works`** for non-trivial mechanics.
- **TOC** for long READMEs (maintained manually).

Tone: terse, technical, English. No marketing sentences.

## 3. CHANGELOG.md

[Keep a Changelog](https://keepachangelog.com) style:

```markdown
# Changelog

## [1.2.0] - 2026-04-29

### Added
- New `Foo.bar` factory.

### Changed
- Default of `useCarriageReturn` is now `!isCi`.

### Fixed
- Race condition in `dispose`.

### Removed
- Deprecated `legacyMethod`.

## [1.1.5] - 2026-04-12
...

[1.2.0]: https://github.com/<org>/<pkg>/compare/1.1.5...1.2.0
[1.1.5]: https://github.com/<org>/<pkg>/compare/1.1.4...1.1.5
```

Rules:

- **Reverse chronological** (newest on top).
- **Sections** only when relevant: `Added`, `Changed`, `Fixed`, `Removed`
  (sometimes `Deprecated`, `Security`).
- **Version header**: `## [<semver>] - <YYYY-MM-DD>`. Square brackets for
  linked versions.
- **Compare links** at the end of the file — maintain them manually or let
  project tooling generate them.
- **Bullet items** are short and imperative ("Add X", "Fix Y").

## 4. example/

- **Dart packages**: `example/<pkg>_example.dart` — one file, runnable via
  `dart run example/<pkg>_example.dart`. Optional shebang
  `#!/usr/bin/env dart`.
- **Flutter packages**: `example/` is a separate Flutter sub-project
  (`example/lib/main.dart`, `example/pubspec.yaml`, `example/test/`).
- **License header** in examples too.
- **Functionally complete**: the example shows the happy path including
  setup. No "TODO: implement".

## 5. Workflow Files (.github/workflows/)

Which pipeline runs is project-specific — a higher DNA layer overrides
this section with the concrete setup. The typical structure:

- Trigger: `push` to `main` (and PRs where applicable).
- Steps: checkout → SDK setup → `pub get` → `dart analyze` →
  `dart format --set-exit-if-changed` → `dart test`.
- Optional: `pana` for packages before publishing, `flutter test` for
  Flutter packages.

Pipeline changes should be agreed with the team, not made unilaterally.

## 6. CLAUDE.md

The `CLAUDE.md` in the repo root is loaded automatically by Claude Code.
Recommended content:

- **Repo-specific guidance**: architecture sketch, domain terms,
  project-specific workflows, the commands that matter.
- **References to the instantiated conventions**: the DNA places these
  convention documents at `doc/conventions/` in every consumer. Import
  them with `@` imports (e.g. `@doc/conventions/code_conventions.md`)
  instead of duplicating their content. When `dna/_dna.json` configures
  `claude.claudeMdInclude`, the DNA test maintains such an import
  block automatically between `<!-- gg_dna:claude_md:start -->` and
  `<!-- gg_dna:claude_md:end -->` — leave those markers untouched and put
  hand-written notes outside the block.

Not in CLAUDE.md: onboarding prose, marketing, anything that is better
placed in the README or in code documentation.

## 7. What Not to Document

- **Trivialities**: a getter `length` needs no doc comment saying "Returns
  the length" — the lint forces one, but then the plain variant is enough.
- **"How the code does it"**: that is what the code is for. Doc comments
  explain *what* and *why*, not *how*.
- **Personal notes**, "maybe later" plans, "FIXME: I don't understand
  this" — such comments do not belong in the repo.
