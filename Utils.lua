-- stack-renamer.lrplugin/Utils.lua
-- Shared helpers for the Stack Renamer plugin.
--
-- Module returns a table of pure helper functions:
--   * parsePattern / resolvePattern  - token-based naming pattern
--   * formatSeq / formatDate         - sequence padding and date formatting
--   * stackKey                       - grouping key per stack (unstacked = size-1 stack)
--   * findCollisions                 - case-insensitive duplicate detection
local LrDate = import 'LrDate'

local Utils = {}

--------------------------------------------------------------------------------
-- Pattern parsing
--------------------------------------------------------------------------------

-- Parse a pattern string into a list of tokens.
-- Supported tokens (case-insensitive):
--   {date}        capture date, format from the dialog's date-format setting
--   {date:<fmt>}  capture date with an explicit LrDate format string
--   {custom}      free-text from the dialog
--   {seq}         per-stack sequence number (padding/start from the dialog)
--   {orig}        the photo's current base name
-- Everything else (including unknown {...} brackets) is treated as literal text.
function Utils.parsePattern(pattern)
    pattern = pattern or ""
    local tokens = {}
    local i = 1
    local n = #pattern
    while i <= n do
        local open = string.find(pattern, "{", i, true)
        if not open then
            if i <= n then
                table.insert(tokens, { kind = "text", value = string.sub(pattern, i) })
            end
            break
        end
        if open > i then
            table.insert(tokens, { kind = "text", value = string.sub(pattern, i, open - 1) })
        end
        local close = string.find(pattern, "}", open + 1, true)
        if not close then
            table.insert(tokens, { kind = "text", value = string.sub(pattern, open) })
            break
        end
        local inner = string.sub(pattern, open + 1, close - 1)
        local name, arg = string.match(inner, "^([^:]+):(.+)$")
        if not name then name = inner; arg = nil end
        name = string.lower(name or "")
        if name == "date" or name == "custom" or name == "seq" or name == "orig" then
            table.insert(tokens, { kind = "token", name = name, arg = arg })
        else
            -- Unknown token: keep it verbatim so the user sees what they typed.
            table.insert(tokens, { kind = "text", value = "{" .. inner .. "}" })
        end
        i = close + 1
    end
    return tokens
end

-- Resolve a pattern into a concrete base name for one stack.
-- ctx fields: time (number|nil), custom (string), dateFmt (string),
--             seq (number), seqWidth (number), orig (string).
function Utils.resolvePattern(pattern, ctx)
    local tokens = Utils.parsePattern(pattern)
    local parts = {}
    for _, t in ipairs(tokens) do
        if t.kind == "text" then
            table.insert(parts, t.value)
        elseif t.name == "date" then
            local fmt = (t.arg and t.arg ~= "") and t.arg or (ctx.dateFmt or "DD")
            table.insert(parts, Utils.formatDate(ctx.time, fmt))
        elseif t.name == "custom" then
            table.insert(parts, ctx.custom or "")
        elseif t.name == "seq" then
            table.insert(parts, Utils.formatSeq(ctx.seq, ctx.seqWidth))
        elseif t.name == "orig" then
            table.insert(parts, ctx.orig or "")
        end
    end
    return table.concat(parts)
end

--------------------------------------------------------------------------------
-- Formatting helpers
--------------------------------------------------------------------------------

-- Zero-pad a sequence number to the requested width (default 2 -> "02").
function Utils.formatSeq(seq, width)
    width = width or 2
    local s = tostring(seq)
    if width > 0 then
        while #s < width do s = "0" .. s end
    end
    return s
end

-- Format a time value with LrDate.timeToUserFormat, defaulting to "DD" (day)
-- -> "25". Friendly tokens (DD, YY, YYYYMMDD, …) are translated to the
-- %-style formats LrDate understands; formats already containing '%' are
-- passed through unchanged (native LrDate format). Returns "" when the time
-- is missing (falls back to the current time, so the name never stays empty).
local FRIENDLY_TO_NATIVE = {
    { "YYYY", "%Y" },   -- must run before "YY"
    { "YY",   "%y" },
    { "MM",   "%m" },
    { "DD",   "%d" },
    { "HH",   "%H" },
    { "mm",   "%M" },
    { "ss",   "%S" },
}

function Utils.formatDate(time, fmt)
    fmt = fmt or "DD"
    if not time then
        time = LrDate.currentTime() -- capture date missing -> today
    end
    if not string.find(fmt, "%%", 1, true) then
        for _, pair in ipairs(FRIENDLY_TO_NATIVE) do
            -- function replacement avoids '%' being parsed as a capture.
            fmt = string.gsub(fmt, pair[1], function() return pair[2] end)
        end
    end
    local ok, res = pcall(function() return LrDate.timeToUserFormat(time, fmt) end)
    if ok and res then return res end
    return ""
end

--------------------------------------------------------------------------------
-- Stack grouping
--------------------------------------------------------------------------------

-- Return a stable grouping key for a photo.
-- Stacked photos are grouped via their stack's top photo: every member reports
-- the same `topOfStackInFolderContainingPhoto`, whose `uuid` forms the key.
-- Unstacked photos get a unique key (their path), so each becomes its own
-- size-1 "stack". Virtual copies share the master's stack via the same top.
function Utils.stackKey(photo)
    local isInStack = photo:getRawMetadata("isInStackInFolder")
    if isInStack then
        local top = photo:getRawMetadata("topOfStackInFolderContainingPhoto")
        local topUuid = top and top:getRawMetadata("uuid")
        if topUuid then
            return "S:" .. tostring(topUuid)
        end
        -- Fallback: derive a stable key from the (sorted) member UUIDs.
        local members = photo:getRawMetadata("stackInFolderMembers") or {}
        local ids = {}
        for _, m in ipairs(members) do
            local u = m:getRawMetadata("uuid")
            if u then table.insert(ids, tostring(u)) end
        end
        table.sort(ids)
        return "S:" .. table.concat(ids, "|")
    end
    local path = photo:getRawMetadata("path")
    if path and path ~= "" then
        return "U:" .. path
    end
    return "U:" .. tostring(photo:getRawMetadata("uuid") or tostring(photo))
end

--------------------------------------------------------------------------------
-- Collision detection
--------------------------------------------------------------------------------

-- Given an array of resolved base names, return the list of names that collide
-- (case-insensitive, as macOS filesystems are case-insensitive by default).
function Utils.findCollisions(names)
    local seen = {}      -- lowercased name -> canonical (first-seen) spelling
    local dupes = {}
    for _, name in ipairs(names) do
        if name and name ~= "" then
            local key = string.lower(name)
            if seen[key] then
                dupes[seen[key]] = true  -- report the first-seen spelling
            else
                seen[key] = name
            end
        end
    end
    local list = {}
    for k in pairs(dupes) do table.insert(list, k) end
    return list
end

--------------------------------------------------------------------------------
-- Duplicate-extension numbering + folder-scoped collisions
--------------------------------------------------------------------------------

-- Return the file extension including the leading dot, preserving the original
-- case (".CR3", ".JPG"). Returns "" when the name has no extension.
function Utils.extensionWithDot(fileName)
    if not fileName then return "" end
    local ext = string.match(fileName, "%.([^.]*)$")
    if not ext or ext == "" then return "" end
    return "." .. ext
end

-- Assign per-photo final base names for one stack.
-- The 1st file of each extension keeps `base`, the 2nd gets `base-2`, the 3rd
-- `base-3`, and so on. Extension comparison is case-insensitive (lowercased
-- key); the returned bases keep `base` untouched. `extList` holds extension
-- strings (with or without leading dot, any case) in deterministic in-stack
-- order. Returns an array of final bases aligned with `extList`.
function Utils.assignNumberedBases(base, extList)
    local counts = {}
    local out = {}
    for i, ext in ipairs(extList or {}) do
        local key = string.lower(ext or "")
        key = string.gsub(key, "^%.", "")
        counts[key] = (counts[key] or 0) + 1
        local n = counts[key]
        if n == 1 then
            out[i] = base
        else
            out[i] = base .. "-" .. tostring(n)
        end
    end
    return out
end

-- Folder-scoped intra-plan collision detection (case-insensitive).
-- `targets` is an array of { folder = string, name = string } holding final
-- file names (e.g. "25_Island_02.JPG"). Two targets collide only when they
-- share the same folder (case-insensitive path) AND the same file name
-- (case-insensitive). Same names in different folders are NOT collisions.
-- Returns an array of { folder, name } with the first-seen spelling,
-- sorted by folder then name (case-insensitive).
function Utils.findIntraPlanCollisions(targets)
    local seen = {}        -- folderKey .. NUL .. lowerName -> { folder, name }
    local displayByFolder = {} -- folderKey -> first-seen display folder
    local dupKeys = {}
    for _, t in ipairs(targets or {}) do
        local folder = t.folder or ""
        local name = t.name or ""
        if name ~= "" then
            local fkey = string.lower(folder)
            if not displayByFolder[fkey] then displayByFolder[fkey] = folder end
            local key = fkey .. "\0" .. string.lower(name)
            if seen[key] then
                dupKeys[key] = true
            else
                seen[key] = { folder = displayByFolder[fkey], name = name }
            end
        end
    end
    local out = {}
    for key in pairs(dupKeys) do table.insert(out, seen[key]) end
    table.sort(out, function(a, b)
        local fa, fb = string.lower(a.folder or ""), string.lower(b.folder or "")
        if fa ~= fb then return fa < fb end
        return string.lower(a.name or "") < string.lower(b.name or "")
    end)
    return out
end

-- Folder-vs-disk collision detection (case-insensitive, folder-scoped).
-- `planned` is an array of { folder, name } with final target names.
-- `existingByFolder` maps (lowercased) folder path -> array of leaf file names
-- currently on disk. `sourcesByFolder` maps (lowercased) folder path -> set of
-- lowercased source file names that are part of the rename plan (they move
-- away, so they never count as collisions).
-- Returns an array of { folder, name } with the first-seen planned spelling,
-- sorted by folder then name (case-insensitive).
function Utils.findFolderCollisions(planned, existingByFolder, sourcesByFolder)
    local existingSets = {} -- lowerFolder -> { [lowerName] = true }
    for fkey, files in pairs(existingByFolder or {}) do
        local lk = string.lower(fkey or "")
        local set = {}
        if type(files) == "table" then
            for _, fn in ipairs(files) do
                if type(fn) == "string" and fn ~= "" then
                    set[string.lower(fn)] = true
                end
            end
            -- Also accept set-shaped tables { ["Name.ext"] = true }.
            for k, v in pairs(files) do
                if type(k) == "string" and v == true then
                    set[string.lower(k)] = true
                end
            end
        end
        existingSets[lk] = set
    end
    local sourceSets = {} -- lowerFolder -> { [lowerName] = true }
    for fkey, set in pairs(sourcesByFolder or {}) do
        local lk = string.lower(fkey or "")
        local norm = {}
        if type(set) == "table" then
            for k, v in pairs(set) do
                if type(k) == "string" then
                    norm[string.lower(k)] = true
                elseif type(v) == "string" then
                    norm[string.lower(v)] = true
                end
            end
        end
        sourceSets[lk] = norm
    end
    local reported = {} -- dedupKey -> { folder, name }
    for _, t in ipairs(planned or {}) do
        local folder = t.folder or ""
        local name = t.name or ""
        if name ~= "" then
            local fkey = string.lower(folder)
            local nkey = string.lower(name)
            local srcSet = sourceSets[fkey]
            if not (srcSet and srcSet[nkey]) then
                local exSet = existingSets[fkey]
                if exSet and exSet[nkey] then
                    local dkey = fkey .. "\0" .. nkey
                    if not reported[dkey] then
                        reported[dkey] = { folder = folder, name = name }
                    end
                end
            end
        end
    end
    local out = {}
    for _, v in pairs(reported) do table.insert(out, v) end
    table.sort(out, function(a, b)
        local fa, fb = string.lower(a.folder or ""), string.lower(b.folder or "")
        if fa ~= fb then return fa < fb end
        return string.lower(a.name or "") < string.lower(b.name or "")
    end)
    return out
end

-- True if a file name has a JPEG/JPG extension (case-insensitive).
function Utils.isJpegFileName(name)
    if not name then return false end
    local ext = name:match("%.([^.]+)$")
    if not ext then return false end
    ext = string.lower(ext)
    return ext == "jpg" or ext == "jpeg"
end

return Utils
