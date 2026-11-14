RefreshMod = RefreshMod or {}

local ClientOptions = RefreshMod.ClientOptions or {}
RefreshMod.ClientOptions = ClientOptions

local hideFavoriteOption = nil
local warnBankUndoOption = nil

if PZAPI and PZAPI.ModOptions then
    local options = PZAPI.ModOptions:create("ExtractionModeExpanded", "UI_ExtractionModeExpanded_OptionsTitle")
    hideFavoriteOption = options:addTickBox(
        "hideFavoriteItemDetails",
        "UI_ExtractionModeExpanded_HideFavoriteItemDetails",
        false,
        "UI_ExtractionModeExpanded_HideFavoriteItemDetailsTooltip")
    warnBankUndoOption = options:addTickBox(
        "warnEndBankUndo",
        "UI_ExtractionModeExpanded_WarnEndBankUndo",
        true,
        "UI_ExtractionModeExpanded_WarnEndBankUndoTooltip")
end

function ClientOptions.hideFavoriteItemDetails()
    if hideFavoriteOption == nil then return false end
    return hideFavoriteOption:getValue()
end

function ClientOptions.warnEndBankUndo()
    if warnBankUndoOption == nil then return true end
    return warnBankUndoOption:getValue()
end

return ClientOptions
