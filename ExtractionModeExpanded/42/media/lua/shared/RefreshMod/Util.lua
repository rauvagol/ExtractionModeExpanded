RefreshMod = RefreshMod or {}
local Util = {}
RefreshMod.Util = Util

local function emUtil(name)
    local util = ExtractionMode and ExtractionMode.Util
    return util and util[name]
end

local function named(value)
    if value == nil then return nil end
    value = tostring(value)
    if value == "" then return nil end
    return value
end

function Util.fullType(item)
    return item and item:getFullType() or nil
end

function Util.itemCount(item)
    if not item then return 0 end
    return math.max(1, item:getCount())
end

function Util.clamp(value, minimum, maximum)
    value = tonumber(value) or 0
    return math.max(minimum, math.min(maximum, value))
end

function Util.conditionFactor(item)
    local maximum = item and item:getConditionMax()
    if maximum == nil or maximum <= 0 then return 1 end
    return Util.clamp((item:getCondition() or 0) / maximum, 0, 1)
end

function Util.inList(value, list)
    if list == nil then return false end
    for _, entry in ipairs(list) do
        if entry == value then return true end
    end
    return false
end

function Util.roundCost(value)
    value = tonumber(value) or 0
    if value <= 0 then return 0 end
    return math.floor(value + 0.5)
end

function Util.scaleAmount(base, multiplier)
    base = math.max(0, math.floor(tonumber(base) or 0))
    multiplier = tonumber(multiplier) or 1
    if base == 0 or multiplier <= 1 then return base end
    return math.max(base, Util.roundCost(base * multiplier))
end

function Util.distance(ax, ay, bx, by)
    local dx = ax - bx
    local dy = ay - by
    return math.sqrt(dx * dx + dy * dy)
end

function Util.localPlayer(playerNum)
    return getSpecificPlayer(playerNum or 0)
end

function Util.isRemoteClient()
    return isClient and isClient() and not (isServer and isServer())
end

function Util.javaList(list)
    local result = {}
    if list == nil then return result end
    for index = 0, list:size() - 1 do
        local entry = list:get(index)
        if entry ~= nil then result[#result + 1] = entry end
    end
    return result
end

function Util.username(player)
    local base = emUtil("username")
    if base then return base(player) end
    if player == nil then return "singleplayer" end
    local name = player:getUsername()
    if name and name ~= "" then return name end
    return "singleplayer"
end

function Util.players()
    local base = emUtil("players")
    if base then return base() end
    local player = Util.localPlayer(0)
    if player == nil then return {} end
    return { player }
end

function Util.worldHours()
    local base = emUtil("worldHours")
    if base then return base() end
    local gameTime = getGameTime()
    if gameTime == nil then return 0 end
    return gameTime:getWorldAgeHours()
end

function Util.gameDay()
    return math.max(0, math.floor(Util.worldHours() / 24))
end

local SUNDAY = 6

local function gregorianDay(year, month, day)
    local a = math.floor((14 - month) / 12)
    local y = year + 4800 - a
    local m = month + 12 * a - 3
    return day + math.floor((153 * m + 2) / 5) + 365 * y
        + math.floor(y / 4) - math.floor(y / 100) + math.floor(y / 400) - 32045
end

local function gameDate()
    local gameTime = getGameTime()
    if gameTime == nil then return 1993, 7, 9 end
    return gameTime:getYear(), gameTime:getMonth() + 1, gameTime:getDay() + 1
end

local function daysSinceSunday(dayNumber)
    return (dayNumber - SUNDAY) % 7
end

function Util.sundayPeriodId()
    local today = gregorianDay(gameDate())
    return today - daysSinceSunday(today)
end

function Util.daysUntilNextSundayMidnight()
    local since = daysSinceSunday(gregorianDay(gameDate()))
    if since == 0 then return 7 end
    return 7 - since
end

function Util.nextSundayMidnightLabel()
    local days = Util.daysUntilNextSundayMidnight()
    if days == 1 then return getText("IGUI_ExtractionModeExpanded_SundayTomorrow") end
    if days == 7 then return getText("IGUI_ExtractionModeExpanded_SundayNextWeek") end
    return getText("IGUI_ExtractionModeExpanded_SundayInDays", days)
end

function Util.inventoryItems(player)
    local access = ExtractionMode and ExtractionMode.InventoryAccess
    if access and access.items then return access.items(player) end
    local inventory = player and player:getInventory()
    if inventory == nil then return {} end
    return Util.javaList(inventory:getItems())
end

function Util.removeItem(item)
    local container = item and item:getContainer()
    if container == nil then return false end
    if sendRemoveItemFromContainer then
        sendRemoveItemFromContainer(container, item)
    end
    container:Remove(item)
    return true
end

function Util.setItemCount(item, count)
    count = math.max(0, math.floor(tonumber(count) or 0))
    if count <= 0 then return Util.removeItem(item) end
    if item == nil then return false end
    item:setCount(count)
    return true
end

function Util.itemId(item)
    return item and item:getID() or nil
end

function Util.packSelection(entry)
    if type(entry) ~= "table" then return nil end
    local item = entry.item
    local itemId, fullType
    if item ~= nil and type(item) ~= "table" then
        itemId = Util.itemId(item)
        fullType = Util.fullType(item)
    else
        itemId = entry.itemId
        fullType = entry.fullType
    end
    return {
        itemId = itemId,
        quantity = entry.quantity,
        fullType = fullType,
        collectionKey = entry.collectionKey,
        slotIndex = entry.slotIndex,
    }
end

function Util.findItemById(player, itemId)
    if player == nil or itemId == nil then return nil end
    for _, item in ipairs(Util.inventoryItems(player)) do
        if Util.itemId(item) == itemId then return item end
    end
    return nil
end

local function isMoveableFullType(fullType)
    fullType = tostring(fullType or "")
    if fullType == "" then return false end
    if fullType == "Base.Moveable" or fullType == "Moveables.Moveable" then return true end
    return fullType:find("^Moveables%.") ~= nil or fullType:find("^Base%.Mov_") ~= nil
end

local function itemFromMoveableProps(sprite)
    if not ISMoveableSpriteProps then return nil end
    local spriteObj = getSprite(sprite)
    if not spriteObj then return nil end
    local props = ISMoveableSpriteProps.new(spriteObj)
    if not props then return nil end
    return props:instanceItem(sprite)
end

local function createMoveableFromSnapshot(snapshot)
    local sprite = named(snapshot.worldSprite)
    if sprite == nil then
        sprite = tostring(snapshot.fullType or ""):match("^Moveables%.(.+)$")
        if sprite == "Moveable" then sprite = nil end
    end
    if sprite == nil then return nil end

    local item = itemFromMoveableProps(sprite)
    if item then return item end

    item = instanceItem("Moveables.Moveable")
    if item and item:ReadFromWorldSprite(sprite) then return item end
    return nil
end

local function applySnapshot(item, snapshot, quantity)
    if item == nil then return end
    if quantity > 1 then item:setCount(quantity) end
    if snapshot.condition ~= nil then
        item:setCondition(tonumber(snapshot.condition) or item:getCondition())
    end
    if snapshot.favorite then item:setFavorite(true) end
    if snapshot.weight ~= nil then
        item:setActualWeight(tonumber(snapshot.weight) or item:getActualWeight())
    end
    if type(snapshot.modData) == "table" then
        local data = item:getModData()
        for key, value in pairs(snapshot.modData) do
            if type(value) ~= "table" then data[key] = value end
        end
    end
end

local function itemFromSnapshot(snapshot, fullType)
    local sprite = named(snapshot.worldSprite)
    local item
    if sprite ~= nil or isMoveableFullType(fullType) then
        item = createMoveableFromSnapshot(snapshot)
    end
    if item ~= nil then return item end

    item = instanceItem(fullType)
    if item ~= nil and sprite ~= nil and instanceof(item, "Moveable") then
        item:ReadFromWorldSprite(sprite)
    end
    return item
end

function Util.restoreBankedItem(player, snapshot)
    if player == nil or type(snapshot) ~= "table" or snapshot.fullType == nil then return nil end
    local fullType = snapshot.fullType
    local quantity = math.max(1, math.floor(tonumber(snapshot.quantity) or 1))

    local existing = Util.findItemById(player, snapshot.itemId)
    if existing ~= nil and Util.fullType(existing) == fullType then
        Util.setItemCount(existing, Util.itemCount(existing) + quantity)
        return existing
    end

    local inventory = player:getInventory()
    if inventory == nil then return nil end
    local item = itemFromSnapshot(snapshot, fullType)
    if item == nil then return nil end

    applySnapshot(item, snapshot, quantity)
    inventory:AddItem(item)
    if sendAddItemToContainer then sendAddItemToContainer(inventory, item) end
    return item
end

local function scriptItem(fullType)
    if fullType == nil or getScriptManager == nil then return nil end
    return getScriptManager():FindItem(fullType)
end

function Util.itemTexture(fullType)
    local script = scriptItem(fullType)
    if script == nil then return nil end
    return script:getNormalTexture()
end

function Util.displayName(fullType)
    if fullType == nil then return "" end
    local script = scriptItem(fullType)
    if script == nil then return fullType end
    local name = script:getDisplayName()
    if name == nil or name == "" then return fullType end
    return name
end

function Util.itemName(item)
    if item == nil then return "" end
    local name = item:getName()
    if name == nil or name == "" then return Util.displayName(item:getFullType()) end
    if instanceof(item, "Moveable") then
        name = tostring(name):gsub(" %(%d+/%d+%)$", "")
    end
    return name
end

function Util.insideHideout(player)
    local infection = ExtractionMode and ExtractionMode.Infection
    if player == nil or infection == nil then return false end
    return infection.playerInsideHideout(player)
end

function Util.raidViewState(data)
    local config = ExtractionMode and ExtractionMode.Config
    if data == nil or config == nil then return false end
    local state = data.state
    return state == config.STATE_RAID
        or state == config.STATE_EXTRACTING
        or state == config.STATE_BOARDING
end

function Util.log(message)
    if getDebug and getDebug() then
        print("[ExtractionModeExpanded] " .. tostring(message))
    end
end

return Util
