require "RefreshMod/Config"
require "RefreshMod/State"
require "RefreshMod/Util"

RefreshMod = RefreshMod or {}
local Config = RefreshMod.Config
local State = RefreshMod.State
local Util = RefreshMod.Util
local World = {}
RefreshMod.World = World

local CHUNK = 10

local function boundsForTown(townKey)
    local town = Config.emTown(townKey)
    return town and town.raidBounds or nil
end

local function inside(bounds, x, y)
    return bounds ~= nil
        and x >= bounds.minX and x <= bounds.maxX
        and y >= bounds.minY and y <= bounds.maxY
end

local function jobBounds(job)
    local rectangles = {}
    for _, townKey in ipairs(job.towns or {}) do
        local bounds = boundsForTown(townKey)
        if bounds then rectangles[#rectangles + 1] = bounds end
    end
    return rectangles
end

local function inJob(job, x, y)
    for _, bounds in ipairs(jobBounds(job)) do
        if inside(bounds, x, y) then return true end
    end
    return false
end

local function cellBounds(x, y)
    local x1 = math.floor(x / CHUNK) * CHUNK
    local y1 = math.floor(y / CHUNK) * CHUNK
    return x1, y1, x1 + CHUNK - 1, y1 + CHUNK - 1
end

local function eachVehicle(fn)
    local cell = getCell()
    if cell == nil then return end
    for _, vehicle in ipairs(Util.javaList(cell:getVehicles())) do
        fn(vehicle)
    end
end

local function vehicleXY(vehicle)
    if vehicle == nil then return nil, nil end
    return vehicle:getX(), vehicle:getY()
end

local function areaBusy(job)
    local RefreshApi = RefreshMod.Refresh
    if job == nil or RefreshApi == nil then return false end
    local reason = RefreshApi.blockedReason(job.areaKey)
    return reason ~= nil and reason ~= "unknown area"
end

local function vehicleNear(x, y, radius)
    local hit = false
    local limit = radius * radius
    eachVehicle(function(vehicle)
        if hit then return end
        local vx, vy = vehicleXY(vehicle)
        if vx ~= nil and vy ~= nil then
            local dx, dy = vx - x, vy - y
            if dx * dx + dy * dy <= limit then hit = true end
        end
    end)
    return hit
end

local function removeVehiclesInRect(job, x1, y1, x2, y2)
    if not job.vehicles then return end

    local doomed = {}
    eachVehicle(function(vehicle)
        local x, y = vehicleXY(vehicle)
        if x ~= nil and y ~= nil and x >= x1 and x <= x2 and y >= y1 and y <= y2 and inJob(job, x, y) then
            doomed[#doomed + 1] = vehicle
        end
    end)
    for _, vehicle in ipairs(doomed) do
        pcall(function() vehicle:permanentlyRemove() end)
    end
end

local function objectText(object)
    local parts = {}
    local sprite = object:getSprite()
    if sprite then
        local spriteName = sprite:getName()
        if spriteName and spriteName ~= "" then parts[#parts + 1] = spriteName end
        local props = sprite:getProperties()
        if props:has("CustomName") then parts[#parts + 1] = props:get("CustomName") end
        if props:has("GroupName") then parts[#parts + 1] = props:get("GroupName") end
    end
    local objectName = object:getName()
    if objectName and objectName ~= "" then parts[#parts + 1] = objectName end
    return string.lower(table.concat(parts, " "))
end

local function looksLikePump(label)
    if label == nil or label == "" then return false end
    label = string.lower(label):gsub("[%s_]", "")
    return string.find(label, "fuelpump", 1, true) ~= nil
        or string.find(label, "gaspump", 1, true) ~= nil
end

local function isPump(object)
    if object == nil then return false end
    if looksLikePump(objectText(object)) then return true end
    local container = object:getFluidContainer()
    if container == nil then return false end
    return looksLikePump(tostring(container:getContainerName() or ""))
end

local function clearPump(object, job)
    if object == nil or job == nil or job.id == nil then return end
    local data = object:getModData()
    if data == nil then return end
    local seq = tonumber(job.seq) or 0
    local stamped = tonumber(data.refreshModPumpSeq)
    if stamped ~= nil and stamped >= seq and seq > 0 then return end
    if seq <= 0 and data.refreshModPumpJob == job.id then return end

    data.fuelAmount = nil
    data.FuelAmount = nil
    local container = object:getFluidContainer()
    if container then container:removeFluid() end
    data.refreshModPumpSeq = tonumber(job.seq) or 0
    data.refreshModPumpJob = job.id
    object:transmitModData()
end

local function clearPumpsOnSquare(square, job)
    if not job.pumps or square == nil then return end
    for _, object in ipairs(Util.javaList(square:getObjects())) do
        if isPump(object) then clearPump(object, job) end
    end
end

local function zonesAt(x, y)
    return Util.javaList(getZones(x, y, 0))
end

local function zoneInfo(zone)
    if zone == nil then return nil, nil, nil, nil, nil, nil end
    return zone:getX(), zone:getY(), zone:getWidth(), zone:getHeight(), zone:getName(), zone:getType()
end

local function distributionFor(name, kind)
    if VehicleZoneDistribution == nil then return nil end
    local function lookup(value)
        if value == nil or tostring(value) == "" then return nil end
        return VehicleZoneDistribution[string.lower(tostring(value))]
    end
    local dist = lookup(name) or lookup(kind)
    if (dist == nil or dist.vehicles == nil) and VehicleZoneDistribution.parkingstall then
        dist = VehicleZoneDistribution.parkingstall
    end
    if dist == nil or dist.vehicles == nil then return nil end
    return dist
end

local function isVehicleZone(name, kind)
    local text = string.lower(tostring(kind or ""))
    if text == "parkingstall" or text == "vehicle" or text == "trailerpark" then return true end
    if VehicleZoneDistribution == nil or name == nil or tostring(name) == "" then return false end
    local dist = VehicleZoneDistribution[string.lower(tostring(name))]
    return dist ~= nil and dist.vehicles ~= nil
end

local function chanceOf(entry)
    if type(entry) == "number" then return entry end
    if type(entry) == "table" then
        return tonumber(entry.spawnChance) or tonumber(entry.weight) or 0
    end
    return 0
end

local function pickScript(dist)
    if dist == nil or dist.vehicles == nil then return nil end
    local total = 0
    local list = {}
    for vehicleName, entry in pairs(dist.vehicles) do
        local chance = chanceOf(entry)
        if chance > 0 then
            total = total + chance
            list[#list + 1] = { name = vehicleName, chance = chance }
        end
    end
    if total <= 0 then return nil end
    local roll = ZombRand(math.floor(total)) + 1
    local acc = 0
    for _, entry in ipairs(list) do
        acc = acc + entry.chance
        if roll <= acc then return entry.name end
    end
    return list[#list].name
end

local function applyVehicleExtras(vehicle, dist)
    if vehicle == nil or dist == nil then return end
    local keyChance = tonumber(dist.chanceToSpawnKey) or 70
    if ZombRand(100) < keyChance then
        vehicle:addKeyToGloveBox()
    end
    local damageChance = tonumber(dist.chanceToPartDamage) or 0
    local quality = tonumber(dist.baseVehicleQuality) or 1
    if damageChance <= 0 then return end
    local maxCond = math.max(1, math.floor(quality * 100))
    for index = 0, vehicle:getPartCount() - 1 do
        local part = vehicle:getPartByIndex(index)
        local installed = part and part:getInventoryItem()
        if installed and ZombRand(100) < damageChance then
            part:setCondition(ZombRand(maxCond))
        end
    end
end

local function spawnZoneInCell(zone, job, x1, y1, x2, y2)
    local x, y, w, h, name, kind = zoneInfo(zone)
    if x == nil or y == nil or w == nil or h == nil or w <= 0 or h <= 0 then return end
    if not isVehicleZone(name, kind) then return end
    local dist = distributionFor(name, kind)
    if dist == nil or addVehicleDebug == nil or IsoDirections == nil then return end
    local northSouth = h >= w
    local stepX = northSouth and 3 or 5
    local stepY = northSouth and 4 or 3
    local rate = tonumber(dist.spawnRate) or 16
    local normalChance = tonumber(dist.chanceToSpawnNormal) or 0
    local sx = x
    while sx < x + w do
        local sy = y
        while sy < y + h do
            local ax = sx + math.floor(stepX / 2)
            local ay = sy + math.floor(stepY / 2)
            if ax >= x1 and ax <= x2 and ay >= y1 and ay <= y2 and inJob(job, ax, ay) then
                if ZombRand(100) < rate then
                    local list = dist
                    if normalChance > 0 and VehicleZoneDistribution.parkingstall
                        and ZombRand(100) < normalChance then
                        list = VehicleZoneDistribution.parkingstall
                    end
                    local script = pickScript(list)
                    local square = getCell and getCell() and getCell():getGridSquare(ax, ay, 0) or nil

                    if script and square and not vehicleNear(ax, ay, 1) then
                        local dir = northSouth and IsoDirections.S or IsoDirections.E
                        local vehicle = nil
                        pcall(function() vehicle = addVehicleDebug(script, dir, nil, square) end)
                        applyVehicleExtras(vehicle, dist)
                    end
                end
            end
            sy = sy + stepY
        end
        sx = sx + stepX
    end
end

local function spawnVehiclesInCell(job, x1, y1, x2, y2)
    if not job.vehicles then return end
    local seen = {}
    for x = x1, x2 do
        for y = y1, y2 do
            if inJob(job, x, y) then
                for _, zone in ipairs(zonesAt(x, y)) do
                    local zx, zy, zw, zh, name = zoneInfo(zone)
                    if zx ~= nil then
                        local id = tostring(zx) .. ":" .. tostring(zy) .. ":" .. tostring(zw) .. ":" .. tostring(zh) .. ":" .. tostring(name)
                        seen[id] = zone
                    end
                end
            end
        end
    end
    for _, zone in pairs(seen) do
        spawnZoneInCell(zone, job, x1, y1, x2, y2)
    end
end

local function cellLoaded(job, x1, y1, x2, y2)
    local cell = getCell()
    if cell == nil then return false end
    local any = false
    for x = x1, x2 do
        for y = y1, y2 do
            if inJob(job, x, y) then
                any = true
                if cell:getGridSquare(x, y, 0) == nil then return false end
            end
        end
    end
    return any
end

local progressDirty = false

local function noteProgress()
    progressDirty = true
end

local function flushProgress()
    if not progressDirty then return end
    progressDirty = false
    State.markDirty()
end

local function processCell(job, x, y)

    if areaBusy(job) then return end
    local x1, y1, x2, y2 = cellBounds(x, y)
    local key = tostring(x1) .. ":" .. tostring(y1)
    job.vehicleCells = job.vehicleCells or {}
    if job.vehicleCells[key] then return end
    if not cellLoaded(job, x1, y1, x2, y2) then return end
    if job.vehicles then
        removeVehiclesInRect(job, x1, y1, x2, y2)
        spawnVehiclesInCell(job, x1, y1, x2, y2)
    end
    if job.pumps and getCell() then
        for sx = x1, x2 do
            for sy = y1, y2 do
                local square = getCell():getGridSquare(sx, sy, 0)
                if square then clearPumpsOnSquare(square, job) end
            end
        end
    end

    job.vehicleCells[key] = true
    noteProgress()
end

function World.startJob(job)
    if job == nil or areaBusy(job) then return end
    job.id = job.id or (tostring(job.areaKey or "area") .. ":" .. tostring(job.hour or 0))
    job.vehicleCells = job.vehicleCells or {}
    local cell = getCell()
    if cell == nil then return end

    local seen = {}
    for _, bounds in ipairs(jobBounds(job)) do
        local x1 = math.floor((tonumber(bounds.minX) or 0) / CHUNK) * CHUNK
        local y1 = math.floor((tonumber(bounds.minY) or 0) / CHUNK) * CHUNK
        local x2 = math.floor((tonumber(bounds.maxX) or 0) / CHUNK) * CHUNK
        local y2 = math.floor((tonumber(bounds.maxY) or 0) / CHUNK) * CHUNK
        for x = x1, x2, CHUNK do
            for y = y1, y2, CHUNK do
                local key = tostring(x) .. ":" .. tostring(y)
                if not seen[key] then
                    seen[key] = true
                    local square = cell:getGridSquare(x + 1, y + 1, 0)
                    if square then processCell(job, x + 1, y + 1) end
                end
            end
        end
    end
end

function World.onLoadSquare(square)
    if square == nil then return end
    local x, y = square:getX(), square:getY()
    local best, bestSeq = nil, nil
    for _, job in ipairs(State.root().refreshJobs or {}) do
        if inJob(job, x, y) then
            local seq = tonumber(job.seq) or 0
            if best == nil or seq >= bestSeq then
                best, bestSeq = job, seq
            end
        end
    end
    if best and not areaBusy(best) then
        best.id = best.id or (tostring(best.areaKey or "area") .. ":" .. tostring(best.hour or 0))
        if best.vehicles then processCell(best, x, y) end
        if best.pumps then clearPumpsOnSquare(square, best) end
    end
    if RefreshMod.Bonuses and RefreshMod.Bonuses.freshenLoadedSquare then
        RefreshMod.Bonuses.freshenLoadedSquare(square)
    end
end

if Events and Events.LoadGridsquare then
    Events.LoadGridsquare.Add(World.onLoadSquare)
end

local function eachCellKey(job, fn)
    for _, bounds in ipairs(jobBounds(job)) do
        local x1 = math.floor((tonumber(bounds.minX) or 0) / CHUNK) * CHUNK
        local y1 = math.floor((tonumber(bounds.minY) or 0) / CHUNK) * CHUNK
        local x2 = math.floor((tonumber(bounds.maxX) or 0) / CHUNK) * CHUNK
        local y2 = math.floor((tonumber(bounds.maxY) or 0) / CHUNK) * CHUNK
        for x = x1, x2, CHUNK do
            for y = y1, y2, CHUNK do
                fn(tostring(x) .. ":" .. tostring(y))
            end
        end
    end
end

function World.settleJobs()
    local root = State.root()
    local jobs = root.refreshJobs or {}
    if #jobs == 0 then
        flushProgress()
        return
    end
    local kept = {}
    local removed = false
    for _, job in ipairs(jobs) do
        if areaBusy(job) then
            kept[#kept + 1] = job
        else
            World.startJob(job)
            local finished = true
            local any = false
            eachCellKey(job, function(key)
                any = true
                if job.vehicleCells == nil or not job.vehicleCells[key] then
                    finished = false
                end
            end)
            if finished and any then
                removed = true
            else
                kept[#kept + 1] = job
            end
        end
    end
    if removed then
        root.refreshJobs = kept
        noteProgress()
    end
    flushProgress()
end

local nextSettle = 0
local function onTick()
    local now = getTimestampMs and getTimestampMs() or 0
    if now <= 0 and os and os.time then now = os.time() * 1000 end
    if now < nextSettle then return end
    nextSettle = now + 5000
    if #(State.root().refreshJobs or {}) == 0 then return end
    World.settleJobs()
end

if Events and Events.OnTick then
    Events.OnTick.Add(onTick)
end

return World
