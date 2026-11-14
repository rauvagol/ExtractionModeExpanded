RefreshMod = RefreshMod or {}

local Config = {}
RefreshMod.Config = Config
RefreshMod.COMMAND_MODULE = "ExtractionModeExpanded"

RefreshMod.DATA_KEY = "ExtractionModeExpanded.State"
Config.DATA_KEY = RefreshMod.DATA_KEY
Config.BACKUP_DATA_KEY = "ExtractionModeExpanded.StateBackup"

Config.defaults = {
    costScale = 1.0,
    weaponScale = 1.0,
    penaltyPerRefresh = 1.0,
    decayPerOtherRefresh = 1 / 15,
    keyItemStep = 3,
    resetVehicles = true,
    resetGasPumps = true,
}

Config.REFRESH_TOWNS = {
    louisville = { "louisville", "grand_ohio_mall" },
    rosewood = { "rosewood", "knox_penitentiary" },
}

Config.OVERLAP_PAIRS = {
    { "brandenburg", "sunderland_hills_sanatorium" },
    { "brandenburg", "the_boonies" },
    { "louisville_checkpoint", "valley_station_crossroads_mall" },
    { "valley_station_crossroads_mall", "west_point" },
}

Config.SPIFFO_FOOD = {
    ["Base.Burger"] = true,
    ["Base.BurgerRecipe"] = true,
    ["Base.Fries"] = true,
    ["Base.FrenchFries"] = true,
    ["Base.Frozen_FrenchFries"] = true,
}

Config.VALUE_TIER_BOUNDS = { 1, 5, 12 }
Config.VALUE_TIER_KEYS = { "low", "medium", "high", "extreme" }

Config.REGISTER_FLAG = "RefreshModRegistered"

function Config.value(key)
    local section = SandboxVars and SandboxVars.ExtractionModeExpanded
    local value = section and section[key]
    if value == nil then
        return Config.defaults[key]
    end
    if key == "decayPerOtherRefresh" then
        local number = tonumber(value)

        if number == nil or math.abs(number - (1 / 15)) < 0.00005 then
            return 1 / 15
        end
    end
    return value
end

function Config.area(key)
    key = tostring(key or "")
    for _, area in ipairs(RefreshMod.Areas or {}) do
        if area.key == key then return area end
    end
end

function Config.areas()
    return RefreshMod.Areas or {}
end

function Config.townsForArea(key)
    return Config.REFRESH_TOWNS[key] or { key }
end

function Config.areaForTown(townKey)
    townKey = tostring(townKey or "")
    for areaKey, towns in pairs(Config.REFRESH_TOWNS) do
        for _, town in ipairs(towns) do
            if town == townKey then return areaKey end
        end
    end
    if Config.area(townKey) then return townKey end
end

function Config.collection(key)
    for _, collection in ipairs(RefreshMod.Collections or {}) do
        if collection.key == key then return collection end
    end
end

function Config.collections()
    return RefreshMod.Collections or {}
end

function Config.trophyTier(fullType)
    local trophies = RefreshMod.Trophies or {}
    for tier, data in pairs(trophies) do
        for _, itemType in ipairs(data.items or {}) do
            if itemType == fullType then return tier, data end
        end
    end
end

Config.TROPHY_TOKEN_KEY = {
    uncommon = "small",
    rare = "medium",
    legendary = "large",
}
Config.TOKEN_RELIEF = {
    small = 0.25,
    medium = 0.5,
    large = 1.0,
}
Config.TOKEN_ORDER = { "large", "medium", "small" }

function Config.trophyTokenKey(tier)
    return Config.TROPHY_TOKEN_KEY[tostring(tier or "")]
end

function Config.tokenRelief(tokenKey)
    return tonumber(Config.TOKEN_RELIEF[tostring(tokenKey or "")]) or 0
end

function Config.trophies()
    return RefreshMod.Trophies or {}
end

function Config.multiplier()
    return RefreshMod.Multiplier or {
        penaltyPerRefresh = 1.0,
        decayPerOtherRefresh = 1 / 15,
        floor = 1.0,
        keyItemStep = 3,
    }
end

function Config.overlaps(a, b)
    if a == b then return true end
    local townsA = Config.townsForArea(a)
    local townsB = Config.townsForArea(b)
    for _, left in ipairs(townsA) do
        for _, right in ipairs(townsB) do
            if left == right then return true end
        end
    end
    for _, pair in ipairs(Config.OVERLAP_PAIRS) do
        if (pair[1] == a and pair[2] == b) or (pair[1] == b and pair[2] == a) then
            return true
        end
        for _, left in ipairs(townsA) do
            for _, right in ipairs(townsB) do
                if (pair[1] == left and pair[2] == right) or (pair[1] == right and pair[2] == left) then
                    return true
                end
            end
        end
    end
    return false
end

function Config.emTown(key)
    local em = ExtractionMode and ExtractionMode.Config
    if em and em.town then return em.town(key) end
end

function Config.questCompleted(completions, questId)
    if questId == nil then return true end
    if type(completions) ~= "table" then return false end
    if completions[questId] == true then return true end
    local Quests = ExtractionMode and ExtractionMode.Quests
    if Quests and Quests.isCompleted then
        return Quests.isCompleted(completions, questId) == true
    end
    return false
end

function Config.areaUnlocked(areaKey, completions)
    local em = ExtractionMode and ExtractionMode.Config
    for _, townKey in ipairs(Config.townsForArea(areaKey)) do
        local town = em and em.town and em.town(townKey)
        if town ~= nil then
            if town.unlockQuestId == nil then
                return true
            elseif Config.questCompleted(completions, town.unlockQuestId) then
                return true
            end
        end
    end
    return false
end

function Config.forceLocationRefreshSandbox()

end

return Config
