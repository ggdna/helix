# gg_dna

gg_dna ist ein Repository, in dem verschiedene Anleitungen, Scripts und Konfigurationen fuer KI-Agenten liegen. Es stellt Anleitungen sowie Anweisungen fuer Code-Struktur, Test, Deployment und Programmierprinzipien dar. Es ist sozusagen die DNA, also der Aufbauplan fuer Programmierprojekte, die damit erzeugt werden.

## Sync

`gg_dna sync` spiegelt den `dna/`-Ordner dieses Packages in das Zielrepo
(`<target>/dna`) und legt darueber die **DNA-Schichten**, die im Zielrepo
konfiguriert sind. Spaetere Schichten gewinnen bei Pfad-Kollisionen; die
Basis-DNA aus gg_dna ist immer die unterste Schicht.

Die Konfiguration ist ein `dna:`-Block und darf in **genau einer** dieser
Dateien in der Repo-Wurzel liegen (mehrere gleichzeitig sind ein Fehler):

1. `dna.yaml` — neutrale Datei, funktioniert fuer jede Sprache
2. `package.json` — `"dna"`-Key, fuer TypeScript-/JavaScript-Repos
3. `pubspec.yaml` — fuer Dart-/Flutter-Repos

Eine vorhandene `dna.yaml` ohne `dna:`-Block ist ein harter Fehler (statt
eines stillen Basis-Syncs, der lokale Schichten loeschen wuerde). Ein
`"dna"`-Feld in der package.json zaehlt nur, wenn es ein Objekt ist —
Fremdfelder anderer Tools werden ignoriert. Nicht parsebare Dateien
blockieren den Sync nur, wenn keine andere Datei die Konfiguration
liefert; sonst gibt es eine Warnung.

```yaml
dna:
  order:
    - dna_company
    - dna_project
    - dna_repo
  dependencies:
    dna_company:
      git: https://github.com/acme/dna_company.git
      version: ^1.4.0
    dna_project:
      path: ../dna_project
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

Dasselbe als `"dna"`-Key in einer `package.json`:

```json
{
  "name": "my-ts-project",
  "dna": {
    "order": ["dna_company", "dna_repo"],
    "dependencies": {
      "dna_company": { "git": "gg_dna_company", "version": "^1.4.0" },
      "dna_repo": { "path": "dna/_override" }
    },
    "config": {
      "claude": {
        "claude_md": { "include": ["dna/agents/conventions"] },
        "skills": { "include": ["dna/agents/skills"] }
      }
    }
  }
}
```

- **git-Schichten** werden geklont. Ein optionales `version:` ist ein
  Semver-Constraint (pub-Semantik), das gegen die Git-Tags des Repos
  aufgeloest wird — der hoechste passende Tag wird ausgecheckt. Tags mit
  und ohne `v`-Praefix werden erkannt. `gg_*`-Kurzformen expandieren zu
  `https://github.com/ggsuite/<name>.git`.
- **path-Schichten** sind lokale Ordner, relativ zur Wurzel des Zielrepos
  (Vorwaerts- wie Rueckwaerts-Schraegstriche funktionieren auf allen
  Plattformen). Enthaelt der Ordner ein `dna/`-Unterverzeichnis, wird
  dieses verwendet, sonst der Ordner selbst.
- **Repo-lokale Schichten** wie `dna/_override` liegen innerhalb von
  `<target>/dna` und ueberleben den Sync woertlich — ihre Marker bleiben
  erhalten, damit der naechste Sync sie erneut anwenden kann. Existiert der
  Ordner (noch) nicht — etwa auf einem frischen Clone, weil Git leere
  Ordner nicht uebertraegt — wird die Schicht als leer uebersprungen.

Nach dem Sync schreibt `gg_dna sync` ein Manifest `dna/.dna.json` —
`dna/` und das Manifest gehoeren mit ins Repo committet, damit `--check`
in der CI laufen kann. `gg_dna sync --check` prueft ohne zu schreiben, ob
`dna/` aktuell ist: lokale Aenderungen, neue Basis-Inhalte,
Konfigurations-Drift, neue passende Git-Tags bzw. Commits und geaenderte
lokale Schichten werden gemeldet. Bei `version:`-Constraints gewinnt der
hoechste passende **stabile** Tag; Prereleases werden nur gewaehlt, wenn
nichts Stabiles passt oder der Constraint selbst eine Prerelease anpeilt.

Der Sync baut den neuen Baum in `<target>/.gg_dna_staging` und tauscht ihn
atomar ein; nach einem abgebrochenen Lauf raeumt der naechste Sync die
Ordner `.gg_dna_staging`/`.gg_dna_backup` auf bzw. stellt `dna/` aus dem
Backup wieder her. Beide Ordner sind fluechtig und gehoeren nicht ins Repo.

## Claude-Konfiguration (`config: claude:`)

Der Sync ist vollstaendig **non-interaktiv** — was frueher die Subcommands
`install-skills`/`apply-conventions` per Rueckfrage erledigten, steuert
jetzt der optionale `config: claude:`-Block:

- **`claude_md: include:`** — Liste aus Dateien und/oder Ordnern (relativ
  zur Zielrepo-Wurzel). Der Sync pflegt in `<target>/CLAUDE.md` einen
  verwalteten Block zwischen `<!-- gg_dna:claude_md:start -->` und
  `<!-- gg_dna:claude_md:end -->` mit einer `@pfad`-Import-Zeile pro Datei
  (Ordner werden rekursiv zu ihren `.md`-Dateien expandiert, alphabetisch
  sortiert). Claude Code laedt diese Imports beim Session-Start (relative
  Pfade, maximal vier Ebenen tief; Imports in Code-Bloecken werden
  ignoriert). Fehlt die `CLAUDE.md`, wird sie angelegt; handgeschriebener
  Inhalt vor/nach dem Block bleibt unangetastet. Ein uebrig gebliebener
  pre-3.0-`gg_dna:conventions`-Block wird entfernt. Fehlende Include-Pfade
  sind ein Fehler — kaputte `@`-Imports entstehen nie.
- **`skills: include:`** — Liste von Ordnern, deren Skills
  (`<name>/SKILL.md`) nach `.claude/skills/<name>` gespiegelt werden.
  gg_dna verwaltet nur die von ihm installierten Skills (gemerkt im
  Manifest): Diese werden aktualisiert bzw. — wenn nicht mehr
  konfiguriert — geloescht. Handinstallierte Skills werden **nie**
  angefasst; eine Namenskollision erzeugt nur eine Warnung.

Ohne `config: claude:` fasst der Sync weder `CLAUDE.md` noch
`.claude/skills` an (zuvor von gg_dna installierte Skills werden dann als
nicht mehr konfiguriert entfernt).

## Tag-Overrides in Markdown-Dateien

Schichten koennen `.md`-Dateien nicht nur komplett ersetzen, sondern auch
gezielt einzelne Abschnitte oder Zeichenketten ueberschreiben.

In der Quelldatei (z. B. `guide.md`) markieren Tags die Override-Punkte:

```markdown
## [greeting] Begruessung

Sag {{tone|freundlich}} hallo.
```

- `## [tag] Ueberschrift` markiert einen **ersetzbaren Abschnitt** — von der
  Ueberschrift bis zur naechsten Ueberschrift gleicher oder hoeherer Ebene.
- `{{tag|Standardwert}}` markiert eine **ersetzbare Zeichenkette** (auch
  `{{tag}}` fuer einen leeren Standardwert).

Eine hoehere Schicht legt daneben eine Datei `guide.tag.md` mit den
Ersetzungen ab. Erlaubte Blockformen:

```markdown
## [greeting] Neue Ueberschrift

Neuer Abschnittsinhalt.

<!-- greeting -->
## Auch ohne Tag in der Ueberschrift
Der Tag wird automatisch wieder angeheftet.
<!-- greeting -->

<!-- tone --> foermlich <!-- tone -->
```

Regeln:

- Ob ein Tag als Abschnitt oder Zeichenkette ersetzt wird, entscheidet die
  Zieldatei (Ueberschrift vs. Platzhalter). Unbekannte Tags erzeugen eine
  Warnung.
- `.tag.md`-Dateien werden beim Sync **konsumiert** und nie ins Ziel
  kopiert.
- Im fertigen Ergebnis werden alle Marker entfernt: `## [tag] T` wird zu
  `## T`, `{{tag|wert}}` zum Wert.
- Inhalte in Code-Fences und Inline-Code bleiben unangetastet — Beispiele
  fuer die Syntax gehoeren deshalb immer in Code-Bloecke, sonst werden sie
  beim Sync ersetzt.

## Migration von 2.x

- Die Layer-Maps wandern in einen `dependencies:`-Block unter `dna:` —
  die alte Syntax (Layer direkt unter `dna:`) wird mit einem
  Migrationshinweis abgelehnt.
- Die Subcommands `install-skills` und `apply-conventions` wurden entfernt;
  gewuenschte CLAUDE.md-Includes und Skill-Ordner werden in
  `dna: config: claude:` konfiguriert und von `gg_dna sync` ohne
  Rueckfragen angewendet.
- Einmal `gg_dna sync` ausfuehren: Der alte `gg_dna:conventions`-Block in
  der CLAUDE.md wird ersetzt; Kopien unter `.claude/conventions/` werden
  nicht mehr benutzt und koennen geloescht werden.
- `.dna.json` hat ein neues Format (v3); `--check` meldet alte Manifeste
  als veraltet — einmal `gg_dna sync` ausfuehren.
