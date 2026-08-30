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

-- True if a file name has a JPEG/JPG extension (case-insensitive).
function Utils.isJpegFileName(name)
    if not name then return false end
    local ext = name:match("%.([^.]+)$")
    if not ext then return false end
    ext = string.lower(ext)
    return ext == "jpg" or ext == "jpeg"
end

-- True if a file name has a DNG extension (case-insensitive).
function Utils.isDngFileName(name)
    if not name then return false end
    local ext = name:match("%.([^.]+)$")
    if not ext then return false end
    return string.lower(ext) == "dng"
end

-- True if a file name refers to a non-raw, renderable image format
-- (JPEG/JPG, HEIC/HEIF, PNG, GIF, BMP, WEBP, PSD, PSB, …). TIFF is NOT in
-- this list: it is treated as a raw/scan format (counted with CR3/DNG-style
-- files), matching the user's stack-format rules.
function Utils.isNonRawFileName(name)
    if not name then return false end
    local ext = name:match("%.([^.]+)$")
    if not ext then return false end
    ext = string.lower(ext)
    return ext == "jpg" or ext == "jpeg" or ext == "heic" or ext == "heif"
        or ext == "png" or ext == "gif" or ext == "bmp" or ext == "webp"
        or ext == "psd" or ext == "psb"
end

return Utils
