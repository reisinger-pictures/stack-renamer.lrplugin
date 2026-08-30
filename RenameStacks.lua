-- stack-renamer.lrplugin/RenameStacks.lua
-- Library-menu entry point. Mirrors the sibling plugin's SelectionManager.lua:
-- the file is EXECUTED directly by Lightroom (no returned function!) and must
-- start the work itself, so the async task is launched at load time.
local LrTasks = import 'LrTasks'
local LrDialogs = import 'LrDialogs'
local LrLogger = import 'LrLogger'
local RenameCore = require "RenameCore"

-- Standard Lightroom logger -> ~/Documents/lrClassicLogs/StackRenamerLog.log
local myLogger = LrLogger('StackRenamerLog')
myLogger:enable("logfile")

LrTasks.startAsyncTask(function()
    local function reportError(context, err)
        local detail = ""
        if debug and debug.traceback then
            detail = debug.traceback(tostring(err), 2)
        else
            detail = tostring(err)
        end
        myLogger:trace("ERROR[" .. tostring(context) .. "]: " .. tostring(detail))
        LrDialogs.message("Stack Renamer Fehler",
            "Unerwarteter Fehler (" .. tostring(context) .. "):\n\n"
            .. tostring(detail), "critical")
    end

    local ok, err = LrTasks.pcall(RenameCore.run)
    if not ok then
        reportError("run", err)
    end
end)
