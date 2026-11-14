require "RefreshMod/Config"
require "RefreshMod/Util"
require "RefreshMod/Items"
require "RefreshMod/State"
require "RefreshMod/Multiplier"

RefreshMod = RefreshMod or {}
local Config = RefreshMod.Config
local Util = RefreshMod.Util
local Items = RefreshMod.Items
local State = RefreshMod.State
local Multiplier = RefreshMod.MultiplierLogic
local Banks = {}
RefreshMod.Banks = Banks

local function countTypes(bag, types)
    local total = 0
    for _, fullType in ipairs(types or {}) do
        total = total + math.max(0, bag[fullType] or 0)
    end
    return total
end

function Banks.addType(bag, fullType, amount)
    bag[fullType] = (bag[fullType] or 0) + amount
    if bag[fullType] <= 0 then bag[fullType] = nil end
end

function Banks.lineProgress(ledger, line)
    if line == nil then return 0, 0 end
    local primary = countTypes(line.tier == "bulk" and ledger.bulk or ledger.keyItems, line.types)
    local alt = 0
    if line.alt then
        alt = countTypes(line.tier == "bulk" and ledger.bulk or ledger.keyItems, line.alt.types)
    end
    return primary, alt
end

local function consumeTypes(bag, types, need)
    local remaining = need
    for _, fullType in ipairs(types or {}) do
        local have = bag[fullType] or 0
        if have > 0 and remaining > 0 then
            local take = math.min(have, remaining)
            Banks.addType(bag, fullType, -take)
            remaining = remaining - take
        end
    end
    return remaining <= 0
end

local function eachReady(bag, types, perType)
    if types == nil or #types == 0 then return false, 0, 0 end
    local filled = 0
    for _, fullType in ipairs(types) do
        if (bag[fullType] or 0) >= perType then
            filled = filled + 1
        end
    end
    return filled >= #types, filled, #types
end

local function consumeEach(bag, types, perType)
    for _, fullType in ipairs(types or {}) do
        Banks.addType(bag, fullType, -perType)
    end
end

function Banks.questCoverage(ledger, area)
    local bulk = {}
    local keys = {}
    for fullType, count in pairs(ledger and ledger.bulk or {}) do
        bulk[fullType] = count or 0
    end
    for fullType, count in pairs(ledger and ledger.keyItems or {}) do
        keys[fullType] = count or 0
    end
    local rows = {}
    local ready = area ~= nil and ledger ~= nil
    if not ready then return rows, false end
    for _, line in ipairs(area.quest or {}) do
        local need, altNeed = Multiplier.lineNeed(ledger, area, line)
        local bag = line.tier == "bulk" and bulk or keys
        local have = countTypes(bag, line.types)
        local each = line.alt ~= nil and line.alt.each
        local altHave = 0
        local havePieces, pieceCount = 0, 0
        local altOk = false
        if each then
            altOk, havePieces, pieceCount = eachReady(bag, line.alt.types, altNeed)
        elseif line.alt then
            altHave = countTypes(bag, line.alt.types)
            altOk = altNeed > 0 and altHave >= altNeed
        end
        local primary = have >= need
        local alt = altOk
        local funded = primary or alt
        if not funded then ready = false end
        if primary then
            consumeTypes(bag, line.types, need)
        elseif alt and each then
            consumeEach(bag, line.alt.types, altNeed)
        elseif alt then
            consumeTypes(bag, line.alt.types, altNeed)
        end
        rows[#rows + 1] = {
            line = line,
            tier = line.tier,
            need = need,
            altNeed = altNeed,
            have = have,
            altHave = each and havePieces or altHave,
            pieceCount = pieceCount,
            each = each,
            perType = each and altNeed or nil,
            primary = primary,
            alt = alt,
            funded = funded,
        }
    end
    return rows, ready
end

function Banks.lineSatisfied(ledger, area, line)
    local rows = Banks.questCoverage(ledger, area)
    for _, row in ipairs(rows) do
        if row.line == line then return row.funded end
    end
    return false
end

function Banks.materialsReady(ledger, area)
    if area == nil or ledger == nil then return false end
    if ledger.value + 0.0001 < Multiplier.valueCost(ledger, area) then return false end
    if ledger.weapons + 0.0001 < Multiplier.weaponCost(ledger, area) then return false end
    local _, ready = Banks.questCoverage(ledger, area)
    return ready
end

function Banks.homeTheaterOwned(ledger)
    local Logic = RefreshMod.CollectionsLogic
    return Logic ~= nil and Logic.completed(ledger, "home_theater")
end

function Banks.homeTheaterFreeAvailable(ledger)
    if ledger == nil or not Banks.homeTheaterOwned(ledger) then return false end
    local period = Util.sundayPeriodId()
    return ledger.homeTheaterFreeWeek ~= period
end

function Banks.homeTheaterFreeStatus(ledger)
    if not Banks.homeTheaterOwned(ledger) then
        return { owned = false, available = false, label = nil }
    end
    if Banks.homeTheaterFreeAvailable(ledger) then
        return { owned = true, available = true, label = getText("IGUI_ExtractionModeExpanded_HomeTheaterFree") }
    end
    return {
        owned = true,
        available = false,
        label = getText("IGUI_ExtractionModeExpanded_HomeTheaterNext", Util.nextSundayMidnightLabel()),
    }
end

function Banks.consumeHomeTheaterFree(ledger)
    if ledger == nil then return end
    ledger.homeTheaterFreeWeek = Util.sundayPeriodId()
end

function Banks.areaReady(ledger, area, useFree)
    if area == nil then return false end
    if useFree then
        return Banks.homeTheaterFreeAvailable(ledger)
    end
    return Banks.materialsReady(ledger, area)
end

function Banks.spendRefresh(ledger, area, useFree)

    if useFree then
        if not Banks.homeTheaterFreeAvailable(ledger) then return false, false end
        Banks.consumeHomeTheaterFree(ledger)
        return true, true
    end
    local rows, ready = Banks.questCoverage(ledger, area)
    if not ready then return false, false end
    ledger.value = ledger.value - Multiplier.valueCost(ledger, area)
    ledger.weapons = ledger.weapons - Multiplier.weaponCost(ledger, area)
    for _, row in ipairs(rows) do
        local bag = row.tier == "bulk" and ledger.bulk or ledger.keyItems
        if row.primary then
            consumeTypes(bag, row.line.types, row.need)
        elseif row.each and row.line.alt then
            consumeEach(bag, row.line.alt.types, row.perType or row.altNeed)
        elseif row.alt and row.line.alt then
            consumeTypes(bag, row.line.alt.types, row.altNeed)
        end
    end
    return true, false
end

local function takeFromItem(item, quantity)
    quantity = math.max(1, math.floor(tonumber(quantity) or 1))
    local count = Util.itemCount(item)
    local taken = math.min(count, quantity)
    if taken <= 0 then return 0 end
    if taken >= count then
        if not Util.removeItem(item) then return 0 end
    elseif not Util.setItemCount(item, count - taken) then
        return 0
    end
    return taken
end

local function captureModData(item)
    local data = {}
    local modData = item and item.getModData and item:getModData()
    if type(modData) ~= "table" then return data end
    for key, value in pairs(modData) do
        if type(value) ~= "table" then data[key] = value end
    end
    return data
end

local function snapshotItem(item, quantity)
    local snap = {
        fullType = Util.fullType(item),
        quantity = math.max(1, math.floor(tonumber(quantity) or 1)),
        itemId = Util.itemId(item),
        condition = nil,
        favorite = false,
        worldSprite = nil,
        weight = nil,
        modData = captureModData(item),
    }
    if item.getCondition then snap.condition = item:getCondition() end
    if item:isFavorite() then snap.favorite = true end
    if Items and Items.worldSpriteOf then
        snap.worldSprite = Items.worldSpriteOf(item)
    elseif item.getWorldSprite then
        local sprite = item:getWorldSprite()
        if sprite and tostring(sprite) ~= "" then snap.worldSprite = tostring(sprite) end
    end
    if item.getActualWeight then snap.weight = item:getActualWeight() end
    return snap
end

function Banks.sell(player, selections)
    if not Util.insideHideout(player) then return false, "hideout only" end
    local ledger = State.ledger(player)
    local gained = 0
    for _, entry in ipairs(selections or {}) do
        local item = entry.item
        local reason = Items.bankRejectReason(item, player)
        if reason then return false, reason end
        local unit = Items.valueOf(item, ledger)
        if unit > 0 then
            local taken = takeFromItem(item, entry.quantity)
            gained = gained + unit * taken
        end
    end
    ledger.value = ledger.value + gained
    return true, gained
end

function Banks.deposit(player, kind, selections)
    if not Util.insideHideout(player) then return false, "hideout only" end
    if kind ~= "value" and kind ~= "weapons" and kind ~= "bulk" and kind ~= "key" then
        return false, "unknown action"
    end
    local ledger = State.ledger(player)
    local plan = {}
    local reserved = {}
    for _, entry in ipairs(selections or {}) do
        local item = entry.item
        if item == nil then return false, "missing item" end
        local reason = Items.bankRejectReason(item, player)
        if reason then return false, reason end
        local quantity = math.max(1, math.floor(tonumber(entry.quantity) or 1))
        local reserveKey = Util.itemId(item) or item
        local claimed = (reserved[reserveKey] or 0) + quantity
        if Util.itemCount(item) < claimed then return false, "not enough" end
        reserved[reserveKey] = claimed
        if kind == "value" then
            local unit = Items.valueOf(item, ledger)
            if unit <= 0 then return false, "unknown item" end
            plan[#plan + 1] = { item = item, quantity = quantity, unit = unit }
        elseif kind == "weapons" then
            local unit = Items.weaponPointsOf(item)
            if unit <= 0 then return false, "not a weapon" end
            plan[#plan + 1] = { item = item, quantity = quantity, unit = unit }
        else
            if not Items.matchesBankKind(item, kind) then
                return false, kind == "bulk" and "not a supply item" or "not a key item"
            end
            plan[#plan + 1] = {
                item = item,
                quantity = quantity,
                fullType = Util.fullType(item),
            }
        end
    end
    local gained = 0
    local undos = {}
    for _, step in ipairs(plan) do
        local count = Util.itemCount(step.item)
        local snap = snapshotItem(step.item, math.min(step.quantity, count))
        local taken = takeFromItem(step.item, step.quantity)
        if taken <= 0 then
            for index = #undos, 1, -1 do
                Banks.undoDeposit(player, undos[index])
            end
            return false, "could not remove item"
        end
        snap.quantity = taken
        if kind == "value" or kind == "weapons" then
            local amount = step.unit * taken
            gained = gained + amount
            if kind == "value" then
                ledger.value = ledger.value + amount
            else
                ledger.weapons = ledger.weapons + amount
            end
            undos[#undos + 1] = { kind = kind, amount = amount, item = snap }
        else
            local bag = kind == "bulk" and ledger.bulk or ledger.keyItems
            Banks.addType(bag, step.fullType, taken)
            gained = gained + taken
            undos[#undos + 1] = { kind = kind, amount = taken, item = snap, fullType = step.fullType }
        end
    end
    return true, gained, undos
end

function Banks.undoDeposit(player, entry)
    if not Util.insideHideout(player) then return false, "hideout only" end
    if type(entry) ~= "table" then return false, "missing undo" end
    local ledger = State.ledger(player)
    local kind = entry.kind
    local amount = tonumber(entry.amount) or 0
    local fullType = entry.fullType or (entry.item and entry.item.fullType)
    local qty = math.max(1, math.floor(tonumber(entry.item and entry.item.quantity) or amount or 1))
    if kind == "value" then
        if ledger.value + 0.0001 < amount then
            return false, "already spent"
        end
    elseif kind == "weapons" then
        if ledger.weapons + 0.0001 < amount then
            return false, "already spent"
        end
    elseif kind == "bulk" or kind == "key" then
        local bag = kind == "bulk" and ledger.bulk or ledger.keyItems
        if fullType == nil then return false, "missing type" end
        if (bag[fullType] or 0) < qty then
            return false, "already spent"
        end
    else
        return false, "unknown action"
    end
    if entry.item then
        local restored = Util.restoreBankedItem(player, entry.item)
        if restored == nil then return false, "could not restore item" end
    end
    if kind == "value" then
        ledger.value = ledger.value - amount
    elseif kind == "weapons" then
        ledger.weapons = ledger.weapons - amount
    elseif kind == "bulk" or kind == "key" then
        local bag = kind == "bulk" and ledger.bulk or ledger.keyItems
        Banks.addType(bag, fullType, -qty)
    end
    return true
end

function Banks.sellTrophy(player, item)
    if not Util.insideHideout(player) then return false, "hideout only" end
    local ledger = State.ledger(player)
    local reason = Items.bankRejectReason(item, player)
    if reason then return false, reason end
    local fullType = Util.fullType(item)
    local tier, trophy = Config.trophyTier(fullType)
    if trophy == nil then return false, "not a trophy" end
    local value = Items.valueOf(item, ledger)
    if not Util.removeItem(item) then return false, "could not remove item" end
    ledger.value = ledger.value + value
    return true, value, tier
end

function Banks.bankTrophy(player, item)
    if not Util.insideHideout(player) then return false, "hideout only" end
    local ledger = State.ledger(player)
    local reason = Items.bankRejectReason(item, player)
    if reason then return false, reason end
    local fullType = Util.fullType(item)
    local tier, trophy = Config.trophyTier(fullType)
    if trophy == nil then return false, "not a trophy" end
    local tokenKey = Config.trophyTokenKey(tier)
    if tokenKey == nil then return false, "unknown trophy tier" end
    if not Util.removeItem(item) then return false, "could not remove item" end
    ledger.reliefTokens = ledger.reliefTokens or { small = 0, medium = 0, large = 0 }
    ledger.reliefTokens[tokenKey] = math.max(0, math.floor(tonumber(ledger.reliefTokens[tokenKey]) or 0)) + 1
    return true, tokenKey, tier
end

local function tokenTotalRelief(tokens)
    tokens = tokens or {}
    local total = 0
    for _, key in ipairs(Config.TOKEN_ORDER or { "large", "medium", "small" }) do
        total = total + (math.max(0, math.floor(tonumber(tokens[key]) or 0)) * Config.tokenRelief(key))
    end
    return total
end

local function consumeTokensForRelief(tokens, amount)
    amount = tonumber(amount) or 0
    local used = 0
    local spent = { small = 0, medium = 0, large = 0 }
    if amount <= 0 then return used, spent end
    for _, key in ipairs(Config.TOKEN_ORDER or { "large", "medium", "small" }) do
        local unit = Config.tokenRelief(key)
        if unit > 0 then
            while (tonumber(tokens[key]) or 0) > 0 and used + unit <= amount + 0.0001 do
                tokens[key] = (tonumber(tokens[key]) or 0) - 1
                spent[key] = spent[key] + 1
                used = used + unit
            end
        end
    end

    if used + 0.0001 < amount then
        for _, key in ipairs({ "small", "medium", "large" }) do
            local unit = Config.tokenRelief(key)
            if unit > 0 and (tonumber(tokens[key]) or 0) > 0 and used + 0.0001 < amount then
                tokens[key] = (tonumber(tokens[key]) or 0) - 1
                spent[key] = spent[key] + 1
                used = used + unit
                break
            end
        end
    end
    return used, spent
end

function Banks.previewReliefTokens(ledger, areaKey)
    if ledger == nil or Config.area(areaKey) == nil then return nil, "unknown area" end
    local excess = Multiplier.excess(ledger, areaKey)
    if excess <= 0 then return nil, "no excess" end
    local source = ledger.reliefTokens or {}
    local tokens = {
        small = math.max(0, math.floor(tonumber(source.small) or 0)),
        medium = math.max(0, math.floor(tonumber(source.medium) or 0)),
        large = math.max(0, math.floor(tonumber(source.large) or 0)),
    }
    local have = tokenTotalRelief(tokens)
    if have <= 0 then return nil, "no relief tokens" end
    local amount = math.min(have, excess)
    local applied, spent = consumeTokensForRelief(tokens, amount)
    if applied <= 0 then return nil, "no relief tokens" end
    local used = math.min(excess, applied)
    return {
        applied = applied,
        used = used,
        wasted = math.max(0, applied - used),
        spent = spent,
        excess = excess,
        after = math.max(0, excess - applied),
    }
end

function Banks.applyReliefTokens(player, areaKey, amount)
    if not Util.insideHideout(player) then return false, "hideout only" end
    local ledger = State.ledger(player)
    if Config.area(areaKey) == nil then return false, "unknown area" end
    ledger.reliefTokens = ledger.reliefTokens or { small = 0, medium = 0, large = 0 }
    local have = tokenTotalRelief(ledger.reliefTokens)
    if have <= 0 then return false, "no relief tokens" end
    local excess = Multiplier.excess(ledger, areaKey)
    if excess <= 0 then return false, "no excess" end
    amount = tonumber(amount)
    if amount == nil or amount <= 0 then amount = math.min(have, excess) end
    amount = math.min(have, excess, amount)
    local applied, spent = consumeTokensForRelief(ledger.reliefTokens, amount)
    if applied <= 0 then return false, "no relief tokens" end
    local used, wasted = Multiplier.spend(ledger, areaKey, applied)
    return true, used, wasted, spent
end

function Banks.spendTrophy(player, item, areaKey)
    if not Util.insideHideout(player) then return false, "hideout only" end
    local ledger = State.ledger(player)
    local reason = Items.bankRejectReason(item, player)
    if reason then return false, reason end
    local fullType = Util.fullType(item)
    local tier, trophy = Config.trophyTier(fullType)
    if trophy == nil then return false, "not a trophy" end
    if Config.area(areaKey) == nil then return false, "unknown area" end
    if not Util.removeItem(item) then return false, "could not remove item" end
    local used, wasted = Multiplier.spend(ledger, areaKey, tonumber(trophy.excessRelief) or 0)
    return true, used, wasted, tier
end

return Banks
