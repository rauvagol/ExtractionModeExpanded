require "RefreshMod/Config"
require "RefreshMod/Util"
require "RefreshMod/State"
require "RefreshMod/Banks"
require "RefreshMod/Multiplier"

RefreshMod = RefreshMod or {}
local Config = RefreshMod.Config
local Util = RefreshMod.Util
local State = RefreshMod.State
local Banks = RefreshMod.Banks
local Multiplier = RefreshMod.MultiplierLogic
local Refresh = {}
RefreshMod.Refresh = Refresh

local uiLocked = false

function Refresh.uiLocked()
    return uiLocked
end

function Refresh.setUiLocked(value)
    uiLocked = value == true
end

local function townOccupied(townKey)
    local em = ExtractionMode
    local Runtime = em and em.RaidRuntime
    if Runtime and Runtime.getRootStore then
        local store = Runtime.getRootStore()
        for _, raid in pairs((store and store.raids) or {}) do
            if Runtime.isActiveRaid and Runtime.isActiveRaid(raid) then
                local selected = raid.selectedTownKey
                local area = Config.areaForTown(selected) or selected
                if Config.overlaps(Config.areaForTown(townKey) or townKey, area) then
                    return true
                end
                for _, member in ipairs(Config.townsForArea(Config.areaForTown(townKey) or townKey)) do
                    if member == selected then return true end
                end
            end
        end
    end
    local emConfig = em and em.Config
    local areaKey = Config.areaForTown(townKey) or townKey
    local watched = { areaKey }
    for _, pair in ipairs(Config.OVERLAP_PAIRS) do
        if pair[1] == areaKey then watched[#watched + 1] = pair[2]
        elseif pair[2] == areaKey then watched[#watched + 1] = pair[1]
        end
    end
    for _, player in ipairs(Util.players()) do
        if player and not player:isDead() then
            local x, y = player:getX(), player:getY()
            for _, watchedKey in ipairs(watched) do
                for _, member in ipairs(Config.townsForArea(watchedKey)) do
                    if emConfig and emConfig.pointInsideRaidBounds
                        and emConfig.pointInsideRaidBounds(member, { x = x, y = y }) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

function Refresh.blockedReason(areaKey)
    local area = Config.area(areaKey)
    if area == nil then return "unknown area" end

    if townOccupied(areaKey) then
        return "Someone is deployed in this area or an overlapping area."
    end
    return nil
end

local function locationRefresh()
    return ExtractionMode and ExtractionMode.LocationRefresh
end

local regionLookup = false

local function regionRecord(townKey)
    local RefreshApi = locationRefresh()
    local Runtime = ExtractionMode and ExtractionMode.RaidRuntime
    if RefreshApi == nil or Runtime == nil then return nil end
    regionLookup = true
    local ok, status = pcall(function()
        RefreshApi.bind(Runtime.getRootStore())
        return RefreshApi.status(townKey)
    end)
    regionLookup = false
    if not ok or status == nil or status.region == nil then return nil end
    local store = Runtime.getRootStore()
    local regions = store.locationRefresh and store.locationRefresh.regions
    return regions and regions[status.region] or nil
end

local function markRegionPending(townKey)
    local record = regionRecord(townKey)
    if record == nil then return false end
    record.pending = true
    record.refreshModPaid = true
    return true
end

function Refresh.execute(player, areaKey, useFree)
    if not Util.insideHideout(player) then return false, "hideout only" end
    local area = Config.area(areaKey)
    if area == nil then return false, "unknown area" end
    local blocked = Refresh.blockedReason(areaKey)
    if blocked then return false, blocked end
    local ledger = State.ledger(player)
    if not Config.areaUnlocked(areaKey, State.completions(player)) then
        return false, "This area is still locked."
    end
    if not Banks.areaReady(ledger, area, useFree) then
        return false, useFree and "free refresh unavailable" or "requirements not met"
    end
    local towns = Config.townsForArea(areaKey)
    for _, townKey in ipairs(towns) do
        if regionRecord(townKey) == nil then
            return false, "area cannot be refreshed"
        end
    end
    Refresh.setUiLocked(true)
    local spent, usedFree = Banks.spendRefresh(ledger, area, useFree)
    if not spent then
        Refresh.setUiLocked(false)
        return false, useFree and "free refresh unavailable" or "requirements not met"
    end

    if not usedFree then
        Multiplier.applyRefresh(ledger, areaKey)
    end
    local rootJobs = State.root()
    local kept = {}
    local seq = 1
    for _, existing in ipairs(rootJobs.refreshJobs or {}) do
        local existingSeq = tonumber(existing.seq) or 0
        if existingSeq + 1 > seq then seq = existingSeq + 1 end
        if existing.areaKey ~= areaKey then
            kept[#kept + 1] = existing
        end
    end
    rootJobs.refreshJobs = kept
    local job = {
        id = tostring(areaKey) .. ":" .. tostring(Util.worldHours()) .. ":" .. tostring(seq),
        seq = seq,
        areaKey = areaKey,
        towns = towns,
        vehicles = Config.value("resetVehicles") == true,
        pumps = Config.value("resetGasPumps") == true,
        vehicleCells = {},
        hour = Util.worldHours(),
        freeHomeTheater = usedFree,
    }
    kept[#kept + 1] = job
    for _, townKey in ipairs(job.towns) do
        markRegionPending(townKey)
    end
    if RefreshMod.World and RefreshMod.World.startJob then
        RefreshMod.World.startJob(job)
    end
    Refresh.setUiLocked(false)
    return true
end

function Refresh.installAutomaticRefreshBlock()
    local api = locationRefresh()
    if api == nil or api._refreshModWrapped then return end
    api._refreshModWrapped = true
    local originalEnabled = api.enabled

    api.enabled = function()
        if regionLookup then return true end
        local Runtime = ExtractionMode and ExtractionMode.RaidRuntime
        local rootStore = Runtime and Runtime.getRootStore and Runtime.getRootStore() or nil
        local regions = rootStore and rootStore.locationRefresh and rootStore.locationRefresh.regions
        if type(regions) == "table" then
            for _, record in pairs(regions) do
                if type(record) == "table" and record.refreshModPaid
                    and (record.pending or record.preparing) then
                    return true
                end
            end
        end
        if originalEnabled then return originalEnabled() end
        return false
    end
    api.closed = function(raid)
        if raid == nil or raid.locationRefreshCounted then return false end
        raid.locationRefreshCounted = true
        return false
    end
end

return Refresh
