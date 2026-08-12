# Test Conventions (Dart / Flutter)

Tests are mandatory, not a recommendation. The default bar is 100 %
coverage with all tests green — pre-commit tooling and CI are expected to
block anything below it. This document is the generic base shipped with
`gg_dna`; organization-specific tooling commands live in a higher DNA
layer.

## 1. File Structure

- **1:1 mirror** of `lib/src/` to `test/`:
  - `lib/src/foo.dart` → `test/foo_test.dart`
  - `lib/src/sub/bar.dart` → `test/sub/bar_test.dart`
- **One test file per source file.**
- Test files start with the **license header** (see
  `code_conventions.md`, §2).
- Top-level `main()` function, no explicit return type.

## 2. Imports in Tests

```dart
import 'package:test/test.dart';                     // Dart packages
// or:
import 'package:flutter_test/flutter_test.dart';     // Flutter packages

import 'package:<pkg>/<pkg>.dart';                   // own package via public API
```

Only import `package:<pkg>/src/...` in exceptional cases — typically when
an internal helper must be tested that is deliberately not exported.

## 3. Nesting with `group` / `test`

A three-level hierarchy is the default:

```dart
void main() {
  group('FooBar', () {                    // class name
    group('run()', () {                   // method with (args)
      group('Should print running and', () {
        test('success messages', () { ... });
        test('error messages', () { ... });
      });
    });
    group('logTask(...)', () {
      test('with success should print success status', () { ... });
    });
  });
}
```

- **Outer group** = class or top-level function name.
- **Inner group** = method signature (`run()`, `logTask(...)`,
  `copyWithValue(i, value)`).
- **Test name** starts with "should" or describes the observed behavior.

## 4. Setup, Teardown, Helpers

- `setUp` for resetting shared state (clearing lists, resetting test
  singletons).
- `tearDown` for cleaning up external resources (temporary directories,
  setting fakes back to null).
- **Local helper closures** in `main()` for setup logic used by several
  tests (no magic helper module, no inheritance).

```dart
void main() {
  late Directory tmp;
  final messages = <String>[];

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('foo_test_');
    messages.clear();
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Directory makeFixture(String name) => Directory(p.join(tmp.path, name))..createSync();

  group('Foo', () { ... });
}
```

## 5. Combinatorial Tests

When the same logic must be tested with several inputs, use a **for loop
around `test(...)`**, not parameterized frameworks:

```dart
for (final cr in [null, false]) {
  test('with carriage return = $cr', () async { ... });
}
```

## 6. Mocking Policy

- **Prefer real types.** Constructors allow dependency injection via
  optional parameters (e.g. `ggLog`, `promptUser`, `homeOverride`) — then
  tests work without mocks.
- **Functions instead of mocks**: a callback (`String? Function(String)`)
  is easier to test than a mocked `Stdin` class.
- **Test singletons**: for global flags there are project-wide test
  overrides (`testIsCi`, `testHomeDir`, …); set them in `setUp` and reset
  them to `null` in `tearDown`.
- **`mockito`/`mocktail`**: only when no reasonable test strategy is
  possible without a mock (rare).

## 7. Test Content

- One `test(...)` tests **one** behavior. Several `expect`s are allowed as
  long as together they prove exactly that behavior.
- Prefer **structural comparisons** (`expect(messages, equals([...]))`)
  over individual asserts for lists.
- For exceptions:
  `expectLater(future, throwsA(isA<XyzError>().having((e) => e.message, 'message', contains('...'))))`.
- For future successes: `final result = await ...; expect(result, ...);`.
- **No `print`** in tests. If output must be captured, use a capture helper
  such as `gg_capture_print`'s `capturePrint(...)`.

## 8. Coverage

- **100 % required** as the default bar. Pre-commit tooling and CI block
  otherwise.
- Mark **unreachable or irrelevant code paths** with comments:

  ```dart
  // coverage:ignore-line
  // coverage:ignore-start
  ...
  // coverage:ignore-end
  ```

- Examples of legitimate ignores:
  - Surfacing an `UnsupportedError` variant in a container implementation.
  - `dart:io` calls that cannot be tested in isolation (e.g. a
    `stdin.readLineSync()` wrapper in a default fallback).
- **Ignores are not for hiding laziness.** If a path is theoretically
  testable (including via dependency injection), test it instead of
  ignoring it.

## 9. Style Consistency

- **Section separators** in tests too:

  ```dart
  // #########################################################################
  group('subList(start, end)', () { ... });
  ```

- Test code is code: license header, single quotes, trailing commas, the
  80-character rule (in Dart packages).

## 10. Local Validation Before Commit

Before every commit, the following must run and pass:

- `dart analyze` (clean)
- `dart format` (clean)
- `dart test` (all green, required coverage reached)

Which tool automates this (a git hook, a CLI wrapper, a CI job) is
organization-specific — a higher DNA layer overrides this section with the
concrete commands. Never attempt to push with red tests.
