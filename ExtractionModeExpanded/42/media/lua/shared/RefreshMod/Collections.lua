require "RefreshMod/Config"
require "RefreshMod/Util"
require "RefreshMod/Items"

RefreshMod = RefreshMod or {}
local Config = RefreshMod.Config
local Util = RefreshMod.Util
local Items = RefreshMod.Items
local Logic = {}
RefreshMod.CollectionsLogic = Logic

function Logic.slotFilled(ledger, collectionKey, slotIndex)
    if ledger == nil or collectionKey == nil then return false end
    local index = math.floor(tonumber(slotIndex) or 0)
    if index < 1 then return false end
    local key = tostring(collectionKey)
    local flat = ledger.collectionSlots
    if type(flat) == "table" then
        local flag = flat[key .. ":" .. tostring(index)]
        if flag and flag ~= 0 then return true end
    end
    local collection = ledger.collections and ledger.collections[key]
    if type(collection) ~= "table" then return false end
    local flag = collection[tostring(index)]
    if flag == nil then flag = collection[index] end
    return flag and flag ~= 0
end

function Logic.markSlot(ledger, collectionKey, slotIndex)
    if ledger == nil or collectionKey == nil then return end
    local index = math.floor(tonumber(slotIndex) or 0)
    if index < 1 then return end
    local key = tostring(collectionKey)
    local slotKey = tostring(index)

    ledger.collections = ledger.collections or {}
    ledger.collections[key] = ledger.collections[key] or {}
    ledger.collections[key][slotKey] = true

    ledger.collectionSlots = ledger.collectionSlots or {}
    ledger.collectionSlots[key .. ":" .. slotKey] = true
end

function Logic.normalizeLedgerCollections(ledger)
    if ledger == nil then return end
    ledger.collections = ledger.collections or {}
    ledger.collectionSlots = ledger.collectionSlots or {}
    for flatKey, filled in pairs(ledger.collectionSlots) do
        if filled and filled ~= 0 then
            local collectionKey, slot = tostring(flatKey):match("^(.+):(%d+)$")
            if collectionKey and slot then
                ledger.collections[collectionKey] = ledger.collections[collectionKey] or {}
                ledger.collections[collectionKey][tostring(slot)] = true
            end
        end
    end
    for collectionKey, slots in pairs(ledger.collections) do
        if type(slots) == "table" then
            local normalized = {}
            for index, filled in pairs(slots) do
                if filled and filled ~= 0 then
                    local n = math.floor(tonumber(index) or 0)
                    if n >= 1 then
                        local slotKey = tostring(n)
                        normalized[slotKey] = true
                        ledger.collectionSlots[tostring(collectionKey) .. ":" .. slotKey] = true
                    end
                end
            end
            ledger.collections[collectionKey] = normalized
        end
    end
end

function Logic.collectedCount(ledger, collection)
    if collection == nil or ledger == nil then return 0 end
    Logic.normalizeLedgerCollections(ledger)
    local count = 0
    for index = 1, #(collection.items or {}) do
        if Logic.slotFilled(ledger, collection.key, index) then count = count + 1 end
    end
    return count
end

function Logic.completed(ledger, collectionKey)
    local collection = Config.collection(collectionKey)
    if collection == nil or ledger == nil then return false end
    return Logic.collectedCount(ledger, collection) >= (tonumber(collection.slots) or #collection.items)
end

function Logic.completedForPlayer(player, collectionKey)
    local State = RefreshMod.State
    if State == nil then return false end
    return Logic.completed(State.ledger(player), collectionKey)
end

local function literatureTitleOf(item)
    if item == nil then return nil end
    local title = item:getModData().literatureTitle
    if title == nil or title == "" then return nil end
    return tostring(title)
end

local function mediaIdOf(item)
    if item == nil then return nil end
    local media = item:getMediaData()
    if media == nil then return nil end
    local id = media:getId()
    if id == nil or id == "" then return nil end
    return tostring(id)
end

local function slotMatches(item, slot)
    if item == nil or slot == nil then return false end
    if slot.literatureTitle then
        local title = literatureTitleOf(item)
        if title == nil then return false end
        local wanted = tostring(slot.literatureTitle)
        if title == wanted then return true end

        if string.sub(wanted, 1, 19) == "IGUI_MagazineTitle_" then
            return string.sub(title, 1, #wanted + 1) == (wanted .. "_")
        end
        return false
    end
    if slot.mediaId then
        return mediaIdOf(item) == tostring(slot.mediaId)
    end
    return Items.matchesTypes(item, slot)
end

local function titleOfMediaData(mediaData)
    if mediaData == nil then return nil end
    local title
    if mediaData:hasTitle() then
        title = mediaData:getTranslatedTitle()
        if mediaData:hasSubTitle() and mediaData:getSubtitleEN() ~= "Home VHS" then
            title = tostring(title or "") .. " " .. tostring(mediaData:getTranslatedSubTitle() or "")
        end
    elseif mediaData:hasSubTitle() then
        title = mediaData:getTranslatedSubTitle()
    else
        title = mediaData:getTranslatedItemDisplayName()
    end
    if title and title ~= "" then return tostring(title) end
end

local mediaTitles = nil

local function loadMediaTitles()
    if mediaTitles ~= nil then return end
    if getZomboidRadio == nil then return end
    local radio = getZomboidRadio()
    if radio == nil then return end
    local recorded = radio:getRecordedMedia()
    if recorded == nil then return end
    local categories = recorded:getCategories()
    if categories == nil or categories:size() <= 0 then return end
    local built = {}
    local found = false
    for i = 0, categories:size() - 1 do
        local category = categories:get(i)
        local mediaType = RecordedMedia.getMediaTypeForCategory(category)
        local list = mediaType and recorded:getAllMediaForType(mediaType)
            or recorded:getAllMediaForCategory(category)
        if list then
            for j = 0, list:size() - 1 do
                local data = list:get(j)
                local id = data and data:getId()
                local title = titleOfMediaData(data)
                if id and title then
                    built[tostring(id)] = title
                    found = true
                end
            end
        end
    end
    if found then mediaTitles = built end
end

local function mediaTitle(mediaId)
    if mediaId == nil then return nil end
    loadMediaTitles()
    return mediaTitles and mediaTitles[tostring(mediaId)] or nil
end

function Logic.slotLabel(slot)
    if slot == nil then return "" end
    if slot.literatureTitle then
        local translated = getText and getText(tostring(slot.literatureTitle))
        if translated and tostring(translated) ~= "" and tostring(translated) ~= tostring(slot.literatureTitle) then
            return tostring(translated)
        end
    end
    if slot.mediaId then
        local title = mediaTitle(slot.mediaId)
        if title then return title end
    end
    if slot.titleKey then
        local translated = getText and getText(tostring(slot.titleKey))
        if translated and tostring(translated) ~= "" and tostring(translated) ~= tostring(slot.titleKey) then
            return tostring(translated)
        end
    end
    if slot.label and tostring(slot.label) ~= "" then return slot.label end
    if slot.mediaId then return tostring(slot.mediaId) end
    return Util.displayName(slot[1])
end

function Logic.lookupMatches(item, ledger)
    local matches = {}
    if item == nil then return matches end
    if ledger ~= nil then Logic.normalizeLedgerCollections(ledger) end
    local registeredKey = Items.registeredCollection(item)
    for _, collection in ipairs(Config.collections()) do
        for index, slot in ipairs(collection.items or {}) do
            if slotMatches(item, slot) then
                local registered = registeredKey ~= nil and tostring(registeredKey) == tostring(collection.key)
                matches[#matches + 1] = {
                    collection = collection,
                    slotIndex = index,
                    slotLabel = Logic.slotLabel(slot),
                    filled = Logic.slotFilled(ledger, collection.key, index),
                    registered = registered,
                    count = Logic.collectedCount(ledger, collection),
                    slots = tonumber(collection.slots) or #(collection.items or {}),
                }
                break
            end
        end
    end
    return matches
end

function Logic.lookupItem(item, ledger)
    local matches = Logic.lookupMatches(item, ledger)
    local fallback = nil
    for _, info in ipairs(matches) do
        if info.registered then return info end
        if not info.filled and fallback == nil then fallback = info end
    end
    return fallback or matches[1]
end

function Logic.matchForItem(item, ledger, collection)
    if item == nil or collection == nil then return nil end
    if Items.registeredCollection(item) then return nil end
    for index, slot in ipairs(collection.items or {}) do
        if not Logic.slotFilled(ledger, collection.key, index) and slotMatches(item, slot) then
            return index, slot
        end
    end
end

function Logic.registerCandidates(player, ledger, preferKey)
    local rows = {}
    if player == nil or ledger == nil then return rows end
    ledger.collections = ledger.collections or {}
    Logic.syncRegisteredItems(player, ledger)
    for _, item in ipairs(Util.inventoryItems(player)) do
        if Items.registerRejectReason(item, player) == nil then
            for _, collection in ipairs(Config.collections()) do
                local index, slot = Logic.matchForItem(item, ledger, collection)
                if index then
                    rows[#rows + 1] = {
                        item = item,
                        collectionKey = collection.key,
                        collectionName = collection.name,
                        slotIndex = index,
                        slotLabel = Logic.slotLabel(slot),
                        favorite = Items.isFavorite(item),
                    }
                end
            end
        end
    end
    table.sort(rows, function(a, b)
        local ap = preferKey ~= nil and a.collectionKey == preferKey
        local bp = preferKey ~= nil and b.collectionKey == preferKey
        if ap ~= bp then return ap end
        if a.collectionName ~= b.collectionName then
            return tostring(a.collectionName) < tostring(b.collectionName)
        end
        return tostring(a.slotLabel) < tostring(b.slotLabel)
    end)
    return rows
end

function Logic.registerOne(player, ledger, selection)
    if not Util.insideHideout(player) then return false end
    if selection == nil or ledger == nil then return false end
    local item = selection.item
    local collectionKey = selection.collectionKey
    local slotIndex = tonumber(selection.slotIndex)
    if item == nil or collectionKey == nil or slotIndex == nil then return false end
    if Items.registerRejectReason(item, player) then return false end
    local collection = Config.collection(collectionKey)
    local slot = collection and collection.items and collection.items[slotIndex]
    if slot == nil then return false end
    if Logic.slotFilled(ledger, collection.key, slotIndex) then return false end
    if not slotMatches(item, slot) then return false end
    Items.markRegistered(item, collection.key, player)
    Logic.markSlot(ledger, collection.key, slotIndex)
    if RefreshMod.State then RefreshMod.State.markDirty() end
    return true
end

function Logic.syncRegisteredItems(player, ledger)
    if player == nil or ledger == nil then return end
    Logic.normalizeLedgerCollections(ledger)
    ledger.collections = ledger.collections or {}
    local changed = false
    for _, item in ipairs(Util.inventoryItems(player)) do
        local key = Items.registeredCollection(item)
        if key then
            local collection = Config.collection(key)
            if collection ~= nil then
                local already = false
                for index, slot in ipairs(collection.items or {}) do
                    if Logic.slotFilled(ledger, collection.key, index) and slotMatches(item, slot) then
                        already = true
                        break
                    end
                end
                if not already then
                    for index, slot in ipairs(collection.items or {}) do
                        if not Logic.slotFilled(ledger, collection.key, index) and slotMatches(item, slot) then
                            Logic.markSlot(ledger, collection.key, index)
                            changed = true
                            break
                        end
                    end
                end
            end
        end
    end
    if changed and RefreshMod.State then RefreshMod.State.markDirty() end
end

function Logic.register(player, ledger)
    if not Util.insideHideout(player) then return 0 end
    local registered = 0
    for _, row in ipairs(Logic.registerCandidates(player, ledger)) do
        if Logic.registerOne(player, ledger, row) then
            registered = registered + 1
        end
    end
    return registered
end

return Logic
