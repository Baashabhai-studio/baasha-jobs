-- ── Baasha Delivery — Server ─────────────────────────────────────────────
-- Route + manifest state lives here, per crew. The core handles crews, pay, XP and the van.

local JOB = 'delivery'
local Core = exports.baasha_jobcore
local Routes = {}   -- crewId -> route

local function register() Core:RegisterJob(JOB, Config.Job) end
CreateThread(register)
AddEventHandler('onResourceStart', function(res)
    if res == 'baasha_jobcore' then SetTimeout(500, register) end
end)

-- qb-shops' own store-delivery job uses the GoPostal lot too: walking into its 3 m zone starts it
-- (charges a deposit), and driving any boxville2 into its 10 m deposit zone DELETES the van.
-- These are its stock coords; warn if our depot or van spawns sit on top of them.
CreateThread(function()
    Wait(2000)
    if GetResourceState('qb-shops') ~= 'started' then return end
    -- the depot ped vs the 3x3 m start zone; van spawns vs the deposit zone (only boxville2 gets deleted)
    local checks = { { Config.Job.depot.coords, vector3(69.09, 127.68, 79.21), 2.5 } }
    if Config.Job.vehicle.model == 'boxville2' then
        for _, sp in ipairs(Config.Job.vehicle.spawns) do checks[#checks + 1] = { sp, vector3(62.73, 124.98, 79.09), 12.0 } end
    end
    for _, c in ipairs(checks) do
        if #(vector3(c[1].x, c[1].y, c[1].z) - c[2]) < c[3] then
            print('^3[baasha_delivery] Depot / van spawn overlaps qb-shops store deliveries at the GoPostal lot. Its zones will charge players and delete the van: move Config.Job.depot / vehicle.spawns, or move qb-shops Config.DeliveryLocations.^7')
            return
        end
    end
end)

-- ── Helpers ───────────────────────────────────────────────────────────────
local function rand(range) return math.random(range[1], range[2]) end

local function pedCoords(src)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and GetEntityCoords(ped) or nil
end

local function distTo(src, c)
    local p = pedCoords(src)
    return p and #(p - vector3(c.x, c.y, c.z)) or math.huge
end

-- Doors: flat distance + a height allowance (steps, porches and stoops put the ped a few metres
-- above or below the recorded spot). Returns math.huge if the height is off.
local function doorDist(src, door)
    local p = pedCoords(src)
    if not p or math.abs(p.z - door.z) > Config.Delivery.doorHeight then return math.huge end
    return #(vector2(p.x, p.y) - vector2(door.x, door.y))
end

local function routeOf(src)
    local crewId = Core:GetPlayerCrew(src)
    if not crewId or not Core:IsOnShift(src, JOB) then return nil end
    return crewId, Routes[crewId]
end

local function truckOf(crewId)
    local crew = Core:GetCrew(crewId)
    if not crew or not crew.vehicle then return nil end
    local veh = NetworkGetEntityFromNetworkId(crew.vehicle)
    return veh ~= 0 and DoesEntityExist(veh) and veh or nil
end

-- GetOffsetFromEntityInWorldCoords is client-only, so rotate the offset by the van's heading here.
local function nearTruckRear(src, crewId)
    local truck = truckOf(crewId)
    if not truck then return false end
    local o = Config.Delivery.rearOffset
    local pos, h = GetEntityCoords(truck), math.rad(GetEntityHeading(truck))
    local rear = vector3(pos.x + o.x * math.cos(h) - o.y * math.sin(h), pos.y + o.x * math.sin(h) + o.y * math.cos(h), pos.z + o.z)
    return distTo(src, rear) <= Config.Delivery.takeDistance + 2.0
end

local function vanAtDepot(crewId)
    local truck = truckOf(crewId)
    if not truck then return false end
    local depot = Config.Job.depot.coords
    return #(GetEntityCoords(truck) - vector3(depot.x, depot.y, depot.z)) <= Config.Delivery.returnDistance
end

-- Loading happens at the back of the van, parked at the depot.
local function canLoad(src, crewId)
    if not vanAtDepot(crewId) then return false, L('not_at_depot') end
    if not nearTruckRear(src, crewId) then return false, L('near_van') end
    return true
end

local function parcelById(route, id)
    for _, p in ipairs(route.parcels) do
        if p.id == id then return p end
    end
end

local function nearOtherDoor(src, route, ownPos)
    for pos, idx in ipairs(route.stops) do
        if pos ~= ownPos then
            if doorDist(src, Config.Stops[idx].door) <= Config.Delivery.wrongDoorDistance then return true end
        end
    end
    return false
end

-- ── Route generation ──────────────────────────────────────────────────────
local function stopsForLevel(level)
    local count = 5
    for lvl, n in pairs(Config.Route.StopsByLevel) do
        if level >= lvl and n > count then count = n end
    end
    return math.min(count, #Config.Stops)
end

local function stopPos(idx)
    local d = Config.Stops[idx].door
    return vector3(d.x, d.y, d.z)
end

-- One neighbourhood per route: a random seed stop + the stops closest to it.
local function pickStops(count)
    local seed = math.random(#Config.Stops)
    local seedPos = stopPos(seed)
    local pool = {}
    for i = 1, #Config.Stops do pool[i] = { idx = i, d = #(stopPos(i) - seedPos) + math.random() * Config.Route.Spread } end
    table.sort(pool, function(a, b) return a.d < b.d end)
    local chosen = {}
    for i = 1, count do chosen[i] = pool[i].idx end

    -- Nearest-neighbour ordering, starting from the depot.
    local ordered, remaining = {}, {}
    for _, idx in ipairs(chosen) do remaining[#remaining + 1] = idx end
    local depot = Config.Job.depot.coords
    local from = vector3(depot.x, depot.y, depot.z)
    while #remaining > 0 do
        local bestI, bestD = 0, math.huge
        for i, idx in ipairs(remaining) do
            local d = Config.Stops[idx].door
            local dist = #(vector3(d.x, d.y, d.z) - from)
            if dist < bestD then bestI, bestD = i, dist end
        end
        local idx = remaining[bestI]
        ordered[#ordered + 1] = idx
        local d = Config.Stops[idx].door
        from = vector3(d.x, d.y, d.z)
        table.remove(remaining, bestI)
    end
    return ordered
end

local function rollType(lvl)
    local pool, total = {}, 0
    for name, t in pairs(Config.ParcelTypes) do
        if lvl >= (t.level or 1) then
            pool[#pool + 1] = { name = name, w = t.weight or 1 }
            total = total + (t.weight or 1)
        end
    end
    local r = math.random() * total
    for _, e in ipairs(pool) do
        r = r - e.w
        if r <= 0 then return e.name end
    end
    return pool[#pool].name
end

local function makeParcel(id, stop, ptype, stopDef)
    local shapes = Config.ParcelTypes[ptype].shapes
    local shapeName = shapes[math.random(#shapes)]
    local cells = Config.Shapes[shapeName].cells
    return {
        id       = ('A%02d'):format(id),
        stop     = stop,
        type     = ptype,
        shape    = shapeName,
        cells    = cells,
        weight   = #cells,
        fragile  = ptype == 'fragile',
        heavy    = ptype == 'large',
        label    = stopDef.label,
        customer = ptype == 'signature' and Config.Customers[math.random(#Config.Customers)] or nil,
        condition = 100,
        status   = 'van',
        deadline = nil,
        expressSeconds = nil,
    }
end

local function ensurePackable(manifest)
    local grid = manifest.grid
    -- Never ask for more than Config.Loading.maxFill of the cargo bay: drop extra parcels
    -- (keeping at least one per stop), then shrink big ones.
    local budget = math.floor(grid.w * grid.h * Config.Loading.maxFill)
    local function used()
        local n = 0
        for _, p in ipairs(manifest.parcels) do n = n + #p.cells end
        return n
    end
    local perStop = {}
    for _, p in ipairs(manifest.parcels) do perStop[p.stop] = (perStop[p.stop] or 0) + 1 end
    for i = #manifest.parcels, 1, -1 do
        if used() <= budget then break end
        local p = manifest.parcels[i]
        if perStop[p.stop] > 1 then
            perStop[p.stop] = perStop[p.stop] - 1
            table.remove(manifest.parcels, i)
        end
    end
    for _, p in ipairs(manifest.parcels) do
        if used() <= budget then break end
        if #p.cells > 2 then
            local def = Config.Shapes['1x2']
            p.shape, p.cells, p.weight = '1x2', def.cells, #def.cells
        end
    end
    if Puzzle.AutoPack(manifest, grid) then return end
    -- Shrink the largest parcels until it fits.
    local order = {}
    for _, p in ipairs(manifest.parcels) do order[#order + 1] = p end
    table.sort(order, function(a, b) return #a.cells > #b.cells end)
    for _, p in ipairs(order) do
        if #p.cells > 2 then
            local def = Config.Shapes['1x2']
            p.shape, p.cells, p.weight, p.heavy = '1x2', def.cells, #def.cells, false
            if Puzzle.AutoPack(manifest, grid) then return end
        end
    end
    -- Absolute fallback: all 1×2 parcels always pack.
    for _, p in ipairs(manifest.parcels) do
        local def = Config.Shapes['1x2']
        p.shape, p.cells, p.weight, p.heavy = '1x2', def.cells, #def.cells, false
    end
end

local function newRoute(leader)
    local lvl = Core:GetLevel(leader, JOB)
    local stops = pickStops(stopsForLevel(lvl))

    local parcels, id = {}, 0
    for pos, stopIdx in ipairs(stops) do
        local stopDef = Config.Stops[stopIdx]
        local isBusiness = stopDef.type == 'business'
        local n = 1
        if isBusiness and lvl >= Config.Delivery.bulkLevel then
            n = math.random(2, 3)
        elseif not isBusiness and lvl >= Config.Route.BiggerManifestLevel and math.random(100) <= Config.Route.BiggerManifestChance then
            n = 2
        end
        for _ = 1, n do
            id = id + 1
            local ptype = (isBusiness and lvl >= Config.Delivery.bulkLevel) and 'large' or rollType(lvl)
            parcels[#parcels + 1] = makeParcel(id, pos, ptype, stopDef)
        end
    end

    local manifest = { grid = { w = Config.Loading.grid.w, h = Config.Loading.grid.h }, parcels = parcels }
    ensurePackable(manifest)

    return {
        stage = 'loading',
        stops = stops,
        current = 1,
        parcels = manifest.parcels,
        carried = {},
        signPending = {},
        impactWindow = {},
        score = 0,
        stopStartedAt = nil,
        startedAt = os.time(),
    }
end

-- ── State broadcast ───────────────────────────────────────────────────────
local function publicState(route)
    local stopIdx = route.stops[route.current]
    local stopDef = Config.Stops[stopIdx]
    local parcelsLeft, remaining, returns = 0, 0, 0
    for _, p in ipairs(route.parcels) do
        if p.status == 'van' or p.status == 'carried' then
            remaining = remaining + 1
            if p.status == 'van' and p.stop == route.current then parcelsLeft = parcelsLeft + 1 end
        elseif p.status == 'return' then
            returns = returns + 1
        end
    end
    local stopList = {}
    for pos, idx in ipairs(route.stops) do
        local d = Config.Stops[idx].door
        stopList[#stopList + 1] = { x = d.x, y = d.y, z = d.z, label = Config.Stops[idx].label }
    end
    return {
        stage = route.stage,
        index = route.current,
        total = #route.stops,
        stops = stopList,
        stop = route.stage == 'driving' and { x = stopDef.door.x, y = stopDef.door.y, z = stopDef.door.z, w = stopDef.door.w } or nil,
        stopId = route.stage == 'driving' and stopIdx or nil,
        stopLabel = route.stage == 'driving' and stopDef.label or nil,
        stopType = route.stage == 'driving' and stopDef.type or nil,
        parcelsLeft = parcelsLeft,
        remaining = remaining,
        returns = returns,
        done = route.stage == 'done',
    }
end

local function broadcast(crewId, msg)
    local route, crew = Routes[crewId], Core:GetCrew(crewId)
    if not route or not crew then return end
    local state = publicState(route)
    state.msg = msg
    for _, m in ipairs(crew.members) do
        TriggerClientEvent('baasha_delivery:client:state', m, state)
    end
end

-- ── Delivery / rating / pay ───────────────────────────────────────────────
local function computeStars(p, took)
    local stars = 3
    local R = Config.Delivery.rating
    if took <= R.good then stars = stars + 2
    elseif took <= R.ok then stars = stars + 1
    elseif took > R.late then stars = stars - 1 end
    if p.type == 'fragile' then
        local c = p.condition or 100
        if c >= 90 then stars = stars + 1 elseif c < 50 then stars = stars - 1 end
    end
    if p.type == 'express' and p.deadline and os.time() > p.deadline then
        stars = math.min(stars, 3)   -- late = no tip
    end
    return math.max(1, math.min(5, stars))
end

local function stopComplete(route)
    for _, p in ipairs(route.parcels) do
        if p.stop == route.current and (p.status == 'van' or p.status == 'carried') then return false end
    end
    return true
end

local function maybeAdvance(crewId, route)
    if not stopComplete(route) then
        broadcast(crewId)
        return
    end
    if route.current >= #route.stops then
        route.stage = 'done'
        broadcast(crewId, L('route_done'))
    else
        route.current = route.current + 1
        route.stopStartedAt = nil
        broadcast(crewId, L('next_stop'))
    end
end

local function deliverStack(crewId, route, src, ids, method)
    local lvl = Core:GetLevel(src, JOB)
    local primary = parcelById(route, ids[1])
    local took = route.stopStartedAt and (os.time() - route.stopStartedAt) or 0
    local stars = computeStars(primary, took)
    local tipMult = stars > 3 and ((stars - 3) * Config.Delivery.tipPerStar) or 0

    local totalPay, totalXp, baseSum, cond, onTime = 0, 0, 0, nil, true
    for _, id in ipairs(ids) do
        local p = parcelById(route, id)
        if p and p.status == 'carried' then
            local base = rand(Config.ParcelTypes[p.type].pay)
            local pay = base
            if p.type == 'fragile' then
                cond = math.max(0, p.condition or 100)
                pay = math.floor(base * cond / 100)
            elseif p.type == 'express' then
                if p.deadline and os.time() <= p.deadline then
                    pay = pay + math.floor(base * Config.Delivery.expressBonus)
                else
                    onTime = false
                end
            end
            baseSum = baseSum + base
            totalPay = totalPay + pay
            totalXp = totalXp + (Config.ParcelTypes[p.type].xp or 0)
            p.status = 'delivered'
        end
    end
    route.carried[src] = nil

    local cap = lvl >= 8 and Config.Delivery.tipCapLvl8 or Config.Delivery.tipCap
    local tip = math.min(math.floor(baseSum * tipMult), cap)
    if primary.type == 'fragile' and (primary.condition or 100) < Config.Fragile.damagedBelow then
        tip = 0   -- damaged: base pay only, no tip
    end
    totalPay = totalPay + tip
    if totalPay > 0 then Core:RewardCrew(crewId, totalPay, totalXp) end

    maybeAdvance(crewId, route)
    return { stars = stars, tip = tip, condition = cond, pay = totalPay, express = primary.type == 'express', onTime = onTime }
end

local function parcelInfo(p, ids, handTruck)
    return {
        ids = ids, id = p.id, type = p.type, label = p.label,
        fragile = p.fragile, heavy = p.heavy, express = p.type == 'express',
        expressSeconds = p.expressSeconds, condition = p.condition,
        stack = #ids, size = #p.cells, handTruck = handTruck == true,
    }
end

-- ── Loading callbacks ─────────────────────────────────────────────────────
local function manifestForNui(route)
    local parcels = {}
    for _, p in ipairs(route.parcels) do
        parcels[#parcels + 1] = {
            id = p.id, type = p.type, label = p.label,
            cells = p.cells, weight = p.weight,
            fragile = p.fragile, heavy = p.heavy, stop = p.stop,
        }
    end
    return {
        grid = { w = Config.Loading.grid.w, h = Config.Loading.grid.h },
        parcels = parcels,
        mode = Config.Loading.mode,
        allowAutoPack = Config.Loading.allowAutoPack,
    }
end

lib.callback.register('baasha_delivery:getManifest', function(src)
    local crewId, route = routeOf(src)
    if not route or route.stage ~= 'loading' then return false end
    local can, why = canLoad(src, crewId)
    if not can then return false, why end
    return true, manifestForNui(route)
end)

lib.callback.register('baasha_delivery:autoPack', function(src)
    local crewId, route = routeOf(src)
    if not route or route.stage ~= 'loading' then return false end
    local can, why = canLoad(src, crewId)
    if not can then return false, why end
    local manifest = { grid = { w = Config.Loading.grid.w, h = Config.Loading.grid.h }, parcels = route.parcels }
    local placements = Puzzle.AutoPack(manifest, Config.Loading.grid)
    if not placements then return false end
    route.autoPlan = Puzzle.Key(placements)
    return true, placements
end)

lib.callback.register('baasha_delivery:loadDone', function(src, placements)
    local crewId, route = routeOf(src)
    if not route or route.stage ~= 'loading' then return false end
    local can, why = canLoad(src, crewId)
    if not can then return false, why end

    local manifest = { grid = { w = Config.Loading.grid.w, h = Config.Loading.grid.h }, parcels = route.parcels }
    if Config.Loading.mode == 'quick' then
        placements = Puzzle.AutoPack(manifest, Config.Loading.grid)
        if not placements then return false, L('no_parcel_here') end
    end

    local ok, score, err = Puzzle.Check(manifest, Config.Loading.grid, placements)
    if not ok then return false, err end
    -- Auto-packed (or quick mode) layouts are valid but never earn the full packing bonus.
    if Config.Loading.mode == 'quick' or (route.autoPlan and route.autoPlan == Puzzle.Key(placements)) then
        score = math.min(score, Config.Loading.autoPackMaxScore)
    end
    route.score = score
    route.stage = 'driving'
    route.stopStartedAt = nil
    broadcast(crewId, L('route_started', #route.stops))
    return true, { score = score, stops = #route.stops }
end)

-- ── Route callbacks ───────────────────────────────────────────────────────
lib.callback.register('baasha_delivery:takeParcel', function(src)
    local crewId, route = routeOf(src)
    if not route or route.stage ~= 'driving' then return false end
    if route.carried[src] then return false, L('already_carrying') end
    if not nearTruckRear(src, crewId) then return false, L('near_van') end

    local pick = {}
    for _, p in ipairs(route.parcels) do
        if p.stop == route.current and p.status == 'van' then pick[#pick + 1] = p end
    end
    if #pick == 0 then return false, L('no_parcel_here') end

    local lvl = Core:GetLevel(src, JOB)
    local count = 1
    if pick[1].heavy and lvl >= Config.Delivery.bulkLevel and #pick > 1 then
        count = math.min(3, #pick)   -- hand truck bulk grab
    end

    local ids = {}
    for i = 1, count do
        local p = pick[i]
        p.status = 'carried'
        if p.type == 'express' then
            p.expressSeconds = math.random(Config.Delivery.expressTime[1], Config.Delivery.expressTime[2])
            p.deadline = os.time() + p.expressSeconds
        end
        ids[#ids + 1] = p.id
    end
    route.carried[src] = ids
    if not route.stopStartedAt then route.stopStartedAt = os.time() end
    broadcast(crewId)
    return true, parcelInfo(pick[1], ids, pick[1].heavy and lvl >= Config.Delivery.bulkLevel)
end)

lib.callback.register('baasha_delivery:deliver', function(src)
    local crewId, route = routeOf(src)
    if not route or route.stage ~= 'driving' then return false end
    local ids = route.carried[src]
    if not ids or #ids == 0 then return false, L('not_carrying') end
    local primary = parcelById(route, ids[1])
    if primary.type == 'signature' then return false, L('needs_signature') end
    local ownDoor = Config.Stops[route.stops[primary.stop]].door
    if doorDist(src, ownDoor) > Config.Delivery.doorDistance then
        if nearOtherDoor(src, route, primary.stop) then return false, L('wrong_address') end
        return false, L('near_door')
    end
    return true, deliverStack(crewId, route, src, ids, 'leave')
end)

lib.callback.register('baasha_delivery:ring', function(src)
    local crewId, route = routeOf(src)
    if not route or route.stage ~= 'driving' then return false end
    local ids = route.carried[src]
    if not ids or #ids == 0 then return false, L('not_carrying') end
    local p = parcelById(route, ids[1])
    if p.type ~= 'signature' then return false end
    local ownDoor = Config.Stops[route.stops[p.stop]].door
    if doorDist(src, ownDoor) > Config.Delivery.doorDistance then
        if nearOtherDoor(src, route, p.stop) then return false, L('wrong_address') end
        return false, L('near_door')
    end
    local pend = route.signPending[src]
    if pend and os.time() - pend.at < 15 then return false, L('ring_wait') end

    local home = route.forceHome or math.random(100) <= Config.Signature.homeChance
    route.signPending[src] = { parcel = p.id, at = os.time() }
    if home then
        return true, { home = true, customer = p.customer, model = Config.CustomerPeds[math.random(#Config.CustomerPeds)] }
    end
    return true, { home = false }
end)

lib.callback.register('baasha_delivery:signDone', function(src)
    local crewId, route = routeOf(src)
    if not route or route.stage ~= 'driving' then return false end
    local pending = route.signPending[src]
    route.signPending[src] = nil
    if not pending then return false end
    local ids = route.carried[src]
    if not ids or #ids == 0 or ids[1] ~= pending.parcel then return false end
    local p = parcelById(route, ids[1])
    if not p or p.status ~= 'carried' then return false end
    if os.time() - pending.at < 2 then return false end
    local ownDoor = Config.Stops[route.stops[p.stop]].door
    if doorDist(src, ownDoor) > Config.Delivery.doorDistance * 2 then return false end
    return true, deliverStack(crewId, route, src, ids, 'signature')
end)

lib.callback.register('baasha_delivery:missed', function(src)
    local crewId, route = routeOf(src)
    if not route or route.stage ~= 'driving' then return false end
    local pending = route.signPending[src]
    route.signPending[src] = nil
    if not pending then return false end
    local ids = route.carried[src]
    if not ids or #ids == 0 or ids[1] ~= pending.parcel then return false end
    parcelById(route, ids[1]).status = 'return'
    maybeAdvance(crewId, route)
    return true, { stars = 1, tip = 0, pay = 0, condition = nil, express = false, onTime = false }
end)

lib.callback.register('baasha_delivery:stowReturn', function(src)
    local crewId, route = routeOf(src)
    if not route or route.stage == 'loading' then return false end
    local ids = route.carried[src]
    if not ids or #ids == 0 then return false end
    if parcelById(route, ids[1]).status ~= 'return' then return false, L('not_return') end
    if not nearTruckRear(src, crewId) then return false, L('near_van') end
    route.carried[src] = nil
    broadcast(crewId)
    return true
end)

lib.callback.register('baasha_delivery:dropParcel', function(src)
    local crewId, route = routeOf(src)
    if not route then return false end
    route.signPending[src] = nil
    local ids = route.carried[src]
    if not ids or #ids == 0 then return false end
    for _, id in ipairs(ids) do
        local p = parcelById(route, id)
        if p and p.status == 'carried' then
            p.status = 'van'
            if p.fragile then p.condition = math.max(0, (p.condition or 100) - Config.Fragile.dropLoss) end
        end
    end
    route.carried[src] = nil
    broadcast(crewId)
    return true
end)

-- ── Fragile damage events (clamped + rate-limited) ────────────────────────
local function reportDamage(src, value, inVan)
    local crewId, route = routeOf(src)
    if not route then return false end
    value = math.max(0, math.min(tonumber(value) or 0, Config.Fragile.maxLossPerReport))
    if value <= 0 then return true, nil end

    local w = route.impactWindow[src] or { n = 0, at = os.time() }
    if os.time() - w.at >= 60 then w.n, w.at = 0, os.time() end
    w.n = w.n + 1
    route.impactWindow[src] = w
    if w.n > Config.Fragile.maxReportsPerMin then return true, nil end

    local ids = route.carried[src]
    local result
    for _, p in ipairs(route.parcels) do
        if p.fragile then
            local carried = false
            for _, id in ipairs(ids or {}) do if id == p.id then carried = true break end end
            local hit
            if inVan then hit = (p.status == 'van') else hit = carried end
            if hit then
                p.condition = math.max(0, (p.condition or 100) - value)
                result = p.condition
            end
        end
    end
    return true, result
end

lib.callback.register('baasha_delivery:reportImpact', function(src, value)
    return reportDamage(src, value, false)
end)

lib.callback.register('baasha_delivery:reportVanDamage', function(src, value)
    return reportDamage(src, value, true)
end)

-- ── Finish route ──────────────────────────────────────────────────────────
lib.callback.register('baasha_delivery:finishRoute', function(src)
    local crewId, route = routeOf(src)
    if not route or route.stage ~= 'done' then return false end
    if next(route.carried) ~= nil then return false, L('still_carrying') end
    local truck = truckOf(crewId)
    local depot = Config.Job.depot.coords
    if not truck or #(GetEntityCoords(truck) - vector3(depot.x, depot.y, depot.z)) > Config.Delivery.returnDistance then
        return false, L('not_at_depot')
    end

    local returnPay = 0
    for _, p in ipairs(route.parcels) do
        if p.status == 'return' then
            returnPay = returnPay + math.floor(rand(Config.ParcelTypes[p.type].pay) * Config.Delivery.returnPay)
        end
    end
    local stops = #route.stops
    local routeBonus = Config.Route.RouteBonusPerStop * stops
    local packing = math.floor(routeBonus * Config.Loading.packBonusMax * route.score / 100)
    local total = returnPay + routeBonus + packing
    if total > 0 then Core:RewardCrew(crewId, total, Config.Route.RouteXpPerStop * stops) end

    if Config.Items.enabled then
        local crew = Core:GetCrew(crewId)
        if crew then
            for _, m in ipairs(crew.members) do
                local lvl = Core:GetLevel(m, JOB)
                for _, r in ipairs(Config.Items.rewards) do
                    if lvl >= (r.level or 1) and math.random(100) <= (r.chance or 5) then
                        Core:GiveItem(m, r.item, math.random(r.min or 1, r.max or 1))
                    end
                end
            end
        end
    end

    local crew = Core:GetCrew(crewId)
    Routes[crewId] = newRoute(crew.leader)
    broadcast(crewId, L('new_route', #Routes[crewId].stops))
    return true, { returnPay = returnPay, routeBonus = routeBonus, packing = packing, total = total }
end)

-- ── Core events ───────────────────────────────────────────────────────────
AddEventHandler('baasha_jobcore:server:shiftStarted', function(jobId, crewId, crew)
    if jobId ~= JOB then return end
    Routes[crewId] = newRoute(crew.leader)
    broadcast(crewId)
end)

AddEventHandler('baasha_jobcore:server:shiftEnded', function(jobId, crewId)
    if jobId == JOB then Routes[crewId] = nil end
end)

AddEventHandler('baasha_jobcore:server:memberLeft', function(jobId, crewId, src)
    if jobId ~= JOB then return end
    local route = Routes[crewId]
    if not route then return end
    local ids = route.carried[src]
    if ids then
        for _, id in ipairs(ids) do
            local p = parcelById(route, id)
            if p and p.status == 'carried' then p.status = 'van' end
        end
        route.carried[src] = nil
    end
    route.signPending[src] = nil
    route.impactWindow[src] = nil
    broadcast(crewId)
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        for crewId in pairs(Routes) do Routes[crewId] = nil end
    end
end)

-- ── Automation exports (showcase / test tools) ────────────────────────────
exports('ForceStop', function(crewId, index)
    local route = Routes[crewId]
    if not route or route.stage ~= 'driving' then return false end
    index = tonumber(index) or 1
    if index < 1 or index > #route.stops then return false end
    route.current = index
    route.stopStartedAt = nil
    for src, ids in pairs(route.carried) do
        for _, id in ipairs(ids) do
            local p = parcelById(route, id)
            if p and p.status == 'carried' then p.status = 'van' end
        end
    end
    route.carried = {}
    route.signPending = {}
    broadcast(crewId)
    return true
end)

--- Showcase: a hand-picked route. list = { { stop = <Config.Stops index>, type = 'standard'|'signature'|... }, ... }
--- Customers are always home on this route so the signature scene can be filmed.
exports('SetRoute', function(crewId, list)
    if not Routes[crewId] or type(list) ~= 'table' or #list == 0 then return false end
    local stops, parcels = {}, {}
    for pos, e in ipairs(list) do
        local idx = tonumber(e.stop)
        if not idx or not Config.Stops[idx] or not Config.ParcelTypes[e.type or 'standard'] then return false end
        stops[pos] = idx
        parcels[#parcels + 1] = makeParcel(pos, pos, e.type or 'standard', Config.Stops[idx])
    end
    local manifest = { grid = { w = Config.Loading.grid.w, h = Config.Loading.grid.h }, parcels = parcels }
    ensurePackable(manifest)
    local route = newRoute(Core:GetCrew(crewId).leader)
    route.stops, route.parcels, route.forceHome = stops, manifest.parcels, true
    Routes[crewId] = route
    broadcast(crewId)
    return true
end)

exports('ResetRoute', function(crewId)
    local route = Routes[crewId]
    if not route then return false end
    local crew = Core:GetCrew(crewId)
    if not crew then return false end
    Routes[crewId] = newRoute(crew.leader)
    broadcast(crewId)
    return true
end)
