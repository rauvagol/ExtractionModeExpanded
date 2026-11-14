require "RefreshMod/Config"
require "RefreshMod/Util"

RefreshMod = RefreshMod or {}
local Config = RefreshMod.Config
local Util = RefreshMod.Util
local State = {}
RefreshMod.State = State

local root
local fixedLedger = {}

local function dataKey()
    return Config.DATA_KEY or RefreshMod.DATA_KEY or "ExtractionModeExpanded.State"
end

local function backupKey()
    return Config.BACKUP_DATA_KEY or "ExtractionModeExpanded.StateBackup"
end

local function emptyReliefTokens()
    return { small = 0, medium = 0, large = 0 }
end

local function emptyLedger()
    local ledger = {
        value = 0,
        weapons = 0,
        bulk = {},
        keyItems = {},
        excess = {},
        collections = {},
        collectionSlots = {},
        reliefTokens = emptyReliefTokens(),
        gpsTomorrow = nil,
        gpsTomorrowDay = nil,
        homeTheaterFreeWeek = nil,
    }
    fixedLedger[ledger] = true
    return ledger
end

local function numberMap(bag)
    if type(bag) ~= "table" then return {} end
    for key, count in pairs(bag) do
        bag[key] = tonumber(count) or 0
    end
    return bag
end

local function fixLoadedLedger(ledger)
    if type(ledger) ~= "table" or fixedLedger[ledger] then return ledger end
    fixedLedger[ledger] = true
    ledger.value = tonumber(ledger.value) or 0
    ledger.weapons = tonumber(ledger.weapons) or 0
    ledger.bulk = numberMap(ledger.bulk)
    ledger.keyItems = numberMap(ledger.keyItems)
    ledger.excess = numberMap(ledger.excess)
    if type(ledger.collections) ~= "table" then ledger.collections = {} end
    if type(ledger.collectionSlots) ~= "table" then ledger.collectionSlots = {} end
    if ledger.homeTheaterFreeWeek ~= nil then
        ledger.homeTheaterFreeWeek = tonumber(ledger.homeTheaterFreeWeek)
    end
    local tokens = ledger.reliefTokens
    if type(tokens) ~= "table" then
        local legacy = tonumber(tokens) or 0
        tokens = emptyReliefTokens()
        if legacy > 0 then
            tokens.large = math.floor(legacy + 0.0001)
            local rem = legacy - tokens.large
            if rem >= 0.5 - 0.0001 then
                tokens.medium = tokens.medium + 1
                rem = rem - 0.5
            end
            if rem >= 0.25 - 0.0001 then
                tokens.small = tokens.small + 1
            end
        end
        ledger.reliefTokens = tokens
    else
        tokens.small = math.max(0, math.floor(tonumber(tokens.small) or 0))
        tokens.medium = math.max(0, math.floor(tonumber(tokens.medium) or 0))
        tokens.large = math.max(0, math.floor(tonumber(tokens.large) or 0))
    end
    if RefreshMod.CollectionsLogic and RefreshMod.CollectionsLogic.normalizeLedgerCollections then
        RefreshMod.CollectionsLogic.normalizeLedgerCollections(ledger)
    end
    return ledger
end

local function fixSavedOwners(store)
    if store == nil then return end
    store.owners = store.owners or {}
    for key, ledger in pairs(store.owners) do
        if type(ledger) == "table" then
            fixLoadedLedger(ledger)
        else
            store.owners[key] = emptyLedger()
        end
    end
end

local function mergeCollections(into, from)
    if type(from) ~= "table" then return into end
    into = into or {}
    for key, slots in pairs(from) do
        if type(slots) == "table" then
            into[key] = into[key] or {}
            for index, filled in pairs(slots) do
                if filled and filled ~= 0 then
                    local n = math.floor(tonumber(index) or 0)
                    if n >= 1 then into[key][tostring(n)] = true end
                end
            end
        end
    end
    return into
end

local function mergeCollectionSlots(into, from)
    if type(from) ~= "table" then return into end
    into = into or {}
    for key, filled in pairs(from) do
        if filled and filled ~= 0 then into[tostring(key)] = true end
    end
    return into
end

local function mergeLedger(into, from)
    if type(into) ~= "table" or type(from) ~= "table" then return into end
    into.value = math.max(tonumber(into.value) or 0, tonumber(from.value) or 0)
    into.weapons = math.max(tonumber(into.weapons) or 0, tonumber(from.weapons) or 0)
    into.bulk = into.bulk or {}
    into.keyItems = into.keyItems or {}
    into.excess = into.excess or {}
    for fullType, count in pairs(from.bulk or {}) do
        into.bulk[fullType] = math.max(tonumber(into.bulk[fullType]) or 0, tonumber(count) or 0)
    end
    for fullType, count in pairs(from.keyItems or {}) do
        into.keyItems[fullType] = math.max(tonumber(into.keyItems[fullType]) or 0, tonumber(count) or 0)
    end
    for areaKey, excess in pairs(from.excess or {}) do
        into.excess[areaKey] = math.max(tonumber(into.excess[areaKey]) or 0, tonumber(excess) or 0)
    end
    into.collections = mergeCollections(into.collections or {}, from.collections)
    into.collectionSlots = mergeCollectionSlots(into.collectionSlots or {}, from.collectionSlots)

    if RefreshMod.CollectionsLogic and RefreshMod.CollectionsLogic.normalizeLedgerCollections then
        RefreshMod.CollectionsLogic.normalizeLedgerCollections(into)
    end
    local a = into.reliefTokens
    local b = from.reliefTokens
    if type(a) ~= "table" then a = emptyReliefTokens() end
    if type(b) == "table" then
        a.small = math.max(tonumber(a.small) or 0, tonumber(b.small) or 0)
        a.medium = math.max(tonumber(a.medium) or 0, tonumber(b.medium) or 0)
        a.large = math.max(tonumber(a.large) or 0, tonumber(b.large) or 0)
    elseif tonumber(b) then
        local legacy = tonumber(b) or 0
        a.large = math.max(tonumber(a.large) or 0, math.floor(legacy + 0.0001))
    end
    into.reliefTokens = a
    if from.gpsTomorrow and not into.gpsTomorrow then
        into.gpsTomorrow = from.gpsTomorrow
        into.gpsTomorrowDay = from.gpsTomorrowDay
    end
    if from.homeTheaterFreeWeek ~= nil then
        local a = tonumber(into.homeTheaterFreeWeek)
        local b = tonumber(from.homeTheaterFreeWeek)
        if a == nil or (b ~= nil and b > a) then
            into.homeTheaterFreeWeek = b
        end
    end
    return into
end

local function copyLedger(from)
    if type(from) ~= "table" then return emptyLedger() end
    local into = emptyLedger()
    mergeLedger(into, from)
    into.gpsTomorrow = from.gpsTomorrow
    into.gpsTomorrowDay = from.gpsTomorrowDay
    into.homeTheaterFreeWeek = from.homeTheaterFreeWeek
    return into
end

local function mergeOwners(intoOwners, fromOwners)
    if type(fromOwners) ~= "table" then return end
    intoOwners = intoOwners or {}
    for key, ledger in pairs(fromOwners) do
        if type(ledger) == "table" then
            if intoOwners[key] == nil then
                intoOwners[key] = copyLedger(ledger)
            else
                mergeLedger(intoOwners[key], ledger)
            end
        end
    end
end

local function ownersEmpty(owners)
    return type(owners) ~= "table" or next(owners) == nil
end

local function fillEmptyOwners(intoOwners, fromOwners)
    if not ownersEmpty(intoOwners) or type(fromOwners) ~= "table" then return end
    intoOwners = intoOwners or {}
    for key, ledger in pairs(fromOwners) do
        if type(ledger) == "table" and intoOwners[key] == nil then
            intoOwners[key] = copyLedger(ledger)
        end
    end
end

local function liveModDataStore()
    if ModData == nil then return nil end
    return ModData.getOrCreate(dataKey())
end

local function recoverFromBackup(store)
    if store == nil or ModData == nil then return end
    local mirror = ModData.get(backupKey())
    if type(mirror) ~= "table" or type(mirror.owners) ~= "table" then return end
    if mirror.sharedConsolidated == true then store.sharedConsolidated = true end

    store.owners = store.owners or {}
    if next(store.owners) == nil then
        mergeOwners(store.owners, mirror.owners)
    end
    if type(mirror.refreshJobs) == "table" and (store.refreshJobs == nil or not next(store.refreshJobs)) then
        store.refreshJobs = mirror.refreshJobs
    end
end

local function writeBackup(store)
    if store == nil or ModData == nil then return end
    local mirror = ModData.getOrCreate(backupKey())
    if mirror == nil then return end
    mirror.version = 1
    local owners = {}
    for key, ledger in pairs(store.owners or {}) do
        if type(ledger) == "table" then
            owners[key] = copyLedger(ledger)
        end
    end
    mirror.owners = owners
    mirror.sharedConsolidated = store.sharedConsolidated == true
    mirror.refreshJobs = store.refreshJobs or {}
    mirror.zones = nil
end

function State.bind(store, forceReload)
    local orphan = root
    if forceReload then root = nil end

    local live = liveModDataStore()
    if store ~= nil then
        if live ~= nil and live ~= store then
            if ownersEmpty(live.owners) then
                live.owners = live.owners or {}
                fillEmptyOwners(live.owners, store.owners)
            end
            root = live
        else
            root = store
            if live == nil and ModData then
                ModData.add(dataKey(), root)
            end
        end
    elseif live ~= nil then
        root = live
    elseif root == nil then
        root = { version = 1, owners = {}, refreshJobs = {} }
        if ModData then ModData.add(dataKey(), root) end

        live = liveModDataStore()
        if live ~= nil and live ~= root then
            if ownersEmpty(live.owners) then
                live.owners = live.owners or {}
                fillEmptyOwners(live.owners, root.owners)
            end
            root = live
        end
    end

    root.version = root.version or 1
    root.owners = root.owners or {}
    root.refreshJobs = root.refreshJobs or {}
    root.zones = nil

    if orphan ~= nil and orphan ~= root and ownersEmpty(root.owners) then
        fillEmptyOwners(root.owners, orphan.owners)
    end
    if orphan ~= nil and orphan ~= root
        and type(orphan.refreshJobs) == "table" and next(orphan.refreshJobs) ~= nil
        and (root.refreshJobs == nil or next(root.refreshJobs) == nil) then
        root.refreshJobs = orphan.refreshJobs
    end

    recoverFromBackup(root)
    fixSavedOwners(root)
    return root
end

function State.root()

    if root ~= nil and ModData then
        local live = ModData.get(dataKey())
        if live ~= nil and live ~= root then
            local orphan = root
            root = live
            root.owners = root.owners or {}
            root.refreshJobs = root.refreshJobs or {}
            root.zones = nil
            if ownersEmpty(root.owners) then
                fillEmptyOwners(root.owners, orphan.owners)
            end
            if type(orphan.refreshJobs) == "table" and next(orphan.refreshJobs) ~= nil
                and (root.refreshJobs == nil or next(root.refreshJobs) == nil) then
                root.refreshJobs = orphan.refreshJobs
            end
        end
    end
    if root == nil then State.bind() end
    fixSavedOwners(root)
    return root
end

function State.markDirty()
    local store = State.root()

    if ModData then ModData.add(dataKey(), store) end
    writeBackup(store)
    if ModData and not Util.isRemoteClient() then
        ModData.transmit(dataKey())
        ModData.transmit(backupKey())
    end
end

function State.captureForSave()
    State.bind(nil, false)
    local store = State.root()
    writeBackup(store)
    if ModData then ModData.add(dataKey(), store) end
end

local function playerOwner(player)
    local username = Util.username(player)
    if username == "" then username = "singleplayer" end
    return { key = "player:" .. username, kind = "player", name = username }
end

local function shareFactionProgress()
    local em = ExtractionMode and ExtractionMode.Config
    if em and em.value then
        local flag = em.value("ShareFactionQuestProgress")
        if flag ~= nil then return flag == true end
    end
    return true
end

local function groupRegistry()
    local Runtime = ExtractionMode and ExtractionMode.RaidRuntime
    if Runtime and Runtime.getRootStore then
        local store = Runtime.getRootStore()
        if store and store.groupRegistry then return store.groupRegistry end
    end
    return nil
end

function State.ownerFor(player)
    local personal = playerOwner(player)
    local Groups = ExtractionMode and ExtractionMode.Groups
    if Groups == nil then return personal end
    local owner = Groups.forPlayer(player, groupRegistry())
    if owner == nil or owner.key == nil then return personal end
    if owner.kind == "faction" and not shareFactionProgress() then
        return personal
    end
    return owner
end

function State.questOwner(player)
    return State.ownerFor(player)
end

local function playerHasFaction(player)
    if player == nil or Faction == nil then return false end
    return Faction.getPlayerFaction(player) ~= nil
end

local function adoptLegacyLedgers(store, owner, player)
    if owner == nil or owner.key == nil then return end
    store.owners = store.owners or {}
    if store.legacySharedClaimed == true then
        store.owners.shared = nil
        return
    end
    if type(store.owners.shared) ~= "table" then
        store.legacySharedClaimed = true
        return
    end

    if owner.kind ~= "faction" and shareFactionProgress() and playerHasFaction(player) then
        return
    end
    local into = store.owners[owner.key]
    if type(into) ~= "table" then into = emptyLedger() end
    mergeLedger(into, store.owners.shared)
    store.owners[owner.key] = into
    store.owners.shared = nil
    store.legacySharedClaimed = true
end

function State.ledger(player)
    local store = State.root()
    local owner = State.ownerFor(player)
    if not Util.isRemoteClient() then
        adoptLegacyLedgers(store, owner, player)
    end
    local ledger = store.owners[owner.key]
    if type(ledger) ~= "table" then
        ledger = emptyLedger()
        store.owners[owner.key] = ledger
    else
        fixLoadedLedger(ledger)
    end
    return ledger, owner
end

function State.completions(player)

    local owner = State.questOwner(player)
    local ownerKey = owner and owner.key
    local Runtime = ExtractionMode and ExtractionMode.RaidRuntime
    if Runtime and Runtime.getRootStore and ownerKey then
        local rootStore = Runtime.getRootStore()
        local progress = rootStore and rootStore.questProgress
        if type(progress) == "table" and type(progress[ownerKey]) == "table" then
            return progress[ownerKey]
        end
    end
    local client = nil
    if ExtractionMode and ExtractionMode.Client and ExtractionMode.Client.stateFor then
        client = ExtractionMode.Client.stateFor(player)
    end
    if type(client) ~= "table" then
        client = ExtractionMode and ExtractionMode.ClientState
    end
    if type(client) == "table" and type(client.quests) == "table" then
        return client.quests
    end
    return {}
end

local function copyFlat(bag)
    local out = {}
    if type(bag) ~= "table" then return out end
    for key, value in pairs(bag) do
        if type(value) ~= "table" then out[key] = value end
    end
    return out
end

local function copyCollections(collections)
    local out = {}
    if type(collections) ~= "table" then return out end
    for key, slots in pairs(collections) do
        if type(slots) == "table" then
            out[key] = copyFlat(slots)
        end
    end
    return out
end

function State.uiLedger(player)
    if Util.isRemoteClient() then
        local name = player and Util.username(player) or nil
        local states = RefreshMod.ClientStates
        if name and type(states) == "table" and type(states[name]) == "table" and states[name].value ~= nil then
            return states[name]
        end
        local snap = RefreshMod.ClientState
        if type(snap) == "table" and snap.value ~= nil
            and (name == nil or snap.username == nil or snap.username == name) then
            return snap
        end
    end
    return State.ledger(player)
end

function State.snapshot(player)
    local ledger, owner = State.ledger(player)
    local areas = {}
    for _, area in ipairs(Config.areas()) do
        areas[#areas + 1] = {
            key = area.key,
            name = area.name,
            unlocked = Config.areaUnlocked(area.key, State.completions(player)),
        }
    end
    local undoCount = 0
    local lastResult = nil
    local pendingKey = Util.username(player)
    local pending = RefreshMod.Pending and RefreshMod.Pending[pendingKey]
    if pending == nil and owner and owner.key then
        pending = RefreshMod.Pending and RefreshMod.Pending[owner.key]
    end
    undoCount = pending and #(pending.undoStack or {}) or 0
    local result = pending and pending.lastResult
    if type(result) == "table" then
        lastResult = {
            ok = result.ok == true,
            result = result.result,
            wasted = result.wasted,
            requestId = result.requestId,
        }
    end
    return {
        username = Util.username(player),
        ownerKey = owner.key,
        value = ledger.value,
        weapons = ledger.weapons,
        bulk = copyFlat(ledger.bulk),
        keyItems = copyFlat(ledger.keyItems),
        excess = copyFlat(ledger.excess),
        collections = copyCollections(ledger.collections),
        collectionSlots = copyFlat(ledger.collectionSlots),
        homeTheaterFreeWeek = ledger.homeTheaterFreeWeek,
        reliefTokens = {
            small = ledger.reliefTokens.small,
            medium = ledger.reliefTokens.medium,
            large = ledger.reliefTokens.large,
        },
        gpsTomorrow = ledger.gpsTomorrow,
        gpsTomorrowDay = ledger.gpsTomorrowDay,
        homeTheaterFreeAvailable = RefreshMod.Banks
            and RefreshMod.Banks.homeTheaterFreeAvailable
            and RefreshMod.Banks.homeTheaterFreeAvailable(ledger),
        bankUndoCount = undoCount,
        areas = areas,
        locked = RefreshMod.Refresh and RefreshMod.Refresh.uiLocked() or false,
        lastResult = lastResult,
    }
end

function State.syncPlayer(player)
    if player == nil then return end
    State.bind(nil, false)
    local ledger = State.ledger(player)
    if RefreshMod.CollectionsLogic and RefreshMod.CollectionsLogic.syncRegisteredItems then
        RefreshMod.CollectionsLogic.syncRegisteredItems(player, ledger)
    end
    State.markDirty()
end

if Events and Events.OnInitGlobalModData then
    Events.OnInitGlobalModData.Add(function()

        State.bind(nil, true)
        Config.forceLocationRefreshSandbox()
    end)
end

if Events and Events.OnCreatePlayer then
    Events.OnCreatePlayer.Add(function(playerIndex)
        local player = getSpecificPlayer and getSpecificPlayer(playerIndex) or Util.localPlayer(playerIndex)
        State.syncPlayer(player)
    end)
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(function()
        State.bind(nil, true)
        for i = 0, 3 do
            local player = getSpecificPlayer and getSpecificPlayer(i)
            if player then State.syncPlayer(player) end
        end
    end)
end

local function onWorldSave()
    State.captureForSave()
end
if Events and Events.OnSave then
    Events.OnSave.Add(onWorldSave)
elseif Events and Events.OnPostSave then
    Events.OnPostSave.Add(onWorldSave)
end

return State
