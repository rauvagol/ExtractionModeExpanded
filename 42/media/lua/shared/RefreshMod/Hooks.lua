require "RefreshMod/Config"
require "RefreshMod/Util"
require "RefreshMod/State"
require "RefreshMod/Refresh"
require "RefreshMod/Collections"

RefreshMod = RefreshMod or {}
local Config = RefreshMod.Config
local Util = RefreshMod.Util
local State = RefreshMod.State
local Refresh = RefreshMod.Refresh
local Collections = RefreshMod.CollectionsLogic
local Hooks = {}
RefreshMod.Hooks = Hooks

local function wrapOnce(container, name, wrapper)
    if container == nil or container[name] == nil then return end
    local flag = "_refreshMod_" .. name
    if container[flag] then return end
    container[flag] = true
    local original = container[name]
    container[name] = wrapper(original)
end

local function authoritative()
    return not Util.isRemoteClient()
end

function Hooks.install()
    Config.forceLocationRefreshSandbox()
    Refresh.installAutomaticRefreshBlock()

    local Logistics = ExtractionMode and ExtractionMode.Logistics
    if Logistics and Logistics.refreshTownChoices then
        wrapOnce(Logistics, "refreshTownChoices", function(original)
            return function(data, preserveRoadConditions, rotationAlreadyAdvanced)
                if not authoritative() then
                    return original(data, preserveRoadConditions, rotationAlreadyAdvanced)
                end

                local day = Util.gameDay()
                local holders = {}
                for _, player in ipairs(Util.players()) do
                    if Collections.completedForPlayer(player, "rotary_phones") then
                        holders[#holders + 1] = player
                    end
                end

                local predicted = nil
                if #holders > 0 and data and data.refreshModGpsTomorrow
                    and tonumber(data.gpsSpecialTownDay) ~= day then
                    predicted = data.refreshModGpsTomorrow
                end
                local result = original(data, preserveRoadConditions, rotationAlreadyAdvanced)
                if predicted and data then
                    local em = ExtractionMode.Config
                    local town = em and em.town and em.town(predicted)
                    local LogisticsApi = ExtractionMode.Logistics
                    local blocked = LogisticsApi and LogisticsApi.raidDeathBlockPhase
                        and LogisticsApi.raidDeathBlockPhase(data, predicted) ~= nil
                    local Upgrades = ExtractionMode.Upgrades
                    local uplink = Upgrades and Upgrades.isInstalled
                        and Upgrades.isInstalled(data.upgrades, "gps_uplink") == true
                    if uplink and town and town.gpsSpecial == true and not blocked then
                        data.gpsSpecialTownKey = predicted
                        data.gpsSpecialTownDay = day
                    end
                end
                if #holders > 0 and data and data.gpsSpecialTownKey then
                    local sample = State.ledger(holders[1])
                    local kept = sample and tonumber(sample.gpsTomorrowDay) == day and sample.gpsTomorrow
                    if kept then
                        data.refreshModGpsTomorrow = kept
                    else
                        local em = ExtractionMode.Config
                        local today = tostring(data.gpsSpecialTownKey)
                        local gpsKeys = {}
                        for _, key in ipairs(em.townKeys and em.townKeys() or {}) do
                            local town = em.town(key)
                            if town and town.gpsSpecial == true then
                                gpsKeys[#gpsKeys + 1] = key
                            end
                        end
                        local candidates = {}
                        for _, key in ipairs(gpsKeys) do
                            if #gpsKeys <= 1 or tostring(key) ~= today then
                                candidates[#candidates + 1] = key
                            end
                        end
                        if #candidates > 0 then
                            data.refreshModGpsTomorrow = candidates[ZombRand(#candidates) + 1]
                        end
                    end
                    local written = {}
                    for _, player in ipairs(holders) do
                        local ledger = State.ledger(player)
                        if ledger and written[ledger] ~= true then
                            written[ledger] = true
                            ledger.gpsTomorrow = data.refreshModGpsTomorrow
                            ledger.gpsTomorrowDay = day
                        end
                    end
                    State.markDirty()

                    if isServer and isServer() and sendServerCommand then
                        for _, player in ipairs(holders) do
                            sendServerCommand(player, Config.COMMAND_MODULE, "State", State.snapshot(player))
                        end
                    end
                end
                return result
            end
        end)
    end
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(function()
        Hooks.install()
        if RefreshMod.Bonuses and RefreshMod.Bonuses.install then
            RefreshMod.Bonuses.install()
        end
    end)
end

if Events and Events.OnGameBoot then
    Events.OnGameBoot.Add(function()
        Config.forceLocationRefreshSandbox()
    end)
end

Hooks.install()

return Hooks
