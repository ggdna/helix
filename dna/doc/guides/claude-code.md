# Working with Claude Code

A quick guide for developers. Goal: be productive with Claude Code in
under 10 minutes.

## 1. Installation

**Windows (PowerShell):**

```powershell
irm https://claude.ai/install.ps1 | iex
```

**macOS / Linux / WSL:**

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

Alternatives: `brew install --cask claude-code` (macOS),
`winget install Anthropic.ClaudeCode` (Windows),
`npm install -g @anthropic-ai/claude-code`.

Prerequisite: a Claude account (Pro/Max/Team/Enterprise) or a Console API
key. On native Windows,
[Git for Windows](https://git-scm.com/downloads/win) is additionally
recommended.

Verify:

```bash
claude --version
claude doctor
```

## 2. Initialize a Project

Change into the project folder and start Claude:

```bash
cd path/to/project
claude
```

On first start: log in once (the browser opens automatically).

Optionally, as the first step in a project:

```
/init
```

This creates a `CLAUDE.md` with project context that Claude loads
automatically in every session.

## 3. Plan Mode vs. Programming Mode

Claude Code has two relevant working modes:

| Mode | What it does | Touches files? |
|---|---|---|
| **Programming mode** (default) | Reads, writes, edits code, runs commands | Yes — asks for permission before every change (or `Auto-Accept`) |
| **Plan mode** | Only reads, analyzes, asks back, produces a plan | **No** — read-only, no edits, no write commands |

### Switching back and forth

- **In the session:** `Shift+Tab` cycles through the modes:
  *Normal → Auto-Accept → Plan → Normal …*. The current mode is shown at
  the bottom of the status line (`⏸ plan mode on`).
- **At startup:** `claude --permission-mode plan`
- **Accepting a plan:** Claude presents a plan at the end — you confirm,
  then it switches to programming mode automatically and implements it.
- **Leaving plan mode without a plan:** `Esc` or `Shift+Tab` again.

## 4. Why Plan First?

For non-trivial tasks (several files, refactoring, a new feature, unclear
architecture), plan mode pays off:

- **No accidental making-things-worse** — read-only; you see the strategy
  *before* anything is written.
- **You can correct** — if Claude suspects the bug in the wrong place, you
  fix the plan instead of reverting a broken patch.
- **Better results** — Claude analyzes the codebase and the requirements
  first, before producing code. That saves iterations.
- **Shared understanding** — you know what will happen and can add edge
  cases Claude does not know yet.

Rule of thumb: **Trivial edits → straight to programming mode. Everything
else (fixing a bug without a known line, features, refactors, migrations)
→ plan mode first.**

## 5. Working Across Several Repos

When a task needs changes in several repositories, work in a shared
**workspace folder** that contains the affected repos (e.g. side by side
as subfolders or as git submodules) and start Claude Code there:

```bash
cd path/to/workspace
claude
```

This way Claude can read and change across repos and keep them
consistent — e.g. adapt a schema change in the backend together with the
UI.

For tasks that touch only a single repo, `claude` directly in the repo
folder is enough.

## 6. Frequent Commands

| Command | Purpose |
|---|---|
| `claude` | Start an interactive session |
| `claude -c` | Continue the last session in the current folder |
| `claude -r` | Session picker |
| `claude -p "<question>"` | One-off question, immediate answer, exit |
| `/init` | Create a `CLAUDE.md` with project context |
| `/clear` | Clear the current session's history |
| `/help` | Show all commands |
| `Shift+Tab` | Switch between modes |
| `Esc` | Cancel an action / leave plan mode |
| `Ctrl+D` or `exit` | Quit |

More: [code.claude.com/docs](https://code.claude.com/docs/en/quickstart)
