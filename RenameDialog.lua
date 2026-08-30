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
        props.inStackOrder = (prefs.inStackOrder ~= false) -- convenience option, default ON
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
        local photoInfo = {}
        for _, g in ipairs(groups) do
            for _, photo in ipairs(g.photos) do
                photoInfo[photo] = {
                    isVC = (photo:getRawMetadata("isVirtualCopy") == true),
                    name = photo:getFormattedMetadata("fileName") or "?",
                }
            end
        end

        -- Within a stack: move a DNG to position 1 and the first non-raw file
        -- (JPEG/HEIC/PNG/…, JPG=JPEG) to position 2 while every other member
        -- keeps its original relative order. Examples:
        --   CR3, DNG, JPEG -> DNG, JPEG, CR3
        --   CR3, DNG       -> DNG, CR3
        --   CR3, JPEG      -> CR3, JPEG  (unchanged)
        -- Pure Lua (uses the photoInfo cache), safe inside observers.
        local function moveTo(list, item, toIdx)
            for i, p in ipairs(list) do
                if p == item then
                    table.remove(list, i)
                    if toIdx > #list then toIdx = #list + 1 end
                    table.insert(list, toIdx, item)
                    return list
                end
            end
            return list
        end

        local function orderInStack(photos)
            local dng, nonRaw = nil, nil
            for _, p in ipairs(photos) do
                local pi = photoInfo[p]
                local name = pi and pi.name or ""
                if not dng and Utils.isDngFileName(name) then dng = p end
                if not nonRaw and Utils.isNonRawFileName(name) then nonRaw = p end
            end
            local res = {}
            for _, p in ipairs(photos) do table.insert(res, p) end
            if dng then res = moveTo(res, dng, 1) end
            if nonRaw then res = moveTo(res, nonRaw, 2) end
            return res
        end

        -- One preview line for a plan entry: "old1, old2 -> new1 / new2".
        local function previewLine(entry)
            local olds = {}
            local news = {}
            for _, photo in ipairs(entry.members or entry.group.photos) do
                local pi = photoInfo[photo]
                if pi and not pi.isVC then
                    local fn = pi.name
                    table.insert(olds, fn)
                    local ext = LrPathUtils.extension(fn)
                    if ext ~= "" and string.sub(ext, 1, 1) ~= "." then
                        ext = "." .. ext
                    end
                    table.insert(news, entry.base .. ext)
                end
            end
            return table.concat(olds, ", ") .. "  →  " .. table.concat(news, " / ")
        end

        -- Compute the rename plan (sorted groups + resolved base names) and the
        -- set of colliding base names.
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
            local bases = {}
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
                if settings.inStackOrder then
                    members = orderInStack(g.photos)
                end
                table.insert(plan, { group = g, base = base, seq = seq, members = members })
                table.insert(bases, base)
                seq = seq + 1
            end

            -- Case-insensitive collision detection (delegated to Utils; see
            -- Utils.findCollisions for the first-seen spelling rule).
            local collisions = Utils.findCollisions(bases)
            table.sort(collisions)
            return plan, collisions
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
                inStackOrder = (props.inStackOrder ~= false),
            }
            local plan, collisions = buildPlan(groups, settings)
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

            if #collisions > 0 then
                props.collisionNote = "Namens-Kollision: " .. table.concat(collisions, ", ")
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
        for _, key in ipairs({ "custom", "dateFmt", "start", "padding", "pattern", "sortOrder", "inStackOrder" }) do
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
                f:static_text { title = "In-Stack-Ordnung:", width = 120 },
                f:checkbox {
                    title = "DNG zuerst, Non-Raw (JPEG/HEIC/…) auf Position 2",
                    value = LrView.bind { key = "inStackOrder", bind_to_object = props },
                },
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
            f:edit_field {
                value = LrView.bind { key = "preview", bind_to_object = props },
                height_in_lines = 15,
                width_in_chars = 80,
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
        prefs.inStackOrder = (props.inStackOrder ~= false)
        prefs.metaField = props.metaField or "instructions"

        if res == "ok" and props.canApply then
            result = { plan = latestPlan, canceled = false, metaField = props.metaField or "instructions" }
        end
    end)

    return result
end
