# Ticket: feat-dna-config-v3 — Neues Config-Format, CLAUDE.md-Verwaltung, non-interaktiver Sync

**Breaking Change → Version 3.0.0**

Referenz-Projekt mit dem Ziel-Format: `P:\workspace_grace_cloud\.master\testproject_dna_project`
(bzw. dessen Remote), insbesondere dessen `dna.yaml`.

## 1. Neues Config-Format (harter Bruch)

Die Layer wandern von direkt unter `dna:` in einen `dependencies:`-Block; neu kommt ein
`config:`-Block hinzu. Zielstruktur (identisch in `dna.yaml`, `pubspec.yaml` und
`package.json` unter dem `"dna"`-Key):

```yaml
dna:
  order:
    - gg_dna_ggsuite
    - dna_repo
  dependencies:
    gg_dna_ggsuite:
      git: https://github.com/ggsuite/gg_dna_ggsuite.git
      # optional: version: ^1.4.0  (Semver-Constraint gegen Git-Tags, wie bisher)
    dna_repo:
      path: dna/_override
  config:
    claude:
      claude_md:
        include:
          - dna/agents/conventions
          - project_structure.md
      skills:
        include:
          - dna/agents/skills
```

- **Kein Fallback** auf das alte Format (Layer als direkte Geschwister von `order:`).
  Altes Format → klare Fehlermeldung mit Migrationshinweis („Layer gehören unter
  `dna: dependencies:` — siehe README, gg_dna 3.0").
- Alle bestehenden Layer-Regeln bleiben: `git:` xor `path:`, `version:` nur bei git,
  `gg_*`-Shorthand-Expansion, Pfad-Normalisierung, `dna/`-Unterordner-Erkennung.
- `dna: order:`-Einträge ohne Eintrag in `dependencies:` → Fehler; `dependencies:`-Einträge
  ohne `order:`-Listung → Warnung (wie bisher).
- `config:` ist optional. Unbekannte Keys unter `config:` → Warnung, kein Fehler
  (Vorwärtskompatibilität für weitere Tools neben `claude`).
- Betroffene Datei: `lib/src/util/dna_config.dart` (Parser + neue `DnaToolConfig`-Struktur),
  Manifest `lib/src/util/dna_manifest.dart` (Config-Hash muss `config:` mit einbeziehen,
  Manifest-Version auf 3).

## 2. CLAUDE.md-Verwaltung über managed Block

`gg_dna sync` verwaltet in `<target>/CLAUDE.md` einen Block zwischen Markern und schreibt
dessen Inhalt bei jedem Sync komplett neu:

```markdown
<!-- gg_dna:claude_md:start -->
@dna/agents/conventions/code-conventions.md
@dna/agents/conventions/documentation-conventions.md
@dna/agents/conventions/test-conventions.md
@project_structure.md
<!-- gg_dna:claude_md:end -->
```

- Quelle: `config.claude.claude_md.include` — Liste aus Dateien und/oder Ordnern,
  Pfade relativ zur Target-Wurzel.
- **Ordner-Einträge werden expandiert**: alle `*.md`-Dateien darin (rekursiv, alphabetisch
  sortiert) ergeben je eine eigene `@`-Import-Zeile. Grund: Die Claude-Code-Import-Syntax
  (`@pfad`) importiert nur Dateien, keine Ordner.
- **Direkte Imports statt Kopie**: Es wird nichts mehr nach `.claude/conventions/` kopiert —
  die `@`-Zeilen zeigen direkt auf die Dateien unter `dna/…` bzw. die konfigurierten Pfade.
- Datei-Handling:
  - `CLAUDE.md` fehlt → wird angelegt, Inhalt = nur der managed Block.
  - `CLAUDE.md` existiert ohne Marker → Block wird ans Ende angehängt (getrennt durch Leerzeile).
  - Marker vorhanden → nur der Inhalt zwischen den Markern wird ersetzt; handgeschriebener
    Inhalt davor/danach bleibt unangetastet.
  - Start-Marker ohne End-Marker → Fehler (wie heute in `ApplyConventions.upsertBlock`).
- Fehlt `config.claude.claude_md`, fasst der Sync die `CLAUDE.md` nicht an.
- Include-Pfad existiert nach dem Sync nicht → Fehler (kaputte `@`-Imports dürfen nicht
  entstehen).

### Offizielle Claude-Code-Import-Syntax (Recherche-Ergebnis)

Quelle: https://code.claude.com/docs/en/memory („Import additional files")

- Syntax: `@pfad/zur/datei` irgendwo in der CLAUDE.md (eigene Zeile empfohlen).
- Relative Pfade werden **relativ zur Datei mit dem Import** aufgelöst, nicht zum CWD —
  für unsere Zwecke gleichbedeutend mit Target-Wurzel, da die CLAUDE.md dort liegt.
- Rekursive Imports bis maximal **4 Ebenen** tief.
- Imports in Markdown-Code-Spans/-Fences werden **nicht** ausgewertet (`` `@README` ``
  bleibt Literal) — deshalb dürfen die generierten `@`-Zeilen nie in Code-Fences stehen.
- Importierte Dateien landen beim Session-Start vollständig im Kontext (kein Lazy-Loading).
- Pfade außerhalb des Arbeitsverzeichnisses lösen einen Approval-Dialog aus — die
  generierten Imports bleiben daher innerhalb des Repos.

## 3. Skills non-interaktiv installieren

- Quelle: `config.claude.skills.include` — Liste von Ordnern (relativ zur Target-Wurzel),
  in denen Skill-Ordner (`<name>/SKILL.md`) gesucht werden.
- Ziel: `.claude/skills/<name>` — Installation ohne Rückfrage, vorhandene gleichnamige
  von gg_dna installierte Skills werden überschrieben.
- **Nur gg_dna-eigene Skills werden gespiegelt**: Der Sync merkt sich die von ihm
  installierten Skills (im Manifest `dna/.dna.json`). Verschwindet ein Skill aus der
  Config/Quelle, löscht der nächste Sync ihn aus `.claude/skills/`. Handinstallierte
  Skills (nicht im Manifest) werden **nie** angefasst oder gelöscht; Namenskollision mit
  einem handinstallierten Skill → Warnung, kein Überschreiben.
- Fehlt `config.claude.skills`, werden keine Skills installiert (und zuvor von gg_dna
  installierte beim Sync entfernt, da nicht mehr konfiguriert).

## 4. Sync komplett non-interaktiv

- Die interaktive Post-Sync-Phase (`_promptAndInstallSkills`, `_promptAndApplyConventions`,
  `YesNoSelector`, `interact`-Dependency) wird ersatzlos entfernt.
- Die Subcommands `install-skills` und `apply-conventions` werden **entfernt**
  (`lib/src/commands/install_skills.dart`, `lib/src/commands/apply_conventions.dart`,
  Registrierung in `lib/src/gg_dna.dart`). Wiederverwendbares (z. B. `copyDirectory`,
  `upsertBlock`, `discoverSkills`) zieht in `lib/src/util/` um.
- Das Flag `--no-install` entfällt; `gg_dna sync` tut immer genau das, was die Config sagt.
- `gg_dna sync --check` prüft zusätzlich zum `dna/`-Stand: CLAUDE.md-Block aktuell,
  konfigurierte Skills installiert und aktuell, keine verwaisten gg_dna-Skills.

## 5. Drumherum

- Version `3.0.0`, CHANGELOG-Eintrag mit Migrationsanleitung (2.x → 3.0):
  1. Layer unter `dependencies:` schieben.
  2. Gewünschte CLAUDE.md-Includes und Skill-Ordner in `config.claude` eintragen.
  3. Einmal `gg_dna sync` laufen lassen; alte `.claude/conventions/`-Kopien und den alten
     `gg_dna:conventions`-Block entfernt der Sync bzw. sie können gelöscht werden.
- README: Config-Beispiel auf neues Format umstellen, Abschnitt zu `config.claude`
  (claude_md + skills) ergänzen, Abschnitte zu `install-skills`/`apply-conventions` entfernen.
- Tests: Parser-Tests für `dependencies:`/`config:` (inkl. Fehlerfälle altes Format),
  Sync-Tests für CLAUDE.md-Block (anlegen/anhängen/ersetzen/Fehler), Skill-Spiegelung
  (installieren, aktualisieren, verwaiste entfernen, handinstallierte schonen),
  `--check`-Abdeckung; E2E gegen `testproject_dna_project`.

## Entscheidungen (mit Göran am 2026-07-24 geklärt)

- Altes Config-Format: **harter Bruch**, keine Rückwärtskompatibilität → 3.0.0.
- CLAUDE.md: **managed Block** (nicht komplett generieren); Datei wird angelegt, falls sie fehlt.
- `install-skills` / `apply-conventions`: **entfernen**, alles läuft über `sync` + Config.
- Spiegelung: **nur gg_dna-eigene** Skills/Artefakte verwalten und aufräumen,
  handinstallierte bleiben unberührt.
