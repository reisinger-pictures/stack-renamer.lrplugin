-- stack-renamer.lrplugin/RenameDialog.lua
-- Settings + live preview/confirm dialog (UI strings in German).
--
-- Shows editable settings (custom text, date format, start number, padding,
-- pattern, sort order) plus a live "old -> new" preview. The "Anwenden" button
-- is disabled (via actionBinding) whenever a name collision is detected or the
-- pattern resolves to an empty name. Returns { plan = <plan>, canceled = false }
-- on confirm, or nil when the user cancels.
local LrView = import 'LrView'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrPathUtils = import 'LrPathUtils'
local LrFileUtils = import 'LrFileUtils'
local LrBinding = import 'LrBinding'
local LrColor = import 'LrColor'
local LrPrefs = import 'LrPrefs'

local Utils = require "Utils"

-- Maximum number of stacks listed individually before summarizing.
local PREVIEW_LIMIT = 50

return function(groups)
    local result = nil

    LrFunctionContext.callWithContext("StackRenamerDialog", function(context)
        local f = LrView.osFactory()
        local props = LrBinding.makePropertyTable(context)
        local prefs = LrPrefs.prefsForPlugin()

        -- Default settings (UI is German). Values persist via LrPrefs so the
        -- last-used values come back the next time the dialog opens.
        props.custom = prefs.custom or "Island"
        props.dateFmt = prefs.dateFmt or "DD"
        props.start = prefs.start or 1
        props.padding = prefs.padding or 2
        props.pattern = prefs.pattern or "{date}_{custom}_{seq}"
        props.sortOrder = prefs.sortOrder or "capture" -- "selection" | "capture" | "filename"
        props.metaField = prefs.metaField or "instructions" -- "instructions" | "headline"

        local metaFieldItems = {
            { title = "Instructions (Anweisungen)", value = "instructions" },
            { title = "Headline (Überschrift)",      value = "headline" },
        }

        -- Computed preview state.
        props.preview = ""
        props.collisionNote = ""
        props.canApply = false

        local sortItems = {
            { title = "Aktuelle Reihenfolge", value = "selection" },
            { title = "Aufnahmezeit", value = "capture" },
            { title = "Dateiname",    value = "filename" },
        }

        -- Pre-fetch per-photo info ONCE (yielding SDK calls must not run inside
        -- the property observers that drive the live preview below). This cache
        -- is plain Lua data, so recompute() stays yield-free in every context.
        -- Besides the display name it holds the containing folder and the
        -- extension (case preserved, with dot) used for per-photo numbering
        -- and folder-scoped collision checks.
        local photoInfo = {}
        for _, g in ipairs(groups) do
            for _, photo in ipairs(g.photos) do
                local fn = photo:getFormattedMetadata("fileName") or "?"
                local path = photo:getRawMetadata("path") or ""
                local folder = ""
                if path ~= "" then
                    local ok, parent = pcall(function() return LrPathUtils.parent(path) end)
                    if ok and parent then folder = parent end
                end
                local rawExt = LrPathUtils.extension(fn) or ""
                local extWithDot = rawExt
                if extWithDot ~= "" and string.sub(extWithDot, 1, 1) ~= "." then
                    extWithDot = "." .. extWithDot
                end
                photoInfo[photo] = {
                    isVC = (photo:getRawMetadata("isVirtualCopy") == true),
                    name = fn,
                    folder = folder,
                    ext = extWithDot,
                    extKey = string.lower(extWithDot or ""),
                }
            end
        end

        -- Pre-fetch the on-disk file listing ONCE per involved folder (yielding
        -- file-system access must not run inside property observers either).
        -- Keys are lowercased folder paths (folder-scoped, case-insensitive);
        -- values are arrays of leaf file names. Failures fall back to an empty
        -- list so the dialog still works without the folder check.
        local function listFilesInFolder(dir)
            if not dir or dir == "" then return {} end
            if LrFileUtils and type(LrFileUtils.files) == "function" then
                local ok, res = pcall(function() return LrFileUtils.files(dir) end)
                if ok and res then
                    if type(res) == "table" then
                        local out = {}
                        for _, p in ipairs(res) do
                            local leafOk, leaf = pcall(function() return LrPathUtils.leafName(p) end)
                            if leafOk and leaf then table.insert(out, leaf)
                            else table.insert(out, tostring(p)) end
                        end
                        return out
                    elseif type(res) == "function" then
                        local out = {}
                        for p in res do
                            local leafOk, leaf = pcall(function() return LrPathUtils.leafName(p) end)
                            if leafOk and leaf then table.insert(out, leaf)
                            else table.insert(out, tostring(p)) end
                        end
                        return out
                    end
                end
            end
            if LrFileUtils and type(LrFileUtils.directoryContents) == "function" then
                local ok, files = pcall(function() return LrFileUtils.directoryContents(dir) end)
                if ok and type(files) == "table" then
                    local out = {}
                    for _, p in ipairs(files) do
                        local leafOk, leaf = pcall(function() return LrPathUtils.leafName(p) end)
                        if leafOk and leaf then table.insert(out, leaf)
                        else table.insert(out, tostring(p)) end
                    end
                    return out
                end
            end
            return {}
        end

        local distinctFolders = {} -- lowerFolder -> display folder
        for _, pi in pairs(photoInfo) do
            if not pi.isVC and pi.folder and pi.folder ~= "" then
                local key = string.lower(pi.folder)
                if not distinctFolders[key] then distinctFolders[key] = pi.folder end
            end
        end
        local existingByFolder = {} -- lowerFolder -> array of leaf names
        for key, display in pairs(distinctFolders) do
            existingByFolder[key] = listFilesInFolder(display)
        end

        -- Members always keep the stack order delivered by buildGroups in
        -- RenameCore.lua (the SDK offers no API to reorder existing stacks).
        -- One preview line for a plan entry: "old1, old2 -> new1 / new2".
        -- Uses the per-photo final base (duplicate-extension numbering), so
        -- the preview shows exactly what performRename will write.
        local function previewLine(entry)
            local olds = {}
            local news = {}
            for _, photo in ipairs(entry.members or entry.group.photos) do
                local pi = photoInfo[photo]
                if pi and not pi.isVC then
                    local fn = pi.name
                    table.insert(olds, fn)
                    local finalBase = entry.base
                    if entry.perPhotoBases and entry.perPhotoBases[photo] then
                        finalBase = entry.perPhotoBases[photo]
                    end
                    table.insert(news, finalBase .. (pi.ext or ""))
                end
            end
            return table.concat(olds, ", ") .. "  →  " .. table.concat(news, " / ")
        end

        -- Compute the rename plan (sorted groups + per-photo base names) and the
        -- folder-scoped collision sets. Pure Lua over the photoInfo cache and
        -- the pre-fetched folder listing: no yielding SDK calls here, so this
        -- is safe inside property observers. Returns plan, intraCollisions,
        -- folderCollisions.
        local function buildPlan(grpList, settings)
            local sorted = {}
            for _, g in ipairs(grpList) do table.insert(sorted, g) end
            if settings.sortOrder ~= "selection" then
                table.sort(sorted, function(a, b)
                    if settings.sortOrder == "filename" then
                        return (a.representativeName or "") < (b.representativeName or "")
                    end
                    local ta = a.representativeTime or 0
                    local tb = b.representativeTime or 0
                    if ta ~= tb then return ta < tb end
                    return (a.representativeName or "") < (b.representativeName or "")
                end)
            end

            local plan = {}
            local targets = {} -- { folder, name } final file names for collision checks
            local seq = settings.start or 1
            for _, g in ipairs(sorted) do
                local ctx = {
                    time = g.representativeTime,
                    custom = settings.custom,
                    dateFmt = settings.dateFmt,
                    seq = seq,
                    seqWidth = settings.padding,
                    orig = g.representativeName,
                }
                local base = Utils.resolvePattern(settings.pattern, ctx)
                local members = g.photos
                -- Per-photo final bases: group real (non-VC) members by
                -- lowercased extension in deterministic in-stack order. The
                -- 1st file per extension keeps `base`, later ones get
                -- `base-2`, `base-3`, ... Extension case stays untouched.
                local perPhotoBases = {}
                local realOrdered = {}
                for _, photo in ipairs(members) do
                    local pi = photoInfo[photo]
                    if pi and not pi.isVC then
                        table.insert(realOrdered, photo)
                    end
                end
                local extList = {}
                for _, photo in ipairs(realOrdered) do
                    local pi = photoInfo[photo]
                    table.insert(extList, (pi and pi.extKey) or "")
                end
                local numbered = Utils.assignNumberedBases(base, extList)
                for idx, photo in ipairs(realOrdered) do
                    local finalBase = numbered[idx]
                    perPhotoBases[photo] = finalBase
                    local pi = photoInfo[photo]
                    local finalName = finalBase .. ((pi and pi.ext) or "")
                    table.insert(targets, { folder = (pi and pi.folder) or "", name = finalName })
                end
                table.insert(plan, { group = g, base = base, seq = seq, members = members, perPhotoBases = perPhotoBases })
                seq = seq + 1
            end

            -- Intra-plan duplicates: folder-scoped, on final file names
            -- (base + extension, case-insensitive), including same-extension
            -- duplicates inside one stack.
            local intra = Utils.findIntraPlanCollisions(targets)

            -- Folder-vs-disk: planned final names against files already in the
            -- same folder, excluding files that are part of the plan (they
            -- move away). Same names in different folders are NOT collisions.
            local sourcesByFolder = {} -- lowerFolder -> { [lowerName] = true }
            for _, pi in pairs(photoInfo) do
                if not pi.isVC and pi.folder and pi.folder ~= "" and pi.name then
                    local fkey = string.lower(pi.folder)
                    local set = sourcesByFolder[fkey]
                    if not set then set = {}; sourcesByFolder[fkey] = set end
                    set[string.lower(pi.name)] = true
                end
            end
            local folderColls = Utils.findFolderCollisions(targets, existingByFolder, sourcesByFolder)
            return plan, intra, folderColls
        end

        -- Recompute preview + enable/disable state whenever settings change.
        local latestPlan = nil
        local function recompute()
            local settings = {
                custom = props.custom or "",
                dateFmt = props.dateFmt or "DD",
                start = tonumber(props.start) or 1,
                padding = tonumber(props.padding) or 2,
                pattern = props.pattern or "{date}_{custom}_{seq}",
                sortOrder = props.sortOrder or "capture",
            }
            local plan, intra, folderColls = buildPlan(groups, settings)
            latestPlan = plan

            local lines = {}
            for idx, entry in ipairs(plan) do
                if idx <= PREVIEW_LIMIT then
                    table.insert(lines, previewLine(entry))
                end
            end
            local note = ""
            if #plan > PREVIEW_LIMIT then
                note = string.format("\n… und %d weitere Stacks.", #plan - PREVIEW_LIMIT)
            end
            props.preview = table.concat(lines, "\n") .. note

            local anyEmpty = false
            for _, e in ipairs(plan) do
                if e.base == "" then anyEmpty = true; break end
            end

            local notes = {}
            if #intra > 0 then
                local names = {}
                for _, c in ipairs(intra) do table.insert(names, c.name) end
                table.insert(notes, "Namens-Kollision: " .. table.concat(names, ", "))
            end
            if #folderColls > 0 then
                local parts = {}
                for _, c in ipairs(folderColls) do
                    table.insert(parts, "'" .. (c.folder or "") .. "': " .. (c.name or ""))
                end
                table.insert(notes, "Ordner-Kollision: " .. table.concat(parts, ", ")
                    .. " ist bereits vorhanden.")
            end
            if #notes > 0 then
                props.collisionNote = table.concat(notes, "\n")
                props.canApply = false
            elseif anyEmpty then
                props.collisionNote = "Das Namensmuster ergibt einen leeren Dateinamen."
                props.canApply = false
            elseif #plan == 0 then
                props.collisionNote = "Keine Stacks zum Umbenennen."
                props.canApply = false
            else
                props.collisionNote = ""
                props.canApply = true
            end
        end

        -- Initial compute + observers that keep the preview live.
        recompute()
        for _, key in ipairs({ "custom", "dateFmt", "start", "padding", "pattern", "sortOrder" }) do
            props:addObserver(key, function() recompute() end)
        end

        local helpText = "Platzhalter: {date} (Aufnahmedatum, Format siehe oben), "
            .. "{custom} (Freitext), {seq} (Laufnummer), {orig} (bisheriger Name). "
            .. "Die Dateiendung wird automatisch beibehalten."

        local contents = f:column {
            spacing = f:control_spacing(),
            width = 640,
            f:static_text { title = "Einstellungen", font = "<system/bold>" },
            f:row {
                f:static_text { title = "Freitext:", width = 120 },
                f:edit_field { value = LrView.bind { key = "custom", bind_to_object = props }, fill_horizontal = 1, width_in_chars = 30 }
            },
            f:row {
                f:static_text { title = "Datumsformat:", width = 120 },
                f:edit_field { value = LrView.bind { key = "dateFmt", bind_to_object = props }, fill_horizontal = 1, width_in_chars = 12, placeholder_string = "DD" },
                f:static_text { title = "(z. B. DD, YY, YYYYMMDD)", text_color = LrColor(0.5, 0.5, 0.5) }
            },
            f:row {
                f:static_text { title = "Startnummer:", width = 120 },
                f:edit_field { value = LrView.bind { key = "start", bind_to_object = props }, width_in_chars = 6 }
            },
            f:row {
                f:static_text { title = "Auffüllen (Padding):", width = 120 },
                f:edit_field { value = LrView.bind { key = "padding", bind_to_object = props }, width_in_chars = 6 }
            },
            f:row {
                f:static_text { title = "Namensmuster:", width = 120 },
                f:edit_field { value = LrView.bind { key = "pattern", bind_to_object = props }, fill_horizontal = 1, width_in_chars = 40 }
            },
            f:row {
                f:static_text { title = "Sortierung:", width = 120 },
                f:popup_menu { items = sortItems, value = LrView.bind { key = "sortOrder", bind_to_object = props }, fill_horizontal = 1 }
            },
            f:row {
                f:static_text { title = "Namens-Feld:", width = 120 },
                f:popup_menu { items = metaFieldItems, value = LrView.bind { key = "metaField", bind_to_object = props }, fill_horizontal = 1 },
                f:static_text { title = "(in der F2-Vorlage verwendetes IPTC-Feld)", text_color = LrColor(0.5, 0.5, 0.5) }
            },
            f:row {
                f:spacer { width = 120 },
                f:static_text { title = helpText, width_in_chars = 70, text_color = LrColor(0.5, 0.5, 0.5) }
            },
            f:spacer { height = 10 },
            f:separator { fill_horizontal = 1 },
            f:spacer { height = 5 },
            f:static_text { title = "Vorschau (alt → neu)", font = "<system/bold>" },
            f:scrolled_view {
                fill_horizontal = 1,
                height = 220,
                vertical_scrollbar = true,
                horizontal_scrollbar = false,
                f:static_text {
                    title = LrView.bind { key = "preview", bind_to_object = props },
                    fill_horizontal = 1,
                    width_in_chars = 80,
                },
            },
            f:static_text {
                title = LrView.bind { key = "collisionNote", bind_to_object = props },
                text_color = LrColor(0.8, 0, 0),
            },
        }

        local res = LrDialogs.presentModalDialog {
            title = "Stacks konsistent umbenennen",
            contents = contents,
            actionVerb = "Anwenden",
            cancelVerb = "Abbrechen",
            -- Disable "Anwenden" when a collision or empty name is detected.
            actionBinding = { enabled = LrView.bind { key = "canApply", bind_to_object = props } },
            resizable = "vertically",
        }

        -- Persist all settings for the next run (also on cancel, so the dialog
        -- opens with the last-used values).
        prefs.custom = props.custom or ""
        prefs.dateFmt = props.dateFmt or "DD"
        prefs.start = tonumber(props.start) or 1
        prefs.padding = tonumber(props.padding) or 2
        prefs.pattern = props.pattern or "{date}_{custom}_{seq}"
        prefs.sortOrder = props.sortOrder or "capture"
        prefs.metaField = props.metaField or "instructions"

        if res == "ok" and props.canApply then
            result = { plan = latestPlan, canceled = false, metaField = props.metaField or "instructions" }
        end
    end)

    return result
end
