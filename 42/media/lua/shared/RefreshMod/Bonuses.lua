require "RefreshMod/Config"
require "RefreshMod/Util"
require "RefreshMod/State"
require "RefreshMod/Collections"
require "RefreshMod/Items"

RefreshMod = RefreshMod or {}
local Config = RefreshMod.Config
local Util = RefreshMod.Util
local State = RefreshMod.State
local Collections = RefreshMod.CollectionsLogic
local Items = RefreshMod.Items
local Bonuses = {}
RefreshMod.Bonuses = Bonuses

local secondXpTrigger = false
local insideXpWrap = false

local function passivePerk(perk)
    if perk == nil or Perks == nil then return true end
    if perk == Perks.Strength or perk == Perks.Fitness then return true end
    return perk:isPassiv()
end

local function libraryApplies(player, perk, amount)
    if Util.isRemoteClient() then return false end
    if secondXpTrigger then return false end
    amount = tonumber(amount) or 0
    if amount <= 0 then return false end
    if player == nil or passivePerk(perk) then return false end
    if not Util.insideHideout(player) then return false end
    return Collections.completed(State.uiLedger(player), "skill_library")
end

local function grantRawXp(player, perk, amount)
    if player == nil then return end
    player:getXp():AddXP(perk, amount, true)
end

local function onAddXP(player, perk, amount)
    if insideXpWrap or secondXpTrigger then return end
    if not libraryApplies(player, perk, amount) then return end
    secondXpTrigger = true
    pcall(grantRawXp, player, perk, amount)
    secondXpTrigger = false
end

local function wrapXpFunction(name)
    local original = _G[name]
    if type(original) ~= "function" or original._refreshModLibrary then return end
    local function wrapped(player, perk, amount, ...)
        if secondXpTrigger then
            return original(player, perk, amount, ...)
        end
        insideXpWrap = true
        local ok, err = pcall(original, player, perk, amount, ...)
        if ok and libraryApplies(player, perk, amount) then
            secondXpTrigger = true
            pcall(original, player, perk, amount, ...)
            secondXpTrigger = false
        end
        insideXpWrap = false
        if not ok then error(err) end
    end
    wrapped._refreshModLibrary = true
    _G[name] = wrapped
end

function Bonuses.installXpTriggers()
    wrapXpFunction("addXp")
    wrapXpFunction("addXpNoMultiplier")
    if Events and Events.AddXP and Events.AddXP.Add and not Bonuses._addXpEvent then
        Bonuses._addXpEvent = true
        Events.AddXP.Add(onAddXP)
    end
end

local lastHour = {}

local MOOD_STAT = {
    panic = "PANIC",
    stress = "STRESS",
    unhappiness = "UNHAPPINESS",
    boredom = "BOREDOM",
}

local function reduceStat(player, stat, amount)
    if amount <= 0 or player == nil or CharacterStat == nil then return end
    local characterStat = CharacterStat[MOOD_STAT[stat] or ""]
    if characterStat == nil then return end
    local stats = player:getStats()
    if stats == nil then return end
    local current = stats:get(characterStat) or 0
    local reduced = math.max(0, current - amount)
    if reduced < current then
        stats:set(characterStat, reduced)
    end
end

local function quietBase(key, fallback)
    local em = ExtractionMode and ExtractionMode.Config
    return (em and em.value and tonumber(em.value(key))) or fallback
end

local function upgradeTable(player)
    local Runtime = ExtractionMode and ExtractionMode.RaidRuntime
    if Runtime and Runtime.dataForPlayer then
        local data = Runtime.dataForPlayer(player)
        if type(data) == "table" and type(data.upgrades) == "table" then
            return data.upgrades
        end
    end
    local client = nil
    if ExtractionMode and ExtractionMode.Client and ExtractionMode.Client.stateFor then
        client = ExtractionMode.Client.stateFor(player)
    end
    if type(client) ~= "table" then
        client = ExtractionMode and ExtractionMode.ClientState
    end
    return client and client.upgrades
end

local function hasQuietQuarters(player)
    local Upgrades = ExtractionMode and ExtractionMode.Upgrades
    if Upgrades == nil then return false end
    return Upgrades.isInstalled(upgradeTable(player), "quiet_quarters")
end

local function quietCollectionExtra(player, base)
    if hasQuietQuarters(player) then return base + base * 0.5 end
    return base * 0.5
end

function Bonuses.applyMoodles(player)
    if player == nil then return end
    local key = Util.username(player)
    local hour = Util.worldHours()
    if not Util.insideHideout(player) then
        lastHour[key] = hour
        return
    end
    local previous = lastHour[key]
    lastHour[key] = hour
    if previous == nil or hour <= previous then return end
    local elapsed = math.min(1, hour - previous)
    local ledger = State.uiLedger(player)
    local stress = quietCollectionExtra(player, quietBase("QuietStressReductionPerHour", 0.10))
    local unhappy = quietCollectionExtra(player, quietBase("QuietUnhappinessReductionPerHour", 10))
    local panic = quietCollectionExtra(player, quietBase("QuietPanicReductionPerHour", 10))
    local boredom = 15
    if Collections.completed(ledger, "plushies") then reduceStat(player, "unhappiness", unhappy * elapsed) end
    if Collections.completed(ledger, "ornaments") then reduceStat(player, "panic", panic * elapsed) end
    if Collections.completed(ledger, "dice") then reduceStat(player, "boredom", boredom * elapsed) end
    if Collections.completed(ledger, "music_shirts") then reduceStat(player, "stress", stress * elapsed) end
end

local FROZEN_OFF_AGE = 1000000
local hadSpiffo = {}

function Bonuses.freezeSpiffoItem(item, player)
    if item == nil or not Config.SPIFFO_FOOD[Util.fullType(item)] then return false end
    local data = item:getModData()
    if data.refreshModFresh and not item:isRotten()
        and item:getAge() <= 0 and item:getOffAgeMax() >= FROZEN_OFF_AGE then
        return false
    end
    item:setAge(0)
    item:setRotten(false)
    item:setOffAge(FROZEN_OFF_AGE)
    item:setOffAgeMax(FROZEN_OFF_AGE)
    data.refreshModFresh = true
    if player and syncItemFields then syncItemFields(player, item) end
    return true
end

local function freezeItemTree(item, depth, player)
    if item == nil or depth > 6 then return end
    Bonuses.freezeSpiffoItem(item, player)
    local container = item:getInventory()
    if container == nil then return end
    for _, child in ipairs(Util.javaList(container:getItems())) do
        freezeItemTree(child, depth + 1, player)
    end
end

function Bonuses.freezePlayerInventory(player)
    if player == nil then return end
    if not Collections.completedForPlayer(player, "spiffo_superfan") then return end
    for _, item in ipairs(Util.inventoryItems(player)) do
        freezeItemTree(item, 0, player)
    end
end

local function freshenContainer(container, player)
    if container == nil then return end
    local items = container:getItems()
    for _, item in ipairs(Util.javaList(items)) do
        freezeItemTree(item, 0, player)
    end
end

local function freshenGroundSquare(square)
    if square == nil then return end
    for _, obj in ipairs(Util.javaList(square:getWorldObjects())) do
        if instanceof(obj, "IsoWorldInventoryObject") then
            local item = obj:getItem()
            if Bonuses.freezeSpiffoItem(item) and isServer() then
                obj:transmitCompleteItemToClients()
            end
        end
    end
end

local function anyoneHasSpiffo()
    for _, player in ipairs(Util.players()) do
        if Collections.completedForPlayer(player, "spiffo_superfan") then return true end
    end
    return false
end

function Bonuses.freshenLoadedSquare(square)
    if not anyoneHasSpiffo() then return end
    freshenGroundSquare(square)
end

function Bonuses.freshenOpenedSquare(player, args)
    if player == nil or type(args) ~= "table" then return end
    if not Collections.completedForPlayer(player, "spiffo_superfan") then return end
    local x, y = tonumber(args.x), tonumber(args.y)
    local z = tonumber(args.z) or 0
    if x == nil or y == nil then return end
    if Util.distance(player:getX(), player:getY(), x, y) > 8 then return end
    local cell = getCell()
    if cell == nil then return end
    local square = cell:getGridSquare(x, y, z)
    if square == nil then return end
    freshenGroundSquare(square)
    for _, obj in ipairs(Util.javaList(square:getObjects())) do
        freshenContainer(obj:getContainer(), player)
    end
end

local function freezeNewlyCompleted(player)
    if player == nil then return end
    local key = Util.username(player)
    local has = Collections.completedForPlayer(player, "spiffo_superfan")
    if has and hadSpiffo[key] ~= true then
        Bonuses.freezePlayerInventory(player)
    end
    hadSpiffo[key] = has
end

local function lockUndoOutsideHideout(player)
    if Util.insideHideout(player) then return end
    local pending = RefreshMod.Pending and RefreshMod.Pending[Util.username(player)]
    if type(pending) ~= "table" or type(pending.undoStack) ~= "table" or #pending.undoStack == 0 then
        return
    end
    pending.undoStack = {}
    pending.lastResult = { ok = true, result = "committed", undoCount = 0 }
    if isServer and isServer() and sendServerCommand then
        sendServerCommand(player, Config.COMMAND_MODULE, "State", State.snapshot(player))
    end
end

local function scaleUp(before, now)
    if before == nil or now == nil or now == before then return nil end
    local delta = now - before
    if delta > 0 then delta = delta * 1.25 else delta = delta * 0.75 end
    return math.max(0, before + delta)
end

local function scaleDown(before, now)
    if before == nil or now == nil or now == before then return nil end
    local delta = now - before
    if delta < 0 then delta = delta * 1.25 else delta = delta * 0.75 end
    return math.max(0, before + delta)
end

local function beginFoodScale(character)
    local stats = character and character:getStats()
    local nutrition = character and character:getNutrition()
    local hunger, thirst, unhappy, boredom, stress, sick, fatigue, endurance
    local calories, carbs, proteins, lipids

    if stats and CharacterStat then
        if CharacterStat.HUNGER then hunger = tonumber(stats:get(CharacterStat.HUNGER)) end
        if CharacterStat.THIRST then thirst = tonumber(stats:get(CharacterStat.THIRST)) end
        if CharacterStat.UNHAPPINESS then unhappy = tonumber(stats:get(CharacterStat.UNHAPPINESS)) end
        if CharacterStat.BOREDOM then boredom = tonumber(stats:get(CharacterStat.BOREDOM)) end
        if CharacterStat.STRESS then stress = tonumber(stats:get(CharacterStat.STRESS)) end
        if CharacterStat.FOOD_SICKNESS then sick = tonumber(stats:get(CharacterStat.FOOD_SICKNESS)) end
        if CharacterStat.FATIGUE then fatigue = tonumber(stats:get(CharacterStat.FATIGUE)) end
        if CharacterStat.ENDURANCE then endurance = tonumber(stats:get(CharacterStat.ENDURANCE)) end
    end
    if nutrition then
        if nutrition.getCalories then calories = tonumber(nutrition:getCalories()) end
        if nutrition.getCarbohydrates then carbs = tonumber(nutrition:getCarbohydrates()) end
        if nutrition.getProteins then proteins = tonumber(nutrition:getProteins()) end
        if nutrition.getLipids then lipids = tonumber(nutrition:getLipids()) end
    end

    local function putStat(stat, before)
        if stat == nil then return end
        local now = tonumber(stats:get(stat))
        local updated
        if stat == CharacterStat.ENDURANCE then
            updated = scaleUp(before, now)
        else
            updated = scaleDown(before, now)
        end
        if updated ~= nil then stats:set(stat, updated) end
    end

    return function()
        if stats and CharacterStat then
            putStat(CharacterStat.HUNGER, hunger)
            putStat(CharacterStat.THIRST, thirst)
            putStat(CharacterStat.UNHAPPINESS, unhappy)
            putStat(CharacterStat.BOREDOM, boredom)
            putStat(CharacterStat.STRESS, stress)
            putStat(CharacterStat.FOOD_SICKNESS, sick)
            putStat(CharacterStat.FATIGUE, fatigue)
            putStat(CharacterStat.ENDURANCE, endurance)
        end
        if nutrition == nil then return end
        if nutrition.getCalories and nutrition.setCalories then
            local updated = scaleUp(calories, tonumber(nutrition:getCalories()))
            if updated ~= nil then nutrition:setCalories(updated) end
        end
        if nutrition.getCarbohydrates and nutrition.setCarbohydrates then
            local updated = scaleUp(carbs, tonumber(nutrition:getCarbohydrates()))
            if updated ~= nil then nutrition:setCarbohydrates(updated) end
        end
        if nutrition.getProteins and nutrition.setProteins then
            local updated = scaleUp(proteins, tonumber(nutrition:getProteins()))
            if updated ~= nil then nutrition:setProteins(updated) end
        end
        if nutrition.getLipids and nutrition.setLipids then
            local updated = scaleUp(lipids, tonumber(nutrition:getLipids()))
            if updated ~= nil then nutrition:setLipids(updated) end
        end
    end
end

local uiLedger = State.uiLedger

local function shouldScaleHideoutFood(character)
    return character ~= nil
        and Util.insideHideout(character)
        and Collections.completed(uiLedger(character), "specimen_cases")
end

local function wrapEatActions()
    if ISEatFoodAction == nil or ISEatFoodAction._refreshModWrapped then return end
    ISEatFoodAction._refreshModWrapped = true
    local originalComplete = ISEatFoodAction.complete
    if originalComplete then
        ISEatFoodAction.complete = function(self)
            if not shouldScaleHideoutFood(self.character) then
                return originalComplete(self)
            end
            local apply = beginFoodScale(self.character)
            local result = originalComplete(self)
            apply()
            return result
        end
    end
    local originalEat = ISEatFoodAction.eat
    if originalEat then
        ISEatFoodAction.eat = function(self, food, percentage)
            if not shouldScaleHideoutFood(self.character) then
                return originalEat(self, food, percentage)
            end
            local apply = beginFoodScale(self.character)
            local result = originalEat(self, food, percentage)
            apply()
            return result
        end
    end
end

local function wrapDrinkActions()
    if ISDrinkFluidAction == nil or ISDrinkFluidAction.updateEat == nil then return end
    if ISDrinkFluidAction._refreshModWrapped then return end
    ISDrinkFluidAction._refreshModWrapped = true
    local originalUpdate = ISDrinkFluidAction.updateEat
    function ISDrinkFluidAction:updateEat(delta)
        if not shouldScaleHideoutFood(self.character) then
            return originalUpdate(self, delta)
        end
        local apply = beginFoodScale(self.character)
        local result = originalUpdate(self, delta)
        apply()
        return result
    end
end

local lastTick = {}

function Bonuses.tickPlayer(player)
    if player == nil then return end
    local key = Util.username(player)
    local now = Util.worldHours()
    local previous = lastTick[key] or 0
    if now - previous < (2 / 3600) then return end
    lastTick[key] = now
    Bonuses.applyMoodles(player)
    freezeNewlyCompleted(player)
    lockUndoOutsideHideout(player)
end

local function formatTooltipAmount(amount)
    amount = tonumber(amount) or 0
    if math.abs(amount - math.floor(amount + 0.0001)) < 0.005 then
        return tostring(math.floor(amount + 0.0001))
    end
    if math.abs(amount * 10 - math.floor(amount * 10 + 0.0001)) < 0.05 then
        return string.format("%.1f", amount)
    end
    return string.format("%.2f", amount)
end

local function shouldShowExactItemValues(player)
    if player == nil then return false end
    if Util.insideHideout(player) then return true end
    return Collections.completed(uiLedger(player), "novelty_glasses")
end

local function appendRelevanceLines(lines, item, player)
    if item == nil or not Items or not Items.alternateUses then return end
    local uses = Items.alternateUses(item, player)
    if not uses or not uses.any then return end
    for _, name in ipairs(uses.upgrades or {}) do
        lines[#lines + 1] = getText("IGUI_ExtractionModeExpanded_TipUpgrade", name)
    end
    for _, name in ipairs(uses.quests or {}) do
        lines[#lines + 1] = getText("IGUI_ExtractionModeExpanded_TipQuest", name)
    end
    for _, name in ipairs(uses.refreshBulk or {}) do
        lines[#lines + 1] = getText("IGUI_ExtractionModeExpanded_TipRefreshSupply", name)
    end
    for _, name in ipairs(uses.refreshKey or {}) do
        lines[#lines + 1] = getText("IGUI_ExtractionModeExpanded_TipRefreshKey", name)
    end
    if #(uses.refreshKey or {}) == 0 and uses.refreshKeyHidden then
        lines[#lines + 1] = getText("IGUI_ExtractionModeExpanded_TipRefreshKeyHidden")
    end
end

local function appendValueLines(lines, item, player, ledger)
    local value = Items.valueOf(item, ledger) or 0
    local weapons = Items.weaponPointsOf(item, ledger) or 0
    local inHideout = player ~= nil and Util.insideHideout(player)

    if value > 0 and not inHideout then
        local tier = Items.valueTierLabel(value)
        if tier then
            lines[#lines + 1] = getText("IGUI_ExtractionModeExpanded_Value", tier)
        end
    end
    if not shouldShowExactItemValues(player) then return end
    if value > 0 then
        lines[#lines + 1] = getText("IGUI_ExtractionModeExpanded_Value", formatTooltipAmount(value))
    end
    if weapons > 0 then
        lines[#lines + 1] = getText("IGUI_ExtractionModeExpanded_Weapons", formatTooltipAmount(weapons))
    end
end

local function wrapTooltip()
    if ISToolTipInv == nil or ISToolTipInv._refreshModWrapped then return end
    ISToolTipInv._refreshModWrapped = true
    local original = ISToolTipInv.render
    if original == nil then return end
    ISToolTipInv.render = function(self)
        original(self)
        local item = self.item
        if item == nil then return end
        local ClientOptions = RefreshMod.ClientOptions
        if ClientOptions and ClientOptions.hideFavoriteItemDetails() and Items.isFavorite(item) then
            return
        end
        local lines = {}
        local player = nil
        local container = item:getContainer()
        local parent = container and container:getParent() or nil
        if parent and instanceof(parent, "IsoPlayer") then
            player = parent
        end
        player = player or Util.localPlayer(0)
        local ledger = uiLedger(player)
        local exactValues = shouldShowExactItemValues(player)
        local matches = Collections.lookupMatches(item, ledger)
        if matches == nil then
            local one = Collections.lookupItem(item, ledger)
            matches = one and { one } or nil
        end
        if matches and #matches > 0 then
            for _, collectionInfo in ipairs(matches) do
                if collectionInfo.collection then
                    lines[#lines + 1] = getText(
                        "IGUI_ExtractionModeExpanded_CollectionProgress",
                        tostring(collectionInfo.collection.name),
                        tostring(collectionInfo.count),
                        tostring(collectionInfo.slots))
                    if collectionInfo.registered then
                        lines[#lines + 1] = getText("IGUI_ExtractionModeExpanded_AlreadyRegistered")
                    else
                        lines[#lines + 1] = getText("IGUI_ExtractionModeExpanded_Unregistered")
                    end
                end
            end
        else
            local key, name = Items.registeredCollection(item)
            if key then
                lines[#lines + 1] = getText("IGUI_ExtractionModeExpanded_Registered", tostring(name))
            end
        end
        local tier, trophy = Config.trophyTier(Util.fullType(item))
        if trophy then
            local tierName = tostring(tier or "trophy")
            tierName = tierName:sub(1, 1):upper() .. tierName:sub(2)
            if exactValues then
                local sellValue = Items.valueOf(item, ledger)
                lines[#lines + 1] = getText(
                    "IGUI_ExtractionModeExpanded_TrophyTip",
                    tierName,
                    formatTooltipAmount(sellValue),
                    formatTooltipAmount(tonumber(trophy.excessRelief) or 0))
            else
                lines[#lines + 1] = getText("IGUI_ExtractionModeExpanded_TrophyTipRaid", tierName)
            end
        end
        appendRelevanceLines(lines, item, player)
        appendValueLines(lines, item, player, ledger)
        if #lines == 0 then return end
        local lineH = 16
        local add = #lines * lineH + 6

        local baseH = self.height
        if self.tooltip then
            local measured = tonumber(self.tooltip:getHeight())
            if measured and measured > 0 then baseH = measured end
        end
        local textW = self.width
        if getTextManager then
            for _, text in ipairs(lines) do
                textW = math.max(textW, getTextManager():MeasureStringX(UIFont.Small, tostring(text)) + 10)
            end
        end
        local bg = self.backgroundColor or { r = 0, g = 0, b = 0, a = 0.8 }
        self:setWidth(math.max(self.width, textW))
        self:setHeight(baseH + add)
        self:drawRect(0, baseH - 1, self.width, add + 1, bg.a or 0.8, bg.r or 0, bg.g or 0, bg.b or 0)
        for index, text in ipairs(lines) do
            self:drawText(text, 5, baseH + (index - 1) * lineH, 0.96, 0.72, 0.18, 1, UIFont.Small)
        end
    end
end

local function wrapReadDuration()
    if ISReadABook == nil or ISReadABook._refreshModDurationWrapped then return end
    ISReadABook._refreshModDurationWrapped = true
    local original = ISReadABook.getDuration
    if original == nil then return end
    ISReadABook.getDuration = function(self)
        local time = original(self)
        local player = self.character
        if player == nil or not Util.insideHideout(player) then return time end

        if not Collections.completed(uiLedger(player), "book_subjects") then return time end
        return math.max(1, math.floor((tonumber(time) or 1) * 0.1))
    end
end

local function wrapContainerOpen()
    if ISInventoryPage == nil or ISInventoryPage._refreshModSpiffo then return end
    if ISInventoryPage.setNewContainer == nil then return end
    ISInventoryPage._refreshModSpiffo = true
    local original = ISInventoryPage.setNewContainer
    function ISInventoryPage:setNewContainer(inventory)
        original(self, inventory)
        local player = self.player ~= nil and getSpecificPlayer(self.player) or Util.localPlayer(0)
        if player == nil or inventory == nil then return end
        if not Collections.completed(uiLedger(player), "spiffo_superfan") then return end
        freshenContainer(inventory, player)
        local parent = inventory:getParent()
        local square = parent and parent:getSquare() or nil
        if square and RefreshMod.Client and RefreshMod.Client.send then
            RefreshMod.Client.send(player, "FreshenSpiffo", {
                x = square:getX(),
                y = square:getY(),
                z = square:getZ(),
            })
        end
    end
end

local function wrapTransfer()
    if ISTransferAction == nil or ISTransferAction._refreshModSpiffo then return end
    if ISTransferAction.transferItem == nil then return end
    ISTransferAction._refreshModSpiffo = true
    local original = ISTransferAction.transferItem
    function ISTransferAction:transferItem(character, item, srcContainer, destContainer, dropSquare)
        local result = original(self, character, item, srcContainer, destContainer, dropSquare)
        if character and Collections.completedForPlayer(character, "spiffo_superfan") then
            freezeItemTree(item, 0, character)
        end
        return result
    end
end

local function onInventoryWindowRefresh(page)
    if page == nil then return end
    local player = getSpecificPlayer and page.player ~= nil and getSpecificPlayer(page.player) or nil
    if player then Bonuses.freezePlayerInventory(player) end
end

function Bonuses.install()
    wrapTooltip()
    wrapEatActions()
    wrapDrinkActions()
    wrapReadDuration()
    wrapContainerOpen()
    wrapTransfer()
    Bonuses.installXpTriggers()
    if Events and Events.OnRefreshInventoryWindowContainers and Events.OnRefreshInventoryWindowContainers.Add
        and not Bonuses._inventoryRefresh then
        Bonuses._inventoryRefresh = true
        Events.OnRefreshInventoryWindowContainers.Add(function(page, state)
            if state ~= "end" then return end
            onInventoryWindowRefresh(page)
        end)
    end
end

Bonuses.installXpTriggers()

if Events and Events.OnPlayerUpdate then
    Events.OnPlayerUpdate.Add(function(player)

        if Util.isRemoteClient() then return end
        Bonuses.tickPlayer(player)
    end)
end

return Bonuses
