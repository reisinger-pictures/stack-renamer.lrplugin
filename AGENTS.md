# AGENTS.md — stack-renamer.lrplugin (Lightroom Classic Lua Plugin)

Plain Lua running inside Lightroom Classic (SDK 8.0). Mirror of the sibling
`portal.reisinger.pictures/admin.lrplugin` conventions. This is a **standalone plugin** (own
`*.lrplugin` folder); it does not share code with the portal plugin.

## Scope

Library-menu plugin ("Stack Renamer") that renames a whole folder / current selection of photos
**stack-consistently**: every member of a stack (e.g. `IMG_1234.CR3` + `.DNG` + `.JPEG`) shares one
base name; only the file extension differs. Stacks of any size are supported; **unstacked photos
are treated as a stack of size 1**.

## Key Files

| File | Role |
|------|------|
| `Info.lua` | Plugin manifest (`LrSdkVersion`, version, `LrExportMenuItems` entry → File → Plug-in Extras) |
| `RenameStacks.lua` | Entry module: **executed directly by Lightroom** (no returned function), starts an async task at load time (like `SelectionManager.lua`) |
| `RenameCore.lua` | Logic: read selection → group into stacks → sort → build preview → rename (like `ManagerCore.lua`) |
| `RenameDialog.lua` | `LrView` dialog: settings + preview/confirm (like `GalleryDialog.lua`) |
| `Utils.lua` | Helpers: token parser, date formatting, stack-grouping key, collision check |
| `AGENTS.todo.md` | Temporary task list + open points (owned by Build Agent) |

## Lua Conventions

- Lua 5.1 / Lightroom SDK 8.0: `import 'LrXxx'` for SDK modules, `require "Xxx"` for local modules.
- Library/export menu entry modules run **directly** when Lightroom loads the file (like
  `SelectionManager.lua`): they must call `LrTasks.startAsyncTask(...)` at load time themselves —
  they do **NOT** `return function() ... end`.
- Catalog writes inside `catalog:withWriteAccessDo(..., function() ... end)`.

## Language Rules

- **Code, comments, commit messages: English.**
- **UI strings: German** (matches the sibling plugin and the user's language).

## Build-Agent Rule (STRICT — Orchestration only)

This plugin is developed under the same Build-Agent policy as the portal repo
(`portal.reisinger.pictures/AGENTS.md` §5). The Build Agent:

1. **Does NOT write plugin code itself.** Implementation is delegated to a `general` subagent with
   full context (this `AGENTS.md`, the plan, and the file list).
2. May make **small edits only** (typo fixes, policy/`AGENTS.md`/`AGENTS.todo.md` adjustments).
3. Owns `AGENTS.todo.md`: keeps actionable TODOs + open points there.
4. **Verification is done by a SEPARATE, independent subagent — never the implementer.** The
   verifier reviews the produced files, runs a Lua syntax check, and checks spec adherence, then
   reports which TODOs are confirmed done.
5. **Prunes `AGENTS.todo.md`**: only TODOs confirmed by the independent verifier are removed.
   Unverified or failed items stay (or are re-added) with a note.

## Definition of Done / Verification

- **Lightroom Classic is required for functional verification** and is NOT available in this
  environment. The implementer can only run a **Lua syntax check** (e.g. `luac -p` if present, or
  a stubbed check of `Utils` logic without SDK `import`s).
- Functional checks (actual rename, sidecar handling, stack grouping, undo) MUST be done manually
  in Lightroom Classic — list them in `AGENTS.todo.md` as a manual checklist.
- One `withWriteAccessDo` block per run → single Undo step.

## Naming Pattern Spec

Token-based pattern string (editable in the dialog), default `{date}_{custom}_{seq}`:

- `{date}` / `{date:<fmt>}` — capture date via `LrDate.timeToUserFormat(time, fmt)`.
  Default `fmt = "DD"` (2-digit day → "25"; switchable to `YY`, `YYYYMMDD`, …).
- `{custom}` — free-text from the dialog (e.g. "Island"), same for all stacks.
- `{seq}` — per-stack sequence number, zero-padded to a configurable width (**default 2 → "02"**),
  start value configurable (default 1).

Result for Ina's wish: `25_Island_02` applied to `.CR3` / `.DNG` / `.JPEG`. The **extension is
preserved automatically per file** (Lightroom appends it on rename); it is NOT part of the pattern.

## Open Points (see AGENTS.todo.md)

- Date-tag interpretation: `DD` (day) vs `YY` (year) — both yield "25"; default `DD`.
- Extension case: preserved as-is (`.CR3`, not lowercased to `.cr3`).
- `LrCatalog:renamePhotoFile` extension/sidecar behavior must be confirmed on the target LR version;
  fallback is `setRawMetadata("fileName", base)` + manual sidecar handling.
