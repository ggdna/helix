---
name: new-ticket
description: Creates a new work ticket. Two modes - (A) multi-repo ticket in a workspace, (B) single-repo ticket as a branch in the repo. Use this skill when the user says something like "create a new ticket", "fix a bug", "implement a feature", or phrases like "I want to work on X" or "let's fix bug Y".
---

# Create a New Ticket

You create tickets for work on one or several repositories. There are
**two modes** — choose based on the request:

- **Mode A — multi-repo ticket**: The changes affect several repos, or it
  is still unclear at creation time which repos exactly are needed → a
  workspace ticket that brackets several repos.
- **Mode B — single-repo ticket**: The bug or feature clearly affects only
  a single repo → a ticket branch directly in the repo.

When in doubt, ask the user which mode fits. If they name only one repo
from the start, mode B is right.

Which concrete tools are used is project-specific. Examples for a
multi-repo setup: a custom workspace CLI with subcommands like
`create ticket` / `add`. Example for single-repo: plain
`git checkout -b <branch>` or a repo-specific helper. If your repo
prescribes a more specific workflow through a higher DNA layer, use that.

---

## Mode A — Multi-repo ticket

### 1. Change into the workspace

The workspace is the folder where the involved repos are gathered (often
organized with a dedicated repo pool and a `tickets/` folder). The path
differs from machine to machine — either ask the user explicitly, or find
the workspace yourself with `Glob` for plausible markers (a `tickets/`
folder, a workspace config file, a hidden folder holding the repo pool).

### 2. Determine the available repositories

List the repos in the workspace so that you have matching names ready for
adding them later. If the project has a dedicated CLI that knows the repo
list, use it; otherwise `Glob`/`ls` directly on the workspace content.

### 3. Clarify ticket name and description

From the user's request you derive:

- **Ticket name** — short, snake_case or kebab-case in the style of
  existing tickets; meaningful (e.g. `fix_login_crash`,
  `add_dashboard_export`).
- **Ticket description** — one or two sentences describing the problem /
  feature.

**Ask the user explicitly whether name and description fit** before
executing anything. Only continue after confirmation.

### 4. Create the ticket

Use the project-typical create command. Query `--help` first if you do
not know the tool, and construct the call from that.

### 5. Select the relevant repositories

Based on the ticket content, think about which repos are needed for the
implementation. When unsure, briefly read the `README.md` / manifest of
the candidate repos.

Rather propose too few repos than too many — the user adds more when
needed.

**Ask the user** whether the selected repos should be added to the
ticket. List them individually with a short justification. Only continue
after confirmation.

### 6. Add the repos to the ticket

Add all confirmed repos in one call using the project-typical add
command.

### 7. Wrap up

Briefly summarize:

- Ticket path
- Added repos
- Suggestion for the next step — but do not start working unasked.

---

## Mode B — Single-repo ticket

When it is clear that the feature or bugfix affects only a single repo.

### 1. Change into the repo and update

```bash
cd <path-to-repo>
git pull
```

If the path to the repo is unclear: ask.

### 2. Clarify branch name and description

- **Branch name** — short, kebab-case, in the style of existing branches
  in the repo (`fix-...`, `feat-...` if customary there, otherwise flat).
- **Description** — one or two sentences about what will change.

**Ask the user explicitly for confirmation** of branch name and
description. Only continue after confirmation.

### 3. Create the branch and ticket note

Standard variant:

```bash
git checkout -b <branch_name>
```

If the project provides its own wrapper (e.g. a CLI that also creates a
`.ticket` file with the description), use that instead. Consult the
project-specific guide (e.g. under `doc/guides/`) if one exists.

### 4. Wrap up

Briefly report:

- Repo path and new branch
- Possible next steps — but do not start the implementation unasked.

---

## Important (applies to both modes)

- **Never** create a ticket or add repos without the user's confirmation.
- Repo names must match the folder names in the workspace or the repo
  parent folder exactly.
- If the user already provides ticket name / branch / repos, do not ask
  redundantly — only clarify missing parts and have the result confirmed
  briefly at the end.
- Mode B: `git pull` **before** the ticket command, never after.
- For diverging paths on the user's machine: ask instead of forcing
  default paths.
