---
name: review
description: Runs a complete review of the current branch. First pulls the tooling green (dependency tightening, static analysis, formatting, tests including coverage and the placed DNA test), offering fixes interactively, then performs an LLM review against the conventions in `doc/conventions/`, plus checks for redundant/unclear code, wrong documentation, performance, and security. Findings are output as a structured report; every fix proposal is confirmed individually before being applied. Use this skill when the user says something like "review", "check my branch", "is this mergeable", "code review", or "check before merging".
---

# Code Review

You run a complete review of the current branch. The skill runs in **four
phases**: first all deterministic tooling checks are pulled green, then
the LLM review is done, then the report is assembled, and at the end
fixes are applied interactively.

**Golden rules:**

- Never change anything unasked. Every step that touches files is
  announced beforehand and confirmed individually.
- No inventions. If a command is not available, report the finding and
  keep going instead of mocking.
- Tooling truth beats LLM taste. What the analyzer/tests say holds;
  subjective points are marked as "Suggestion".
- Language: write reports and prompts in the language the user is using.

---

## 0. Determine the scope

Before anything is checked, clarify and report the scope:

1. **Find the repo root**: `git rev-parse --show-toplevel`. If that
   fails, report "not a git repo" and stop.
2. **Determine the base branch**:
   - Read the remote's default branch:
     `git symbolic-ref refs/remotes/origin/HEAD` → typically
     `refs/remotes/origin/main`.
   - If that fails, fall back to `main`. If `main` does not exist, try
     `master`.
   - If no base can be determined, ask the user for the base branch.
3. **Diff range** = `<base>...HEAD` (three dots, i.e. against the merge
   base).
4. **Determine changed files**: `git diff --name-status <base>...HEAD`,
   plus `git status --porcelain` for untracked / uncommitted files.
5. **Multi-repo workspace?** If the current folder is a workspace that
   gathers several git repos (e.g. a ticket workspace with the involved
   repos side by side), list the sub-repos and announce that phases 1–2
   run serially per sub-repo while the phase-3 report is combined.

Output a short scope message, roughly:

```
Review scope:
  Repo:    <abs-path>
  Branch:  <feature-branch> vs <base-branch>
  Files:   N changed (+L / -L), M untracked
  Mode:    single repo  |  workspace with K sub-repos: …
```

---

## 1. Phase 1 — Tooling fixes (interactive, blocking)

This phase runs **until all checks are green**. On failures, fix
proposals are made; every fix is confirmed individually by the user. Only
then continue.

Order matters — cheap/local checks first, so you don't wait 2 minutes on
tests only to find `dart format` red afterwards.

### 1.1 Dependency tightening

For Dart projects:

- Briefly check `git status --porcelain pubspec.yaml pubspec.lock`
  first — if dirty, warn the user that additional changes may appear now.
- Run:

  ```bash
  dart pub upgrade --tighten
  ```

- If `pubspec.yaml`/`pubspec.lock` were changed:
  - Show the diff (`git diff -- pubspec.yaml pubspec.lock`).
  - Ask the user whether these changes should be part of the commit.
  - On "yes", prepare a commit proposal at the end of the phase
    (message proposal: `chore: dart pub upgrade --tighten`) — but do
    **not** commit immediately; that happens bundled at the end of
    phase 4.
- If `--tighten` aborts with an error (e.g. conflicts): record the error
  as a finding, generate a fix proposal, have the user confirm.

For other ecosystems, use the equivalent (e.g. the project's dependency
update command) or skip with a note in the report.

### 1.2 Static checks

- Run the project's standard checks — for Dart projects:

  ```bash
  dart analyze
  dart format . --set-exit-if-changed
  ```

  If the project ships its own check wrapper (via a DNA layer or a team
  CLI), use that instead.
- On failure:
  - Parse the output. Typical findings: formatter diff, analyzer
    warnings, missing doc comments, unused imports.
  - Generate a concrete fix proposal **per finding** (patch or command,
    e.g. `dart format .`).
  - Offer patches individually for confirmation via `AskUserQuestion`
    ("apply / skip / edit").
  - After every applied fix, run the checks again until green.

### 1.3 Tests (including the DNA test)

- Run:

  ```bash
  dart test
  ```

  (or the project's test command).
- On failure:
  - List failing tests individually (file, test name, error message).
  - Decide per test: is the test wrong or the code? Generate the fix
    proposal as a concrete patch.
  - Have the user confirm individually, then run the tests again until
    green.
- **DNA test**: projects using `gg_dna` run a placed DNA test (e.g.
  `test/dna/dna_test.dart`) as part of the suite — it instantiates the
  DNA and fails when instances drifted:
  - The generated files are committed automatically as
    `#gg: generated DNA` — review that commit like any other change.
  - "generated by the DNA and were modified by hand": move the change
    into the DNA file the report names after `edit instead:`, never
    adjust the generated file.
  - "DNA installation stopped … carry uncommitted work": the listed
    files are produced by the DNA from the sources shown — move changes
    worth keeping into the DNA source, otherwise commit or stash them,
    then rerun.
- **Coverage**: if the test output reports a coverage value and it is
  below **100 %**, record that as a blocker (see
  `doc/conventions/test-conventions.md`). Locate the uncovered lines and
  treat them as a finding in phase 2.

### 1.4 Phase 1 wrap-up

When all checks are green, report briefly:

```
Phase 1 complete — tooling is green.
  dependency tightening: applied (manifest changed: yes/no)
  static checks: ok
  tests: ok (coverage NN%, DNA test ok)
```

Only then move to phase 2.

---

## 2. Phase 2 — LLM review

Now do the actual code review, **exclusively on the changed files from
phase 0**. Other files are only read when they are needed as context for
a finding (e.g. callers of a changed function).

Procedure per changed file:

1. Read the diff (`git diff <base>...HEAD -- <file>`).
2. Read the full file to understand the context of the change.
3. Check the changed places against each of the following axes.

### 2.1 Conventions

Load and reference explicitly:

- `doc/conventions/code-conventions.md`
- `doc/conventions/test-conventions.md`
- `doc/conventions/documentation-conventions.md`

Every convention violation is backed by a quote from the convention
file — that protects against taste-based findings.

### 2.2 Redundancy / DRY

- Identical or nearly identical code blocks in the diff or its immediate
  neighborhood.
- Functions that already exist in the repo and are not reused.
- Duplicate imports, duplicate test setups, copied constants.

### 2.3 Clarity

- Functions > ~40 lines — extraction proposal, but only when the
  extraction clearly reads better.
- Nesting > 3 levels (`if`/`for`/`try`) — early-return proposal.
- Names that do not match the conventions or the purpose.
- Magic numbers / magic strings that would be clearer as named
  constants.

### 2.4 Documentation

- **Correctness**: check doc comments against the actual signature.
  Parameter renamed but doc not? Return type changed but the doc
  describes the old one? Exceptions documented that are no longer
  thrown?
- **Completeness**: public API without doc comments → blocker (per
  `documentation-conventions.md`).
- **README/CHANGELOG**: if public behavior changed, README/CHANGELOG
  should reflect it. Check whether they were changed in the diff.

### 2.5 Performance

Check specifically for typical Dart pitfalls — only what is in the diff
or directly triggered by it:

- `await` in a loop that could be parallelized (`Future.wait`).
- Repeated `toList()` / `.where().toList()` in hot paths.
- `List.add` in tight loops where `List.generate` or a pre-allocated
  buffer would be better.
- Stream subscriptions without `cancel`, timers without `cancel`,
  `StreamController` without `close`.
- Synchronous IO (`readAsStringSync`, `existsSync`) in async code paths.
- Repeated parsing/computation that belongs outside the loop.

Do not speculate — a finding only when the hot path is plausible (e.g.
code runs per frame, per request, per element of a large collection).

### 2.6 Security

- **Secrets in the diff**: `grep` for `API_KEY`, `SECRET`, `PASSWORD`,
  `TOKEN`, plus a heuristic for JWT/Base64-like long strings in new
  lines.
- **`Process.run` / `Process.start`** with interpolated user input →
  shell-injection risk.
- **Input validation** at system boundaries (HTTP handlers, CLI args,
  file paths from external sources).
- **New dependencies** in the manifest: is the package actively
  maintained? Known maintainers? Plausible score? If not assessable,
  report as a suggestion, not a blocker.
- **File paths from external sources** used without normalization →
  path-traversal risk.

---

## 3. Phase 3 — Report

Collect all findings from phases 1 and 2 and output **one single
structured report** before any fix is applied. Classification:

- **Blockers** — prevent the merge. Tooling failures (documented here
  even when already fixed in phase 1), coverage < 100 %, security
  findings with a clear risk justification, missing doc comments on
  public API, convention violations.
- **Suggestions** — should be fixed, but no hard stop. DRY / performance
  / clarity with a clear justification, README/CHANGELOG updates.
- **Nits** — style questions, optional. Naming micro-optimizations,
  slight readability.

Format:

````markdown
## Review: <branch> vs <base>

**Tooling**
- static checks: PASS / FAIL (fixed in phase 1: yes/no)
- tests:         PASS / FAIL (coverage: NN%, DNA test: PASS / FAIL)
- dependency tightening: manifest changed (yes/no)

**Statistics**
- Files: N changed, +L / -L
- Findings: X blockers, Y suggestions, Z nits

---

### Blockers

#### B1. <short title> — `<file>:<line>`
**Convention/axis**: <code-conventions.md §… | Performance | Security | …>
**Finding**: <one to three sentences>
**Patch**:
```diff
- old line
+ new line
```

#### B2. …

### Suggestions

#### S1. …

### Nits

#### N1. …
````

If a category has no findings, mark the section with `(none)` instead of
omitting it — this way the user sees that it was actually checked.

---

## 4. Phase 4 — Interactive fix loop

After the report, ask the user how to proceed. Offer three modes:

1. **Walk through all blockers** — per blocker show the patch,
   "apply / skip / edit" via `AskUserQuestion`. `edit` means: the user
   describes an alternative, you propose a new patch.
2. **Cherry-pick** — the user selects by number from the whole list
   (blockers + suggestions + nits) which ones to fix.
3. **Abort** — the report stands, the user fixes things themselves.

When patches were applied:

1. **Regression check**: run the static checks and tests again. If red,
   report it and offer a mini fix loop (back to phase 1).
2. **Commit proposal**: prepare a commit message summarizing what was
   fixed in the review. If dependency tightening changed the manifest, a
   separate commit proposal for that. Example:

   ```
   review: fix blockers from /review run

   - <B1 title>
   - <B2 title>
   - …
   ```

   Show the proposal, but do **not** commit unasked — the user confirms
   explicitly.
3. **Push**: never push on your own.

---

## Important

- **Never** change files, commit, push, or close tickets without
  confirmation.
- **Never** report a tooling failure as fixed without having rerun the
  check.
- **Never** "invent" a finding just so a section is not empty. Empty
  sections are a good sign.
- **Never** classify performance/security findings as blockers without a
  concrete risk / hot-path justification — otherwise the reports become
  useless.
- In a multi-repo workspace: phases 1–2 serially per sub-repo, phase 3
  combined, phase 4 separately per sub-repo (otherwise patches end up in
  the wrong repos).
- If the user wants to skip parts (e.g. "only phase 2, I checked the
  tooling myself"), respect that and document it at the top of the
  report ("phase 1 skipped on request").
