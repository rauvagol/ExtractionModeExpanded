require "RefreshMod/Config"
require "RefreshMod/Util"

RefreshMod = RefreshMod or {}
local Config = RefreshMod.Config
local Util = RefreshMod.Util
local Multiplier = {}
RefreshMod.MultiplierLogic = Multiplier

local function collectionDone(ledger, key)
    local Logic = RefreshMod.CollectionsLogic
    return Logic ~= nil and Logic.completed(ledger, key)
end

function Multiplier.excess(ledger, areaKey)
    if ledger == nil then return 0 end
    return math.max(0, ledger.excess[areaKey] or 0)
end

function Multiplier.M(ledger, areaKey)
    return math.max(1, 1 + Multiplier.excess(ledger, areaKey))
end

function Multiplier.K(ledger, areaKey)
    local step = tonumber(Config.value("keyItemStep")) or Config.multiplier().keyItemStep or 3
    if step < 1 then step = 1 end
    local m = Multiplier.M(ledger, areaKey)
    return 1 + math.floor((m - 1) / step)
end

-- only affects increase rate, not base costs
function Multiplier.homeTheaterGrowth(multiplier, ledger)
    multiplier = tonumber(multiplier) or 1
    if collectionDone(ledger, "home_theater") then
        return multiplier * 0.5
    end
    return multiplier
end

function Multiplier.effectiveM(ledger, areaKey, channel)
    local m = Multiplier.M(ledger, areaKey)
    if channel == "value" and collectionDone(ledger, "media_library") then
        m = m * 0.5
    elseif channel == "weapons" and collectionDone(ledger, "comic_book_guy") then
        m = m * 0.5
    elseif channel == "items" then
        m = Multiplier.homeTheaterGrowth(m, ledger)
    end
    return m
end

function Multiplier.applyRefresh(ledger, areaKey)
    local penalty = tonumber(Config.value("penaltyPerRefresh")) or 1
    local decay = tonumber(Config.value("decayPerOtherRefresh")) or (1 / 15)
    ledger.excess[areaKey] = Multiplier.excess(ledger, areaKey) + penalty
    for _, area in ipairs(Config.areas()) do
        if area.key ~= areaKey then
            ledger.excess[area.key] = math.max(0, Multiplier.excess(ledger, area.key) - decay)
        end
    end
end

function Multiplier.spend(ledger, areaKey, relief)
    relief = tonumber(relief) or 0
    local current = Multiplier.excess(ledger, areaKey)
    local used = math.min(current, relief)
    ledger.excess[areaKey] = math.max(0, current - relief)
    return used, relief - used
end

function Multiplier.valueCost(ledger, area)
    local scale = tonumber(Config.value("costScale")) or 1
    local discount = 1
    if collectionDone(ledger, "portraits") then
        discount = 0.85
    end
    local raw = (tonumber(area.valueCost) or 0)
        * Multiplier.effectiveM(ledger, area.key, "value")
        * scale
        * discount
    return Util.roundCost(raw)
end

function Multiplier.weaponCost(ledger, area)
    local scale = tonumber(Config.value("weaponScale")) or 1
    local discount = 1
    if collectionDone(ledger, "gang_jackets") then
        discount = 0.85
    end
    local raw = (tonumber(area.weaponPoints) or 0)
        * Multiplier.effectiveM(ledger, area.key, "weapons")
        * scale
        * discount
    return Util.roundCost(raw)
end

function Multiplier.lineNeed(ledger, area, line)
    if line == nil then return 0, 0 end
    local amount = tonumber(line.amount) or 0
    local altAmount = line.alt and (tonumber(line.alt.amount) or 0) or 0
    local itemMult
    if line.tier == "bulk" then
        itemMult = Multiplier.effectiveM(ledger, area.key, "items")
    else
        itemMult = Multiplier.homeTheaterGrowth(Multiplier.K(ledger, area.key), ledger)
    end
    return Util.scaleAmount(amount, itemMult), Util.scaleAmount(altAmount, itemMult)
end

return Multiplier
