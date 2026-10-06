-- ── Baasha Garbage — Server ──────────────────────────────────────────────
-- Route state lives here, per crew. The core handles crews, pay, XP and the truck.

local JOB = 'garbage'
local Core = exports.baasha_jobcore
local Routes = {}   -- crewId -> route

local function register() Core:RegisterJob(JOB, Config.Job) end
CreateThread(register)
AddEventHandler('onResourceStart', function(res)
    if res == 'baasha_jobcore' then SetTimeout(500, register) end
end)

-- ── Helpers ───────────────────────────────────────────────────────────────
local function rand(range) return math.random(range[1], range[2]) end

local function stopsForLevel(level)
    local count = 4
    for lvl, n in pairs(Config.Route.StopsByLevel) do
        if level >= lvl and n > count then count = n end
    end
    return math.min(count, #Config.Stops)
end

local function newRoute(leader, inTruck)
    local pool = {}
    for i = 1, #Config.Stops do pool[i] = i end
    for i = #pool, 2, -1 do
        local j = math.random(i)
        pool[i], pool[j] = pool[j], pool[i]
    end
    local stops = {}
    for i = 1, stopsForLevel(Core:GetLevel(leader, JOB)) do stops[i] = pool[i] end
    return {
        stops = stops, current = 1, bagsLeft = rand(Config.Route.BagsPerStop),
        inTruck = inTruck or 0, carrying = {}, compactStart = {}, done = false,
    }
end

local function broadcast(crewId, msg)
    local route, crew = Routes[crewId], Core:GetCrew(crewId)
    if not route or not crew then return end
    local state = {
        stop = not route.done and Config.Stops[route.stops[route.current]] or nil,
        stopId = not route.done and route.stops[route.current] or nil,
        index = route.current, total = #route.stops,
        bagsLeft = route.bagsLeft, inTruck = route.inTruck, capacity = Config.Route.TruckCapacity,
        done = route.done, msg = msg,
    }
    for _, m in ipairs(crew.members) do
        TriggerClientEvent('baasha_garbage:client:state', m, state)
    end
end

local function routeOf(src)
    local crewId = Core:GetPlayerCrew(src)
    if not crewId or not Core:IsOnShift(src, JOB) then return nil end
    return crewId, Routes[crewId]
end

local function pedDistTo(src, coords)
    local ped = GetPlayerPed(src)
    if ped == 0 then return math.huge end
    return #(GetEntityCoords(ped) - vector3(coords.x, coords.y, coords.z))
end

local function truckOf(crewId)
    local crew = Core:GetCrew(crewId)
    if not crew or not crew.vehicle then return nil end
    local veh = NetworkGetEntityFromNetworkId(crew.vehicle)
    return veh ~= 0 and DoesEntityExist(veh) and veh or nil
end

local function nearTruck(src, crewId)
    local truck = truckOf(crewId)
    return truck and pedDistTo(src, GetEntityCoords(truck)) <= 8.0
end

local function advance(crewId, route)
    route.current = route.current + 1
    if route.current > #route.stops then
        route.done = true
        broadcast(crewId, L('route_done'))
    else
        route.bagsLeft = route.fixedBags or rand(Config.Route.BagsPerStop)
        broadcast(crewId, L('next_stop'))
    end
end

-- ── Callbacks ─────────────────────────────────────────────────────────────
lib.callback.register('baasha_garbage:pickup', function(src)
    local crewId, route = routeOf(src)
    if not route or route.done then return false end
    if route.carrying[src] then return false, L('already_bag') end
    if route.bagsLeft <= 0 then return false, L('no_bags') end
    if pedDistTo(src, Config.Stops[route.stops[route.current]]) > Config.Route.PickupRadius then return false, L('too_far_stop') end

    route.bagsLeft = route.bagsLeft - 1
    route.carrying[src] = true
    broadcast(crewId)
    return true
end)

lib.callback.register('baasha_garbage:drop', function(src)
    local crewId, route = routeOf(src)
    if not route or not route.carrying[src] then return false end
    route.carrying[src] = nil
    route.bagsLeft = route.bagsLeft + 1
    broadcast(crewId)
    return true
end)

lib.callback.register('baasha_garbage:throw', function(src)
    local crewId, route = routeOf(src)
    if not route or not route.carrying[src] then return false end
    if not nearTruck(src, crewId) then return false end
    if route.inTruck >= Config.Route.TruckCapacity then return false, L('truck_full') end

    route.carrying[src] = nil
    route.inTruck = route.inTruck + 1
    Core:RewardCrew(crewId, rand(Config.Route.PayPerBag), Config.Route.XpPerBag)

    local found, level = {}, Core:GetLevel(src, JOB)
    for _, r in ipairs(Config.Recyclables) do
        if level >= (r.level or 1) and math.random(100) <= r.chance then
            local count = math.random(r.min, r.max)
            if Core:GiveItem(src, r.item, count) then found[#found + 1] = { item = r.item, count = count } end
        end
    end

    if route.bagsLeft <= 0 and next(route.carrying) == nil then
        advance(crewId, route)
    else
        broadcast(crewId)
    end
    return true, found
end)

lib.callback.register('baasha_garbage:compactStart', function(src)
    local crewId, route = routeOf(src)
    if not route or route.inTruck == 0 or not nearTruck(src, crewId) then return false end
    route.compactStart[src] = GetGameTimer()
    return true
end)

lib.callback.register('baasha_garbage:compact', function(src)
    local crewId, route = routeOf(src)
    if not route then return false end
    local started = route.compactStart[src]
    route.compactStart[src] = nil
    if not started or GetGameTimer() - started < Config.Route.CompactTime - 750 then return false end
    if not nearTruck(src, crewId) then return false end
    route.inTruck = 0
    broadcast(crewId)
    return true
end)

lib.callback.register('baasha_garbage:finish', function(src)
    local crewId, route = routeOf(src)
    if not route or not route.done then return false end
    local truck = truckOf(crewId)
    local depot = Config.Job.depot.coords
    if not truck or #(GetEntityCoords(truck) - vector3(depot.x, depot.y, depot.z)) > 40.0 then
        return false, L('not_at_depot')
    end

    local stops = #route.stops
    Core:RewardCrew(crewId, Config.Route.RouteBonus * stops, Config.Route.RouteXpPerStop * stops)

    local crew = Core:GetCrew(crewId)
    Routes[crewId] = newRoute(crew.leader, 0)
    broadcast(crewId, L('new_route', #Routes[crewId].stops))
    return true
end)

-- ── Automation hook (showcase tools): force a crew's route to specific stops ──
exports('SetRoute', function(crewId, stops, bagsPerStop)
    local route = Routes[crewId]
    if not route or type(stops) ~= 'table' or #stops == 0 then return false end
    for _, i in ipairs(stops) do
        if not Config.Stops[i] then return false end
    end
    route.stops, route.current, route.done = stops, 1, false
    route.fixedBags = bagsPerStop                                  -- nil = random like a normal route
    route.bagsLeft = bagsPerStop or rand(Config.Route.BagsPerStop)
    route.carrying = {}
    broadcast(crewId)
    return true
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
    local route = jobId == JOB and Routes[crewId]
    if route and route.carrying[src] then
        route.carrying[src] = nil
        route.bagsLeft = route.bagsLeft + 1
        broadcast(crewId)
    end
end)
