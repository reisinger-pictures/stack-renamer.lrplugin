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

The build/verify flow is defined centrally in the skill `build-verify` (repo `agents-skills`,
always-on kernel `.agents/rules/build-verify.md`): pull first, orchestration only, independent
verifier, commit after *every* verify round regardless of verdict, amend on redo, push + CI
watch. It applies here unchanged — this `AGENTS.md` defines only *what* must be green in this
repo, which is the "Definition of Done / Verification" section below.

## Definition of Done / Verification

- **Lightroom Classic is required for functional verification** and is NOT available in this
  environment. The only automatable check is a **Lua syntax check** (e.g. `luac -p` if present, or
  a stubbed check of `Utils` logic without SDK `import`s).
- Functional checks (actual rename, sidecar handling, stack grouping, undo) MUST be done manually
  in Lightroom Classic — list them in `AGENTS.todo.md` as a manual checklist.
- **After any file change inside the `.lrplugin` folder** (delete / restore / rename, or a new
  script referenced from `Info.lua`): **quit and restart Lightroom Classic completely** (closing
  the window is not enough). LR scans the plugin folder only at startup; otherwise a menu click
  fails with `No script by the name <file>.lua` even though the file is on disk. Fallback: remove
  and re-add the plugin in File → Plug-in Manager. Details: see the incident note in `AGENTS.todo.md`.
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

## CodeGraph — Index & MCP (bevorzugt nutzen!)

- **Status:** CodeGraph ist initialisiert (`.codegraph/` vorhanden, 5 Lua-Files, 66 Nodes, 89 Edges, Stand 2026-09-02, `codegraph status` → ✓ up to date). Lua wird unterstützt.
- **CLI:** `~/.local/bin/codegraph` (auf `$PATH`):
  `codegraph explore "<symbol oder Frage>"` — gleiche Ausgabe wie MCP-Tool `codegraph_explore`
  `codegraph status` — Index-Statistik, `codegraph sync` — inkrementell, `codegraph index` — Rebuild
- **MCP-Server (für den Agenten, bevorzugt):** Global in `~/.config/opencode/opencode.jsonc` konfiguriert:
  ```json
  { "mcp": { "codegraph": { "type": "local", "command": ["codegraph", "serve", "--mcp"], "enabled": true } } }
  ```
  Tools: `codegraph_explore` (eine Abfrage = Verbatim-Source + Call-Paths + Blast-Radius), `codegraph_node`, `codegraph_query`, `codegraph_files`. **Immer MCP nutzen wenn `.codegraph/` existiert** — ersetzt grep+Read-Loop. Ohne `.codegraph/` → Built-in Tools (Read/Grep) nutzen, nicht selbst `codegraph init` ausführen (User-Entscheidung).
- **Git Hook:** `.githooks/pre-commit` läuft `codegraph sync -q` vor jedem Commit (fails open, nie blockierend). Aktivieren via `git config core.hooksPath .githooks` (pro Clone einmal).
- **Kein `.codegraph/`?** Dann CodeGraph überspringen — kein Ersatz nötig.

## Open Points (see AGENTS.todo.md)

- Date-tag interpretation: `DD` (day) vs `YY` (year) — both yield "25"; default `DD`.
- Extension case: preserved as-is (`.CR3`, not lowercased to `.cr3`).
- `LrCatalog:renamePhotoFile` extension/sidecar behavior must be confirmed on the target LR version;
  fallback is `setRawMetadata("fileName", base)` + manual sidecar handling.
