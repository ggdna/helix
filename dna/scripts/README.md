# scripts

Helper scripts shipped by DNA layers. Everything in this folder is
instantiated to `scripts/` in the project root of every consumer.

The gg_dna base layer ships no scripts of its own — higher DNA layers add
organization- or project-specific helpers here (setup, tooling,
maintenance, and convenience scripts). Script files use canonical
kebab-case names in the DNA and are converted to the target's naming
standard at instantiation.

Not to be confused with `bin/`: in Dart packages, `bin/` holds the entry
points of the published CLI application; `scripts/` holds everything
around it (shell, PowerShell, Dart scripts) that is not part of the
published package.
