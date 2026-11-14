require "RefreshMod/Config"
require "RefreshMod/Util"

RefreshMod = RefreshMod or {}
local Config = RefreshMod.Config
local Util = RefreshMod.Util
local Items = {}
RefreshMod.Items = Items

function Items.registeredCollection(item)
    if item == nil then return nil end
    local data = item:getModData()
    local key = data and data[Config.REGISTER_FLAG]
    if key == nil or key == "" then return nil end
    local collection = Config.collection(key)
    return key, collection and collection.name or key
end

function Items.markRegistered(item, collectionKey, player)
    if item == nil or collectionKey == nil then return end
    item:getModData()[Config.REGISTER_FLAG] = collectionKey
    if player and syncItemModData then
        syncItemModData(player, item)
    end
end

function Items.valueOf(item, ledger)
    local fullType = Util.fullType(item)
    if fullType == nil then return 0 end
    if Items.isKey(item) then return 0 end
    local registered = Items.registeredCollection(item)
    if registered then return 0 end
    local tier, trophy = Config.trophyTier(fullType)
    if trophy then
        local value = tonumber(trophy.sellValue) or 0
        if RefreshMod.CollectionsLogic and RefreshMod.CollectionsLogic.completed(ledger, "halloween_masks") then
            value = value * 1.25
        end
        return value
    end
    local tableValue = Items.tableValue(item, fullType)
    return (tonumber(tableValue) or 0) * Util.conditionFactor(item)
end

function Items.valueTierKey(value)
    value = tonumber(value) or 0
    if value <= 0 then return nil end
    local bounds = Config.VALUE_TIER_BOUNDS or { 1, 5, 12 }
    local keys = Config.VALUE_TIER_KEYS or { "low", "medium", "high", "extreme" }
    for index, bound in ipairs(bounds) do
        if value < bound then return keys[index] end
    end
    return keys[#keys] or "extreme"
end

function Items.valueTierLabel(value)
    local key = Items.valueTierKey(value)
    if key == nil then return nil end
    return getText("IGUI_ExtractionModeExpanded_ValueTier_" .. key)
end

local VALUE_OVERRIDES = {
    ["Base.Diamond"] = 12.0,
    ["Base.Necklace_Pearl"] = 2.5,
    ["Base.Necklace_Crucifix"] = 1.5,
    ["Base.Necklace_YingYang"] = 1.25,
}

local MOVEABLE_BASE_VW = 0.4
local MOVEABLE_LUXURY_BONUS = 0.5
local MOVEABLE_MULT = {
    high = 2.0,
    mid = 1.5,
    low = 0.7,
    veryLow = 0.3,
    terrible = 0.1,
}

local TRASH_WORDS = {
    "trash", "garbage", "debris", "rubble", "dumpster", "litter",
    "barrel", "pallet", "cardboard", "coffin", "grave", "hydrant",
    "road cone", "roadcone", "road barrier", "roadbarrier", "concrete road",
    "poster", "curtain", "cork",
    "cactus", "fern", "ficus", "flower", "planter",
    "flamingo", "gnome", "haystack",
}
local TRASH_PATTERNS = {
    "%f[%w]bin%f[%W]",
    "%f[%w]sign%f[%W]",
    "%f[%w]plant%f[%W]",
    "%f[%w]tree%f[%W]",
}
local POOR_WORDS = { "poorly crafted", "poor quality", "mediocre", "shoddy" }
local CRAFTED_WORDS = { "crafted", "crafter" }
local CRAFTED_SKIP = { "quality crafted", "exceptionally" }
local QUALITY_WORDS = { "quality crafted", "exceptionally crafted", "exceptional" }
local CHEAP_WORDS = {
    "mini", "trailer", "plastic", "folding", "crude", "valuetech",
    "prisoners", "stretcher", "hospital", "beach", "mall", "picnic",
}
local PRICEY_WORDS = {
    "fancy", "industrial", "chrome", "large", "grand", "victorian",
    "deluxe", "gallery", "popsicle", "china", "military", "premium technologies",
}
local SMALL_WORDS = { "simple", "small" }
local LUXURY_WORDS = { "piano", "arcade", "pinball", "jukebox" }

local function moveableHaulWeight(item, sprite)
    local weight = item and item:getActualWeight() or nil
    if weight == nil or weight <= 0.55 then
        local spriteObj = sprite and getSprite(sprite)
        local props = spriteObj and spriteObj:getProperties()
        if props and props:has("PickUpWeight") then
            weight = (tonumber(props:get("PickUpWeight")) or 0) / 10
        end
    end
    if (weight == nil or weight <= 0) and item then
        weight = item:getWeight()
    end

    if weight ~= nil and weight > 50 then
        weight = weight / 10
    end
    return math.max(0.25, weight or 0.5)
end

local function containsAny(label, words)
    for i = 1, #words do
        if string.find(label, words[i], 1, true) then return true end
    end
    return false
end

local function isMoveableTrash(label)
    if containsAny(label, TRASH_WORDS) then return true end
    for i = 1, #TRASH_PATTERNS do
        if string.find(label, TRASH_PATTERNS[i]) then return true end
    end
    return false
end

local function moveableLabel(item, sprite, fullType)
    local parts = {}
    local info = sprite and Items.moveableIdentity(sprite) or nil
    if info and info.identity then parts[#parts + 1] = info.identity end
    if item and instanceof(item, "Moveable") then
        local name = item:getCustomNameFull()
        if name and tostring(name) ~= "" then parts[#parts + 1] = tostring(name) end
    end
    if item then
        local name = item:getName()
        if name and tostring(name) ~= "" then parts[#parts + 1] = tostring(name) end
    end
    if fullType then parts[#parts + 1] = tostring(fullType) end
    if sprite then parts[#parts + 1] = tostring(sprite) end
    return string.lower(table.concat(parts, " "))
end

local function moveableTierMult(label)
    label = tostring(label or "")

    if isMoveableTrash(label) or string.find(label, "makeshift", 1, true) then
        return MOVEABLE_MULT.terrible
    end

    if containsAny(label, POOR_WORDS)
        or (containsAny(label, CRAFTED_WORDS) and not containsAny(label, CRAFTED_SKIP))
    then
        return MOVEABLE_MULT.veryLow
    end

    if containsAny(label, QUALITY_WORDS)
        or (string.find(label, "quality", 1, true) and not string.find(label, "poor", 1, true))
    then
        return MOVEABLE_MULT.low
    end

    if containsAny(label, CHEAP_WORDS) then
        return MOVEABLE_MULT.veryLow
    end

    if containsAny(label, PRICEY_WORDS) then
        return MOVEABLE_MULT.high
    end

    if containsAny(label, SMALL_WORDS) then
        return MOVEABLE_MULT.veryLow
    end

    return MOVEABLE_MULT.mid
end

local function moveableLuxuryBonus(label)
    label = tostring(label or "")
    if containsAny(label, LUXURY_WORDS) then
        return MOVEABLE_LUXURY_BONUS
    end
    if string.find(label, "pool", 1, true) and string.find(label, "table", 1, true) then
        return MOVEABLE_LUXURY_BONUS
    end
    return 0
end

local function moveablePrice(item, sprite, fullType)
    local label = moveableLabel(item, sprite, fullType)
    local weight = moveableHaulWeight(item, sprite)
    local mult = moveableTierMult(label) + moveableLuxuryBonus(label)
    return weight * MOVEABLE_BASE_VW * mult
end

local function pairedSideValue(fullType, values)
    local value = tonumber(values[fullType]) or 0
    local other = nil
    if string.find(fullType, "_Left_", 1, true) then
        other = fullType:gsub("_Left_", "_Right_", 1)
    elseif string.find(fullType, "_Right_", 1, true) then
        other = fullType:gsub("_Right_", "_Left_", 1)
    end
    if other and values[other] ~= nil then
        value = math.max(value, tonumber(values[other]) or 0)
    end
    return value
end

local function isEmptyContainerType(fullType)
    local short = tostring(fullType or ""):gsub("^Base%.", "")
    if short == "" then return false end

    if string.find(short, "BagSeed", 1, true) then return false end
    if string.find(short, "Empty", 1, true) then return true end
    return false
end

local function emptyContainerCap(fullType)
    local short = tostring(fullType or ""):gsub("^Base%.", "")

    if string.find(short, "Jar", 1, true)
        or string.find(short, "Paint", 1, true)
        or string.find(short, "Bucket", 1, true)
        or string.find(short, "GardeningSpray", 1, true)
        or string.find(short, "Sandbag", 1, true) then
        return 0.4
    end

    return 0.08
end

local function adjustListedValue(fullType, value, item)
    value = tonumber(value) or 0
    if value <= 0 then return 0 end
    if VALUE_OVERRIDES[fullType] ~= nil then return VALUE_OVERRIDES[fullType] end

    local values = RefreshMod.ItemValue or {}
    if string.find(fullType, "_Left_", 1, true) or string.find(fullType, "_Right_", 1, true) then
        value = pairedSideValue(fullType, values)
    end

    if isEmptyContainerType(fullType) then
        value = math.min(value, emptyContainerCap(fullType))
    end

    local category = nil
    if item then category = item:getDisplayCategory() end
    if category == nil then
        local script = getScriptManager():FindItem(fullType)
        if script then category = script:getDisplayCategory() end
    end
    category = category and tostring(category) or ""
    if category == "Junk" or category == "JunkWeapon" then
        value = math.min(value, 0.35)
    elseif category == "Accessory" or category == "Jewelry" or category == "Jewellery" then
        value = math.max(value, 0.75)
    end

    return value
end

local TILE_PREFIXES = {
    "location_", "furniture_", "appliances_", "walls_", "street_",
    "vegetation_", "recycling_", "industry_", "construction_", "d_trash_", "trash_",
}

local function spriteFromFullType(fullType)
    local fromMoveable = fullType:match("^Moveables%.(.+)$")
    if fromMoveable then return fromMoveable end
    local rest = fullType:match("^Base%.(.+)$")
    if rest == nil then return nil end
    for i = 1, #TILE_PREFIXES do
        local prefix = TILE_PREFIXES[i]
        if string.sub(rest, 1, #prefix) == prefix then return rest end
    end
end

function Items.tableValue(item, fullType)
    fullType = fullType or Util.fullType(item)
    if fullType == nil then return 0 end
    if VALUE_OVERRIDES[fullType] ~= nil then return VALUE_OVERRIDES[fullType] end
    local values = RefreshMod.ItemValue or {}
    local direct = tonumber(values[fullType])
    if direct and direct > 0 and string.sub(fullType, 1, 9) ~= "Base.Mov_" then
        return adjustListedValue(fullType, direct, item)
    end

    local sprite = Items.worldSpriteOf(item) or spriteFromFullType(fullType)
    local info = sprite and Items.moveableIdentity(sprite) or nil
    local isMoveable = string.sub(fullType, 1, 9) == "Base.Mov_"
        or string.sub(fullType, 1, 10) == "Moveables."
        or (item ~= nil and instanceof(item, "Moveable"))
        or info ~= nil
    if isMoveable then
        return moveablePrice(item, sprite, fullType)
    end
    return 0
end

function Items.weaponPointsOf(item, ledger)
    local fullType = Util.fullType(item)
    if fullType == nil then return 0 end
    if Items.registeredCollection(item) then return 0 end
    local points = RefreshMod.WeaponPoints and RefreshMod.WeaponPoints[fullType] or 0
    points = (tonumber(points) or 0) * Util.conditionFactor(item)
    return points
end

function Items.isAmmo(item)
    local fullType = Util.fullType(item)
    if fullType == nil then return false end
    return string.find(fullType, "Bullets", 1, true) ~= nil
        or string.find(fullType, "ShotgunShells", 1, true) ~= nil
end

local worldSpriteByType = {}
local moveableIdBySprite = {}

local function normalizeSpriteName(sprite)
    if sprite == nil then return nil end
    sprite = tostring(sprite)
    if sprite == "" then return nil end
    sprite = sprite:gsub("%.png$", "")
    return sprite
end

function Items.worldSpriteForType(fullType)
    if fullType == nil then return nil end
    local cached = worldSpriteByType[fullType]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end
    local script = getScriptManager():FindItem(fullType)
    local sprite = script and script:getWorldObjectSprite() or nil
    sprite = normalizeSpriteName(sprite)
    if sprite == nil then
        worldSpriteByType[fullType] = false
        return nil
    end
    worldSpriteByType[fullType] = sprite
    return sprite
end

function Items.worldSpriteOf(item)
    if item == nil then return nil end
    local sprite = nil
    if instanceof(item, "Moveable") then sprite = item:getWorldSprite() end
    if sprite == nil or sprite == "" then sprite = item:getWorldObjectSprite() end
    sprite = normalizeSpriteName(sprite)
    if sprite then return sprite end
    local fullType = Util.fullType(item)
    if fullType then
        local fromType = tostring(fullType):match("^Moveables%.(.+)$")
        if fromType then return normalizeSpriteName(fromType) end
    end
    return nil
end

function Items.moveableIdentity(spriteName)
    spriteName = normalizeSpriteName(spriteName)
    if spriteName == nil then return nil end
    local cached = moveableIdBySprite[spriteName]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end
    local identity, customItem, gridKey = nil, nil, nil
    local sprite = getSprite(spriteName)
    local props = sprite and sprite:getProperties()
    if props ~= nil then
        local group, custom = "", ""
        if props:has("GroupName") then group = tostring(props:get("GroupName") or "") end
        if props:has("CustomName") then custom = tostring(props:get("CustomName") or "") end
        if group ~= "" or custom ~= "" then
            identity = (group ~= "" and (group .. " ") or "") .. custom
        end
        if props:has("CustomItem") then
            customItem = tostring(props:get("CustomItem") or "")
        end
        local grid = sprite:getSpriteGrid()
        if grid then gridKey = tostring(grid) end
    end
    if (identity == nil or identity == "") and (customItem == nil or customItem == "") and gridKey == nil then
        moveableIdBySprite[spriteName] = false
        return nil
    end
    local packed = { identity = identity, customItem = customItem, gridKey = gridKey }
    moveableIdBySprite[spriteName] = packed
    return packed
end

local function normalizeType(fullType)
    if fullType == nil then return nil end
    fullType = tostring(fullType)
    if string.sub(fullType, 1, 5) ~= "Base." and not string.find(fullType, ".", 1, true) then
        return "Base." .. fullType
    end
    return fullType
end

function Items.matchesTypes(item, types)
    if types == nil or item == nil then return false end
    local fullType = Util.fullType(item)
    if Util.inList(fullType, types) then return true end
    local sprite = Items.worldSpriteOf(item)
    local info = sprite and Items.moveableIdentity(sprite) or nil
    for _, candidate in ipairs(types) do
        if sprite and (candidate == sprite or candidate == "Base." .. sprite or candidate == "Moveables." .. sprite) then
            return true
        end
        if info and info.customItem and info.customItem ~= "" then
            if normalizeType(info.customItem) == normalizeType(candidate) then return true end
        end
        local wantedSprite = Items.worldSpriteForType(candidate)
        if wantedSprite ~= nil and wantedSprite == sprite then return true end
        local wanted = wantedSprite and Items.moveableIdentity(wantedSprite)
        if info and wanted and info.identity and wanted.identity and info.identity == wanted.identity then
            return true
        end
    end
    return false
end

function Items.lineTypes(line)
    local types = {}
    if line == nil then return types end
    for _, fullType in ipairs(line.types or {}) do types[#types + 1] = fullType end
    if line.alt then
        for _, fullType in ipairs(line.alt.types or {}) do types[#types + 1] = fullType end
    end
    return types
end

function Items.isFavorite(item)
    return item ~= nil and item:isFavorite()
end

function Items.isKey(item)
    if item == nil then return false end
    local fullType = Util.fullType(item)
    if fullType == "Base.Padlock" or fullType == "Base.CombinationPadlock" or fullType == "Base.KeyPadlock" then
        return false
    end
    if instanceof(item, "Key") then
        return not item:isPadlock() and not item:isDigitalPadlock()
    end
    if fullType == "Base.CarKey" or fullType == "Base.Key" or fullType == "Base.Key_Blank" then
        return true
    end
    return fullType ~= nil and string.match(fullType, "^Base%.Key%d+$") ~= nil
end

function Items.inCharacterInventory(player, item)
    if player == nil or item == nil then return false end
    local container = item:getContainer()
    if container == nil then return false end
    return container:isInCharacterInventory(player)
end

function Items.isEquippedOn(player, item)
    if player == nil or item == nil then return false end
    return player:isEquipped(item) or player:isEquippedClothing(item)
end

function Items.isOnHotbar(player, item)
    if player == nil or item == nil then return false end
    if item:getAttachedSlot() > -1 then return true end
    if getPlayerHotbar == nil then return false end
    local hotbar = getPlayerHotbar(player:getPlayerNum())
    return hotbar ~= nil and hotbar:isInHotbar(item)
end

function Items.offerBlockReason(item, player, allowFavorite, allowKeys, allowEquipped, allowHotbar)
    if item == nil then return "missing item" end
    if not allowKeys and Items.isKey(item) then
        return getText("IGUI_ExtractionModeExpanded_KeysBlocked")
    end
    if not Items.inCharacterInventory(player, item) then
        return getText("IGUI_ExtractionModeExpanded_NotInInventory")
    end
    if not allowEquipped and Items.isEquippedOn(player, item) then
        return getText("IGUI_ExtractionModeExpanded_Equipped")
    end
    if not allowHotbar and Items.isOnHotbar(player, item) then
        return getText("IGUI_ExtractionModeExpanded_OnHotbar")
    end
    if not allowFavorite and Items.isFavorite(item) then
        return getText("IGUI_ExtractionModeExpanded_Favorited")
    end
    local key, name = Items.registeredCollection(item)
    if key then
        return getText("IGUI_ExtractionModeExpanded_Registered", tostring(name))
    end
end

function Items.containedCount(item)
    if item == nil then return 0 end
    local inventory = item:getInventory()
    if inventory == nil then return 0 end
    return inventory:getItems():size()
end

function Items.contentsBlockReason(item)
    if Items.containedCount(item) <= 0 then return nil end
    return getText("IGUI_ExtractionModeExpanded_EmptyContainer")
end

function Items.bankRejectReason(item, player)
    return Items.offerBlockReason(item, player, false, false) or Items.contentsBlockReason(item)
end

function Items.matchesBankKind(item, kind)
    if kind ~= "bulk" and kind ~= "key" then return true end
    if item == nil then return false end
    for _, area in ipairs(Config.areas() or {}) do
        for _, line in ipairs(area.quest or {}) do
            if line.tier == kind and Items.matchesTypes(item, Items.lineTypes(line)) then
                return true
            end
        end
    end
    return false
end

function Items.registerRejectReason(item, player)

    return Items.offerBlockReason(item, player, true, true, true, true)
end

local function uniqueNames(names, limit)
    local seen = {}
    local out = {}
    for _, name in ipairs(names or {}) do
        name = tostring(name or "")
        if name ~= "" and not seen[name] then
            seen[name] = true
            out[#out + 1] = name
            if limit and #out >= limit then break end
        end
    end
    return out
end

function Items.primaryRefreshLabel(line)
    if line == nil then return "" end
    if line.bankLabel then return line.bankLabel end
    local label = line.label or ""
    if line.alt then
        local stripped = string.match(label, "^(.-),%s*or%s+") or string.match(label, "^(.-)%s+or%s+")
        if stripped and stripped ~= "" then return stripped end
    end
    return label
end

local function emClientState(player)
    if ExtractionMode and ExtractionMode.Client and ExtractionMode.Client.stateFor then
        local state = ExtractionMode.Client.stateFor(player)
        if type(state) == "table" then return state end
    end
    return ExtractionMode and ExtractionMode.ClientState
end

function Items.alternateUses(item, player, options)
    local result = {
        upgrades = {},
        quests = {},
        refreshBulk = {},
        refreshKey = {},
        refreshKeyHidden = false,
        any = false,
    }
    if item == nil then return result end
    options = options or {}
    local ignoreRefresh = options.ignoreRefreshTier
    local state = emClientState(player) or {}
    local Upgrades = ExtractionMode and ExtractionMode.Upgrades
    local Quests = ExtractionMode and ExtractionMode.Quests

    if Upgrades and Upgrades.definitions and Upgrades.itemMatchesRequirement then
        local installed = state.upgrades or {}
        for _, definition in ipairs(Upgrades.definitions() or {}) do
            if not Upgrades.isInstalled(installed, definition.id) then
                for _, requirement in ipairs(definition.requirements or {}) do
                    if Upgrades.itemMatchesRequirement(item, requirement) then
                        result.upgrades[#result.upgrades + 1] = (Upgrades.name and Upgrades.name(definition))
                            or definition.name or definition.id
                        break
                    end
                end
            end
        end
    end

    if Quests and Quests.definitions and Upgrades and Upgrades.itemMatchesRequirement then
        local completions = state.quests or {}
        for _, definition in ipairs(Quests.definitions() or {}) do
            local available = Quests.isAcquired
                and Quests.isAcquired(completions, definition)
                and not Quests.isCompleted(completions, definition.id)
            if available then
                for _, requirement in ipairs(definition.requirements or {}) do
                    if Upgrades.itemMatchesRequirement(item, requirement) then
                        result.quests[#result.quests + 1] = (Quests.name and Quests.name(definition))
                            or definition.name or definition.id
                        break
                    end
                end
            end
        end
    end

    local State = RefreshMod.State
    local completions = (State and State.completions(player)) or {}
    for _, area in ipairs(Config.areas() or {}) do
        local unlocked = Config.areaUnlocked(area.key, completions)
        for _, line in ipairs(area.quest or {}) do
            local matchedLabel = nil
            if Items.matchesTypes(item, line.types) then
                matchedLabel = Items.primaryRefreshLabel(line)
            elseif line.alt and Items.matchesTypes(item, line.alt.types) then
                matchedLabel = line.alt.label or Items.primaryRefreshLabel(line)
            end
            if matchedLabel and matchedLabel ~= "" then
                if line.tier == "bulk" and ignoreRefresh ~= "bulk" then
                    result.refreshBulk[#result.refreshBulk + 1] = matchedLabel
                elseif line.tier == "key" and ignoreRefresh ~= "key" then
                    if unlocked then
                        result.refreshKey[#result.refreshKey + 1] = string.format(
                            "%s (%s)", matchedLabel, area.name or area.key)
                    else
                        result.refreshKeyHidden = true
                    end
                end
            end
        end
    end

    result.upgrades = uniqueNames(result.upgrades, 8)
    result.quests = uniqueNames(result.quests, 8)
    result.refreshBulk = uniqueNames(result.refreshBulk, 8)
    result.refreshKey = uniqueNames(result.refreshKey, 8)
    result.any = #result.upgrades > 0 or #result.quests > 0
        or #result.refreshBulk > 0 or #result.refreshKey > 0 or result.refreshKeyHidden
    return result
end

function Items.alternateUseTip(usesOrItem, player, options)
    local uses = usesOrItem
    if type(usesOrItem) ~= "table" or usesOrItem.any == nil or usesOrItem.upgrades == nil then
        uses = Items.alternateUses(usesOrItem, player, options)
    end
    if not uses or not uses.any then return nil end
    local parts = {}
    for _, name in ipairs(uses.upgrades or {}) do
        parts[#parts + 1] = getText("IGUI_ExtractionModeExpanded_TipUpgrade", name)
    end
    for _, name in ipairs(uses.quests or {}) do
        parts[#parts + 1] = getText("IGUI_ExtractionModeExpanded_TipQuest", name)
    end
    for _, name in ipairs(uses.refreshBulk or {}) do
        parts[#parts + 1] = getText("IGUI_ExtractionModeExpanded_TipRefreshSupply", name)
    end
    for _, name in ipairs(uses.refreshKey or {}) do
        parts[#parts + 1] = getText("IGUI_ExtractionModeExpanded_TipRefreshKey", name)
    end
    if #(uses.refreshKey or {}) == 0 and uses.refreshKeyHidden then
        parts[#parts + 1] = getText("IGUI_ExtractionModeExpanded_TipRefreshKeyHidden")
    end

    return table.concat(parts, " <LINE> ")
end

return Items
