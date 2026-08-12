# Code Conventions (Dart / Flutter)

These rules define a uniform code style for Dart and Flutter packages. They
are the generic base shipped with `gg_dna` — organization- or
project-specific additions (class prefixes, the concrete license header,
extra lints) belong in a higher DNA layer, which can override single
sections or whole files (see `../guides/dna.md`).

## 1. Package & File Layout

- **Package name = repo name = class prefix.** Example: `foo_bar` exports
  `FooBar`. Never put two top-level concepts into one package.
- **The public API lives in `lib/<package>.dart`** and is a pure barrel
  file: license header, `library;`, then exclusively `export 'src/...';`
  lines. No implementation.
- **The implementation lives in `lib/src/<file>.dart`.** External consumers
  never import `package:<pkg>/src/...`.
- **File names are snake_case** and mirror the main type they contain
  (`foo_bar.dart` contains `class FooBar`). Closely related small helpers
  (enums, typedefs, short data classes) may live in the same file.
- **Tests mirror `lib/src/` 1:1**: `lib/src/foo.dart` →
  `test/foo_test.dart`. See `test_conventions.md`.

## 2. License Header

**Every `.dart` file** starts with a uniform license header. The concrete
wording is organization-specific — a higher DNA layer overrides this
section with the exact header. Example:

```dart
// @license
// Copyright (c) <YEARS> <AUTHOR>. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.
```

After the header: a blank line, then `library;` (only in the barrel file)
or the imports.

## 3. Imports

- **Order:** `dart:` first, then `package:`, then relative imports — each
  group alphabetical, separated by blank lines.
- **Within the package**: prefer relative imports
  (`import '../foo_bar.dart';`) — the `prefer_relative_imports` lint is
  active in most setups.
- **In tests**, import your own package via `package:<pkg>/<pkg>.dart`,
  not via `src/`.

## 4. Class Layout

Member order:

1. **Constructor(s)** first, with a `///` doc comment.
2. **Factory constructors** next (`Foo.generate(...)`, `Foo.fromList(...)`).
3. **Public methods**, ordered by logical relatedness, not alphabetically.
4. **Public fields / getters** (all `final`).
5. **Static constants and methods.**
6. **Private fields & methods** at the end, prefixed with `_`.

Fields are `final` by default. Mutability is avoided; "changing" happens
via copy-with methods (`copyWithValue`, `transform`).

## 5. Constructors & API

- **Named parameters with `required`** are the default. Positional
  parameters only for trivial one-argument constructors.
- Sensible defaults in the constructor (`ggLog = print`,
  `useCarriageReturn = !isCi`).
- **Generic type parameters** wherever reusable containers/workflows are
  involved (`FooContainer<T>`, `BarList<T>`).
- **Factory constructors** for alternative creation (`.generate`,
  `.fromList`, `.fromX`).
- Async code: return `Future<T>`, handle errors with
  `try / catch / rethrow` (no swallowing).
- The `unawaited_futures` lint is active — either await every `Future` or
  mark it explicitly with `unawaited(...)`.

## 6. Section Comments (Visual Landmarks)

These markers are a codebase-wide convention — they help with scanning and
are not doc comments:

- **`// #############################################################################`**
  — before classes, enums, or other top-level constructs.
- **`// ...........................................................................`**
  — before every method, getter, or field block that carries a doc comment.
- **`// .............................................................................`**
  (longer) — at the start of a file or for larger section separators.
- **`// ######################\n// Section Name\n// ######################`**
  — inside large classes to mark logical sections (e.g. `Constructors`,
  `Data access`, `List methods`, `Private`).

Keep the style consistent across all files — **do not omit it**, do not
replace it with home-grown variants.

## 7. Documentation in Code

- **Every public member** has a `///` doc comment (the
  `public_member_api_docs` lint is active).
- **First line**: a short, complete statement in 3rd-person indicative
  ("Runs the operation and displays the status").
- **Keep it dense**: at most **3 `///` lines before a class**; default to
  **one `///` line per method, getter, constructor, or field** (blank `///`
  lines count). Longer explanations (grammars, formats, pipelines) belong
  in a library header, the README, or `//` comments inside the code.
- **Parameters** that genuinely need explanation are documented with the
  `- [name] <description>` syntax on follow-up lines — the accepted
  exception to the one-line default:

  ```dart
  /// Run the operation and display the status.
  ///
  /// - [task] to be executed.
  ///   - If the task throws, an error state will be printed.
  ///   - If the task completes successfully, a success state will be printed.
  ```

- **Bullet lists** are indented with `-`; nested bullets with `  -`.
- **Examples** in doc comments only as a fenced `dart` block and only when
  the call is not obvious from signature + description — otherwise the
  README is the place.
- **Make throw behavior explicit** when relevant:
  `Throws a [StateError] when ...`.

## 8. Linter Rules (Mandatory Set)

`analysis_options.yaml` contains:

```yaml
include: package:lints/recommended.yaml

linter:
  rules:
    - camel_case_types
    - prefer_relative_imports        # possibly off in Flutter packages with example/
    - lines_longer_than_80_chars     # often disabled in Flutter packages
    - prefer_single_quotes
    - void_checks
    - require_trailing_commas
    - prefer_const_constructors
    - always_declare_return_types
    - prefer_const_constructors_in_immutables
    - prefer_const_declarations
    - prefer_const_literals_to_create_immutables
    - prefer_constructors_over_static_methods
    - package_api_docs
    - public_member_api_docs
    - missing_whitespace_between_adjacent_strings
    - unawaited_futures

analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
  errors:
    always_declare_return_types: true
```

Flutter packages may disable `lines_longer_than_80_chars` and `strict-*`
**when necessary** — but only there.

## 9. Naming Quickref

| Construct      | Style                                  | Example                    |
| -------------- | -------------------------------------- | -------------------------- |
| Class          | PascalCase                             | `RouterDelegate`           |
| File           | snake_case                             | `router_delegate.dart`     |
| Test file      | `<filename>_test.dart`                 | `router_delegate_test.dart` |
| Private member | `_camelCase`                           | `_updateState`             |
| Constant       | `lowerCamelCase` (no SCREAMING_SNAKE)  | `carriageReturn`           |
| Enum value     | `lowerCamelCase`                       | `Status.success`           |

Project-specific class prefixes (e.g. a package-family-wide `Foo` prefix)
belong in a higher DNA layer, not in this base file.

## 10. What Not to Do

- **No** `dynamic` return types (the `always_declare_return_types` lint is
  an error).
- **No** double quotes (the `prefer_single_quotes` lint).
- **No** unawaited futures without `unawaited(...)`.
- **No** mutations of public fields; setters only with a clear
  justification.
- **No** TODO comments without an issue/ticket reference.
- **No** commented-out code blocks "for later" — git is the history.
- **No** Co-Authored-By trailers in commits (applies repository-wide).
