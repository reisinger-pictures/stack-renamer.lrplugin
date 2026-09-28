# AGENTS.todo.md — stack-renamer.lrplugin

Actionable tasks for the Stack Renamer Lightroom plugin. Build Agent owns this file; only items
confirmed by an independent verifier subagent are removed. Source plan:
`/Users/florianreisinger/.opencode/plan/stack-renamer-plugin.md`.

## Status
- **AKTIV: 2 UI-Bugs vom User gemeldet (2026-09-28), Fix läuft (general subagent).** Siehe
  "Offene Bugs". Bitte noch nicht als "fertig" werten — beide Bugs sind in Lightroom unbestätigt.
- Implementation (Info / Utils / RenameCore / RenameDialog / RenameStacks + syntax): geschrieben
  und `luac -p`-clean, aber **die direkte Umbenennung wurde nie in Lightroom ausgeführt**.
  Die Prüfung "verified DONE" unten bezieht sich auf Syntax + Stub-Logik, NICHT auf echtes
  Umbenennen in Lightroom.
- Renaming-Workflow ist seit `1b8d657` der **F2-2-Schritte-Ansatz** (Metadaten-Feld + Lightroom
  F2), NICHT `renamePhotoFile`. Details siehe "Verworfen".
- Functional verification needs Lightroom Classic (not available here) — see Manual Verification.

## Offene Bugs (vom User gemeldet 2026-09-28, Lightroom-Test ausstehend)

Beide gemeldet beim Lauf des Dialogs mit gemischter Auswahl (gestackte + nicht gestackte Fotos).

- [ ] **Bug 1 — Edit-Felder nur halb breit.** `RenameDialog.lua`: die `f:row`-Felder `custom`
  und `pattern` (sowie `sortOrder`/`metaField`-Popups) sollen die volle Zeilenbreite füllen.
  Verdacht: `width_in_chars = 30/40` (Z. 327/331/344) kollidiert mit `fill_horizontal = 1` und
  gewinnt, sodass das Feld nicht expandiert. Fix: `width_in_chars` entfernen, `fill_horizontal`
  beibehalten. `start`/`padding` (schmal) und `dateFmt` (klein) sollen schmal BLEIBEN.
  Status: Implementierung an general subagent delegiert.
- [ ] **Bug 2 — Nur EIN Foto erscheint in der Umbenenn-Vorschau**, obwohl mehrere ausgewählt und
  gemischt gestackt/ungestackt sind. Root Cause **NICHT bewiesen**. Hauptverdacht: `LrPhoto`-
  Objekte als Lua-Table-Keys — `getRawMetadata("stackInFolderMembers")` liefert pro Aufruf neue
  Wrapper-Objekte, was `photoInfo[photo]`, `perPhotoBases[photo]` und `g.seen[m]` stillschweigend
  brechen könnte. Alternative Verdachtsmomente: `hasReal`-Filter in `buildGroups` verwirft Gruppen;
  Gruppen werden in `Utils.stackKey` gemerged; `buildPlan` filtert zu wenige Member.
  Status: Root-Cause-Recherche + Diagnose-Logging an general subagent delegiert.
  **Erwartung des Users:** ALLE ausgewählten Fotos sollen durchnummeriert werden, Stack-Zugehörigkeit
  und Stacking selbst dürfen sich NICHT ändern.
- [ ] **Diagnose-Logging** (durch Bug-2-Recherche ergänzt) muss nach dem LR-Test wieder entfernt
  werden. Alle Blöcke sind als `TODO(diagnostics): remove before release` markiert.
  Log-Ziel: `~/Documents/lrClassicLogs/StackRenamerLog.log` (Logger `StackRenamerLog` aus
  `RenameStacks.lua`, logfile bereits aktiv).

## Build-Agent Vorfall: fehlgeschlagener Revert (2026-09-28) — behoben

- Der User bat um einen Revert, "das hat schon geklappt". **Die Annahme war falsch:** `1b8d657`
  ("F2 2-step") ist der **erste Commit, der überhaupt Plugin-Code hinzugefügt hat** (+1031/-0,
  7 neue Dateien). Es existiert **keine** ältere Version mit direkter `renamePhotoFile`-Umbenennung
  im Repo. Ein Revert löschte daher das **komplette Plugin** (Info.lua + RenameStacks.lua fielen
  aus, Lightroom meldete "The plug-in description script (Info.lua) is missing." und danach
  "No script by the name RenameStacks.lua").
- Auflösung: `Info.lua` und `RenameStacks.lua` aus `1b8d657` wiederhergestellt, die übrigen Dateien
  aus dem Stash zurückgeholt, Revert-Commit (`2ce1f6b`) via `git reset b245cab` aus der Historie
  entfernt, `.githooks/pre-commit` wiederhergestellt. Endstand: identisch zu `b245cab` plus den
  lokalen, uncommitteten Änderungen; alle 5 Lua-Dateien `luac -p`-clean.
- **Regel für künftige Reverts in diesem Repo:** Vor `git revert` prüfen, ob der Commit überhaupt
  ein "vorher"-Stand hat. `git show <commit> --stat` zeigt bei 0 Löschungen, dass es der Root-Commit
  des Codes ist und ein Revert alles löscht. Im Zweifel `git revert -n` (Dry Run) bzw. erst
  `git stash` + Zustand dokumentieren.

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
