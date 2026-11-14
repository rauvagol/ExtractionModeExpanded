require "RefreshMod/Config"
require "RefreshMod/Util"
require "RefreshMod/State"
require "RefreshMod/Items"

RefreshMod = RefreshMod or {}
local Config = RefreshMod.Config
local Util = RefreshMod.Util
local State = RefreshMod.State
local Items = RefreshMod.Items
local Client = {}
RefreshMod.Client = Client

function Client.send(player, command, args)
    player = player or Util.localPlayer(0)
    if player == nil then return end
    if Util.isRemoteClient() then
        sendClientCommand(player, Config.COMMAND_MODULE, command, args or {})
    elseif RefreshMod.Authority and RefreshMod.Authority.handleCommand then
        RefreshMod.Authority.handleCommand(player, command, args or {})
    end
end

function Client.state(player)
    player = player or Util.localPlayer(0)
    local name = Util.username(player)
    local states = RefreshMod.ClientStates
    if type(states) == "table" and name and type(states[name]) == "table" then
        return states[name]
    end
    if not Util.isRemoteClient() then
        local snapshot = State.snapshot(player)
        RefreshMod.ClientStates = RefreshMod.ClientStates or {}
        if name and name ~= "" then RefreshMod.ClientStates[name] = snapshot end
        RefreshMod.ClientState = snapshot
        return snapshot
    end
    return RefreshMod.ClientState or {}
end

local function packList(selections)
    local packed = {}
    for _, entry in ipairs(selections or {}) do
        packed[#packed + 1] = Util.packSelection(entry)
    end
    return packed
end

function Client.applyState(snapshot)
    snapshot = snapshot or {}
    RefreshMod.ClientState = snapshot
    local name = snapshot.username
    if name and tostring(name) ~= "" then
        RefreshMod.ClientStates = RefreshMod.ClientStates or {}
        RefreshMod.ClientStates[name] = snapshot
    end
    local function deliver(panel)
        if panel == nil or panel.applyServerState == nil then return end
        if name == nil or tostring(name) == "" then
            panel:applyServerState(snapshot)
            return
        end
        local player = Util.localPlayer(panel.playerNum or 0)
        local panelName = player and Util.username(player) or nil
        if panelName == nil or panelName == name then
            panel:applyServerState(snapshot)
        end
    end
    local panels = RefreshMod.PanelInstances
    if type(panels) == "table" then
        for _, panel in pairs(panels) do
            deliver(panel)
        end
    else
        deliver(RefreshMod.PanelInstance)
    end
    return snapshot
end

function Client.refreshState(player)
    player = player or Util.localPlayer(0)
    Client.send(player, "RequestState", {})
    if not Util.isRemoteClient() then
        return Client.applyState(State.snapshot(player))
    end
    return Client.state(player)
end

local function requireHideout(player)
    player = player or Util.localPlayer(0)
    return Util.insideHideout(player)
end

function Client.deposit(kind, selections, player)
    player = player or Util.localPlayer(0)
    if not requireHideout(player) then return Client.refreshState(player) end
    RefreshMod.Pending = RefreshMod.Pending or {}
    RefreshMod.Pending[Util.username(player)] = RefreshMod.Pending[Util.username(player)] or {}
    local pending = RefreshMod.Pending[Util.username(player)]
    pending.kind = kind
    pending.selections = packList(selections)
    Client.send(player, "Deposit", { kind = kind, selections = pending.selections })
    return Client.refreshState(player)
end

function Client.undoDeposit(player)
    player = player or Util.localPlayer(0)
    if not requireHideout(player) then return Client.refreshState(player) end
    Client.send(player, "UndoDeposit", {})
    return Client.refreshState(player)
end

function Client.commitBankSession(player)
    player = player or Util.localPlayer(0)
    Client.send(player, "CommitBankSession", {})
    return Client.refreshState(player)
end

function Client.bankUndoCount(player)
    player = player or Util.localPlayer(0)
    if not Util.isRemoteClient() then
        local pending = RefreshMod.Pending and RefreshMod.Pending[Util.username(player)]
        if type(pending) == "table" and type(pending.undoStack) == "table" then
            return #pending.undoStack
        end
    end
    local state = Client.state(player)
    return math.max(0, math.floor(tonumber(state and state.bankUndoCount) or 0))
end

function Client.register(selection, player)
    player = player or Util.localPlayer(0)
    if not requireHideout(player) then return Client.refreshState(player) end
    local selections = packList({ selection })
    RefreshMod.Pending = RefreshMod.Pending or {}
    local key = Util.username(player)
    local pending = RefreshMod.Pending[key] or {}
    pending.selections = selections
    RefreshMod.Pending[key] = pending
    Client.send(player, "Register", { selections = selections })
    return Client.refreshState(player)
end

function Client.refreshArea(areaKey, useFree, player)
    player = player or Util.localPlayer(0)
    if not requireHideout(player) then return Client.refreshState(player), nil end
    RefreshMod._requestSerial = (RefreshMod._requestSerial or 0) + 1
    local requestId = Util.username(player) .. ":" .. tostring(RefreshMod._requestSerial)
    Client.send(player, "RefreshArea", {
        areaKey = areaKey,
        useFree = useFree == true,
        requestId = requestId,
    })
    return Client.refreshState(player), requestId
end

function Client.sellTrophy(item, player)
    player = player or Util.localPlayer(0)
    if not requireHideout(player) then return Client.refreshState(player) end
    Client.send(player, "SellTrophy", { selections = packList({ { item = item, quantity = 1 } }) })
    return Client.refreshState(player)
end

function Client.bankTrophy(item, player)
    player = player or Util.localPlayer(0)
    if not requireHideout(player) then return Client.refreshState(player) end
    Client.send(player, "BankTrophy", { selections = packList({ { item = item, quantity = 1 } }) })
    return Client.refreshState(player)
end

function Client.applyReliefTokens(areaKey, amount, player)
    player = player or Util.localPlayer(0)
    if not requireHideout(player) then return Client.refreshState(player) end
    Client.send(player, "ApplyReliefTokens", { areaKey = areaKey, amount = amount })
    return Client.refreshState(player)
end

function Client.spendTrophy(item, areaKey, player)
    player = player or Util.localPlayer(0)
    if not requireHideout(player) then return Client.refreshState(player) end
    Client.send(player, "SpendTrophy", { areaKey = areaKey, selections = packList({ { item = item, quantity = 1 } }) })
    return Client.refreshState(player)
end

local function layoutHudButtons(hud)
    if hud == nil or hud.expandedButton == nil then return end
    local minimized = hud.minimized == true
    local data = ExtractionMode.ClientState or {}
    local ConfigEM = ExtractionMode.Config
    local hideout = ConfigEM ~= nil and data.state == ConfigEM.STATE_HIDEOUT
    local raid = Util.raidViewState(data)
    local show = (hideout or raid) and not minimized
    hud.expandedButton:setVisible(show == true)
    if show ~= true then return end
    local viewOnly = not Util.insideHideout(Util.localPlayer(hud.playerNum or 0))
    hud.expandedButton:setTooltip(viewOnly
        and getText("IGUI_ExtractionModeExpanded_HUDViewOnly")
        or getText("IGUI_ExtractionModeExpanded_HUDTooltip"))
    local upgradeVisible = hud.upgradeButton and hud.upgradeButton:isVisible() == true
    local questVisible = hud.questButton and hud.questButton:isVisible() == true
    if upgradeVisible or questVisible then
        local y = hud.upgradeButton:getY()
        local height = hud.upgradeButton:getHeight()
        local third = math.floor((hud.width - 36) / 3)
        hud.upgradeButton:setX(12)
        hud.upgradeButton:setWidth(third)
        hud.questButton:setX(18 + third)
        hud.questButton:setWidth(third)
        hud.expandedButton:setX(24 + third * 2)
        hud.expandedButton:setY(y)
        hud.expandedButton:setWidth(third)
        hud.expandedButton:setHeight(height)
        return
    end
    local height = (hud.action and hud.action:getHeight()) or 27
    local y
    if hud.action and hud.action:isVisible() == true then
        y = hud.action:getY() + hud.action:getHeight() + 6
    elseif hud.textLayout and hud.textLayout.y then
        y = hud.textLayout.y + 8
    else
        y = (hud.headerHeight or 36) + 8
    end
    hud.expandedButton:setX(12)
    hud.expandedButton:setY(y)
    hud.expandedButton:setWidth(hud.width - 24)
    hud.expandedButton:setHeight(height)
    local needed = y + height + 4
    if hud.height < needed then
        local extra = needed - hud.height
        hud:setHeight(needed)
        hud:setY(hud:getY() - extra)
    end
end

local function attachHudButton(hud)
    if hud == nil then return end
    local HUD = ExtractionMode and ExtractionMode.HUD
    if HUD == nil then return end
    if hud.expandedButton == nil then
        hud.expandedButton = ISButton:new(0, 0, 100, 27,
            getText("IGUI_ExtractionModeExpanded_HUDButton"), hud, HUD.onExpanded)
        hud.expandedButton:initialise()
        hud.expandedButton:instantiate()
        hud.expandedButton:setTooltip(getText("IGUI_ExtractionModeExpanded_HUDTooltip"))
        hud:addChild(hud.expandedButton)
    end
    layoutHudButtons(hud)
end

local function wrapHUD()
    local HUD = ExtractionMode and ExtractionMode.HUD
    if HUD == nil then return end
    if not HUD._refreshModWrapped then
        HUD._refreshModWrapped = true
        function HUD:onExpanded()
            if RefreshMod.togglePanel then RefreshMod.togglePanel(self.playerNum or 0) end
        end
        local original = HUD.createChildren
        HUD.createChildren = function(self)
            original(self)
            attachHudButton(self)
        end
        local originalLayout = HUD.updateTextLayout
        if originalLayout then
            HUD.updateTextLayout = function(self)
                originalLayout(self)
                layoutHudButtons(self)
            end
        end
        local originalPre = HUD.prerender
        HUD.prerender = function(self)
            originalPre(self)
            layoutHudButtons(self)
        end
    end
    attachHudButton(ExtractionMode.HUDInstance)
end

if ExtractionMode and ExtractionMode.HUD then wrapHUD() end

if Events and Events.OnGameBoot then
    Events.OnGameBoot.Add(wrapHUD)
end

if Events and Events.OnGameStart then
    Events.OnGameStart.Add(function()
        wrapHUD()
        Client.refreshState(Util.localPlayer(0))
    end)
end

if Events and Events.OnServerCommand then
    Events.OnServerCommand.Add(function(module, command, args)
        if module ~= Config.COMMAND_MODULE or command ~= "State" then return end
        Client.applyState(args)
    end)
end

return Client
