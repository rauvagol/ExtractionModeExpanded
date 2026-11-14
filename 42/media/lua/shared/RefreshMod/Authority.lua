require "RefreshMod/Config"
require "RefreshMod/Util"
require "RefreshMod/State"
require "RefreshMod/Banks"
require "RefreshMod/Refresh"
require "RefreshMod/Collections"
require "RefreshMod/Items"

RefreshMod = RefreshMod or {}

if RefreshMod.Util.isRemoteClient() then
    RefreshMod.Authority = RefreshMod.Authority or {}
    return RefreshMod.Authority
end

local Config = RefreshMod.Config
local Util = RefreshMod.Util
local State = RefreshMod.State
local Banks = RefreshMod.Banks
local Refresh = RefreshMod.Refresh
local Collections = RefreshMod.CollectionsLogic
local Items = RefreshMod.Items
local Authority = {}
RefreshMod.Authority = Authority

local function pendingFor(player)
    RefreshMod.Pending = RefreshMod.Pending or {}
    local key = Util.username(player)
    RefreshMod.Pending[key] = RefreshMod.Pending[key] or {}
    local pending = RefreshMod.Pending[key]
    pending.undoStack = pending.undoStack or {}
    return pending
end

local function broadcast(player)
    State.markDirty()
    RefreshMod.ClientState = State.snapshot(player)
    if not (isServer and isServer() and sendServerCommand) then return end
    local sent = false
    for _, target in ipairs(Util.players()) do
        if target then
            sendServerCommand(target, Config.COMMAND_MODULE, "State", State.snapshot(target))
            sent = true
        end
    end
    if not sent and player then
        sendServerCommand(player, Config.COMMAND_MODULE, "State", RefreshMod.ClientState)
    end
end

local function resolveItem(player, packed)
    if packed == nil then return nil end
    if packed.item ~= nil and type(packed.item) ~= "table" and Util.fullType(packed.item) then
        return packed.item
    end
    local item = Util.findItemById(player, packed.itemId)
    if item == nil then return nil end
    if packed.fullType ~= nil and Util.fullType(item) ~= packed.fullType then return nil end
    return item
end

local function resolveSelections(player, selections)
    local resolved = {}
    for _, entry in ipairs(selections or {}) do
        local item = resolveItem(player, entry)
        if item == nil then return nil end
        resolved[#resolved + 1] = {
            item = item,
            quantity = entry.quantity,
            collectionKey = entry.collectionKey,
            slotIndex = entry.slotIndex,
        }
    end
    return resolved
end

local function pushUndos(pending, undos)
    if type(undos) ~= "table" then return end
    pending.undoStack = pending.undoStack or {}
    for _, entry in ipairs(undos) do
        pending.undoStack[#pending.undoStack + 1] = entry
    end
end

function Authority.handleCommand(player, command, args)
    if player == nil or command == nil then return end
    args = args or {}
    local pending = pendingFor(player)
    if command == "CommitBankSession" then
        pending.undoStack = {}
        pending.lastResult = { ok = true, result = "committed", undoCount = 0 }
        broadcast(player)
        return
    end
    local mutate = command == "Deposit" or command == "SellTrophy" or command == "SpendTrophy"
        or command == "BankTrophy" or command == "ApplyReliefTokens"
        or command == "Register" or command == "RefreshArea"
        or command == "UndoDeposit"
    if mutate and not Util.insideHideout(player) then
        pending.lastResult = { ok = false, result = "hideout only" }
        broadcast(player)
        return
    end
    if command == "FreshenSpiffo" then
        if RefreshMod.Bonuses and RefreshMod.Bonuses.freshenOpenedSquare then
            RefreshMod.Bonuses.freshenOpenedSquare(player, args)
        end
        return
    elseif command == "RequestState" then
        broadcast(player)
    elseif command == "SetPending" then
        pending.selections = args.selections
        pending.kind = args.kind
        pending.areaKey = args.areaKey
    elseif command == "Deposit" then
        local selections = resolveSelections(player, args.selections or pending.selections)
        if selections == nil then
            pending.lastResult = { ok = false, result = "missing item" }
            broadcast(player)
            return
        end
        local ok, result, undos = Banks.deposit(player, args.kind or pending.kind, selections)
        if ok then pushUndos(pending, undos) end
        pending.lastResult = { ok = ok, result = result, undoCount = #(pending.undoStack or {}) }
        pending.selections = nil
        broadcast(player)
    elseif command == "UndoDeposit" then
        local stack = pending.undoStack or {}
        local entry = stack[#stack]
        if entry == nil then
            pending.lastResult = { ok = false, result = "nothing to undo" }
        else
            local ok, reason = Banks.undoDeposit(player, entry)
            if ok then stack[#stack] = nil end
            pending.lastResult = { ok = ok, result = reason or ok, undoCount = #stack }
        end
        broadcast(player)
    elseif command == "SellTrophy" then
        local packed = (args.selections or pending.selections or {})[1]
        local item = packed and (resolveItem(player, packed) or (type(packed) ~= "table" and packed or nil))
        local ok, value = Banks.sellTrophy(player, item)
        pending.lastResult = { ok = ok, result = value }
        broadcast(player)
    elseif command == "BankTrophy" then
        local packed = (args.selections or pending.selections or {})[1]
        local item = packed and resolveItem(player, packed)
        local ok, relief = Banks.bankTrophy(player, item)
        pending.lastResult = { ok = ok, result = relief }
        broadcast(player)
    elseif command == "ApplyReliefTokens" then
        local ok, used, wasted = Banks.applyReliefTokens(player, args.areaKey or pending.areaKey, args.amount)
        pending.lastResult = { ok = ok, result = used, wasted = wasted }
        broadcast(player)
    elseif command == "SpendTrophy" then
        local packed = (args.selections or pending.selections or {})[1]
        local item = packed and resolveItem(player, packed)
        local ok, used, wasted = Banks.spendTrophy(player, item, args.areaKey or pending.areaKey)
        pending.lastResult = { ok = ok, result = used, wasted = wasted }
        broadcast(player)
    elseif command == "Register" then
        local ledger = State.ledger(player)
        local selection = resolveSelections(player, args.selections or pending.selections)
        selection = selection and selection[1]
        local ok = Collections.registerOne(player, ledger, selection)
        pending.lastResult = { ok = ok, result = ok and 1 or 0 }
        pending.selections = nil
        broadcast(player)
    elseif command == "RefreshArea" then
        local ok, reason = Refresh.execute(player, args.areaKey, args.useFree == true)
        if ok then pending.undoStack = {} end
        pending.lastResult = { ok = ok, result = reason, requestId = args.requestId }
        broadcast(player)
    end
end

local function onClientCommand(module, command, player, args)
    if module ~= Config.COMMAND_MODULE then return end
    Authority.handleCommand(player, command, args or {})
end

if Events and Events.OnClientCommand then
    Events.OnClientCommand.Add(onClientCommand)
end

return Authority
