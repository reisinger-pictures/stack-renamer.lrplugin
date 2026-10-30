# AGENTS.md — stack-renamer.lrplugin (Lightroom Classic Lua Plugin)

Standalone Lightroom Classic plugin, plain Lua on SDK 8.0. It mirrors the conventions of the
sibling `portal.reisinger.pictures/admin.lrplugin` but never shares code or files with it.

## Scope

Renames a folder / the current selection **stack-consistently**: every member of a stack shares one
base name, only the file extension differs. Stacks of any size are supported; **unstacked photos are
treated as a stack of size 1**.

## Key Files

| File | Role |
|------|------|
| `Info.lua` | Plugin manifest (`LrSdkVersion`, version, `LrExportMenuItems` entry → File → Plug-in Extras) |
| `RenameStacks.lua` | Entry module: **executed directly by Lightroom** (no returned function), starts an async task at load time |
| `RenameCore.lua` | Logic: read selection → group into stacks → sort → build preview → rename |
| `RenameDialog.lua` | `LrView` dialog: settings + preview/confirm |
| `Utils.lua` | Helpers: token parser, date formatting, stack-grouping key, collision check |
| `AGENTS.todo.md` | Open tasks and open points (owned by the Build Agent) |

## Lua Conventions

- Lua 5.1 / Lightroom SDK 8.0: `import 'LrXxx'` for SDK modules, `require "Xxx"` for local modules.
- Library/export menu entry modules run **directly** when Lightroom loads the file (like the sibling
  plugin's `SelectionManager.lua`): they must call `LrTasks.startAsyncTask(...)` at load time
  themselves — they do **NOT** `return function() ... end`.
- Catalog writes inside `catalog:withWriteAccessDo(..., function() ... end)`.

## Language Rules

- **Code, comments, commit messages: English.**
- **UI strings: German.**

## Build-Agent Rule (STRICT — Orchestration only)

The build/verify flow is defined centrally in the skill `build-verify` (repo `agents-skills`, core
rule `.agents/rules/build-verify.md`): pull first, orchestration only, independent verifier, commit
after *every* verify round regardless of verdict, amend on redo, push + CI watch. It applies here
unchanged — this file only defines *what* must be green in this repo, which is the "Definition of
Done / Verification" section below.

## Definition of Done / Verification

- The only automatable check is a **Lua syntax check** (e.g. `luac -p`); functional verification
  requires Lightroom Classic.
- Functional checks (actual rename, sidecar handling, stack grouping, undo) MUST be done manually in
  Lightroom Classic and listed as a manual checklist in `AGENTS.todo.md`.
- **After any file change inside the `.lrplugin` folder** (delete / restore / rename, or a new script
  referenced from `Info.lua`): **quit and restart Lightroom Classic completely** (closing the window
  is not enough). If that does not help: File → Plug-in Manager → remove and re-add the plugin.
- One `withWriteAccessDo` block per run → single Undo step.

## Naming Pattern Spec

Token-based pattern string (editable in the dialog), default `{date}_{custom}_{seq}`:

- `{date}` / `{date:<fmt>}` — capture date via `LrDate.timeToUserFormat(time, fmt)`. Default
  `fmt = "DD"` (switchable to `YY`, `YYYYMMDD`, …).
- `{custom}` — free text from the dialog, same for all stacks.
- `{seq}` — per-stack sequence number, zero-padded to a configurable width (default 2), start value
  configurable (default 1).

The **extension is preserved automatically per file** (Lightroom appends it on rename); it is NOT
part of the pattern.

## CodeGraph

- If `.codegraph/` exists, use CodeGraph (MCP `codegraph_explore`, CLI `codegraph explore`) — it
  replaces grep+Read loops.
- Without `.codegraph/`, use the built-in tools; never run `codegraph init` yourself.
- Commits run `.githooks/pre-commit` (`codegraph sync -q`, fails open, never blocking); activate it
  once per clone with `git config core.hooksPath .githooks`.

## Rules only, no decisions

This file contains **rules only** — instructions that apply to any work in this repo. Durable
decisions, rationale, measurements and history do not belong here but in `docs/`/`features/` or the
project docs; open points go to `AGENTS.todo.md`; finished work lives in the git history.

## Gates

Regeln dieser Ebene. Was nur ein Verzeichnis betrifft, gehört in die
`AGENTS.md` **dieses** Verzeichnisses — sie wird geladen, wenn eine Datei
daraus gelesen wird.

Ein Plan in `docs/plans/` beginnt mit `**Status:** Plan | In Arbeit | Done |
Empfehlung, nicht implementiert`.

Die kanonischen Agent-Regeln laufen über `ratchet` (Preset `agent-rules`):
`ratchet check` vor jedem Commit und in der CI.
