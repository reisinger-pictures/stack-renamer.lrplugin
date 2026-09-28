# AGENTS.todo.md — stack-renamer.lrplugin

Actionable tasks for the Stack Renamer Lightroom plugin. Build Agent owns this file; only items
confirmed by an independent verifier subagent are removed. Source plan:
`/Users/florianreisinger/.opencode/plan/stack-renamer-plugin.md`.

## Status
- **Bug 1 + Bug 2 GELÖST und vom User in Lightroom bestätigt (2026-09-28, „hat geklappt").** Siehe
  "Behobene Bugs" unten. Der LR-getestete Stand ist gesondert committet, damit er nachvollziehbar
  bleibt.
- **Bug 2 war NICHT die Gruppierung, sondern die Vorschau-Widget.** Der Lightroom-Log
  (`~/Documents/lrClassicLogs/StackRenamerLog.log`, Lauf 2026-09-28 19:13) bewies korrekte Daten:
  `getTargetPhotos: 69`, `buildGroups: 65 group(s)`, `photoInfo entries=72`, `preview lines=50`,
  `notFound=0` in ALLEN Plan-Einträgen. Sichtbar war trotzdem nur EINE Zeile, weil der an
  `props.preview` **gebundene `static_text`** nicht mit dem mehrzeiligen String mitwuchs (blieb eine
  Zeile hoch). Fix: Die Vorschau ist jetzt ein read-only `edit_field` (`height_in_lines = 200`) in
  einem `scrolled_view` mit fester Höhe (`height = 420`).
  **Regel für künftige Fehlersuche in diesem Repo:** Bei „nur eine Zeile / nur ein Foto" ZUERST das
  Logfile lesen. Sind die Zahlen dort korrekt (`notFound=0`), ist die UI das Problem, nicht die
  Gruppierungslogik — dann nicht an `buildGroups`/`stackKey` schrauben.
- **Plugin lädt** (2026-09-28): Der „No script by the name RenameStacks.lua"-Fehler war der gecachte
  Plugin-Scan aus dem fehlgeschlagenen Revert. Nach Lightroom-Neustart steht `4) Stack Renamer` in
  der Plugin-Liste (`lrc_console.log`), keine „No script"-Fehler mehr. Details siehe Vorfall unten.
- Renaming-Workflow ist der **F2-2-Schritte-Ansatz** (Metadaten-Feld + Lightroom F2), NICHT
  `renamePhotoFile`. Er wurde am 2026-09-28 erfolgreich durchgeführt (Dateien im Katalog heißen
  `27_ÖFB-Reisinger_NN`), Details siehe "Verworfen".
- **Nächster Schritt:** Diagnose-Logging entfernen (siehe unten). Der getestete Stand ist zuerst
  committet; die Entfernung folgt in einem separaten Commit plus kurzem Smoke-Test.
- Functional verification of new behaviour still needs Lightroom Classic — see Manual Verification.

## Behobene Bugs (2026-09-28, vom User in Lightroom bestätigt)

Beide gemeldet beim Lauf des Dialogs mit gemischter Auswahl (gestackte + nicht gestackte Fotos);
beide sind behoben.

- [x] **Bug 1 — Edit-Felder nur halb breit.** `width_in_chars` bei `custom` und `pattern` entfernt
  (`fill_horizontal = 1` gewinnt jetzt die Breite); `dateFmt` bleibt klein (nur `width_in_chars = 12`,
  `fill_horizontal` entfernt); `start`/`padding` unverändert schmal. — `RenameDialog.lua`
- [x] **Bug 2 — nur EINE Zeile in der Vorschau.** Root Cause war die **Vorschau-Widget**, NICHT die
  Gruppierung (Log-Beweis im Status oben). Umgesetzt:
  - Vorschau: `static_text` → read-only `edit_field` (`height_in_lines = 200`) in `scrolled_view`
    (`height = 420`, `fill_horizontal = 1`), kein `width_in_chars` mehr → volle Breite, mehrzeilig.
    Zusätzlich `PREVIEW_LIMIT` entfernt: alle Stacks werden gelistet, kein „… und N weitere".
  - Datenpfade defensiv gehärtet (bleibt drin, ist unabhängig vom UI-Bug korrekt): stabile Foto-Keys
    `Utils.photoKey` statt `LrPhoto`-Objekten als Table-Keys, `Utils.stackKey` gehärtet.
  - `Utils.photoKey` liest `uuid`/`path` jetzt DIREKT (vorher in plain `pcall` → SDK-Reads yielden,
    Yielding in `pcall` ist verboten → Key degradierte still auf `tostring(LrPhoto)`).
  — `RenameDialog.lua`, `Utils.lua`, `RenameCore.lua`
- [x] **F2-Token/Feld-Abgleich.** Verifiziert durch Lesen der gespeicherten Vorlage
  `~/Library/Application Support/Adobe/Lightroom/Filename Templates/Instructions Only.lrtemplate`:
  sie enthält genau einen Token, `value = "com.adobe.instructions"` — das ist das Feld, das
  `performRename` via `setRawMetadata("instructions", base)` schreibt. Vom User bestätigt
  („hat geklappt", Dateien im Katalog heißen `27_ÖFB-Reisinger_NN`).
- **Entscheidung 2026-09-28 (User, per Frage-Tool): „Diagnose + robuster Fix in einem".** In EINEM
  LR-Lauf sollen sowohl die Ursache sichtbar als auch der Fix geprüft werden. Umgesetzt wird:
  (a) **stabile Foto-Keys** statt `LrPhoto`-Objekten als Table-Keys — neues `Utils.photoKey(photo)`
  (String aus `uuid` + Virtual-Copy-Flag/Copy-Name, Fallback `path`, dann `tostring`), verwendet in
  `buildGroups` (Dedup), `photoInfo`, `perPhotoBases` und beim Lesen in `previewLine`/`buildPlan`/
  `performRename`; (b) **`Utils.stackKey` gehärtet**: nur `isInStackInFolder == true` gilt als
  gestackt, ungestackte Keys enthalten zusätzlich den `photoKey` (können nicht mehr kollidieren),
  gestackter Fallback ohne Mitglieder-UUIDs fällt auf den eigenen `photoKey` zurück statt auf das
  gemeinsame `"S:"`-Bucket; (c) **Diagnose-Logging** (`TODO(diagnostics): remove before release`).
  Delegiert an einen `general`-Subagenten (Modell `opencode-go/deepseek-v4.1-flash`); Verifikation
  danach durch einen SEPARATEN, unabhängigen Subagenten.
  Grund für den Doppel-Schritt: der Root Cause ist unbewiesen und in dieser Umgebung nicht
  reproduzierbar — ohne Messwerte aus einem echten LR-Lauf ist jeder Fix geraten, ein reiner
  Fix-Versuch kostet sonst einen zweiten LR-Lauf.
- [x] **Diagnose-Logging entfernt** (Commit 2, unabhängig verifiziert: reine Löschung, `luac -p` clean,
  keine funktionale Zeile entfernt). Damit schreibt das Plugin NICHT mehr nach
  `~/Documents/lrClassicLogs/StackRenamerLog.log`.
  **Offen: Smoke-Test nach diesem Commit.** Die Dateien haben sich erneut geändert → Lightroom
  Classic komplett neu starten (Regel in AGENTS.md) und Dialog einmal öffnen (Vorschau mehrzeilig,
  Felder volle Breite). Das ist ein reiner Sichtcheck, keine neue Funktionalität.
- [ ] **BUG (vom unabhängigen Verifier gefunden, noch offen): `RenameDialog.listFilesInFolder`**
  wrappt die yieldenden `LrFileUtils.files` / `LrFileUtils.directoryContents` in ein plain `pcall`.
  Folge: der Read kann fehlschlagen → die Funktion liefert `{}` → **die Ordner-Kollisionsprüfung
  greift dann nie** (kein Fehler, kein Hinweis). Das ist KEIN Diagnose-Code, sondern Verhalten.
  Fix: `LrTasks.pcall` verwenden (oder direkt lesen) — danach in Lightroom mit einer echten
  Ordner-Kollision prüfen.

## Build-Agent Vorfall: fehlgeschlagener Revert (2026-09-28)

- Der User bat um einen Revert, "das hat schon geklappt". **Die Annahme war falsch:** `1b8d657`
  ("F2 2-step") ist der **erste Commit, der überhaupt Plugin-Code hinzugefügt hat** (+1031/-0,
  7 neue Dateien). Es existiert **keine** ältere Version mit direkter `renamePhotoFile`-Umbenennung
  im Repo. Ein Revert löschte daher das **komplette Plugin** (Info.lua + RenameStacks.lua fielen
  aus, Lightroom meldete "The plug-in description script (Info.lua) is missing." und danach
  "No script by the name RenameStacks.lua").
- Auflösung (Dateien): `Info.lua` und `RenameStacks.lua` aus `1b8d657` wiederhergestellt, die übrigen
  Dateien aus dem Stash zurückgeholt, Revert-Commit (`2ce1f6b`) via `git reset b245cab` aus der
  Historie entfernt, `.githooks/pre-commit` wiederhergestellt. Endstand: identisch zu `b245cab` plus
  den lokalen, uncommitteten Änderungen; alle 5 Lua-Dateien `luac -p`-clean.
- **Nachtrag 2026-09-28: NICHT "behoben" durch den Datei-Restore — Lightroom blieb kaputt.**
  Der Fehler "No script by the name RenameStacks.lua" trat danach **4×** weiter auf
  (18:55 / 19:00 / 19:02 / 19:04), immer in **derselben LR-Prozess-ID 69480**, ohne Neustart
  dazwischen. Belege (Logs): `lrc_console.log` zeigt den Pfad
  `reloadPlugin → reloadPluginIfNeededForEachUse → loadScript → error(...)`, und
  `LrClassicLogs/StackRenamerLog.log` hat seit 2026-08-30 **keinen neuen Eintrag** → der
  Script-Body wurde nie ausgeführt, der Fehler passiert vor dem Laden.
- **Wahre Ursache: veraltete Plugin-/Script-Liste im Lightroom-Prozess.** Lightroom hat den
  Plugin-Ordner gescannt, **während die Dateien (durch den Revert) fehlten**, und die Script-Liste
  ohne `RenameStacks.lua` im laufenden Prozess gecacht. `reloadPluginIfNeededForEachUse` reicht
  nicht — der Ordner wird pro Sitzung nicht neu gescannt. Beim erneuten Auftreten ist deshalb
  **kein** Code-Regressionsverdacht angebracht, solange `luac -p` clean ist und die
  Info.lua-Referenz stimmt.
- **Regel für künftige Reverts in diesem Repo:** Vor `git revert` prüfen, ob der Commit überhaupt
  ein "vorher"-Stand hat. `git show <commit> --stat` zeigt bei 0 Löschungen, dass es der Root-Commit
  des Codes ist und ein Revert alles löscht. Im Zweifel `git revert -n` (Dry Run) bzw. erst
  `git stash` + Zustand dokumentieren.
- **Regel für Plugin-Datei-Änderungen in diesem Repo:** Nachdem Dateien im `.lrplugin`-Ordner
  gelöscht/wiederhergestellt/umbenannt wurden (oder wenn ein neues Script in `Info.lua`
  referenziert wird), **Lightroom Classic komplett beenden und neu starten** (nicht nur das
  Fenster schließen). Reicht das nicht: File → Plug-in Manager → Plugin entfernen und den
  `.lrplugin`-Ordner neu hinzufügen. Ein bloßer Menü-Klick lädt den Ordner nicht neu.

## Implemented & verified (pruned from active TODOs)
- [x] Same-extension numbering + folder collisions (verified DONE by independent subagent,
  `luac -p` clean, 14/15 stub tests pass — 1 fail was a bad test expectation, fixed via
  leading-dot normalization in `assignNumberedBases`): per-stack `base`, `base-2`, `base-3`, …
  (ext compare case-insensitive, ext case preserved); per-photo `perPhotoBases` in plan,
  preview + `performRename` nutzen sie; Kollisionscheck auf finalen Dateinamen, ordner-scoped,
  case-insensitive, Plan-Quellen exkludiert; SDK pre-fetched außerhalb Observer;
  `canApply=false` + deutsche Meldung mit Ordner+Dateiname. — `Utils.lua`, `RenameDialog.lua`,
  `RenameCore.lua`
- [x] `Info.lua` — manifest + `LrLibraryMenuItems` ("Stacks konsistent umbenennen..." → `RenameStacks.lua`)
- [x] `Utils.lua` — tokens `{date}`/`{date:<fmt>}`/`{custom}`/`{seq}`/`{orig}`; `LrDate` default `DD`;
  `seq` padding default 2; `stackKey` (`stackUuid` + per-photo fallback); `findCollisions` (case-insensitive)
- [x] `RenameCore.lua` — `getTargetPhotos`; group (unstacked = size 1); skip VCs; sort by
  `dateTimeOriginal` then filename; **eine** `withWriteAccessDo`; pro Foto
  `setRawMetadata(metaField, base)` in `metaField` = `instructions` (Default) | `headline`;
  `LrTasks.pcall` pro Schreibvorgang; ProgressScope; Abschlussdialog **außerhalb** des Write-Blocks.
  → Der User vervollständigt die Umbenennung selbst via Lightroom F2 (siehe README).
- [x] `RenameDialog.lua` — German settings dialog (custom, dateFmt `DD`, start 1, padding 2,
  pattern `{date}_{custom}_{seq}`, sort order) + live preview; "Anwenden" disabled on collision/empty
- [x] `RenameStacks.lua` — entry module (**executed directly by Lightroom**, no `return function`;
  `LrTasks.startAsyncTask` → `RenameCore.run()`)
- [x] Lua syntax check (`luac -p`) — all 5 files clean

## Build-Agent small fixes (applied, syntax-checked; still need LR functional confirm)
- Moved the final `LrDialogs.message` **out** of `withWriteAccessDo` (modal dialogs inside a write
  block can deadlock on some LR builds). — `RenameCore.lua`
- De-duplicated collision logic: `RenameDialog.buildPlan` now calls `Utils.findCollisions`
  instead of an inline copy. — `RenameDialog.lua`
- **Menu entry did nothing in LR** (no dialog, no error, clickable item under Library → Plug-in
  Extras). Root cause: `RenameStacks.lua` used `return function() ... end`, but LR **executes**
  Library/export menu files directly and never calls a returned function. Switched to direct
  `LrTasks.startAsyncTask(...)` at load time (like the working `SelectionManager.lua`). — `RenameStacks.lua`
- Menu moved from `LrLibraryMenuItems` (Library → Plug-in Extras) to `LrExportMenuItems`
  (File → Plug-in Extras), matching the sibling portal plugin. — `Info.lua`
- `renamePhotoFile(photo, base, false, nil)` → `renamePhotoFile(photo, base, true, nil)`:
  `baseNameOnly = true` preserves each file's extension (`false` would strip it). — `RenameCore.lua`
- Added pcall error surfacing in `RenameStacks.lua` (any unexpected error now shows a dialog).

## Follow-up (open)
- [ ] `setRawMetadata("instructions"|"headline", base)` auf das **richtige** IPTC-Feld abgleichen:
      Lightroom liest in der F2-File-Naming-Vorlage `{IPTC:Instructions}` bzw. `{IPTC:Headline}`.
      Sicherstellen, dass der von `performRename` geschriebene Feldname exakt dem in der Vorlage
      verwendeten Token entspricht — sonst benennt F2 die Dateien nicht um.
- [ ] F2-Workflow Ende-zu-Ende in Lightroom durchspielen (Vorbereiten → F2 → Vorlage → Dateien auf
      der Platte umbenannt, XMP-Sidecars konsistent, Katalog stimmt).

## Verworfen (nicht erneut implementieren)

- **`catalog:renamePhotoFile(photo, base, true, nil)` für direktes Umbenennen.** Ansatz aus dem
  ersten Entwurf, ersetzt durch den F2-2-Schritte-Ansatz in `1b8d657`. Grund: die Lightroom-SDK
  bietet keine garantierte File-Rename-API; das Verhalten bzgl. Endung und XMP-Sidecar ist auf der
  Ziel-LR-Version unbestätigt, während der F2-Weg Endungen und Sidecars nachweislich korrekt
  behandelt. **Nicht** reaktivieren, solange der F2-Werkflow nicht abgelehnt wurde.
- **Vollständiges Revert auf `1b8d657^`.** Nicht möglich — es ist der Root-Commit des Plugin-Codes
  (siehe "Build-Agent Vorfall" oben).

## Manual Verification (Lightroom Classic required; NOT possible in this env)
- [ ] 3-format stack (CR3+DNG+JPEG) → all three share the base name, only the extension differs.
- [ ] 2× gleiche Endung in einem Stack (z.B. 2× JPG) → `base` + `base-2`, Vorschau zeigt beide.
- [ ] Ordner-Kollision (Zielname existiert bereits im selben Ordner, nicht Teil des Plans)
  → „Anwenden" blockiert mit Ordner+Dateiname; gleicher Name in anderem Ordner → OK.
- [ ] Single unstacked photo → renamed correctly (size-1 stack).
- [ ] Collision detection blocks "Anwenden".
- [ ] Undo reverts the whole operation in one step (single `withWriteAccessDo`).
- [ ] Vorschau ist read-only + scrollbar (`scrolled_view`): scrollt bei >~15 Zeilen /
  50+ Stacks inkl. „… und N weitere"-Zeile; Live-Update bei jeder Settings-Änderung.
- [ ] **Bug 1:** Freitext- und Namensmuster-Feld füllen die volle Dialogbreite; `start`/`padding`
  bleiben schmal.
- [ ] **Bug 2:** gemischte Auswahl (gestackt + ungestackt) → Vorschau listet ALLE ausgewählten
  Fotos; jede Stack-Zeile zeigt alle ihre Mitglieder; Sequenznummer läuft durch.
- [ ] **Stacking unverändert** nach einem Durchlauf: Member-Anzahl + Reihenfolge des Stacks in
  Lightroom vorher/nachher vergleichen.
- [ ] F2 abgeschlossen: Dateien auf der Platte heißen `25_Island_02.CR3/.DNG/.JPEG` (nur Endung
  unterscheidet sich), XMP-Sidecars folgen, Katalog zeigt die neuen Namen.

## Open Points
- Date tag `DD` (day) vs `YY` (year) — both yield "25"; default `DD`, user can change in dialog.
- Extension preserved in original case (`.CR3`, not lowercased to `.cr3`).
- Two-step dialog was collapsed into one combined modal dialog (functionally equivalent).
