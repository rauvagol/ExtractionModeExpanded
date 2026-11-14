require "ISUI/ISPanelJoypad"
require "ISUI/ISButton"
require "ISUI/ISScrollingListBox"
require "ISUI/ISModalDialog"
require "RefreshMod/Config"
require "RefreshMod/Util"
require "RefreshMod/State"
require "RefreshMod/Items"
require "RefreshMod/Banks"
require "RefreshMod/Multiplier"
require "RefreshMod/Collections"
require "RefreshMod/Client"
require "RefreshMod/ClientOptions"

RefreshMod = RefreshMod or {}
local Config = RefreshMod.Config
local Util = RefreshMod.Util
local State = RefreshMod.State
local Items = RefreshMod.Items
local Banks = RefreshMod.Banks
local Multiplier = RefreshMod.MultiplierLogic
local Collections = RefreshMod.CollectionsLogic
local Client = RefreshMod.Client
local ClientOptions = RefreshMod.ClientOptions

local uiLedger = State.uiLedger

local Panel = ISPanelJoypad:derive("ExtractionModeExpandedPanel")
local PANEL_WIDTH = 980
local PANEL_HEIGHT = 720
local PAD = 16
local FOOTER_H = 168
local STOCK_COLS = 4
local STOCK_ROW_H = 20
local AREA_LIST_W = 300
local BANK_POPOUT_W = 380
local BANK_POPOUT_GAP = 10

local GOLD = { 0.96, 0.72, 0.18 }
local GREEN = { 0.35, 0.9, 0.4 }
local RED = { 0.95, 0.45, 0.3 }
local GREY = { 0.7, 0.7, 0.7 }
local WHITE = { 0.92, 0.92, 0.9 }

local function draw(self, text, x, y, c, font)
    self:drawText(text, x, y, c[1], c[2], c[3], 1, font or UIFont.Small)
end

local function drawCentre(self, text, y, c, font, centreX)
    self:drawTextCentre(text, centreX or (self.width / 2), y, c[1], c[2], c[3], 1, font or UIFont.Small)
end

local function bankPopoutTitle(kind)
    local titles = {
        value = getText("IGUI_ExtractionModeExpanded_SellLoot"),
        weapons = getText("IGUI_ExtractionModeExpanded_ProvideWeapons"),
        bulk = getText("IGUI_ExtractionModeExpanded_Contribute"),
        key = getText("IGUI_ExtractionModeExpanded_Donate"),
    }
    return titles[kind] or "BANK"
end

local function bankEmptyMessage(kind)
    local keys = {
        value = "IGUI_ExtractionModeExpanded_BankEmptySell",
        weapons = "IGUI_ExtractionModeExpanded_BankEmptyWeapons",
        bulk = "IGUI_ExtractionModeExpanded_BankEmptySupplies",
        key = "IGUI_ExtractionModeExpanded_BankEmptyKeys",
    }
    local key = keys[kind]
    if key == nil then return "" end
    return getText(key)
end

local function inHideout(player)
    return Util.insideHideout(player)
end

local function packColumns(items, cols)
    local rows = {}
    cols = cols or 2
    for i = 1, #items, cols do
        local cells = {}
        for c = 1, cols do
            cells[c] = items[i + c - 1]
        end
        rows[#rows + 1] = { cells = cells, cols = cols }
    end
    return rows
end

local function countTypes(bag, types)
    local total = 0
    for _, fullType in ipairs(types or {}) do
        total = total + math.max(0, tonumber(bag[fullType]) or 0)
    end
    return total
end

local function slotName(slot)
    if slot == nil then return "" end
    if slot.label and tostring(slot.label) ~= "" then return slot.label end
    return Util.displayName(slot[1])
end

local function formatCount(count, points)
    local n = tonumber(count) or 0
    if points then
        if math.abs(n - math.floor(n + 0.0001)) < 0.05 then
            return tostring(math.floor(n + 0.0001))
        end
        return string.format("%.1f", n)
    end
    return tostring(math.floor(n + 0.0001))
end

local function stockText(row)
    if row == nil then return "" end
    return string.format("%s x %s", row.label, formatCount(row.count, row.points))
end

local function stockColor(row)
    if row == nil then return GREY end
    if (tonumber(row.count) or 0) > 0.0001 then return WHITE end
    return RED
end

local function itemCredit(item, quantity, ledger)
    quantity = math.max(1, math.floor(tonumber(quantity) or 1))
    if item == nil then return 0, 0 end
    return Items.valueOf(item, ledger) * quantity, Items.weaponPointsOf(item, ledger) * quantity
end

local function candidateLabel(entry, bankKind, ledger)
    if entry == nil then return "" end
    if entry.collectionName then
        local label = string.format("%s  ->  %s (%s)", entry.name, entry.collectionName, entry.slotLabel)
        if entry.favorite then
            label = label .. "  (Favorited)"
        end
        return label
    end
    local label = string.format("%s  x%d", entry.name or "", entry.quantity or 1)
    local value, weapons = itemCredit(entry.item, entry.quantity, ledger)
    if bankKind == "value" or (value > 0 and bankKind == "weapons") then
        if value > 0 then
            label = label .. string.format("  Value %s", formatCount(value, true))
        end
    end
    if bankKind == "weapons" or (weapons > 0 and bankKind == "value") then
        if weapons > 0 then
            label = label .. string.format("  Weapons %s", formatCount(weapons, true))
        end
    end
    if entry.trophyTier then
        label = label .. "  [Trophy]"
    end
    if entry.collectionMark then
        label = label .. "  [Collection]"
    end
    if entry.reason then label = label .. "  (" .. entry.reason .. ")" end
    return label
end

local function annotateCandidate(entry, ledger, bankKind, player)
    if entry == nil or entry.item == nil then return entry end
    local tier = Config.trophyTier(Util.fullType(entry.item))
    if tier then entry.trophyTier = tier end
    local info = Collections.lookupItem(entry.item, ledger)
    if info and info.collection then
        entry.collectionMark = true
        entry.collectionInfo = info
    end
    entry.otherUse = false
    entry.otherUseTip = nil
    if Items.alternateUses then
        local ignore = nil
        if bankKind == "bulk" or bankKind == "key" then ignore = bankKind end
        local uses = Items.alternateUses(entry.item, player or Util.localPlayer(0), {
            ignoreRefreshTier = ignore,
        })
        if uses and uses.any then
            entry.otherUse = true
            entry.otherUseTip = Items.alternateUseTip(uses)
        end
    end
    return entry
end

local function trophyTierTitle(tier)
    tier = tostring(tier or "trophy")
    return tier:sub(1, 1):upper() .. tier:sub(2)
end

local function stockColumnCount(banking)
    return STOCK_COLS
end

local function newList(x, y, w, h, itemheight)
    local list = ISScrollingListBox:new(x, y, w, h)
    list:initialise()
    list:instantiate()
    list.itemheight = itemheight or 24
    list.selected = 1
    list.font = UIFont.Small
    list.drawBorder = true
    list.backgroundColor = { r = 0.02, g = 0.02, b = 0.025, a = 0.85 }
    list.borderColor = { r = 0.55, g = 0.4, b = 0.12, a = 0.8 }
    return list
end

function Panel:pauseSinglePlayer()
    if isClient and isClient() then return end
    if self.pauseHeld then return end
    self.pauseHeld = true
    local speed = getGameSpeed and tonumber(getGameSpeed()) or 1
    self.pauseResumeSpeed = speed
    if speed > 0 and setGameSpeed then setGameSpeed(0) end
    if setShowPausedMessage then setShowPausedMessage(false) end
end

function Panel:holdPause()
    if not self.pauseHeld then return end
    if isClient and isClient() then return end
    if setGameSpeed then setGameSpeed(0) end
    if setShowPausedMessage then setShowPausedMessage(false) end
end

function Panel:resumeSinglePlayer()
    if not self.pauseHeld then return end
    self.pauseHeld = false
    local resume = tonumber(self.pauseResumeSpeed)
    self.pauseResumeSpeed = nil
    if resume ~= nil and resume > 0 and setGameSpeed then
        local current = getGameSpeed and tonumber(getGameSpeed()) or 0
        if current <= 0 then setGameSpeed(resume) end
    end
    if setShowPausedMessage then setShowPausedMessage(true) end
end

function Panel:isKeyConsumed(key)
    return Keyboard and key == Keyboard.KEY_ESCAPE
end

function Panel:onKeyRelease(key)
    if Keyboard and key == Keyboard.KEY_ESCAPE then
        self:onClose()
    end
end

function Panel:createChildren()
    ISPanelJoypad.createChildren(self)
    self:setWantKeyEvents(true)
    self.closeButton = ISButton:new(self.width - 36, 8, 24, 24, "X", self, Panel.onClose)
    self.closeButton:initialise()
    self.closeButton:instantiate()
    self:addChild(self.closeButton)

    self.refreshTab = ISButton:new(20, 40, 160, 28, getText("IGUI_ExtractionModeExpanded_Storage"), self, Panel.onSelectTab)
    self.refreshTab.tabId = "refresh"
    self.refreshTab:initialise()
    self.refreshTab:instantiate()
    self:addChild(self.refreshTab)

    self.odditiesTab = ISButton:new(188, 40, 160, 28, getText("IGUI_ExtractionModeExpanded_Oddities"), self, Panel.onSelectTab)
    self.odditiesTab.tabId = "oddities"
    self.odditiesTab:initialise()
    self.odditiesTab:instantiate()
    self:addChild(self.odditiesTab)

    self.trophiesTab = ISButton:new(356, 40, 160, 28, getText("IGUI_ExtractionModeExpanded_Trophies"), self, Panel.onSelectTab)
    self.trophiesTab.tabId = "trophies"
    self.trophiesTab:initialise()
    self.trophiesTab:instantiate()
    self:addChild(self.trophiesTab)

    local btnY = 76
    local btnH = 28
    local gap = 8
    local btnW = math.floor((self.width - PAD * 2 - gap * 3) / 4)
    self.sellButton = ISButton:new(PAD, btnY, btnW, btnH, getText("IGUI_ExtractionModeExpanded_SellLoot"), self, Panel.onBank)
    self.sellButton.kind = "value"
    self.provideButton = ISButton:new(PAD + btnW + gap, btnY, btnW, btnH, getText("IGUI_ExtractionModeExpanded_ProvideWeapons"), self, Panel.onBank)
    self.provideButton.kind = "weapons"
    self.contributeButton = ISButton:new(PAD + (btnW + gap) * 2, btnY, btnW, btnH, getText("IGUI_ExtractionModeExpanded_Contribute"), self, Panel.onBank)
    self.contributeButton.kind = "bulk"
    self.donateButton = ISButton:new(PAD + (btnW + gap) * 3, btnY, btnW, btnH, getText("IGUI_ExtractionModeExpanded_Donate"), self, Panel.onBank)
    self.donateButton.kind = "key"
    for _, button in ipairs({ self.sellButton, self.provideButton, self.contributeButton, self.donateButton }) do
        button:initialise()
        button:instantiate()
        self:addChild(button)
    end

    self.stockList = newList(PAD, 136, self.width - PAD * 2, 300, STOCK_ROW_H)
    self.stockList.doDrawItem = function(list, y, item, alt)
        return self:drawStockItem(list, y, item, alt)
    end
    self:addChild(self.stockList)

    self.candidateList = newList(PAD, 136, 400, 260, 24)
    self.candidateList.onmousedown = function(_, item)
        self.selectedCandidate = item
    end
    self.candidateList.doDrawItem = function(list, y, item, alt)
        return self:drawCandidateItem(list, y, item, alt)
    end
    self:addChild(self.candidateList)

    self.areaList = newList(PAD, self.height - FOOTER_H, AREA_LIST_W, FOOTER_H - 8, 22)
    self.areaList.onmousedown = function(_, item)
        self.selectedAreaKey = item
        self:rebuildRequirements()
    end
    self.areaList.doDrawItem = function(list, y, item, alt)
        return self:drawAreaItem(list, y, item, alt)
    end
    self:addChild(self.areaList)

    self.reqList = newList(PAD + AREA_LIST_W + 8, self.height - FOOTER_H + 40, self.width - PAD * 2 - AREA_LIST_W - 8, FOOTER_H - 48, 20)
    self.reqList.doDrawItem = function(list, y, item, alt)
        return self:drawReqItem(list, y, item, alt)
    end
    self:addChild(self.reqList)

    local refreshW = 150
    self.refreshButton = ISButton:new(self.width - PAD - refreshW, self.height - FOOTER_H + 6, refreshW, 26, "REFRESH AREA", self, Panel.onRefresh)
    self.refreshButton:initialise()
    self.refreshButton:instantiate()
    self:addChild(self.refreshButton)

    self.confirmButton = ISButton:new(self.width - PAD - refreshW - 118, self.height - FOOTER_H + 6, 110, 26, getText("IGUI_ExtractionModeExpanded_PayBanks"), self, Panel.onConfirmRefreshPaid)
    self.confirmButton:initialise()
    self.confirmButton:instantiate()
    self.confirmButton:setVisible(false)
    self:addChild(self.confirmButton)

    self.freeRefreshButton = ISButton:new(self.width - PAD - refreshW - 236, self.height - FOOTER_H + 6, 110, 26, getText("IGUI_ExtractionModeExpanded_UseFree"), self, Panel.onConfirmRefreshFree)
    self.freeRefreshButton:initialise()
    self.freeRefreshButton:instantiate()
    self.freeRefreshButton:setVisible(false)
    self:addChild(self.freeRefreshButton)

    self.cancelButton = ISButton:new(self.width - PAD - refreshW - 354, self.height - FOOTER_H + 6, 110, 26, getText("IGUI_ExtractionModeExpanded_Cancel"), self, Panel.onCancelRefresh)
    self.cancelButton:initialise()
    self.cancelButton:instantiate()
    self.cancelButton:setVisible(false)
    self:addChild(self.cancelButton)

    self.minusButton = ISButton:new(PAD, 0, 28, 26, "-", self, Panel.onQty)
    self.minusButton.delta = -1
    self.plusButton = ISButton:new(PAD + 148, 0, 28, 26, "+", self, Panel.onQty)
    self.plusButton.delta = 1
    self.depositButton = ISButton:new(PAD + 184, 0, 150, 26, getText("IGUI_ExtractionModeExpanded_BankSelected"), self, Panel.onDeposit)
    self.undoButton = ISButton:new(PAD + 372, 0, 90, 26,
        getText("IGUI_ExtractionModeExpanded_Undo"), self, Panel.onUndo)
    for _, button in ipairs({ self.minusButton, self.plusButton, self.depositButton, self.undoButton }) do
        button:initialise()
        button:instantiate()
        self:addChild(button)
    end

    self.registerButton = ISButton:new(PAD, self.height - 50, 320, 28,
        getText("IGUI_ExtractionModeExpanded_Register"), self, Panel.onRegister)
    self.registerButton:initialise()
    self.registerButton:instantiate()
    self:addChild(self.registerButton)

    self.collectionList = newList(PAD, 80, 320, self.height - 140, 24)
    self.collectionList.onmousedown = function(_, item)
        self.selectedCollectionKey = item
        self:rebuildSlots()
        if self.registering then self:refreshRegisterCandidates() end
    end
    self:addChild(self.collectionList)

    self.slotList = newList(352, 124, self.width - 352 - PAD, self.height - 182, 20)
    self.slotList.doDrawItem = function(list, y, item, alt)
        return self:drawSlotItem(list, y, item, alt)
    end
    self:addChild(self.slotList)

    self.bankTrophyButton = ISButton:new(PAD, self.height - 50, 170, 28,
        getText("IGUI_ExtractionModeExpanded_BankTrophy"), self, Panel.onBankTrophy)
    self.applyReliefButton = ISButton:new(PAD + 178, self.height - 50, 140, 28,
        getText("IGUI_ExtractionModeExpanded_ApplyRelief"), self, Panel.onApplyRelief)
    self.bankTrophyButton:initialise()
    self.bankTrophyButton:instantiate()
    self.applyReliefButton:initialise()
    self.applyReliefButton:instantiate()
    self:addChild(self.bankTrophyButton)
    self:addChild(self.applyReliefButton)

    local colW = math.floor((self.width - PAD * 2 - AREA_LIST_W - 32) / 3)
    self.trophyCols = {}
    local function makeTrophyList(tier, x, y, w, h)
        local list = newList(x, y, w, h, 22)
        list.trophyTier = tier
        list.onmousedown = function(_, item)
            self.selectedTrophyEntry = item
            self.selectedTrophyTier = tier
        end
        list.doDrawItem = function(box, y0, item, alt)
            return self:drawTrophyCatalogItem(box, y0, item, alt)
        end
        self:addChild(list)
        return list
    end

    self.trophyCols.uncommon = makeTrophyList("uncommon", PAD, 148, colW, 200)
    self.trophyCols.uncommonMore = makeTrophyList("uncommon", PAD + colW + 8, 148, colW, 100)
    self.trophyCols.rare = makeTrophyList("rare", PAD + colW + 8, 300, colW, 100)
    self.trophyCols.legendary = makeTrophyList("legendary", PAD + (colW + 8) * 2, 148, colW, 100)

    self:applyTabState()
    self:rebuildLists()
end

function Panel:footerY()
    return self.height - FOOTER_H
end

function Panel:trophyPaneLayout()
    local ITEM_H = 22
    local leftW = self.width - PAD * 2 - AREA_LIST_W - 16
    local colW = math.floor((leftW - 16) / 3)
    local gap = 8
    local topY = 120
    local bottomY = self.height - 58
    local labelH = 24
    local labelGap = 4
    local endPad = ITEM_H
    local c1x = PAD
    local c2x = PAD + colW + gap
    local c3x = PAD + (colW + gap) * 2
    local listTop = topY + labelH + labelGap

    local trophies = Config.trophies() or {}
    local uncommonN = #((trophies.uncommon and trophies.uncommon.items) or {})
    local rareN = #((trophies.rare and trophies.rare.items) or {})
    local legendaryN = #((trophies.legendary and trophies.legendary.items) or {})

    local leftListH = bottomY - listTop
    local leftCap = math.max(1, math.floor((leftListH - endPad) / ITEM_H))
    local split = math.min(leftCap, uncommonN)
    local restN = math.max(0, uncommonN - split)

    local moreListH = restN * ITEM_H + endPad
    local rareLabelY = listTop + moreListH + gap
    local rareListY = rareLabelY + labelH + labelGap
    local rareListH = math.max(rareN * ITEM_H + endPad, bottomY - rareListY)

    local moreCap = math.max(1, math.floor((moreListH - endPad) / ITEM_H))
    if restN > moreCap then
        moreListH = moreCap * ITEM_H + endPad
        rareLabelY = listTop + moreListH + gap
        rareListY = rareLabelY + labelH + labelGap
        rareListH = math.max(rareN * ITEM_H + endPad, bottomY - rareListY)
        restN = moreCap
        split = uncommonN - restN
    end

    local legendaryListH = legendaryN * ITEM_H + endPad
    local tutorialY = listTop + legendaryListH + gap
    return {
        itemH = ITEM_H,
        uncommonSplit = split,
        cols = {
            uncommon = {
                x = c1x, labelY = topY, listY = listTop, w = colW,
                listH = leftListH,
                title = getText("IGUI_ExtractionModeExpanded_TrophyUncommon"),
            },
            uncommonMore = {
                x = c2x, labelY = topY, listY = listTop, w = colW,
                listH = moreListH,
                title = getText("IGUI_ExtractionModeExpanded_TrophyUncommonMore"),
            },
            rare = {
                x = c2x, labelY = rareLabelY, listY = rareListY, w = colW,
                listH = rareListH,
                title = getText("IGUI_ExtractionModeExpanded_TrophyRare"),
            },
            legendary = {
                x = c3x, labelY = topY, listY = listTop, w = colW,
                listH = legendaryListH,
                title = getText("IGUI_ExtractionModeExpanded_TrophyLegendary"),
            },
        },
        tutorialX = c3x,
        tutorialY = tutorialY,
        tutorialW = colW,
        tutorialH = math.max(40, bottomY - tutorialY),
    }
end

function Panel:layoutRefresh()
    local banking = self.activeTab == "refresh" and self.bankKind ~= nil
    local registering = self.activeTab == "oddities" and self.registering == true
    local wantW = banking and (PANEL_WIDTH + BANK_POPOUT_GAP + BANK_POPOUT_W) or PANEL_WIDTH
    if math.abs((self.width or 0) - wantW) > 0.5 then
        self:setWidth(wantW)
    end
    if self.closeButton then
        self.closeButton:setX(PANEL_WIDTH - 36)
    end

    local stockY = 136
    local footerY = self:footerY()
    local stockBottom = footerY - 10
    local mainInnerW = PANEL_WIDTH - PAD * 2
    if self.stockList then
        self.stockList:setX(PAD)
        self.stockList:setY(stockY)
        self.stockList:setWidth(mainInnerW)
        self.stockList:setHeight(math.max(80, stockBottom - stockY))
    end
    if self.candidateList then
        if registering then
            self.candidateList:setX(352)
            self.candidateList:setY(124)
            self.candidateList:setWidth(PANEL_WIDTH - 352 - PAD)
            self.candidateList:setHeight(math.max(80, self.height - 182 - 36))
            self.candidateList:setVisible(true)
        elseif banking then
            local px = PANEL_WIDTH + BANK_POPOUT_GAP
            local listX = px + PAD
            local listY = self:bankUndoCount() > 0 and 96 or 72
            local listW = BANK_POPOUT_W - PAD * 2
            local listH = math.max(80, self.height - listY - 78)
            local hasItems = self.candidates ~= nil and #self.candidates > 0
            self.candidateList:setX(listX)
            self.candidateList:setY(listY)
            self.candidateList:setWidth(listW)
            self.candidateList:setHeight(listH)
            self.candidateList:setVisible(hasItems)
            self.candidateList.backgroundColor = { r = 0.02, g = 0.02, b = 0.025, a = 0.96 }
        else
            self.candidateList:setVisible(false)
        end
    end
    if self.areaList then
        self.areaList:setX(PAD)
        self.areaList:setY(footerY)
        self.areaList:setWidth(AREA_LIST_W)
        self.areaList:setHeight(FOOTER_H - 8)
        if self.activeTab == "trophies" then
            self.areaList:setY(148)
            self.areaList:setX(PANEL_WIDTH - PAD - AREA_LIST_W)
            self.areaList:setHeight(math.max(80, self.height - 208))
        end
        if self.reqList then
            self.reqList:setX(PAD + AREA_LIST_W + 8)
            self.reqList:setY(footerY + 40)
            self.reqList:setWidth(PANEL_WIDTH - PAD - (PAD + AREA_LIST_W + 8))
            self.reqList:setHeight(FOOTER_H - 48)
        end
        local refreshW = 150
        local btnY = footerY + 6
        if self.refreshButton then
            self.refreshButton:setX(PANEL_WIDTH - PAD - refreshW)
            self.refreshButton:setY(btnY)
            self.refreshButton:setWidth(refreshW)
            self.refreshButton:setHeight(26)
        end
        if self.confirmButton then
            self.confirmButton:setX(PANEL_WIDTH - PAD - refreshW - 118)
            self.confirmButton:setY(btnY)
            self.confirmButton:setWidth(110)
            self.confirmButton:setHeight(26)
        end
        if self.freeRefreshButton then
            self.freeRefreshButton:setX(PANEL_WIDTH - PAD - refreshW - 236)
            self.freeRefreshButton:setY(btnY)
            self.freeRefreshButton:setWidth(110)
            self.freeRefreshButton:setHeight(26)
        end
        if self.cancelButton then
            self.cancelButton:setX(PANEL_WIDTH - PAD - refreshW - 354)
            self.cancelButton:setY(btnY)
            self.cancelButton:setWidth(110)
            self.cancelButton:setHeight(26)
        end
    end
    if self.trophyList then
        self.trophyList:setVisible(false)
    end
    if self.trophyCols then
        local layout = self:trophyPaneLayout()
        for tier, box in pairs(layout.cols or {}) do
            local list = self.trophyCols[tier]
            if list and box then
                list:setX(box.x)
                list:setY(box.listY)
                list:setWidth(box.w)
                list:setHeight(math.max(box.listH, 1))
                if list.vscroll then
                    list.vscroll:setVisible(false)
                end
            end
        end
        self.trophyLayout = layout
    end
    if self.bankTrophyButton then
        self.bankTrophyButton:setX(PAD)
        self.bankTrophyButton:setY(self.height - 50)
    end
    if self.applyReliefButton then
        self.applyReliefButton:setX(PAD + 178)
        self.applyReliefButton:setY(self.height - 50)
    end
    if banking then
        local px = PANEL_WIDTH + BANK_POPOUT_GAP
        local ctrlY = self.height - 50
        local x = px + PAD
        local hasItems = self.candidates ~= nil and #self.candidates > 0

        if self.minusButton then
            self.minusButton:setX(x)
            self.minusButton:setY(ctrlY)
            self.minusButton:setWidth(28)
            self.minusButton:setVisible(hasItems)
        end
        if self.plusButton then
            self.plusButton:setX(x + 36)
            self.plusButton:setY(ctrlY)
            self.plusButton:setWidth(28)
            self.plusButton:setVisible(hasItems)
        end
        if self.depositButton then
            self.depositButton:setX(x + 72)
            self.depositButton:setY(ctrlY)
            self.depositButton:setWidth(150)
            local titles = {
                value = getText("IGUI_ExtractionModeExpanded_SellSelected"),
                weapons = getText("IGUI_ExtractionModeExpanded_ProvideSelected"),
                bulk = getText("IGUI_ExtractionModeExpanded_ContributeSelected"),
                key = getText("IGUI_ExtractionModeExpanded_DonateSelected"),
            }
            self.depositButton:setTitle(titles[self.bankKind] or getText("IGUI_ExtractionModeExpanded_BankSelected"))
            self.depositButton:setVisible(hasItems)
        end
        if self.undoButton then
            local undoX = hasItems and (x + 72 + 158) or x
            self.undoButton:setX(undoX)
            self.undoButton:setY(ctrlY)
            self.undoButton:setWidth(90)
            self.undoButton:setTitle(getText("IGUI_ExtractionModeExpanded_Undo"))
            self.undoButton:setVisible(true)
        end
    elseif registering then
        if self.depositButton then
            self.depositButton:setX(352)
            self.depositButton:setY(self.height - 50)
            self.depositButton:setWidth(170)
            self.depositButton:setTitle(getText("IGUI_ExtractionModeExpanded_RegisterSelected"))
            self.depositButton:setVisible(true)
        end
        if self.undoButton then self.undoButton:setVisible(false) end
        if self.minusButton then self.minusButton:setVisible(false) end
        if self.plusButton then self.plusButton:setVisible(false) end
        if self.slotList then self.slotList:setVisible(false) end
    else
        if self.minusButton then self.minusButton:setVisible(false) end
        if self.plusButton then self.plusButton:setVisible(false) end
        if self.depositButton and self.activeTab ~= "oddities" then
            self.depositButton:setVisible(false)
        end
        if self.undoButton then self.undoButton:setVisible(false) end
    end
    if self.slotList then
        self.slotList:setX(352)
        self.slotList:setY(124)
        self.slotList:setWidth(PANEL_WIDTH - 352 - PAD)
        self.slotList:setHeight(math.max(80, self.height - 182))
        if not registering and self.activeTab == "oddities" then
            self.slotList:setVisible(true)
        end
    end
    for _, list in ipairs({ self.stockList, self.candidateList, self.areaList, self.reqList, self.collectionList, self.slotList }) do
        if list and list.vscroll then
            list.vscroll:setX(list.width - list.vscroll.width)
            list.vscroll:setHeight(list.height)
        end
    end
    if self.trophyCols then
        for _, list in pairs(self.trophyCols) do
            if list and list.vscroll then
                list.vscroll:setVisible(false)
            end
        end
    end
end

function Panel:applyTabState()
    local refresh = self.activeTab == "refresh"
    local oddities = self.activeTab == "oddities"
    local trophies = self.activeTab == "trophies"
    if self.areaList then self.areaList:setVisible(refresh or trophies) end
    if self.reqList then self.reqList:setVisible(refresh) end
    if self.stockList then self.stockList:setVisible(refresh) end
    if self.sellButton then self.sellButton:setVisible(refresh) end
    if self.provideButton then self.provideButton:setVisible(refresh) end
    if self.contributeButton then self.contributeButton:setVisible(refresh) end
    if self.donateButton then self.donateButton:setVisible(refresh) end
    if self.refreshButton then self.refreshButton:setVisible(refresh) end
    if self.registerButton then self.registerButton:setVisible(oddities) end
    if self.collectionList then self.collectionList:setVisible(oddities) end
    if self.slotList then self.slotList:setVisible(oddities and not self.registering) end
    if self.trophyList then self.trophyList:setVisible(false) end
    if self.trophyCols then
        for _, list in pairs(self.trophyCols) do
            list:setVisible(trophies)
        end
    end
    if refresh or trophies then self.registering = false end
    if self.sellTrophyButton then self.sellTrophyButton:setVisible(false) end
    if self.bankTrophyButton then self.bankTrophyButton:setVisible(trophies) end
    if self.applyReliefButton then self.applyReliefButton:setVisible(trophies) end
    if self.refreshTab then self.refreshTab.enable = not refresh end
    if self.odditiesTab then self.odditiesTab.enable = not oddities end
    if self.trophiesTab then self.trophiesTab.enable = not trophies end
    self:layoutRefresh()
    self:syncBankControls()
end

function Panel:syncBankControls()
    local banking = self.activeTab == "refresh" and self.bankKind ~= nil
    local registering = self.activeTab == "oddities" and self.registering == true
    if not banking and not registering then
        if self.minusButton then self.minusButton:setVisible(false) end
        if self.plusButton then self.plusButton:setVisible(false) end
        if self.depositButton then self.depositButton:setVisible(false) end
        if self.undoButton then self.undoButton:setVisible(false) end
    end
    self:layoutRefresh()
end

function Panel:bankUndoCount()
    return Client.bankUndoCount(Util.localPlayer(self.playerNum)) or 0
end

function Panel:commitBankSession()
    Client.commitBankSession(Util.localPlayer(self.playerNum))
end

function Panel:finishBankLeave(action, payload)
    self:commitBankSession()
    if action == "tab" then
        self:_applyTab(payload)
    elseif action == "bank" then
        self:_applyBank(payload)
    elseif action == "close" then
        self:_applyClose()
    elseif action == "register" then
        self:_applyRegister()
    elseif action == "clear" then
        self.bankKind = nil
        self:rebuildStock()
        self:syncBankControls()
    end
end

function Panel:onConfirmEndBankUndo(button, request)
    self:holdPause()
    if button == nil or button.internal ~= "YES" then return end
    if type(request) ~= "table" then return end
    self:finishBankLeave(request.action, request.payload)
end

function Panel:confirmEndBankUndo(action, payload)
    local text = getText("IGUI_ExtractionModeExpanded_ConfirmEndBankUndo")
    local width, height = 480, 140
    local screenWidth = getCore():getScreenWidth()
    local screenHeight = getCore():getScreenHeight()
    local request = { action = action, payload = payload }
    local modal = ISModalDialog:new(
        math.floor((screenWidth - width) / 2),
        math.floor((screenHeight - height) / 2),
        width, height, text, true, self, Panel.onConfirmEndBankUndo, self.playerNum, request)
    modal:initialise()
    modal:addToUIManager()
    modal:setAlwaysOnTop(true)
    modal.moveWithMouse = true
end

function Panel:requestBankLeave(action, payload)
    local hasUndos = self:bankUndoCount() > 0
    local warn = ClientOptions.warnEndBankUndo()
    if hasUndos and warn then
        self:confirmEndBankUndo(action, payload)
        return
    end
    self:finishBankLeave(action, payload)
end

function Panel:_applyTab(tabId)
    self.activeTab = tabId
    self.bankKind = nil
    self.confirming = false
    self.registering = false
    if self.confirmButton then self.confirmButton:setVisible(false) end
    if self.freeRefreshButton then self.freeRefreshButton:setVisible(false) end
    if self.cancelButton then self.cancelButton:setVisible(false) end
    if self.refreshButton then self.refreshButton:setVisible(true) end
    self:applyTabState()
    self:syncBankControls()
end

function Panel:_applyBank(button)
    self.registering = false
    if button == nil then
        self.bankKind = nil
    elseif self.bankKind == button.kind then
        self.bankKind = nil
    else
        self.bankKind = button.kind
    end
    self:refreshCandidates()
    self:rebuildStock()
    self:syncBankControls()
end

function Panel:_applyClose()
    self.bankKind = nil
    self:resumeSinglePlayer()
    self:setVisible(false)
end

function Panel:_applyRegister()
    self.bankKind = nil
    self.registering = not self.registering
    if self.registering then
        self:refreshRegisterCandidates()
    end
    self:syncBankControls()
end

function Panel:onSelectTab(button)
    if button == nil or button.tabId == nil then return end
    if button.tabId == self.activeTab then return end
    if self:bankUndoCount() > 0 then
        self:requestBankLeave("tab", button.tabId)
        return
    end
    self:commitBankSession()
    self:_applyTab(button.tabId)
end

function Panel:onBank(button)
    if not inHideout(Util.localPlayer(self.playerNum)) then return end

    if self.bankKind ~= nil and button ~= nil and self.bankKind == button.kind then
        if self:bankUndoCount() > 0 then
            self:requestBankLeave("bank", button)
            return
        end
        self:commitBankSession()
    end
    self:_applyBank(button)
end

function Panel:onUndo()
    if not inHideout(Util.localPlayer(self.playerNum)) then return end
    if self:bankUndoCount() <= 0 then return end
    Client.undoDeposit(Util.localPlayer(self.playerNum))
    self:rebuildLists()
    self:syncBankControls()
end

function Panel:drawStockItem(list, y, item, alt)
    if not item.height then item.height = list.itemheight end
    if y + list:getYScroll() >= -item.height and y + list:getYScroll() <= list.height then
        if alt then
            list:drawRect(0, y, list:getWidth(), item.height, 0.08, 1, 1, 1)
        end
        local row = item.item
        local cells = row and (row.cells or { row.left, row.right }) or {}
        local cols = math.max(1, row and row.cols or #cells)
        local colW = math.floor(list:getWidth() / cols)
        for c = 1, cols do
            local cell = cells[c]
            if cell then
                local color = stockColor(cell)
                list:drawText(stockText(cell), 8 + (c - 1) * colW, y + 2, color[1], color[2], color[3], 1, UIFont.Small)
            end
        end
    end
    return y + item.height
end

function Panel:drawSlotItem(list, y, item, alt)
    if not item.height then item.height = list.itemheight end
    if y + list:getYScroll() >= -item.height and y + list:getYScroll() <= list.height then
        if alt then
            list:drawRect(0, y, list:getWidth(), item.height, 0.08, 1, 1, 1)
        end
        local row = item.item or {}
        local color = row.filled and GREEN or GREY
        if row.texture then
            list:drawTextureScaledAspect(row.texture, 6, y + 1, 16, 16, 1, 1, 1, 1)
        end
        list:drawText(row.name or item.text or "", 28, y + 2, color[1], color[2], color[3], 1, UIFont.Small)
    end
    return y + item.height
end

function Panel:drawTrophyCatalogItem(list, y, item, alt)
    if not item.height then item.height = list.itemheight end
    if y + list:getYScroll() >= -item.height and y + list:getYScroll() <= list.height then
        local entry = item.item
        local selected = self.selectedTrophyEntry == entry
        if selected then
            list:drawRect(0, y, list:getWidth(), item.height, 0.28, 0.45, 0.32, 0.12)
        elseif alt then
            list:drawRect(0, y, list:getWidth(), item.height, 0.08, 1, 1, 1)
        end
        local owned = entry and (tonumber(entry.owned) or 0) or 0
        local color = selected and GOLD or (owned > 0 and WHITE or GREY)
        if entry and entry.texture then
            list:drawTextureScaledAspect(entry.texture, 4, y + 2, 16, 16, 1, 1, 1, 1)
        end
        local label = entry and entry.name or (item.text or "")
        if owned > 0 then
            label = string.format("%s  x%d", label, owned)
        end
        list:drawText(label, 24, y + 3, color[1], color[2], color[3], 1, UIFont.Small)
    end
    return y + item.height
end

function Panel:drawCandidateItem(list, y, item, alt)
    if not item.height then item.height = list.itemheight end
    if y + list:getYScroll() >= -item.height and y + list:getYScroll() <= list.height then
        local entry = item.item
        local selected = self.selectedCandidate == entry
        if selected then
            list:drawRect(0, y, list:getWidth(), item.height, 0.28, 0.45, 0.32, 0.12)
        elseif alt then
            list:drawRect(0, y, list:getWidth(), item.height, 0.08, 1, 1, 1)
        end
        local color = WHITE
        if entry and entry.reason then
            color = RED
        elseif selected then
            color = GOLD
        elseif entry and (entry.trophyTier or entry.collectionMark or entry.otherUse) then
            color = GOLD
        end
        local textX = 10
        if entry and entry.otherUse then
            local iconSize = 14
            local iconX = 4
            local iconY = y + math.floor((item.height - iconSize) / 2)
            list:drawRect(iconX, iconY, iconSize, iconSize, 0.95, 0.72, 0.18, 0.16)
            list:drawRectBorder(iconX, iconY, iconSize, iconSize, 0.95, 0.96, 0.72, 0.18)
            list:drawTextCentre("!", iconX + iconSize / 2, iconY - 1, 0.98, 0.82, 0.2, 1, UIFont.Small)
            textX = iconX + iconSize + 6
        end
        local ledger = uiLedger(Util.localPlayer(self.playerNum))
        local label = candidateLabel(entry, self.bankKind, ledger)
        if label == "" then label = item.text or "" end
        list:drawText(label, textX, y + 4, color[1], color[2], color[3], 1, UIFont.Small)
    end
    return y + item.height
end

function Panel:drawAreaItem(list, y, item, alt)
    if not item.height then item.height = list.itemheight end
    if y + list:getYScroll() >= -item.height and y + list:getYScroll() <= list.height then
        local selected = item.item == self.selectedAreaKey
        if selected then
            list:drawRect(0, y, list:getWidth(), item.height, 0.55, 0.45, 0.32, 0.12)
        elseif alt then
            list:drawRect(0, y, list:getWidth(), item.height, 0.08, 1, 1, 1)
        end
        local color = selected and GOLD or WHITE
        local name = item.text or ""
        local ledger = uiLedger(Util.localPlayer(self.playerNum))
        local m = Multiplier.M(ledger, item.item)
        local multText = "x" .. formatCount(m, true)
        list:drawText(name, 8, y + 3, color[1], color[2], color[3], 1, UIFont.Small)
        local multW = getTextManager():MeasureStringX(UIFont.Small, multText)
        list:drawText(multText, list:getWidth() - multW - 10, y + 3, color[1], color[2], color[3], 1, UIFont.Small)
    end
    return y + item.height
end

function Panel:drawReqItem(list, y, item, alt)
    if not item.height then item.height = list.itemheight end
    if y + list:getYScroll() >= -item.height and y + list:getYScroll() <= list.height then
        if alt then
            list:drawRect(0, y, list:getWidth(), item.height, 0.08, 1, 1, 1)
        end
        local row = item.item
        local cells = row and (row.cells or { row }) or {}
        local cols = math.max(1, row and row.cols or #cells)
        local colW = math.floor(list:getWidth() / cols)
        for c = 1, cols do
            local cell = cells[c]
            if cell then
                local tone = cell.tone
                if tone == nil then tone = cell.met and "met" or "short" end
                local color = GREEN
                if tone == "idle" then color = GREY
                elseif tone ~= "met" then color = RED end
                list:drawText(cell.text or "", 8 + (c - 1) * colW, y + 3, color[1], color[2], color[3], 1, UIFont.Small)
            end
        end
    end
    return y + item.height
end

function Panel:selectAreaAt(list, x, y)
    if list == nil or list.items == nil then return end
    local index = nil
    if list.rowAt then
        index = list:rowAt(x, y)
    end
    if index == nil or index < 1 then
        local scroll = 0
        if list.getYScroll then scroll = list:getYScroll() end
        index = math.floor((y - scroll) / math.max(1, list.itemheight or 26)) + 1
    end
    local row = list.items[index]
    if row == nil or row.item == nil then return end
    local payload = row.item
    if payload.cells then
        local cols = payload.cols or 2
        local col = math.floor(x / math.max(1, list:getWidth() / cols)) + 1
        col = Util.clamp(col, 1, cols)
        local cell = payload.cells[col]
        if cell and cell.key then
            self.selectedAreaKey = cell.key
            self:rebuildRequirements()
        end
    end
end

function Panel:materialRows(ledger)
    local rows = {}
    local seen = {}
    local covered = {}
    local function typeKey(types)
        local copy = {}
        for _, fullType in ipairs(types or {}) do
            copy[#copy + 1] = tostring(fullType)
        end
        table.sort(copy)
        return table.concat(copy, "|")
    end
    local function addLine(label, types, bag)
        local key = typeKey(types)
        if label == nil or key == "" or seen[key] then return end
        seen[key] = true
        for _, fullType in ipairs(types or {}) do covered[fullType] = true end
        rows[#rows + 1] = { label = label, count = countTypes(bag, types), points = false }
    end
    local completions = State.completions(Util.localPlayer(self.playerNum))
    for _, area in ipairs(Config.areas()) do
        local unlocked = Config.areaUnlocked(area.key, completions)
        for _, line in ipairs(area.quest or {}) do
            if line.tier == "key" and not unlocked then

            else
                local bag = line.tier == "bulk" and ledger.bulk or ledger.keyItems
                addLine(Items.primaryRefreshLabel(line), line.types, bag)
                if line.alt then addLine(line.alt.label, line.alt.types, bag) end
            end
        end
    end
    table.sort(rows, function(a, b)
        return string.lower(a.label) < string.lower(b.label)
    end)
    local function leftovers(bag)
        for fullType, amount in pairs(bag or {}) do
            if not covered[fullType] and (tonumber(amount) or 0) > 0 then
                rows[#rows + 1] = {
                    label = Util.displayName(fullType) or fullType,
                    count = tonumber(amount) or 0,
                    points = false,
                }
            end
        end
    end
    leftovers(ledger.bulk)
    leftovers(ledger.keyItems)
    return rows
end

function Panel:rebuildStock()
    if self.stockList == nil then return end
    self.stockList:clear()
    local player = Util.localPlayer(self.playerNum)
    local ledger = uiLedger(player)
    local materials = self:materialRows(ledger)
    local cols = stockColumnCount(self.bankKind ~= nil)
    for i = 1, #materials, cols do
        local cells = {}
        for c = 1, cols do
            cells[c] = materials[i + c - 1]
        end
        self.stockList:addItem("", { cells = cells, cols = cols })
    end
end

function Panel:rebuildRequirements()
    if self.reqList == nil then return end
    self.reqList:clear()
    local player = Util.localPlayer(self.playerNum)
    local ledger = uiLedger(player)
    local area = Config.area(self.selectedAreaKey)
    if area == nil then return end
    local unlocked = Config.areaUnlocked(area.key, State.completions(player))
    local freeStatus = Banks.homeTheaterFreeStatus(ledger)
    local valueNeed = Multiplier.valueCost(ledger, area)
    local weaponNeed = Multiplier.weaponCost(ledger, area)
    local entries = {}
    local function toneFor(met)
        return met and "met" or "short"
    end
    if freeStatus.owned and freeStatus.label then
        entries[#entries + 1] = {
            text = freeStatus.label,
            tone = toneFor(freeStatus.available == true),
        }
    end
    entries[#entries + 1] = {
        text = string.format("Value  %s / %s", formatCount(math.min(ledger.value, valueNeed), true), formatCount(valueNeed, true)),
        tone = toneFor(ledger.value + 0.0001 >= valueNeed),
    }
    entries[#entries + 1] = {
        text = string.format("Weapons  %s / %s", formatCount(math.min(ledger.weapons, weaponNeed), true), formatCount(weaponNeed, true)),
        tone = toneFor(ledger.weapons + 0.0001 >= weaponNeed),
    }
    local coverage = Banks.questCoverage(ledger, area) or {}
    for _, row in ipairs(coverage) do
        local line = row.line
        if line and line.tier == "key" and not unlocked then

        elseif line then
            local function sideTone(sideMet)
                if row.funded and sideMet then return "met" end
                if row.funded then return "idle" end
                return "short"
            end
            entries[#entries + 1] = {
                text = string.format("%s  %d / %d", line.label, math.min(row.have, row.need), row.need),
                tone = sideTone(row.primary == true),
            }
            if line.alt then
                local altText
                if row.each then
                    altText = string.format("or %s  %d / %d", line.alt.label, row.altHave or 0, row.pieceCount or 0)
                else
                    altText = string.format("or %s  %d / %d", line.alt.label, math.min(row.altHave, row.altNeed), row.altNeed)
                end
                entries[#entries + 1] = {
                    text = altText,
                    tone = sideTone(row.alt == true),
                }
            end
        end
    end
    if RefreshMod.Refresh then
        local blocked = RefreshMod.Refresh.blockedReason(area.key)
        if blocked then
            entries[#entries + 1] = { text = blocked, tone = "short" }
        end
    end
    for _, row in ipairs(packColumns(entries, 2)) do
        self.reqList:addItem("", row)
    end
end

function Panel:rebuildLists()
    if self.areaList then
        self.areaList:clear()
        for _, area in ipairs(Config.areas()) do
            self.areaList:addItem(area.name, area.key)
        end
        if self.selectedAreaKey == nil and Config.areas()[1] then
            self.selectedAreaKey = Config.areas()[1].key
        end
    end
    if self.collectionList then
        self.collectionList:clear()
        local player = Util.localPlayer(self.playerNum)
        if not Util.isRemoteClient() then
            Collections.syncRegisteredItems(player, State.ledger(player))
        end
        local ledger = uiLedger(player)
        for _, collection in ipairs(Config.collections()) do
            local n = Collections.collectedCount(ledger, collection)
            self.collectionList:addItem(string.format("%s (%d/%d)", collection.name, n, collection.slots), collection.key)
        end
        if self.selectedCollectionKey == nil and Config.collections()[1] then
            self.selectedCollectionKey = Config.collections()[1].key
        end
    end
    self:rebuildStock()
    self:rebuildRequirements()
    if self.registering and self.activeTab == "oddities" then
        self:refreshRegisterCandidates()
    else
        self:refreshCandidates()
    end
    self:rebuildSlots()
    self:rebuildTrophyList()
end

function Panel:rebuildTrophyList()
    local player = Util.localPlayer(self.playerNum)
    local owned = {}
    if player then
        for _, item in ipairs(Util.inventoryItems(player)) do
            local fullType = Util.fullType(item)
            local tier = Config.trophyTier(fullType)
            if tier and not Items.registeredCollection(item) then
                owned[fullType] = (owned[fullType] or 0) + 1
            end
        end
    end
    self.selectedTrophyEntry = nil
    local trophies = Config.trophies() or {}

    local function fillList(list, tier, fullTypes, data)
        if list == nil then return end
        list:clear()
        for _, fullType in ipairs(fullTypes or {}) do
            local entry = {
                fullType = fullType,
                tier = tier,
                name = Util.displayName(fullType),
                texture = Util.itemTexture(fullType),
                owned = owned[fullType] or 0,
                sellValue = data and tonumber(data.sellValue) or 0,
                relief = data and tonumber(data.excessRelief) or 0,
                tokenKey = Config.trophyTokenKey(tier),
            }
            list:addItem(entry.name, entry)
        end
    end

    local uncommonData = trophies.uncommon
    local uncommonItems = (uncommonData and uncommonData.items) or {}
    local layout = self.trophyLayout or self:trophyPaneLayout()
    local split = tonumber(layout.uncommonSplit) or math.ceil(#uncommonItems / 2)
    local first, rest = {}, {}
    for i, fullType in ipairs(uncommonItems) do
        if i <= split then
            first[#first + 1] = fullType
        else
            rest[#rest + 1] = fullType
        end
    end
    fillList(self.trophyCols and self.trophyCols.uncommon, "uncommon", first, uncommonData)
    fillList(self.trophyCols and self.trophyCols.uncommonMore, "uncommon", rest, uncommonData)
    fillList(self.trophyCols and self.trophyCols.rare, "rare", trophies.rare and trophies.rare.items, trophies.rare)
    fillList(self.trophyCols and self.trophyCols.legendary, "legendary", trophies.legendary and trophies.legendary.items, trophies.legendary)
    if self.trophyCols then
        for _, list in pairs(self.trophyCols) do
            if list and list.vscroll then list.vscroll:setVisible(false) end
        end
    end
end

local function findInventoryTrophy(player, fullType)
    if player == nil or fullType == nil then return nil end
    for _, item in ipairs(Util.inventoryItems(player)) do
        if Util.fullType(item) == fullType
            and not Items.registeredCollection(item)
            and Items.bankRejectReason(item, player) == nil then
            return item
        end
    end
end

function Panel:rebuildSlots()
    if self.slotList == nil then return end
    self.slotList:clear()
    local collection = Config.collection(self.selectedCollectionKey)
    if collection == nil then return end
    local ledger = uiLedger(Util.localPlayer(self.playerNum))
    for index, slot in ipairs(collection.items or {}) do
        local entry = {
            name = Collections.slotLabel(slot),
            texture = Util.itemTexture(slot[1]),
            filled = Collections.slotFilled(ledger, collection.key, index),
        }
        self.slotList:addItem(entry.name, entry)
    end
end

local function captureCandidateIndex(self)
    local index = 0
    if self.candidateList then
        index = math.floor(tonumber(self.candidateList.selected) or 0)
    end
    if index < 1 and self.selectedCandidate and type(self.candidates) == "table" then
        for i, entry in ipairs(self.candidates) do
            if entry == self.selectedCandidate then
                index = i
                break
            end
        end
    end
    if index < 1 then index = 1 end
    return index
end

local function applyCandidateIndex(self, prevIndex)
    local count = #(self.candidates or {})
    if count < 1 then
        self.selectedCandidate = nil
        if self.candidateList then self.candidateList.selected = 0 end
        return
    end
    local index = math.min(math.max(1, math.floor(tonumber(prevIndex) or 1)), count)
    self.selectedCandidate = self.candidates[index]
    if self.candidateList then
        self.candidateList.selected = index
        if self.candidateList.ensureVisible then
            if self.candidateList.ensureVisible then self.candidateList:ensureVisible(index) end
        end
    end
end

function Panel:refreshCandidates()
    local prevIndex = captureCandidateIndex(self)
    self.candidates = {}
    if self.candidateList then self.candidateList:clear() end
    local player = Util.localPlayer(self.playerNum)
    if player == nil or self.bankKind == nil then
        applyCandidateIndex(self, prevIndex)
        return
    end
    for _, item in ipairs(Util.inventoryItems(player)) do
        local offer = Items.offerBlockReason(item, player, false, false)
        local contents = Items.contentsBlockReason(item)
        if offer == nil then
            local fullType = Util.fullType(item)
            local accept = false
            if self.bankKind == "value" then
                accept = Items.valueOf(item, uiLedger(player)) > 0
            elseif self.bankKind == "weapons" then
                accept = Items.weaponPointsOf(item) > 0
            elseif self.bankKind == "bulk" or self.bankKind == "key" then
                for _, other in ipairs(Config.areas()) do
                    for _, line in ipairs(other.quest or {}) do
                        if line.tier == self.bankKind and Items.matchesTypes(item, Items.lineTypes(line)) then
                            accept = true
                        end
                    end
                end
            end
            if accept then
                local entry = annotateCandidate({
                    item = item,
                    fullType = fullType,
                    quantity = Util.itemCount(item),
                    max = Util.itemCount(item),
                    name = Util.itemName(item),
                    reason = contents,
                }, uiLedger(player), self.bankKind, player)
                self.candidates[#self.candidates + 1] = entry
                if self.candidateList then
                    self.candidateList:addItem(
                        candidateLabel(entry, self.bankKind, uiLedger(player)),
                        entry,
                        entry.otherUse and entry.otherUseTip or nil)
                end
            end
        end
    end
    applyCandidateIndex(self, prevIndex)
    self:layoutRefresh()
end

function Panel:refreshRegisterCandidates()
    local prevIndex = captureCandidateIndex(self)
    self.candidates = {}
    if self.candidateList then self.candidateList:clear() end
    local player = Util.localPlayer(self.playerNum)
    if player == nil or not self.registering then
        applyCandidateIndex(self, prevIndex)
        return
    end
    local ledger = uiLedger(player)
    for _, row in ipairs(Collections.registerCandidates(player, ledger, self.selectedCollectionKey)) do
        local entry = {
            item = row.item,
            collectionKey = row.collectionKey,
            slotIndex = row.slotIndex,
            name = Util.itemName(row.item),
            collectionName = row.collectionName,
            slotLabel = row.slotLabel,
            favorite = row.favorite == true,
        }
        self.candidates[#self.candidates + 1] = entry
        if self.candidateList then
            local label = string.format("%s  ->  %s (%s)", entry.name, entry.collectionName, entry.slotLabel)
            self.candidateList:addItem(label, entry)
        end
    end
    applyCandidateIndex(self, prevIndex)
end

function Panel:onQty(button)
    if not inHideout(Util.localPlayer(self.playerNum)) then return end
    local entry = self.selectedCandidate
    if entry == nil then return end
    entry.quantity = Util.clamp((entry.quantity or 1) + (button.delta or 0), 1, entry.max or 1)
end

function Panel:doRegister(entry)
    if entry == nil or entry.item == nil then return end
    Client.register({
        item = entry.item,
        collectionKey = entry.collectionKey,
        slotIndex = entry.slotIndex,
    }, Util.localPlayer(self.playerNum))
    self:rebuildLists()
end

function Panel:onConfirmRegisterFavorite(button, entry)
    self:holdPause()
    if button == nil or button.internal ~= "YES" then return end
    self:doRegister(entry)
end

function Panel:confirmRegisterFavorite(entry)
    if entry == nil or entry.item == nil then return end
    local name = entry.name or Util.itemName(entry.item)
    local text = getText("IGUI_ExtractionModeExpanded_ConfirmRegisterFavorite", tostring(name), tostring(entry.collectionName or ""))
    local width, height = 460, 130
    local screenWidth = getCore():getScreenWidth()
    local screenHeight = getCore():getScreenHeight()
    local modal = ISModalDialog:new(
        math.floor((screenWidth - width) / 2),
        math.floor((screenHeight - height) / 2),
        width, height, text, true, self, Panel.onConfirmRegisterFavorite, self.playerNum, entry)
    modal:initialise()
    modal:addToUIManager()
    modal:setAlwaysOnTop(true)
    modal.moveWithMouse = true
end

function Panel:onDeposit()
    if not inHideout(Util.localPlayer(self.playerNum)) then return end
    if self.registering then
        local entry = self.selectedCandidate
        if entry == nil or entry.item == nil then return end
        if entry.favorite or Items.isFavorite(entry.item) then
            self:confirmRegisterFavorite(entry)
            return
        end
        self:doRegister(entry)
        return
    end
    if self.selectedCandidate == nil or self.bankKind == nil then return end
    if self.selectedCandidate.reason then return end
    if self.bankKind == "value" and Config.trophyTier(Util.fullType(self.selectedCandidate.item)) then
        self:confirmSellTrophy(self.selectedCandidate)
        return
    end
    Client.deposit(self.bankKind, {
        { item = self.selectedCandidate.item, quantity = self.selectedCandidate.quantity },
    }, Util.localPlayer(self.playerNum))
    self:rebuildLists()
    self:syncBankControls()
end

function Panel:onConfirmSellTrophy(button, entry)
    self:holdPause()
    if button == nil or button.internal ~= "YES" then return end
    if entry == nil or entry.item == nil then return end
    Client.deposit("value", {
        { item = entry.item, quantity = entry.quantity or 1 },
    }, Util.localPlayer(self.playerNum))
    self:rebuildLists()
    self:syncBankControls()
end

function Panel:confirmSellTrophy(entry)
    if entry == nil or entry.item == nil then return end
    local tier = Config.trophyTier(Util.fullType(entry.item))
    local name = entry.name or Util.itemName(entry.item)
    local value, _ = itemCredit(entry.item, entry.quantity, uiLedger(Util.localPlayer(self.playerNum)))
    local text = getText(
        "IGUI_ExtractionModeExpanded_ConfirmSellTrophy",
        tostring(name),
        trophyTierTitle(tier),
        formatCount(value, true))
    local width, height = 480, 140
    local screenWidth = getCore():getScreenWidth()
    local screenHeight = getCore():getScreenHeight()
    local modal = ISModalDialog:new(
        math.floor((screenWidth - width) / 2),
        math.floor((screenHeight - height) / 2),
        width, height, text, true, self, Panel.onConfirmSellTrophy, self.playerNum, entry)
    modal:initialise()
    modal:addToUIManager()
    modal:setAlwaysOnTop(true)
    modal.moveWithMouse = true
end

function Panel:hideRefreshConfirm()
    self.confirming = false
    self.awaitingRefresh = false
    self.awaitingRefreshId = nil
    if self.confirmButton then self.confirmButton:setVisible(false) end
    if self.freeRefreshButton then self.freeRefreshButton:setVisible(false) end
    if self.cancelButton then self.cancelButton:setVisible(false) end
    if self.refreshButton then self.refreshButton:setVisible(true) end
end

function Panel:syncRefreshConfirmButtons()
    local player = Util.localPlayer(self.playerNum)
    local ledger = uiLedger(player)
    local area = Config.area(self.selectedAreaKey)
    local freeOk = Banks.homeTheaterFreeAvailable(ledger)
    local paidOk = Banks.materialsReady(ledger, area)
    if not self.confirming then
        if self.confirmButton then self.confirmButton:setVisible(false) end
        if self.freeRefreshButton then self.freeRefreshButton:setVisible(false) end
        if self.cancelButton then self.cancelButton:setVisible(false) end
        if self.refreshButton then self.refreshButton:setVisible(true) end
        return
    end
    if self.refreshButton then self.refreshButton:setVisible(false) end
    local waiting = self.awaitingRefresh == true
    if self.cancelButton then
        self.cancelButton:setVisible(true)
        self.cancelButton.enable = true
    end
    if self.freeRefreshButton then
        self.freeRefreshButton:setVisible(freeOk)
        self.freeRefreshButton.enable = freeOk and not waiting
    end
    if self.confirmButton then

        self.confirmButton:setVisible(true)
        self.confirmButton:setTitle(freeOk and getText("IGUI_ExtractionModeExpanded_PayBanks") or getText("IGUI_ExtractionModeExpanded_Confirm"))
        self.confirmButton.enable = paidOk and not waiting
    end
end

function Panel:onRefresh()
    local player = Util.localPlayer(self.playerNum)
    if not inHideout(player) then return end
    self.confirming = true
    self.refreshError = nil
    self:syncRefreshConfirmButtons()
end

function Panel:applyRefreshResult(state)
    self.awaitingRefresh = false
    local result = state and state.lastResult
    if result and result.ok == false then
        self.refreshError = tostring(result.result or getText("IGUI_ExtractionModeExpanded_RefreshFailed"))
        self:rebuildLists()
        return
    end
    self.refreshError = nil
    self:hideRefreshConfirm()
    self:rebuildLists()
    self:syncBankControls()
end

function Panel:applyServerState(state)
    local result = state and state.lastResult
    if self.awaitingRefresh and result and tostring(result.requestId or "") == tostring(self.awaitingRefreshId or "") then
        self:applyRefreshResult(state)
        return
    end
    self:rebuildLists()
    self:syncBankControls()
end

function Panel:finishRefreshChoice(useFree)
    if self.awaitingRefresh then return end
    if not inHideout(Util.localPlayer(self.playerNum)) then return end
    self.awaitingRefresh = true
    self.refreshError = nil
    local state, requestId = Client.refreshArea(self.selectedAreaKey, useFree == true, Util.localPlayer(self.playerNum))
    self.awaitingRefreshId = requestId
    if Util.isRemoteClient() then return end
    self:applyRefreshResult(state)
end

function Panel:onConfirmRefreshPaid()
    self:finishRefreshChoice(false)
end

function Panel:onConfirmRefreshFree()
    self:finishRefreshChoice(true)
end

function Panel:onCancelRefresh()
    self:hideRefreshConfirm()
end

function Panel:onRegister()
    if not inHideout(Util.localPlayer(self.playerNum)) then return end
    if self:bankUndoCount() > 0 then
        self:requestBankLeave("register")
        return
    end
    self:commitBankSession()
    self:_applyRegister()
end

function Panel:onSellTrophy()

end

function Panel:onBankTrophy()
    if not inHideout(Util.localPlayer(self.playerNum)) then return end
    local entry = self.selectedTrophyEntry
    if entry == nil or entry.fullType == nil then return end
    if (tonumber(entry.owned) or 0) <= 0 then return end
    local player = Util.localPlayer(self.playerNum)
    local item = findInventoryTrophy(player, entry.fullType)
    if item == nil then return end
    Client.bankTrophy(item, player)
    self:rebuildLists()
end

function Panel:tokenSpendLabel(spent)
    local parts = {}
    local function add(count, name)
        count = math.floor(tonumber(count) or 0)
        if count <= 0 then return end
        parts[#parts + 1] = string.format("%d %s", count, name)
    end
    add(spent and spent.large, "large")
    add(spent and spent.medium, "medium")
    add(spent and spent.small, "small")
    if #parts == 0 then return "a token" end
    return table.concat(parts, ", ")
end

function Panel:onConfirmTokenWaste(button)
    self:holdPause()
    if button == nil or button.internal ~= "YES" then return end
    if self.selectedAreaKey == nil then return end
    Client.applyReliefTokens(self.selectedAreaKey, nil, Util.localPlayer(self.playerNum))
    self:rebuildLists()
end

function Panel:confirmTokenWaste(preview)
    local spent = self:tokenSpendLabel(preview and preview.spent)
    local wasted = formatCount(preview and preview.wasted or 0, true)
    local text = getText("IGUI_ExtractionModeExpanded_TokenWaste", spent, wasted)
    local width, height = 520, 150
    local screenWidth = getCore():getScreenWidth()
    local screenHeight = getCore():getScreenHeight()
    local modal = ISModalDialog:new(
        math.floor((screenWidth - width) / 2),
        math.floor((screenHeight - height) / 2),
        width, height, text, true, self, Panel.onConfirmTokenWaste, self.playerNum)
    modal:initialise()
    modal:addToUIManager()
    modal:setAlwaysOnTop(true)
    modal.moveWithMouse = true
end

function Panel:onApplyRelief()
    if not inHideout(Util.localPlayer(self.playerNum)) then return end
    if self.selectedAreaKey == nil then return end
    local ledger = uiLedger(Util.localPlayer(self.playerNum))
    local preview = Banks.previewReliefTokens(ledger, self.selectedAreaKey)
    if preview and (tonumber(preview.wasted) or 0) > 0.0001 then
        self:confirmTokenWaste(preview)
        return
    end
    Client.applyReliefTokens(self.selectedAreaKey, nil, Util.localPlayer(self.playerNum))
    self:rebuildLists()
end

function Panel:onSpendTrophy()
    self:onBankTrophy()
end

function Panel:onClose()
    if self:bankUndoCount() > 0 then
        self:requestBankLeave("close")
        return
    end
    self:commitBankSession()
    self:_applyClose()
end

function Panel:prerender()
    ISPanelJoypad.prerender(self)

    if self.activeTab == "refresh" and self.bankKind ~= nil then
        local px = PANEL_WIDTH + BANK_POPOUT_GAP
        local py = 8
        local ph = self.height - 16
        self:drawRect(px, py, BANK_POPOUT_W, ph, 0.96, 0.025, 0.03, 0.035)
        self:drawRectBorder(px, py, BANK_POPOUT_W, ph, 0.9, 0.82, 0.58, 0.16)
    end
    local player = Util.localPlayer(self.playerNum)
    local hideout = inHideout(player)
    if self:bankUndoCount() <= 0 then
        self.commitSent = false
    end
    if not hideout then
        if self:bankUndoCount() > 0 and not self.commitSent then
            self.commitSent = true
            self:commitBankSession()
        end
        if self.bankKind ~= nil then
            self.bankKind = nil
            self:rebuildStock()
            self:syncBankControls()
        end
        if self.registering then
            self.registering = false
            self:syncBankControls()
        end
        if self.confirming then
            self:hideRefreshConfirm()
        end
    end
    if self.confirming then
        self:syncRefreshConfirmButtons()
    else
        local ledger = uiLedger(player)
        local area = Config.area(self.selectedAreaKey)
        local unlocked = area and Config.areaUnlocked(area.key, State.completions(player))
        local blocked = area and RefreshMod.Refresh and RefreshMod.Refresh.blockedReason
            and RefreshMod.Refresh.blockedReason(area.key)
        local canRefresh = unlocked and not blocked
            and (Banks.materialsReady(ledger, area) or Banks.homeTheaterFreeAvailable(ledger))
        if self.refreshButton then
            self.refreshButton:setVisible(self.activeTab == "refresh")
            self.refreshButton.enable = hideout and canRefresh
        end
        if self.confirmButton then self.confirmButton:setVisible(false) end
        if self.freeRefreshButton then self.freeRefreshButton:setVisible(false) end
        if self.cancelButton then self.cancelButton:setVisible(false) end
    end
    if self.sellButton then self.sellButton.enable = hideout end
    if self.provideButton then self.provideButton.enable = hideout end
    if self.contributeButton then self.contributeButton.enable = hideout end
    if self.donateButton then self.donateButton.enable = hideout end
    if self.minusButton then self.minusButton.enable = hideout end
    if self.plusButton then self.plusButton.enable = hideout end
    if self.depositButton then self.depositButton.enable = hideout end
    if self.undoButton then
        local banking = self.activeTab == "refresh" and self.bankKind ~= nil
        self.undoButton.enable = hideout and banking and self:bankUndoCount() > 0
        self.undoButton:setVisible(banking)
    end
    if self.registerButton then self.registerButton.enable = hideout end
    if self.bankTrophyButton then self.bankTrophyButton.enable = hideout end
    if self.applyReliefButton then self.applyReliefButton.enable = hideout end
end

function Panel:render()
    ISPanelJoypad.render(self)
    drawCentre(self, getText("IGUI_ExtractionModeExpanded_Title"), 10, GOLD, UIFont.Medium, PANEL_WIDTH / 2)
    if self.activeTab == "refresh" then
        self:renderRefresh()
    elseif self.activeTab == "trophies" then
        self:renderTrophies()
    else
        self:renderOddities()
    end
end

function Panel:renderBankPopout()
    if self.activeTab ~= "refresh" or self.bankKind == nil then return end
    local px = PANEL_WIDTH + BANK_POPOUT_GAP
    draw(self, bankPopoutTitle(self.bankKind), px + PAD, 20, GOLD, UIFont.Small)
    if self:bankUndoCount() > 0 then
        draw(self, getText("IGUI_ExtractionModeExpanded_UndoLock1"), px + PAD, 40, RED, UIFont.Small)
        draw(self, getText("IGUI_ExtractionModeExpanded_UndoLock2"), px + PAD, 56, RED, UIFont.Small)
    end
    local hasItems = self.candidates ~= nil and #self.candidates > 0
    if not hasItems then
        local msg = bankEmptyMessage(self.bankKind)
        draw(self, msg, px + PAD, 96, GREY, UIFont.Small)
        return
    end
    if self.selectedCandidate then
        local entry = self.selectedCandidate
        local ledger = uiLedger(Util.localPlayer(self.playerNum))
        local qty = string.format("%d / %d", entry.quantity or 1, entry.max or 1)
        local value, weapons = itemCredit(entry.item, entry.quantity, ledger)
        if self.bankKind == "value" and value > 0 then
            qty = qty .. string.format("   Value %s", formatCount(value, true))
        elseif self.bankKind == "weapons" and weapons > 0 then
            qty = qty .. string.format("   Weapons %s", formatCount(weapons, true))
        end
        if self.bankKind == "value" and weapons > 0 then
            qty = qty .. string.format("   Weapons %s", formatCount(weapons, true))
        elseif self.bankKind == "weapons" and value > 0 then
            qty = qty .. string.format("   Value %s", formatCount(value, true))
        end
        draw(self, qty, px + PAD + 32, self.height - 72, WHITE, UIFont.Small)
        if self.depositButton then
            if entry.otherUse and entry.otherUseTip then
                self.depositButton:setTooltip(entry.otherUseTip)
            else
                self.depositButton:setTooltip(nil)
            end
        end
    elseif self.depositButton then
        self.depositButton:setTooltip(nil)
    end
end

function Panel:renderRefresh()
    if self.areaList and self.areaList.items and self.areaList.selected then
        local row = self.areaList.items[self.areaList.selected]
        if row and row.item and row.item ~= self.selectedAreaKey then
            self.selectedAreaKey = row.item
            self:rebuildRequirements()
        end
    end
    local player = Util.localPlayer(self.playerNum)
    local ledger = uiLedger(player)
    local area = Config.area(self.selectedAreaKey)
    local reqX = (self.reqList and self.reqList:getX()) or (PAD + AREA_LIST_W + 8)

    draw(self, "BANKED STOCK", PAD, 114, GOLD, UIFont.Small)
    local valueText = string.format("Value x %s", formatCount(ledger.value, true))
    local weaponText = string.format("Weapons x %s", formatCount(ledger.weapons, true))
    draw(self, valueText, 140, 114, stockColor({ count = ledger.value }), UIFont.Small)
    draw(self, weaponText, 280, 114, stockColor({ count = ledger.weapons }), UIFont.Small)
    if not inHideout(player) then
        draw(self, "VIEW ONLY", PANEL_WIDTH - 120, 114, RED, UIFont.Small)
    end

    self:drawRect(PAD, self:footerY() - 6, PANEL_WIDTH - PAD * 2, 1, 0.45, 0.82, 0.58, 0.16)

    if area then
        local m = Multiplier.M(ledger, area.key)
        draw(self, area.name, reqX, self:footerY() + 8, GOLD, UIFont.Small)
        if self.confirming then
            local freeOk = Banks.homeTheaterFreeAvailable(ledger)
            local paidOk = Banks.materialsReady(ledger, area)
            if self.refreshError then
                draw(self, tostring(self.refreshError), reqX, self:footerY() + 24, RED, UIFont.Small)
            elseif freeOk and paidOk then
                draw(self, getText("IGUI_ExtractionModeExpanded_ChooseFreeOrPay"), reqX, self:footerY() + 24, GOLD, UIFont.Small)
            elseif freeOk then
                draw(self, getText("IGUI_ExtractionModeExpanded_ConfirmFreeRefresh"), reqX, self:footerY() + 24, GOLD, UIFont.Small)
            else
                draw(self, getText("IGUI_ExtractionModeExpanded_ConfirmPayBanks"), reqX, self:footerY() + 24, GOLD, UIFont.Small)
            end
            if self:bankUndoCount() > 0 then
                draw(self, getText("IGUI_ExtractionModeExpanded_ConfirmRefreshClearsUndo"),
                    reqX, self:footerY() + 42, RED, UIFont.Small)
            end
        else
            draw(self, getText("IGUI_ExtractionModeExpanded_Multiplier", string.format("%.2f", m)), reqX, self:footerY() + 24, GREY, UIFont.Small)
        end
    end
    if Collections.completed(ledger, "rotary_phones") and ledger.gpsTomorrow
        and tonumber(ledger.gpsTomorrowDay) == Util.gameDay() then
        local town = Config.emTown(ledger.gpsTomorrow)
        local gps = getText("IGUI_ExtractionModeExpanded_GpsTomorrow", (town and town.name) or ledger.gpsTomorrow)
        draw(self, gps, 430, 114, GOLD, UIFont.Small)
    end
    self:renderBankPopout()
end

function Panel:renderTrophies()
    if self.trophyCols then
        for tier, list in pairs(self.trophyCols) do
            if list and list.items and list.selected then
                local row = list.items[list.selected]
                if row and row.item and self.selectedTrophyTier == tier then
                    self.selectedTrophyEntry = row.item
                end
            end
        end
    end
    if self.areaList and self.areaList.items and self.areaList.selected then
        local row = self.areaList.items[self.areaList.selected]
        if row and row.item then self.selectedAreaKey = row.item end
    end
    local player = Util.localPlayer(self.playerNum)
    local ledger = uiLedger(player)
    local tokens = ledger.reliefTokens or {}
    local smallN = math.max(0, math.floor(tonumber(tokens.small) or 0))
    local mediumN = math.max(0, math.floor(tonumber(tokens.medium) or 0))
    local largeN = math.max(0, math.floor(tonumber(tokens.large) or 0))
    local area = Config.area(self.selectedAreaKey)
    local areaX = PANEL_WIDTH - PAD - AREA_LIST_W
    local leftW = PANEL_WIDTH - PAD * 2 - AREA_LIST_W - 16
    local boxW = math.floor((leftW - 16) / 3)
    local boxY = 76
    local boxH = 36
    local labels = {
        { text = getText("IGUI_ExtractionModeExpanded_TokenSmall", smallN) },
        { text = getText("IGUI_ExtractionModeExpanded_TokenMedium", mediumN) },
        { text = getText("IGUI_ExtractionModeExpanded_TokenLarge", largeN) },
    }
    for i, row in ipairs(labels) do
        local x = PAD + (i - 1) * (boxW + 8)
        self:drawRect(x, boxY, boxW, boxH, 0.55, 0.08, 0.08, 0.08)
        self:drawRectBorder(x, boxY, boxW, boxH, 0.7, 0.82, 0.58, 0.16)
        draw(self, row.text, x + 10, boxY + 10, WHITE, UIFont.Small)
    end

    local layout = self.trophyLayout or self:trophyPaneLayout()
    for _, key in ipairs({ "uncommon", "uncommonMore", "rare", "legendary" }) do
        local box = layout.cols and layout.cols[key]
        if box then
            self:drawRect(box.x, box.labelY, box.w, 24, 0.45, 0.06, 0.06, 0.06)
            self:drawRectBorder(box.x, box.labelY, box.w, 24, 0.75, 0.82, 0.58, 0.16)
            local title = box.title or key
            local titleW = getTextManager():MeasureStringX(UIFont.Small, title)
            draw(self, title, box.x + math.max(8, math.floor((box.w - titleW) / 2)), box.labelY + 4, GOLD, UIFont.Small)
        end
    end
    if layout.tutorialX then
        local tip = getText("IGUI_ExtractionModeExpanded_TrophyTutorial")

        tip = tostring(tip or ""):gsub("\\n", "\n")
        local tipY = layout.tutorialY
        local tipW = layout.tutorialW or 200
        local lineH = 14
        self:drawRect(layout.tutorialX, tipY, tipW, layout.tutorialH or 60, 0.25, 0.05, 0.05, 0.05)
        self:drawRectBorder(layout.tutorialX, tipY, tipW, layout.tutorialH or 60, 0.55, 0.82, 0.58, 0.16)
        local lines = {}
        local function pushWrapped(paragraph)
            if paragraph == nil or paragraph == "" then
                lines[#lines + 1] = ""
                return
            end
            local line = ""
            for word in string.gmatch(paragraph, "%S+") do
                local probe = (line == "") and word or (line .. " " .. word)
                if getTextManager():MeasureStringX(UIFont.Small, probe) > tipW - 12 then
                    if line ~= "" then lines[#lines + 1] = line end
                    line = word
                else
                    line = probe
                end
            end
            if line ~= "" then lines[#lines + 1] = line end
        end
        for paragraph in string.gmatch(tip .. "\n", "(.-)\n") do
            pushWrapped(paragraph)
        end
        if #lines == 0 then pushWrapped(tip) end
        local maxLines = math.max(1, math.floor(((layout.tutorialH or 60) - 10) / lineH))
        for i = 1, math.min(#lines, maxLines) do
            if lines[i] ~= "" then
                draw(self, lines[i], layout.tutorialX + 6, tipY + 6 + (i - 1) * lineH, GREY, UIFont.Small)
            end

        end
    end

    draw(self, getText("IGUI_ExtractionModeExpanded_ApplyToArea"), areaX, 76, GOLD, UIFont.Small)
    if area then
        local excess = Multiplier.excess(ledger, area.key)
        local currentM = Multiplier.M(ledger, area.key)
        local preview = Banks.previewReliefTokens(ledger, area.key)
        draw(self, string.format("Excess: %s", formatCount(excess, true)), areaX, 94, GREY, UIFont.Small)
        if preview then
            local afterM = math.max(1, 1 + (tonumber(preview.after) or 0))
            draw(self, string.format("After tokens: x%s  (spends %s)",
                formatCount(afterM, true), formatCount(preview.applied, true)), areaX, 112, WHITE, UIFont.Small)
            if (tonumber(preview.wasted) or 0) > 0.0001 then
                draw(self, string.format("Wasted: %s", formatCount(preview.wasted, true)),
                    areaX, 128, RED, UIFont.Small)
            elseif (tonumber(preview.after) or 0) > 0.0001 then
                draw(self, string.format("Remaining excess: %s", formatCount(preview.after, true)),
                    areaX, 128, GREY, UIFont.Small)
            else
                draw(self, string.format("Now x%s → after x%s", formatCount(currentM, true), formatCount(afterM, true)),
                    areaX, 128, GREY, UIFont.Small)
            end
        else
            draw(self, string.format("Current mult: x%s", formatCount(currentM, true)), areaX, 112, WHITE, UIFont.Small)
            if excess <= 0 then
                draw(self, getText("IGUI_ExtractionModeExpanded_NoExcess"), areaX, 128, GREY, UIFont.Small)
            else
                draw(self, getText("IGUI_ExtractionModeExpanded_TrophyHintNoTokens"),
                    areaX, 128, GREY, UIFont.Small)
            end
        end
    end
    if not inHideout(player) then
        draw(self, "VIEW ONLY", PANEL_WIDTH - 120, 76, RED, UIFont.Small)
    end
end

function Panel:renderOddities()
    if self.collectionList and self.collectionList.items and self.collectionList.selected then
        local row = self.collectionList.items[self.collectionList.selected]
        if row and row.item and row.item ~= self.selectedCollectionKey then
            self.selectedCollectionKey = row.item
            self:rebuildSlots()
        elseif row and row.item then
            self.selectedCollectionKey = row.item
        end
    end
    local player = Util.localPlayer(self.playerNum)
    local ledger = uiLedger(player)
    local collection = Config.collection(self.selectedCollectionKey)
    if collection == nil then return end
    local n = Collections.collectedCount(ledger, collection)
    local x = 352
    draw(self, string.format("%s  (%d/%d)", collection.name, n, collection.slots), x, 80, GOLD, UIFont.Medium)
    if self.registering then
        draw(self, "Select an item to register. Matches for this collection are listed first.", x, 102, GREY, UIFont.Small)
    else
        draw(self, collection.bonus or "", x, 102, GREY, UIFont.Small)
    end
end

function Panel:new(playerNum)
    local width, height = PANEL_WIDTH, PANEL_HEIGHT
    local screenWidth = getCore():getScreenWidth()
    local screenHeight = getCore():getScreenHeight()
    local x = math.floor((screenWidth - width) / 2)
    local y = math.max(20, math.floor((screenHeight - height) / 2))
    local object = ISPanelJoypad:new(x, y, width, height)
    setmetatable(object, self)
    self.__index = self
    object.background = true
    object.backgroundColor = { r = 0.025, g = 0.03, b = 0.035, a = 0.96 }
    object.borderColor = { r = 0.82, g = 0.58, b = 0.16, a = 0.9 }
    object.moveWithMouse = true
    object.playerNum = playerNum or 0
    object.activeTab = "refresh"
    object.registering = false
    return object
end

function RefreshMod.openPanel(playerNum)
    playerNum = tonumber(playerNum) or 0
    RefreshMod.PanelInstances = RefreshMod.PanelInstances or {}
    local panel = RefreshMod.PanelInstances[playerNum]
    if panel == nil then
        panel = Panel:new(playerNum)
        panel:initialise()
        panel:addToUIManager()
        panel:setAlwaysOnTop(true)
        RefreshMod.PanelInstances[playerNum] = panel
    end
    RefreshMod.PanelInstance = panel
    Client.refreshState(Util.localPlayer(playerNum))
    panel:rebuildLists()
    panel:setVisible(true)
    panel:bringToTop()
    panel:pauseSinglePlayer()
    return panel
end

function RefreshMod.togglePanel(playerNum)
    playerNum = tonumber(playerNum) or 0
    RefreshMod.PanelInstances = RefreshMod.PanelInstances or {}
    local panel = RefreshMod.PanelInstances[playerNum]
    if panel ~= nil and panel:isVisible() then
        panel:onClose()
        return nil
    end
    return RefreshMod.openPanel(playerNum)
end

RefreshMod.Panel = Panel
return Panel
