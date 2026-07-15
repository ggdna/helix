# gg_dna

gg_dna ist ein Repository, in dem verschiedene Anleitungen, Scripts und Konfigurationen fuer KI-Agenten liegen. Es stellt Anleitungen sowie Anweisungen fuer Code-Struktur, Test, Deployment und Programmierprinzipien dar. Es ist sozusagen die DNA, also der Aufbauplan fuer Programmierprojekte, die damit erzeugt werden.

## Sync

`gg_dna sync` spiegelt den `dna/`-Ordner dieses Packages in das Zielrepo
(`<target>/dna`) und legt darueber die **DNA-Schichten**, die in der
`pubspec.yaml` des Zielrepos konfiguriert sind. Spaetere Schichten gewinnen
bei Pfad-Kollisionen; die Basis-DNA aus gg_dna ist immer die unterste
Schicht.

```yaml
dna:
  order:
    - dna_company
    - dna_project
    - dna_repo
  dna_company:
    git: https://github.com/acme/dna_company.git
    version: ^1.4.0
  dna_project:
    path: ../dna_project
  dna_repo:
    path: dna/_override
```

- **git-Schichten** werden geklont. Ein optionales `version:` ist ein
  Semver-Constraint (pub-Semantik), das gegen die Git-Tags des Repos
  aufgeloest wird — der hoechste passende Tag wird ausgecheckt. Tags mit
  und ohne `v`-Praefix werden erkannt. `gg_*`-Kurzformen expandieren zu
  `https://github.com/ggsuite/<name>.git`.
- **path-Schichten** sind lokale Ordner, relativ zur Wurzel des Zielrepos.
  Enthaelt der Ordner ein `dna/`-Unterverzeichnis, wird dieses verwendet,
  sonst der Ordner selbst.
- **Repo-lokale Schichten** wie `dna/_override` liegen innerhalb von
  `<target>/dna` und ueberleben den Sync woertlich — ihre Marker bleiben
  erhalten, damit der naechste Sync sie erneut anwenden kann.

Nach dem Sync schreibt `gg_dna sync` ein Manifest `dna/.dna.json`.
`gg_dna sync --check` prueft ohne zu schreiben, ob `dna/` aktuell ist:
lokale Aenderungen, neue Basis-Inhalte, Konfigurations-Drift, neue passende
Git-Tags bzw. Commits und geaenderte lokale Schichten werden gemeldet.

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

## Migration von 1.x

- Das positionale Overlay-Argument (`gg_dna sync <overlay>`) wurde entfernt.
  Overlays werden als Schicht im `dna:`-Block der Ziel-pubspec.yaml
  konfiguriert.
- Der in `.dna.json` gespeicherte Overlay wird nicht mehr automatisch
  wiederverwendet.
- `.dna.json` hat ein neues Format (v2); `--check` meldet alte Manifeste
  als veraltet — einmal `gg_dna sync` ausfuehren.
