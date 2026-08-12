---
name: init
description: Initialize a new CLAUDE.md file with codebase documentation. Detects the project type, asks the user to confirm, and references the matching guide from `doc/guides/` in the generated CLAUDE.md. Preserves the gg_dna-managed import block. Use when the user says "/init", "create a CLAUDE.md", or asks to set up Claude Code for the repository.
---

# Initialize CLAUDE.md (DNA-aware)

Analyze the current repository and produce a CLAUDE.md tailored to it.
This skill is aware of the **DNA layout** used by `gg_dna` consumers:
guides shipped by DNA layers are instantiated at `doc/guides/`,
conventions at `doc/conventions/`, and CLAUDE.md may contain a **managed
import block** (between `<!-- gg_dna:claude_md:start -->` and
`<!-- gg_dna:claude_md:end -->`) that is maintained by the DNA test and
must be preserved verbatim.

The end result is one CLAUDE.md at the repo root that combines:

1. The standard `init` analysis (commands, architecture, repo-specific
   notes).
2. A reference to the matching guide from `doc/guides/` (if any).
3. The managed DNA import block, if present (kept unchanged).

---

## 1. Discover available guides

List the markdown files in `doc/guides/` (relative to the repo root). Each
file there is a candidate guide for one project type or workflow. If the
folder is missing or empty, skip ahead to step 3 and produce a CLAUDE.md
without a guide reference.

The set of guides — and the heuristics for matching them — is **not
hardcoded in this skill**. DNA layers ship the concrete guides; treat any
specific filenames you encounter as examples, not as a closed list.

## 2. Suggest a guide and confirm with the user

Inspect the working directory (package manifests, file structure, naming
patterns) and pick the most plausible guide from step 1 as your initial
guess. Heuristics you can use:

- **Package manifests**: `package.json` name/dependencies, `pubspec.yaml`
  name, `Cargo.toml`, `pyproject.toml`, etc.
- **Folder structure**: presence of `lib/src/`, `src/`, language-specific
  test layouts.
- **Tooling references**: scripts in `package.json`, workflow files, CLI
  tools mentioned in `README.md`.
- **Sibling repos**: directories next to this repo that share a naming
  prefix.

If none of the signals are conclusive, default to "no guide".

Then use `AskUserQuestion` to confirm:

> Detected project type: **<guide-name | none>**. Reference the matching
> guide from `doc/guides/<guide-name>.md`?

Options:

- `<detected guide> (Recommended)` — reference that guide.
- Each remaining guide found in step 1 as an alternative option.
- `No guide` — skip the guide reference entirely.
- (The `Other` option is added automatically.)

If the chosen guide file does not exist, tell the user, ask whether to
continue **without** a guide reference, and proceed accordingly. Do not
invent guide content.

## 3. Analyze the codebase

1. **Commands** that will be commonly used — build, lint, run tests, run a
   single test, anything specific to this repo.
2. **High-level code architecture and structure** — the "big picture" that
   requires reading multiple files to understand.

Rules:

- If a `CLAUDE.md` already exists, **suggest improvements** to it instead
  of overwriting blindly. Surface the diff to the user before writing.
- Do **not** repeat obvious instructions ("write unit tests", "don't
  commit secrets", "provide helpful error messages").
- Do **not** enumerate every component or file structure that is trivially
  discoverable.
- Do **not** include generic development practices.
- Pull in important parts of `README.md`, `.cursor/rules/`,
  `.cursorrules`, `.github/copilot-instructions.md` if present.
- Do **not** invent sections like "Common Development Tasks", "Tips for
  Development", "Support and Documentation" unless they actually exist in
  source material you read.

## 4. Compose `CLAUDE.md`

Write `CLAUDE.md` at the repo root with this exact ordering:

1. **Required prefix** (verbatim, including the blank line after):

   ```
   # CLAUDE.md

   This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.
   ```

2. **Project structure section** — the repo-specific analysis from step 3
   under a `## Project structure` heading (commands, architecture,
   repo-specific notes; omit subsections that don't apply).

3. **Guide reference** — a single `@` import for the chosen guide under a
   clearly named heading, e.g.:

   ```markdown
   ## <guide-name> workflow

   @doc/guides/<guide-name>.md
   ```

   Import instead of copying: the guide file is instantiated by the DNA
   and stays current automatically. If the user opted to skip the guide in
   step 2, simply omit this section.

4. **Managed DNA block** — if the existing CLAUDE.md contains a block
   between `<!-- gg_dna:claude_md:start -->` and
   `<!-- gg_dna:claude_md:end -->`, keep it exactly where and as it is.

If `CLAUDE.md` already exists:

- Diff your proposal against the existing file.
- Show the user what would change and ask for confirmation before writing.
- Preserve any existing content the user added that isn't part of the
  analysis or the guide reference — when in doubt, ask.

## 5. Wrap up

Briefly tell the user:

- Absolute path of `CLAUDE.md`.
- Which guide was referenced (or that none was, if skipped).

Do not push, commit, or run any further tooling unless explicitly asked.

---

## Important

- **Never** write `CLAUDE.md` without showing the proposed content to the
  user first when an existing file would be overwritten.
- **Never** invent guide content — only reference what actually exists
  under `doc/guides/`.
- **Never** add generic boilerplate ("use unit tests", "don't commit
  secrets", etc.) that this skill explicitly forbids.
- **Never** touch the managed import block in CLAUDE.md — the DNA test
  maintains it.
- **Never** edit `dna/` in a consumer project and never hand-edit DNA
  instances — they are generated, and the DNA test fails on hand-edited
  instances. Repo-specific knowledge belongs in CLAUDE.md (outside the
  managed block) or in the DNA layer that owns the file.
