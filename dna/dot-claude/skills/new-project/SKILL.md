---
name: new-project
description: Creates a new repository / package. Confirms name, target folder, and description with the user and calls the create tool that is customary in the project. Use this skill when the user says something like "create a new project", "create a new repository", "new package", or provides a GitHub/GitLab link for a still-empty repository.
---

# Create a New Project

You create new repositories for the workspace. Stick strictly to this
order — **always** ask for confirmation before actually creating
anything. The concrete create tool (e.g. a project-specific CLI wrapper)
is not pinned down here; a higher DNA layer may replace this skill with a
narrower, organization-specific version.

## 1. Determine the target folder

A team's repositories usually live side by side in a shared parent
folder. The path differs from machine to machine — **ask the user** which
folder the repos live in, or find the folder yourself (search with `Glob`
for sibling directories that match the team's naming conventions).

Once the parent folder is known, list its content with `Glob`/`ls` to:

- verify that the path exists,
- see existing sibling repos (naming conventions, prefixes).

## 2. Get the user's confirmation

Before anything is created, summarize and have the user confirm:

- **Target folder** (`<workspace-root>/<project-name>`).
- **Project name** — should follow the team convention (e.g. snake_case
  or a prefix); when in doubt, ask the user.
- **Hosting org** (GitHub / GitLab organization) — ask explicitly if
  unclear.
- **Description** — the minimum length depends on the create tool; check
  whether the tool has a limit.
- **Open source yes/no** — if the create tool supports the choice.
- **Optional flags** — e.g. language (Dart, Flutter, TypeScript, …)
  depending on the tool.

Only continue after explicit confirmation.

## 3. Create the project

Which tool is used depends on the project setup. Examples:

- a custom CLI (`<team>_create_package`, `make-repo`, …),
- `gh repo create` + template,
- `npm create <template>` / `pnpm create <template>` /
  `yarn create <template>`,
- `dart create` / `flutter create`,
- `cargo new`.

**Always run** the tool with `-h` / `--help` first to see the current
syntax/flags, and construct the call from the help output. Never guess
flags.

## 4. Got a GitHub / GitLab link?

If the user provides a repo link when creating, the remote repo probably
already exists (possibly pre-filled with README/LICENSE/.gitignore).

- Ask the user whether existing files in the remote may be overwritten.
- **When in doubt**, briefly check what is already in the repo
  (`gh repo view <owner>/<repo> --json …` or `git ls-remote`) and report
  to the user if non-trivial content lives there.
- Workflow after creating: commit locally → `git push -u origin main`. If
  the remote already has commits: push with `--force-with-lease` only
  after checking back.

## 5. After creating

- Briefly confirm what was created where (absolute path).
- Name the push command, but **do not push unasked**.
- Do not generate additional boilerplate, CI configs, licenses, or
  READMEs unasked — the create tool provides the standard structure.

## Important

- **Never** create anything without the user's confirmation of path,
  name, hosting org, and description.
- **Never** guess create-tool flags — always call `--help` first.
- Do not overwrite existing folders under the target path without asking.
