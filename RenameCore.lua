-- stack-renamer.lrplugin/RenameCore.lua
-- Core logic for the Stack Renamer plugin.
--
-- Reads the current selection, groups photos into stacks (unstacked photos
-- become size-1 stacks), builds a preview via RenameDialog, and performs the
-- rename inside a single catalog write block (one Undo step). Virtual copies
-- are skipped, because they share the master file and follow it on rename.
local LrApplication = import 'LrApplication'
local LrDialogs = import 'LrDialogs'
local LrProgressScope = import 'LrProgressScope'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'

local Utils = require "Utils"
local RenameDialog = require "RenameDialog"

local RenameCore = {}

--------------------------------------------------------------------------------
-- Phase wrapper: run one stage of run() in its own LrTasks.pcall (the only
-- protected-call form that allows the SDK calls to yield) and, on failure,
-- rethrow with the stage name attached to the message.
--------------------------------------------------------------------------------
local function phaseOk(context, fn)
    local ok, res = LrTasks.pcall(fn)
    if not ok then
        error(context .. " -> " .. tostring(res))
    end
    return res
end

--------------------------------------------------------------------------------
-- Group the target photos into stacks.
--------------------------------------------------------------------------------
local function buildGroups(photos)
    local groupsByKey = {}
    local order = {}
    for _, photo in ipairs(photos) do
        local key = Utils.stackKey(photo)
        local g = groupsByKey[key]
        if not g then
            g = {
                key = key,
                photos = {},
                seen = {},              -- dedup set (LrPhoto objects as keys)
                representativeTime = nil,   -- dateTimeOriginal of the rep. member
                representativeName = nil,   -- current base name of the rep. member
                hasReal = false,            -- has at least one non-virtual-copy file
            }
            groupsByKey[key] = g
            table.insert(order, g)
        end
        -- Expand the stack to ALL its members, not just the selected photos:
        -- stack-consistent renaming must touch every file in a stack. The
        -- selected photo itself is always included (some LR builds report the
        -- member list without the photo itself).
        local members = { photo }
        if photo:getRawMetadata("isInStackInFolder") then
            local ms = photo:getRawMetadata("stackInFolderMembers")
            if ms then
                for _, m in ipairs(ms) do table.insert(members, m) end
            end
        end
        for _, m in ipairs(members) do
            if not g.seen[m] then
                g.seen[m] = true
                table.insert(g.photos, m)
                if m:getRawMetadata("isVirtualCopy") ~= true then
                    g.hasReal = true
                    if not g.representativeTime then
                        g.representativeTime = m:getRawMetadata("dateTimeOriginal")
                        g.representativeName = LrPathUtils.removeExtension(
                            m:getFormattedMetadata("fileName") or "")
                    end
                end
            end
        end
    end
    -- Keep only groups that actually own a real (renameable) file. A group of
    -- virtual copies only (master not in selection) would consume a sequence
    -- number for nothing, and its master is renamed separately anyway.
    local real = {}
    for _, g in ipairs(order) do
        if g.hasReal then table.insert(real, g) end
    end
    return real
end

--------------------------------------------------------------------------------
-- Prepare the rename: Lightroom's SDK cannot rename photo files itself (no
-- file-rename API exists on LrCatalog/LrPhoto). The plugin therefore writes
-- the planned base name into the "Headline" metadata field; the user then runs
-- Lightroom's built-in "Fotos umbenennen" (F2) with a template that inserts
-- Headline, which renames file + XMP sidecars and keeps the catalog consistent.
--------------------------------------------------------------------------------
local function performRename(catalog, plan, metaField)
    metaField = metaField or "instructions"
    -- German display name of the field, used in the follow-up instruction.
    local fieldLabel = (metaField == "headline") and "Überschrift (Headline)" or "Anweisungen (Instructions)"
    local summary = nil
    -- Single write block => a single Undo step for the whole operation.
    catalog:withWriteAccessDo("RenameStacks", function()
        local progress = LrProgressScope { title = "Bereite Stacks für Umbenennung vor..." }
        progress:setCancelable(true)

        -- Count real (non-virtual-copy) files for the progress bar.
        local total = 0
        for _, entry in ipairs(plan) do
            local members = entry.members or entry.group.photos
            for _, photo in ipairs(members) do
                if photo:getRawMetadata("isVirtualCopy") ~= true then
                    total = total + 1
                end
            end
        end

        local errors = {}
        local prepared = 0
        local done = 0

        for _, entry in ipairs(plan) do
            local base = entry.base
            local members = entry.members or entry.group.photos
            for _, photo in ipairs(members) do
                if photo:getRawMetadata("isVirtualCopy") ~= true then
                    done = done + 1
                    local fileName = photo:getFormattedMetadata("fileName") or "?"
                    if base ~= "" then
                        progress:setCaption("Schreibe Namen: " .. fileName)
                        local ok, err = LrTasks.pcall(function()
                            photo:setRawMetadata(metaField, base)
                        end)
                        if ok then
                            prepared = prepared + 1
                        else
                            table.insert(errors, fileName .. ": " .. tostring(err))
                        end
                    end
                    progress:setPortionComplete(done, total)
                    if progress:isCanceled() then break end
                end
            end
            if progress:isCanceled() then break end
        end
        progress:done()

        -- Build the summary inside the block, but SHOW it only after the block
        -- closes: modal dialogs inside a write block can deadlock on some LR
        -- builds (LUA SDK guidance).
        if #errors > 0 then
            summary = {
                title = "Vorbereiten mit Fehlern",
                msg = #errors .. " Datei(en) konnten nicht vorbereitet werden:\n\n"
                    .. table.concat(errors, "\n"),
                kind = "critical",
            }
        elseif prepared > 0 then
            summary = {
                title = "Namen vorbereitet",
                msg = prepared .. " Datei(en) haben den neuen Basisnamen im Feld '"
                    .. fieldLabel .. "' erhalten.\n\n"
                    .. "Jetzt in Lightroom: Fotos ausgewählt lassen und F2 drücken "
                    .. "(Fotos → Fotos umbenennen…). In der File-Naming-Vorlage den "
                    .. "IPTC-Wert '" .. fieldLabel .. "' einfügen und bestätigen. "
                    .. "Lightroom benennt die Dateien dann inkl. Endungen und "
                    .. "Sidecars korrekt um.",
                kind = "info",
            }
        end
    end)

    if summary then
        LrDialogs.message(summary.title, summary.msg, summary.kind)
    end
end

--------------------------------------------------------------------------------
-- Entry point invoked by RenameStacks.lua (inside an async task).
--------------------------------------------------------------------------------
function RenameCore.run()
    local catalog = LrApplication.activeCatalog()

    local photos = phaseOk("getTargetPhotos", function()
        return catalog:getTargetPhotos()
    end)
    if #photos == 0 then
        LrDialogs.message("Keine Fotos ausgewählt",
            "Bitte wähle Fotos oder einen Ordner im Filmstreifen bzw. Folders-Panel aus, "
            .. "bevor du dieses Plug-in startest.", "warning")
        return
    end

    local groups = phaseOk("buildGroups", function()
        return buildGroups(photos)
    end)
    if #groups == 0 then
        LrDialogs.message("Keine umbenennbaren Fotos",
            "Die Auswahl enthält nur virtuelle Kopien oder keine umbenennbaren Dateien.", "warning")
        return
    end

    local dialogResult = phaseOk("RenameDialog", function()
        return RenameDialog(groups)
    end)
    if not dialogResult or dialogResult.canceled then
        return
    end

    phaseOk("performRename", function()
        performRename(catalog, dialogResult.plan, dialogResult.metaField)
    end)
end

return RenameCore
