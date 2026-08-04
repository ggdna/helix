---
name: init-architecture
description: Create or update a `README.architecture.md` at the repo root that documents the system's big-picture architecture — components, core abstractions, control/data flow, and extension points. Detects whether the file already exists and switches between a create mode (full first draft) and an update mode (drift detection against the current code, preserving hand-written prose). Use this skill when the user says "/init-architecture", "document the architecture", "write/update the architecture doc", "README.architecture.md", "architektur dokumentieren", or asks for an architecture overview of the repository.
---

# Initialize / update README.architecture.md (DNA-aware)

Produce **one** `README.architecture.md` at the repository root that explains the *shape* of the system: how the major pieces fit together, the core abstractions, how a typical operation flows end to end, and where the code is meant to be extended. This is a **human-facing architecture document** — distinct from `CLAUDE.md` (agent guidance, produced by the `init` skill) and from per-package `README.md` (usage). Keep all three from duplicating each other.

This skill is **DNA-aware**: a consuming repo may ship architecture conventions or a project-type guide under `dna/agents/guides/`, and project-local overrides live under `dna/_override/`. Consult them when present; never invent their content.

The document is **owned by humans**. This skill assists — it drafts and keeps it honest against the code, but it must never silently discard prose a person wrote.

---

## 1. Decide the mode

Check whether `README.architecture.md` already exists at the repo root.

- **Missing → create mode** (§3a). You are writing the first draft.
- **Present → update mode** (§3b). You are reconciling an existing doc with the current code.

Tell the user which mode you are in before doing the analysis.

## 2. Analyze the architecture

Read enough of the codebase to describe the **big picture that requires reading multiple files to understand** — not a file-by-file inventory. Gather:

1. **Entry points** — `bin/`, `main`, exported library files, CLI command registration, server bootstrap, the public surface of the package.
2. **Components / modules** — the major folders or subsystems and the single responsibility of each. Prefer the boundaries the code already draws (directory layout, package manifest, sub-libraries) over invented groupings.
3. **Core abstractions** — the handful of types/interfaces everything else is built on, and how they relate.
4. **Control / data flow** — trace one representative operation from entry point to result. This is the most valuable section; spend the most effort here.
5. **External dependencies & integration points** — significant third-party packages, network/filesystem/process boundaries, other repos this one talks to.
6. **Extension points** — the seams meant to be extended (where you add a new command, a new provider, a new model), if the design has clear ones.

Pull from existing source material rather than inventing: `README.md`, design notes, `dna/agents/guides/`, `dna/_override/`, doc-comments on the core types. If a matching project-type guide exists under `dna/agents/guides/`, read it for architecture conventions — but the resulting doc is **repo-specific**, so fold in only what genuinely applies here.

## 3a. Create mode — draft the document

Write a draft following the structure below. **Omit any section that does not apply** to this repo — do not pad. A small, true document beats a large, half-invented one.

```markdown
# Architecture — <project / package name>

<1–2 sentences: what this system is, and the single most important thing to know about its shape.>

## Overview

<The big picture: the major pieces and how they fit together. The part a newcomer
cannot get from any single file. A Mermaid diagram is welcome here when it earns
its place — only if it clarifies more than prose would.>

## Components

| Component        | Responsibility                          | Key location          |
| :--------------- | :-------------------------------------- | :-------------------- |
| `<name>`         | <one line>                              | `lib/src/<path>/`     |

## Core abstractions

- **`<Type>`** — what it models and why it is central; its relationship to the others.

## Control / data flow

<Trace one representative operation end to end: entry point → the components it
passes through → the result. Reference real symbols and files (e.g. `Foo.run` in
`lib/src/foo.dart`) so the description stays anchored to the code.>

## External dependencies & integration points

- **`<package / boundary>`** — what it is used for; where the boundary sits.

## Extension points

<Where and how to add a new <command / provider / …>, if the design has clear seams.>
```

Conventions for the content (mirroring `dna/agents/conventions/documentation-conventions.md`):

- **English, concise, technical.** No marketing, no onboarding prose, no generic development advice.
- **Anchor claims to the code** — reference real files/symbols as `path:symbol` so the doc can be checked and stays maintainable.
- Do **not** restate what a `README.md` or doc-comments already cover well; link to them instead.
- Do **not** invent components, flows, or extension points that aren't in the code.

## 3b. Update mode — reconcile with the code

1. **Read the existing `README.architecture.md` in full.** Treat every sentence as potentially hand-authored and intentional.
2. **Diff the doc against your §2 analysis.** Classify each discrepancy:
   - **Stale** — describes code that changed (renamed/moved/removed components, flows that no longer hold).
   - **Missing** — a significant component / abstraction / flow now exists but isn't documented.
   - **Hand-written prose** — rationale, trade-offs, history, "why" notes that aren't mechanically derivable from the code. **Preserve these.** Only touch them if they are now factually wrong, and then flag it explicitly rather than rewriting silently.
3. **Propose a minimal, surgical edit**, not a regeneration: fix stale facts, add missing pieces, leave correct and hand-written content untouched. Keep the existing section order and headings unless they are actively misleading.

## 4. Show, confirm, write

- **Always show the proposed content (create mode) or the diff (update mode) before writing.**
- In update mode, when an edit would change or remove text that looks hand-authored, call it out and **ask** before applying.
- Write `README.architecture.md` only after the user confirms.
- After writing, state the absolute path.

## 5. Optional: link it from README.md

If a root `README.md` exists and has no pointer to the architecture doc, **offer** (do not force) to add a single line such as:

```markdown
See [README.architecture.md](README.architecture.md) for the system architecture.
```

Only add it on confirmation. Do not restructure `README.md` beyond that one line.

## 6. Wrap up

Briefly report:

- Absolute path of `README.architecture.md` and whether it was created or updated.
- In update mode: a short list of what changed (stale facts fixed, sections added) and anything you deliberately left as-is.

Do not commit, push, or run further tooling unless explicitly asked.

---

## Important

- **Never** overwrite or regenerate an existing `README.architecture.md` wholesale — update mode is surgical and preserves hand-written prose.
- **Never** invent components, flows, abstractions, or extension points that the code does not contain.
- **Never** add generic boilerplate ("write tests", "follow SOLID", "don't commit secrets") — this document describes *this* system's architecture only.
- Keep the doc anchored to real `path:symbol` references so it can be verified and maintained.
- This skill produces documentation only; it does not change source code, commit, or push.
