-- stack-renamer.lrplugin/Info.lua
-- Plugin manifest for the "Stack Renamer" Lightroom Classic plugin.
return {
    LrSdkVersion = 8.0,
    LrToolkitIdentifier = 'com.reisinger.stackrenamer',
    LrPluginName = 'Stack Renamer',
    VERSION = { major = 1, minor = 0, revision = 0, build = 0, display = "1.0.0" },

    -- File-menu entry: renames a whole folder / current selection stack-consistently.
    -- Uses LrExportMenuItems (like the sibling portal plugin) so the item shows
    -- under File → Plug-in Extras, not Library → Plug-in Extras.
    LrExportMenuItems = {
        { title = "Stacks konsistent umbenennen...", file = "RenameStacks.lua" }
    }
}
