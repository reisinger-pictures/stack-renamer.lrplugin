# AGENTS.todo.md — stack-renamer.lrplugin

Actionable tasks for the Stack Renamer Lightroom plugin. Build Agent owns this file; only items
confirmed by an independent verifier subagent are removed. Source plan:
`/Users/florianreisinger/.opencode/plan/stack-renamer-plugin.md`.

## Status
- Implementation (Info / Utils / RenameCore / RenameDialog / RenameStacks + syntax): **verified
  DONE** by an independent subagent. Two small Build-Agent fixes applied and syntax-checked (see
  "Build-Agent small fixes" below).
- Functional verification needs Lightroom Classic (not available here) — see Manual Verification.

## Implemented & verified (pruned from active TODOs)
- [x] `Info.lua` — manifest + `LrLibraryMenuItems` ("Stacks konsistent umbenennen..." → `RenameStacks.lua`)
- [x] `Utils.lua` — tokens `{date}`/`{date:<fmt>}`/`{custom}`/`{seq}`/`{orig}`; `LrDate` default `DD`;
  `seq` padding default 2; `stackKey` (`stackUuid` + per-photo fallback); `findCollisions` (case-insensitive)
- [x] `RenameCore.lua` — `getTargetPhotos`; group (unstacked = size 1); skip VCs; sort by
  `dateTimeOriginal` then filename; one `withWriteAccessDo`; `renamePhotoFile(photo, base, true, nil)`;
  `pcall` per rename; progress scope
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
- [ ] Confirm `LrCatalog:renamePhotoFile` keeps the extension + XMP sidecar on the target LR build;
  if not, implement the documented fallback `setRawMetadata("fileName", base)` + manual sidecar
  handling. (Fallback currently only documented, not implemented.)
- [ ] (Optional enhancement) Detect collisions against files already on disk **outside** the
  selection, and avoid false-positive collisions across *different folders*. Currently only
  in-selection (inter-target) collisions are checked.

## Manual Verification (Lightroom Classic required; NOT possible in this env)
- [ ] 3-format stack (CR3+DNG+JPEG) → all three share the base name, only the extension differs.
- [ ] Single unstacked photo → renamed correctly (size-1 stack).
- [ ] Collision detection blocks "Anwenden".
- [ ] Undo reverts the whole operation in one step (single `withWriteAccessDo`).
- [ ] `renamePhotoFile` preserves extension + XMP sidecar (apply fallback above if not).

## Open Points
- Date tag `DD` (day) vs `YY` (year) — both yield "25"; default `DD`, user can change in dialog.
- Extension preserved in original case (`.CR3`, not lowercased to `.cr3`).
- Two-step dialog was collapsed into one combined modal dialog (functionally equivalent).
