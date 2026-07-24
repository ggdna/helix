# Ticket: dna_src_and_overrides_md — /dna/src-Layout, .overrides.md, @-Tag-Notation, global.overrides.md

**Breaking Change → nächste Major-Version.** Beim Publish `version_increment: major`
wählen (Hinweis: die 3.0-Änderungen aus `feat-dna-config-v3` wurden auf pub.dev als
2.1.1 veröffentlicht — die Major-Semantik diesmal explizit setzen).

Multi-Repo-Ticket: `gg_dna` (Implementierung), `gg_dna_ggsuite` (DNA-Repo),
`testproject_dna_project` (Referenz-/E2E-Projekt).

## 1. `<file>.tag.md` → `<file>.overrides.md`

- Suffix überall umbenennen (`md_tags.dart`: `tagFileSuffix`, Sync, Doku, Tests).
- Semantik unverändert: `X.overrides.md` patcht Sektionen/Zeichenketten der
  gemergten `X.md`, wird beim Merge konsumiert und nie ins Ziel kopiert.
- Eine `.tag.md` in irgendeiner Schicht ist ein **harter Fehler** mit
  Migrationshinweis („benenne `<datei>.tag.md` in `<datei>.overrides.md` um").

## 2. Neue Tag-Notation mit `@`

In den Quell-`.md`-Dateien:

- **Sektionen:** `## [@greeting] Begruessung` (bisher `## [greeting] …`).
  Ersetzbar von der Überschrift bis zur nächsten Überschrift gleicher oder
  höherer Ebene.
- **Zeichenketten:** `Sag {{@tone:freundlich}} hallo.` — `@` vor dem Tagnamen,
  `:` (statt `|`) trennt den Default; `{{@tone}}` für leeren Default.

In den `.overrides.md`-Dateien entsprechend:

```markdown
## [@greeting] Neue Ueberschrift

Neuer Abschnittsinhalt.

<!-- @greeting -->
## Auch ohne Tag in der Ueberschrift
<!-- @greeting -->

<!-- @tone --> foermlich <!-- @tone -->
```

- Beim Rendern werden alle Marker entfernt: `## [@tag] T` → `## T`,
  `{{@tag:wert}}` → `wert`, wie bisher.
- Die **alte Notation** (`[tag]` ohne `@`, `{{tag|default}}`, `<!-- tag -->`)
  wird nicht mehr erkannt. Damit stille Fehler auffallen: Wenn eine Quell- oder
  Overrides-Datei ein Muster der alten Notation enthält, gibt der Sync eine
  **Warnung** mit Datei und Zeile aus (kein Abbruch — normale Markdown-Inhalte
  dürfen z. B. `[link]`-Syntax enthalten, daher Warnung nur bei eindeutigen
  Mustern wie `{{name|…}}` und `## [name] …`).
- Code-Fences und Inline-Code bleiben wie bisher unangetastet.

## 3. `/dna/src`-Layout — überall

**In allen DNA-Quellen liegt die mergebare DNA unter `dna/src`:**

- **gg_dna selbst:** die Basis-DNA wandert von `<gg_dna>/dna/` nach
  `<gg_dna>/dna/src/`.
- **git-Layer:** Inhalt kommt aus `<clone>/dna/src`. Fehlt der Ordner →
  Fehler mit Migrationshinweis („verschiebe die DNA nach dna/src").
- **path-Layer:** Inhalt kommt aus `<pfad>/dna/src`. Fehlt der Ordner →
  gleicher Fehler. (Die bisherige Direkt-Ordner-Variante entfällt.)

**Im Zielprojekt:**

- `/dna` enthält **nur das fertig gemergte Ergebnis** (plus Manifest
  `.dna.json` und den `src`-Ordner, s. u.).
- `/dna/src` ist die repo-eigene Override-Quelle: Sie überlebt den Sync
  wörtlich (Marker bleiben erhalten) und wird **implizit als allerletzte
  Schicht** angewendet — sie wird **nicht** in der `dna.yaml` aufgeführt.
  Fehlt der Ordner (frischer Clone, Git überträgt leere Ordner nicht), wird
  er als leer übersprungen; der Sync legt ihn nicht zwingend an.
- Explizite path-Layer, die in das `/dna` des Zielrepos zeigen (z. B. das
  bisherige `dna/_override`), sind ein **Fehler** mit Migrationshinweis:
  „Inhalt nach dna/src verschieben und den Layer-Eintrag entfernen."
- Bestehende Mechanik wiederverwenden: Snapshot/Restore der in-dna-Schicht,
  Hash-Berechnung nach dem Restore, damit `--check` direkt nach dem Sync
  grün ist.

Manifest/`--check`: `dna/src` wird wie bisher die `dna_repo`-Schicht gehasht
(implizite Schicht, fester Name z. B. `src` im Manifest); Änderungen an
`dna/src` nach dem Sync meldet `--check` als Layer-Änderung.

## 4. `global.overrides.md`

- Jede Schicht kann in der **Wurzel ihrer `src`** eine `global.overrides.md`
  haben (auch das Zielprojekt in `/dna/src`).
- Sie enthält **Zeichenketten-Ersetzungen** (`<!-- @tag --> wert <!-- @tag -->`),
  die auf **alle** `.md`-Dateien des gemergten Baums angewendet werden — jeder
  `{{@tag:…}}`-Platzhalter mit passendem Tagnamen, egal in welcher Datei
  (nicht nur in der gleichnamigen `.md`).
- Sektions-Blöcke in `global.overrides.md` sind nicht vorgesehen → Warnung,
  Block wird ignoriert.
- **Präzedenz:** dateispezifische `X.overrides.md` gewinnen über
  `global.overrides.md` derselben Schicht; über Schichten hinweg gilt wie
  immer: spätere Schicht gewinnt, die implizite `/dna/src` des Zielprojekts
  zuletzt.
- Wie alle Overrides-Dateien wird sie konsumiert und nie ins gemergte
  Ergebnis kopiert (im Ziel-`/dna/src` bleibt sie als Quelle natürlich
  liegen).
- Reservierter Name: eine Inhaltsdatei `global.md` kann folglich nicht per
  Overrides-Datei gepatcht werden → Warnung, falls eine `global.md` in einer
  Quelle liegt.

## 5. Repos in diesem Ticket umstellen

- **gg_dna:** Implementierung (Sync, Layer-Auflösung, `md_tags` → neue
  Notation + Umbenennung, implizite src-Schicht, global-Overrides), eigene
  Basis-DNA nach `dna/src`, Sample-Folder der Tests, README, CHANGELOG,
  Install-Skripte prüfen (`install/`, `install.bat`).
- **gg_dna_ggsuite:** `dna/` → `dna/src/`; vorhandene `.tag.md` →
  `.overrides.md`; Notation auf `[@tag]` / `{{@tag:default}}` umstellen.
- **testproject_dna_project:** Inhalt von `dna/_override` nach `dna/src`
  verschieben, `dna_repo`-Layer aus der `dna.yaml` entfernen, Notation
  umstellen; **`project_structure.md` anlegen** (wird in
  `config.claude.claude_md.include` referenziert, fehlt aber — aktuell würde
  jeder Sync dort fehlschlagen).

## 6. Tests

- Parser-/Merge-Tests auf neue Notation und Suffixe umstellen.
- Neue Tests: implizite `/dna/src`-Schicht (angewendet ohne Config-Eintrag,
  überlebt Sync, `--check`-Drift), Fehler bei fehlendem `dna/src` in
  git-/path-Layern, Fehler bei `.tag.md`, Fehler bei in-dna-Layern in der
  Config, `global.overrides.md` (global wirksam, Präzedenz gegen
  dateispezifische Overrides und über Schichten, Warnung bei
  Sektions-Blöcken), Warnung bei Alt-Notation.
- E2E gegen `testproject_dna_project` (im Ticket enthalten).

## Entscheidungen (mit Göran am 2026-07-24 geklärt)

- `/dna/src` **überall** konsequent (gg_dna-Basis, git- und path-Layer);
  Quellen ohne `dna/src` → Fehler mit Migrationshinweis.
- `.tag.md` → **harter Fehler** mit Umbenennungshinweis.
- `dna/_override` entfällt; Inhalt wandert nach `/dna/src` (implizite letzte
  Schicht, ohne dna.yaml-Eintrag).
- Neue Tag-Notation: `## [@tag] …` und `{{@tag:default}}`.
- `global.overrides.md` in `/dna/src` ersetzt Zeichenketten-Tags global über
  alle Dateien.
- Multi-Repo-Ticket mit gg_dna, gg_dna_ggsuite, testproject_dna_project.
