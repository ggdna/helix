# gg_dna

gg_dna ist ein Repository, in dem verschiedene Anleitungen, Scripts und Konfigurationen fuer KI-Agenten liegen. Es stellt Anleitungen sowie Anweisungen fuer Code-Struktur, Test, Deployment und Programmierprinzipien dar. Es ist sozusagen die DNA, also der Aufbauplan fuer Programmierprojekte, die damit erzeugt werden.

## Sync

`gg_dna sync` spiegelt die Basis-DNA dieses Packages (`dna/src`) in das
Zielrepo (`<target>/dna`) und legt darueber die **DNA-Schichten**, die im
Zielrepo konfiguriert sind. Spaetere Schichten gewinnen bei
Pfad-Kollisionen; die Basis-DNA aus gg_dna ist immer die unterste Schicht,
`<target>/dna/src` ist immer die oberste (implizit, ohne Config-Eintrag).

In **allen DNA-Quellen** liegt die mergebare DNA unter `dna/src` — im
gg_dna-Package selbst, in git-Schichten und in path-Schichten. Im Zielrepo
enthaelt `/dna` nur das fertig gemergte Ergebnis (plus Manifest und den
eigenen `src`-Ordner).

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
  dependencies:
    dna_company:
      git: https://github.com/acme/dna_company.git
      version: ^1.4.0
    dna_project:
      path: ../dna_project
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
    "order": ["dna_company"],
    "dependencies": {
      "dna_company": { "git": "gg_dna_company", "version": "^1.4.0" }
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

- **git-Schichten** werden geklont; die DNA kommt aus `<clone>/dna/src`
  (fehlt der Ordner, ist das ein Fehler mit Migrationshinweis). Ein
  optionales `version:` ist ein Semver-Constraint (pub-Semantik), das
  gegen die Git-Tags des Repos aufgeloest wird — der hoechste passende Tag
  wird ausgecheckt. Tags mit und ohne `v`-Praefix werden erkannt.
  `gg_*`-Kurzformen expandieren zu `https://github.com/ggsuite/<name>.git`.
- **path-Schichten** sind lokale Ordner, relativ zur Wurzel des Zielrepos
  (Vorwaerts- wie Rueckwaerts-Schraegstriche funktionieren auf allen
  Plattformen); die DNA kommt aus `<pfad>/dna/src`.
- **`<target>/dna/src`** ist die repo-eigene Override-Schicht: Sie wird
  automatisch als **allerletzte Schicht** angewendet und darf nicht in der
  Config stehen (der Layername `src` ist reserviert). Sie ueberlebt den
  Sync woertlich — ihre Marker bleiben erhalten, damit der naechste Sync
  sie erneut anwenden kann. Existiert der Ordner (noch) nicht — etwa auf
  einem frischen Clone, weil Git leere Ordner nicht uebertraegt — wird die
  Schicht als leer uebersprungen. Path-Schichten, die in `<target>/dna`
  zeigen (frueher `dna/_override`), sind ein Fehler.

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
## [@greeting] Begruessung

Sag {{@tone:freundlich}} hallo.
```

- `## [@tag] Ueberschrift` markiert einen **ersetzbaren Abschnitt** — von
  der Ueberschrift bis zur naechsten Ueberschrift gleicher oder hoeherer
  Ebene.
- `{{@tag:Standardwert}}` markiert eine **ersetzbare Zeichenkette** (auch
  `{{@tag}}` fuer einen leeren Standardwert).

Eine hoehere Schicht legt daneben eine Datei `guide.overrides.md` mit den
Ersetzungen ab. Erlaubte Blockformen:

```markdown
## [@greeting] Neue Ueberschrift

Neuer Abschnittsinhalt.

<!-- @greeting -->
## Auch ohne Tag in der Ueberschrift
Der Tag wird automatisch wieder angeheftet.
<!-- @greeting -->

<!-- @tone --> foermlich <!-- @tone -->
```

Regeln:

- Ob ein Tag als Abschnitt oder Zeichenkette ersetzt wird, entscheidet die
  Zieldatei (Ueberschrift vs. Platzhalter). Unbekannte Tags erzeugen eine
  Warnung.
- `.overrides.md`-Dateien werden beim Sync **konsumiert** und nie ins Ziel
  kopiert. Der alte Suffix `.tag.md` ist ein harter Fehler mit
  Umbenennungshinweis.
- Im fertigen Ergebnis werden alle Marker entfernt: `## [@tag] T` wird zu
  `## T`, `{{@tag:wert}}` zum Wert. Die alte Notation (`[tag]`,
  `{{tag|wert}}`) wird nicht mehr erkannt und bleibt woertlich stehen —
  der Sync warnt bei eindeutigen Alt-Mustern mit Datei und Zeile.
- Inhalte in Code-Fences und Inline-Code bleiben unangetastet — Beispiele
  fuer die Syntax gehoeren deshalb immer in Code-Bloecke, sonst werden sie
  beim Sync ersetzt.

## Globale Overrides (`global.overrides.md`)

Jede Schicht kann in der Wurzel ihrer `dna/src` eine `global.overrides.md`
ablegen. Ihre **Zeichenketten-Bloecke** ersetzen `{{@tag:…}}`-Platzhalter
in **allen** `.md`-Dateien des bis dahin gemergten Baums — nicht nur in
der gleichnamigen Datei:

```markdown
<!-- @tone --> foermlich <!-- @tone -->
```

- Dateispezifische `X.overrides.md` **derselben Schicht gewinnen** ueber
  die globale Datei; ueber Schichten hinweg gilt wie immer: spaetere
  Schicht gewinnt, `<target>/dna/src` zuletzt.
- Abschnitts-Bloecke (`## [@tag] …`) sind in der globalen Datei nicht
  erlaubt und werden mit Warnung uebersprungen.
- Der Name ist reserviert: eine Inhaltsdatei `global.md` kann nicht per
  Overrides-Datei gepatcht werden (Warnung).

## Migration von 3.x

- Die mergebare DNA jedes DNA-Repos wandert von `dna/` nach `dna/src/`
  (gilt auch fuer path-Schichten und gg_dna selbst).
- Der Inhalt von `dna/_override` wandert nach `dna/src`; der zugehoerige
  Layer-Eintrag in der Config entfaellt — `dna/src` wird automatisch als
  letzte Schicht angewendet. Path-Schichten, die in `<target>/dna` zeigen,
  sind jetzt ein Fehler.
- `<datei>.tag.md` wird zu `<datei>.overrides.md` umbenannt (alter Suffix
  ist ein harter Fehler).
- Neue Tag-Notation: `## [@tag] …` statt `## [tag] …` und
  `{{@tag:default}}` statt `{{tag|default}}` — auch in den Blockformen der
  Overrides-Dateien (`<!-- @tag -->`).
- `.dna.json` hat ein neues Format (v4); `--check` meldet alte Manifeste
  als veraltet — einmal `gg_dna sync` ausfuehren.
