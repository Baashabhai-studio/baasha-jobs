-- ── Baasha Lifeguard — Server ────────────────────────────────────────────
-- The server owns every call: where it happens, what it needs (CPR or not), and it checks each step
-- (distance, timing) before paying. The core handles crews, XP, pay and levels.

local JOB = 'lifeguard'
local Core = exports.baasha_jobcore

local Calls = {}      -- crewId -> active call
local Next = {}       -- crewId -> when the next radio call comes in
local Watches = {}    -- src -> binoculars session
local WatchCd = {}    -- src -> next watch allowed
local Paused = {}     -- crewId -> true: no radio calls (test / showcase tools)
local NextOpts = {}   -- crewId -> options for the next call (test / showcase tools)
local nextCallId = 0

local function register() Core:RegisterJob(JOB, Config.Job) end
CreateThread(register)
AddEventHandler('onResourceStart', function(res)
    if res == 'baasha_jobcore' then SetTimeout(500, register) end
end)

-- ── Helpers ───────────────────────────────────────────────────────────────
local function now() return GetGameTimer() / 1000.0 end
local function pedCoords(src)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and GetEntityCoords(ped) or nil
end
local function onShift(src) return Core:IsOnShift(src, JOB) end
local function level(src) return Core:GetLevel(src, JOB) or 1 end
local function flat(a, b) return #(vector2(a.x, a.y) - vector2(b.x, b.y)) end
local function near(src, c, r)
    local here = pedCoords(src)
    return here ~= nil and math.abs(here.z - c.z) < 25.0 and flat(here, c) <= r
end

local function nearestTower(c)
    local best, bestD = 1, 1e9
    for i, t in ipairs(Config.Towers) do
        local d = flat(c, t.coords)
        if d < bestD then best, bestD = i, d end
    end
    return best, bestD
end

local function members(crewId)
    local crew = Core:GetCrew(crewId)
    return crew and crew.members or {}
end
local function toCrew(crewId, event, ...)
    for _, m in ipairs(members(crewId)) do TriggerClientEvent(event, m, ...) end
end

local function spotBonus(lvl)
    local W = Config.Watch
    return lvl >= W.bigBonusFrom and W.bigBonus or W.bonus
end

local function cprParams()
    local P = Config.Cpr
    return { cycles = P.cycles, compressions = P.compressions, bpm = P.bpm, perfect = P.perfect, good = P.good, pass = P.pass, maxExtra = P.maxExtra }
end

-- ── Calls ─────────────────────────────────────────────────────────────────
local function publicCall(c)
    local def = Config.Calls[c.type]
    return {
        id = c.id, type = c.type, label = def.label, icon = def.icon, water = def.water == true,
        coords = { x = c.spot.x, y = c.spot.y, z = c.spot.z, w = c.spot.w or 0.0 },
        tower = c.tower, towerLabel = Config.Towers[c.tower].label,
        expiresIn = math.max(0, math.floor(c.expiresAt - now())), stage = c.stage, ped = c.ped,
        rescuer = c.rescuer, spotted = c.spotted, model = c.model,
    }
end

local function pickType(lvl)
    local list, total = {}, 0
    for id, def in pairs(Config.Calls) do
        if lvl >= def.level then list[#list + 1] = { id = id, w = def.weight } total = total + def.weight end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    local r = math.random() * total
    for _, e in ipairs(list) do
        r = r - e.w
        if r <= 0 then return e.id end
    end
    return list[#list].id
end

local function pickSpot(pool, towerIdx)
    if not towerIdx then return pool[math.random(#pool)] end
    -- spotted from a tower: one of the two spots closest to it
    local t = Config.Towers[towerIdx].coords
    local sorted = {}
    for i, s in ipairs(pool) do sorted[i] = s end
    table.sort(sorted, function(a, b) return flat(a, t) < flat(b, t) end)
    return sorted[math.random(math.min(2, #sorted))]
end

local function scheduleNext(crewId, lvl)
    local D = Config.Dispatch
    local wait = math.random(D.interval[1], D.interval[2])
    if lvl and lvl >= D.fasterFrom then wait = wait * 0.75 end
    Next[crewId] = now() + wait
end

local function deletePed(netId, delay)
    if not netId then return end
    SetTimeout(delay or 0, function()
        local ent = NetworkGetEntityFromNetworkId(netId)
        if ent ~= 0 and DoesEntityExist(ent) then DeleteEntity(ent) end
    end)
end

local function newCall(crewId, forcedType, towerIdx, spotted, opts)
    local crew = Core:GetCrew(crewId)
    if not crew or crew.jobId ~= JOB or Calls[crewId] then return end
    local lvl = level(crew.leader)
    local t = forcedType or pickType(lvl)
    local def = Config.Calls[t]
    opts = opts or NextOpts[crewId]
    NextOpts[crewId] = nil
    local spot = opts and opts.spot or pickSpot(def.water and Config.WaterSpots or Config.BeachSpots, towerIdx)
    if def.farther and not (opts and opts.spot) then
        -- further out to sea, straight out from the nearest tower (a jet ski job)
        local tc = Config.Towers[towerIdx or nearestTower(spot)].coords
        local dir = vector3(spot.x - tc.x, spot.y - tc.y, 0.0)
        if #dir > 1.0 then
            dir = dir / #dir
            spot = vector4(spot.x + dir.x * def.farther, spot.y + dir.y * def.farther, spot.z, spot.w or 0.0)
        end
    end
    nextCallId = nextCallId + 1
    local c = {
        id = nextCallId, crew = crewId, type = t, spot = spot, tower = towerIdx or nearestTower(spot),
        startedAt = now(), expiresAt = now() + def.timeout, stage = 'open', spotted = spotted == true,
        needsCpr = t == 'floating',
        model = t == 'shark' and Config.Shark.model or (opts and opts.model) or Config.VictimModels[math.random(#Config.VictimModels)],
        bonus = spotted and spotBonus(lvl) or 0,
    }
    if opts and opts.needsCpr ~= nil then c.needsCpr = opts.needsCpr == true end
    Calls[crewId] = c
    toCrew(crewId, 'baasha_lifeguard:client:call', publicCall(c))
    if Config.Debug then print(('[baasha_lifeguard] crew %s call #%s %s at %s'):format(crewId, c.id, t, Config.Towers[c.tower].label)) end
    return c
end

--- End the active call: result = { ok, msg, pay, xp, kind }
local function closeCall(crewId, result, pedDelay)
    local c = Calls[crewId]
    if not c then return end
    Calls[crewId] = nil
    local crew = Core:GetCrew(crewId)
    scheduleNext(crewId, crew and level(crew.leader))
    toCrew(crewId, 'baasha_lifeguard:client:callEnded', c.id, result)
    deletePed(c.ped, pedDelay or 20000)
end

local function payCall(crewId, c, extraPay, extraXp, msg, kind)
    local def = Config.Calls[c.type]
    local mult = 1 + (c.bonus or 0)
    local pay = math.floor((def.pay + (extraPay or 0)) * mult)
    local xp = math.floor((def.xp + (extraXp or 0)) * mult)
    Core:RewardCrew(crewId, pay, xp)
    closeCall(crewId, { ok = true, msg = msg, pay = pay, xp = xp, kind = kind, spotted = c.spotted })
end

local function setStage(crewId, c, stage, rescuer)
    c.stage, c.rescuer = stage, rescuer or c.rescuer
    toCrew(crewId, 'baasha_lifeguard:client:stage', c.id, stage, c.rescuer)
end

--- The caller's active call, if `id` matches it
local function myCall(src, id)
    local crewId = Core:GetPlayerCrew(src)
    local c = crewId and Calls[crewId]
    if c and c.id == id then return c, crewId end
end

-- Radio dispatch + timeouts
CreateThread(function()
    while true do
        Wait(2000)
        for crewId, at in pairs(Next) do
            local crew = Core:GetCrew(crewId)
            if not crew or crew.jobId ~= JOB then
                Next[crewId] = nil
            elseif not Calls[crewId] and not Paused[crewId] and now() >= at then
                newCall(crewId)
            end
        end
        for crewId, c in pairs(Calls) do
            -- once someone has the victim the clock stops (a stuck call still clears after 10 more minutes)
            if (c.stage == 'open' and now() > c.expiresAt) or now() > c.expiresAt + 600 then
                closeCall(crewId, { ok = false, msg = L('call_timeout') }, 2000)
            end
        end
    end
end)

-- ── The victim / shark ped: the first crew member close by spawns it (networked) ──
lib.callback.register('baasha_lifeguard:claimPed', function(src, id)
    local c = myCall(src, id)
    if not c or c.ped then return false end
    if c.claimer and now() - c.claimAt < 10 then return false end
    c.claimer, c.claimAt = src, now()
    return true
end)

lib.callback.register('baasha_lifeguard:pedSpawned', function(src, id, netId)
    local c, crewId = myCall(src, id)
    if not c or c.claimer ~= src or c.ped then
        deletePed(netId) -- the call ended while it was spawning
        return false
    end
    c.ped = netId
    toCrew(crewId, 'baasha_lifeguard:client:pedReady', c.id, netId)
    return true
end)

-- ── Drowning swimmer: grab → bring to a tower → (CPR) ─────────────────────
lib.callback.register('baasha_lifeguard:grab', function(src, id)
    local c, crewId = myCall(src, id)
    if not c or (c.type ~= 'drowning' and c.type ~= 'floating') then return false end
    if c.stage ~= 'open' then return false, L('busy') end
    if not near(src, c.spot, 9.0) then return false, L('too_far') end
    c.grabAt = now()
    setStage(crewId, c, 'rescuing', src)
    return true
end)

lib.callback.register('baasha_lifeguard:deliver', function(src, id, how)
    local c, crewId = myCall(src, id)
    if not c or c.stage ~= 'rescuing' or c.rescuer ~= src then return false end
    local here = pedCoords(src)
    local _, d = nearestTower(here)
    if how == 'ski' then
        -- off the jet ski in the shallows: only someone awake (no CPR), and close to a tower's beach
        if c.needsCpr or d > 160.0 or here.z < -1.5 then return false, L('not_sand') end
    elseif d > Config.Shore.beach or here.z < -0.5 then
        return false, L('not_sand')
    end
    if now() - (c.grabAt or 0) < 4.0 then return false, L('too_fast') end -- nobody gets a swimmer ashore this fast
    if c.needsCpr then
        c.cprAt = now()
        setStage(crewId, c, 'cpr', src)
        return true, 'cpr', cprParams()
    end
    payCall(crewId, c, 0, 0, L('rescued'), 'rescued')
    return true, 'ok'
end)

-- ── Unconscious person: CPR on the spot ───────────────────────────────────
lib.callback.register('baasha_lifeguard:startCpr', function(src, id)
    local c, crewId = myCall(src, id)
    if not c or c.type ~= 'unconscious' then return false end
    if c.stage ~= 'open' then return false, L('busy') end
    if not near(src, c.spot, 6.0) then return false, L('too_far') end
    c.cprAt = now()
    setStage(crewId, c, 'cpr', src)
    return true, cprParams()
end)

lib.callback.register('baasha_lifeguard:cprDone', function(src, id, result)
    local c, crewId = myCall(src, id)
    if not c or c.stage ~= 'cpr' or c.rescuer ~= src or type(result) ~= 'table' then return false end
    local P = Config.Cpr
    -- the compressions alone take this long on the beat
    local minTime = P.cycles * P.compressions * 60 / P.bpm * 0.8
    local success = result.success == true and (tonumber(result.accuracy) or 0) >= P.pass and now() - c.cprAt >= minTime
    if success then
        payCall(crewId, c, P.savePay, P.saveXp, L('cpr_saved'), 'saved')
    else
        Core:RewardCrew(crewId, P.lostPay, P.lostXp)
        closeCall(crewId, { ok = false, msg = L('cpr_lost'), pay = P.lostPay, xp = P.lostXp, kind = 'lost' }, 12000)
    end
    return true, success
end)

-- ── Jellyfish sting: first aid ────────────────────────────────────────────
lib.callback.register('baasha_lifeguard:treatStart', function(src, id)
    local c, crewId = myCall(src, id)
    if not c or c.type ~= 'jellyfish' then return false end
    if c.stage ~= 'open' then return false, L('busy') end
    if not near(src, c.spot, 6.0) then return false, L('too_far') end
    c.treatAt = now()
    setStage(crewId, c, 'treat', src)
    return true, Config.FirstAid
end)

lib.callback.register('baasha_lifeguard:treatDone', function(src, id, ok)
    local c, crewId = myCall(src, id)
    if not c or c.stage ~= 'treat' or c.rescuer ~= src then return false end
    if ok ~= true or now() - c.treatAt < Config.FirstAid.minTime then
        c.rescuer = nil
        setStage(crewId, c, 'open', nil)
        return false, L('treat_failed')
    end
    payCall(crewId, c, 0, 0, L('treated'), 'treated')
    return true
end)

-- ── Shark sighting: sound the alarm at the nearest tower ──────────────────
lib.callback.register('baasha_lifeguard:alarm', function(src, id)
    local c, crewId = myCall(src, id)
    if not c or c.type ~= 'shark' then return false end
    if c.stage ~= 'open' then return false, L('busy') end
    if not near(src, Config.Towers[c.tower].coords, 8.0) then return false, L('too_far') end
    c.alarmAt = now()
    setStage(crewId, c, 'alarm', src)
    return true, Config.Shark.clearTime
end)

lib.callback.register('baasha_lifeguard:alarmDone', function(src, id)
    local c, crewId = myCall(src, id)
    if not c or c.stage ~= 'alarm' or c.rescuer ~= src then return false end
    if now() - c.alarmAt < Config.Shark.clearTime * 0.9 then return false end
    payCall(crewId, c, 0, 0, L('shark_cleared'), 'cleared')
    return true
end)

-- ── Tower watch (binoculars) ──────────────────────────────────────────────
lib.callback.register('baasha_lifeguard:watchStart', function(src, towerIdx)
    if not onShift(src) then return false end
    local t = Config.Towers[tonumber(towerIdx) or 0]
    if not t or not near(src, t.coords, 10.0) then return false, L('too_far') end
    local crewId = Core:GetPlayerCrew(src)
    if Calls[crewId] then return false, L('have_call') end
    if WatchCd[src] and now() < WatchCd[src] then return false, L('watch_cooldown', math.ceil(WatchCd[src] - now())) end

    local W, lvl = Config.Watch, level(src)
    local target = 'drowning'
    if lvl >= Config.Calls.shark.level and math.random() < W.sharkChance then target = 'shark' end
    local forced = NextOpts[crewId] and NextOpts[crewId].watchTarget -- test / showcase tools
    if forced == 'drowning' or forced == 'shark' then target = forced end
    local params = {
        tower = towerIdx, towerLabel = t.label, level = lvl, target = target,
        time = math.max(W.time.min, W.time.start - (lvl - 1) * W.time.perLevel),
        swimmers = math.min(W.swimmers.max, W.swimmers.start + (lvl - 1) * W.swimmers.perLevel),
        decoys = lvl >= W.decoysFrom and math.min(4, lvl - W.decoysFrom + 1) or 0,
        falseAlarm = W.falseAlarm, bonus = math.floor(spotBonus(lvl) * 100),
    }
    Watches[src] = { tower = towerIdx, startAt = now(), params = params }
    return true, params
end)

lib.callback.register('baasha_lifeguard:watchDone', function(src, result)
    local s = Watches[src]
    Watches[src] = nil
    WatchCd[src] = now() + Config.Watch.cooldown
    if not s or type(result) ~= 'table' then return false end
    local took = now() - s.startAt
    if result.found ~= true or took < 1.0 or took > s.params.time + 8 then return false, L('watch_nothing') end
    local crewId = Core:GetPlayerCrew(src)
    if not crewId or Calls[crewId] then return false end
    -- the swimmer you marked through the binoculars becomes the call, right where they are
    -- (checked: sea level, in front of this tower). Otherwise one of the usual spots.
    local opts = NextOpts[crewId] or {}
    NextOpts[crewId] = nil
    local sp = type(result.spot) == 'table' and result.spot
    local x, y, z = sp and tonumber(sp.x), sp and tonumber(sp.y), sp and tonumber(sp.z)
    if x and y and z and math.abs(z) < 4.0 and flat(vector3(x, y, z), Config.Towers[s.tower].coords) < 220.0 then
        opts.spot = vector4(x, y, z, tonumber(sp.w) or 0.0)
    end
    for _, m in ipairs(Config.VictimModels) do
        if m == result.model then opts.model = m end
    end
    local c = newCall(crewId, s.params.target, s.tower, true, opts)
    return c ~= nil
end)

-- ── Jet ski ───────────────────────────────────────────────────────────────
--- towerIdx = nil: at HQ (Config.JetSki.spawn). At a tower: the tower's own `jetski` spot, or the water
--- spot the client found in front of it (checked: close to that tower, at sea level).
lib.callback.register('baasha_lifeguard:rentJetski', function(src, towerIdx, spot)
    if not onShift(src) then return nil end
    local J = Config.JetSki
    if level(src) < J.level then return nil, L('level_needed', 'The jet ski', J.level) end
    local at = J.spawn
    if towerIdx then
        local t = Config.Towers[tonumber(towerIdx) or 0]
        if not t or not J.atTowers or not near(src, t.coords, 14.0) then return nil, L('too_far') end
        at = t.jetski
        if not at then
            local x, y, z, w = tonumber(spot and spot.x), tonumber(spot and spot.y), tonumber(spot and spot.z), tonumber(spot and spot.w)
            if not (x and y and z) or math.abs(z) > 4.0 or flat(vector3(x, y, z), t.coords) > 200.0 then return nil, L('no_water') end
            at = vector4(x, y, z, w or 0.0)
        end
    elseif not near(src, Config.Job.depot.coords, 10.0) then
        return nil, L('too_far')
    end
    return Core:RentVehicle(src, { model = J.model, type = 'boat', spot = at, deposit = J.deposit, returnDistance = J.returnDistance, max = 1 })
end)

lib.callback.register('baasha_lifeguard:returnJetski', function(src, netId)
    return Core:ReturnVehicle(src, netId)
end)

lib.callback.register('baasha_lifeguard:info', function(src)
    if not onShift(src) then return nil end
    local crewId = Core:GetPlayerCrew(src)
    local c = crewId and Calls[crewId]
    return { level = level(src), call = c and publicCall(c) or nil }
end)

-- ── Shifts ────────────────────────────────────────────────────────────────
AddEventHandler('baasha_jobcore:server:shiftStarted', function(jobId, crewId)
    if jobId ~= JOB then return end
    Next[crewId] = now() + Config.Dispatch.first
end)

AddEventHandler('baasha_jobcore:server:shiftEnded', function(jobId, crewId)
    if jobId ~= JOB then return end
    local c = Calls[crewId]
    Calls[crewId], Next[crewId], Paused[crewId], NextOpts[crewId] = nil, nil, nil, nil
    if c then deletePed(c.ped, 0) end
end)

AddEventHandler('baasha_jobcore:server:memberLeft', function(jobId, crewId, src)
    if jobId ~= JOB then return end
    local c = Calls[crewId]
    if c and c.rescuer == src and c.stage ~= 'open' then
        c.rescuer = nil
        setStage(crewId, c, 'open', nil)
    end
    Watches[src] = nil
end)

AddEventHandler('playerDropped', function()
    Watches[source], WatchCd[source] = nil, nil
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, c in pairs(Calls) do deletePed(c.ped, 0) end
end)

-- ── Admin tools ───────────────────────────────────────────────────────────
-- /lgspot water|beach : save your position as a new call spot (spots.txt in the resource)
RegisterCommand('lgspot', function(src, args)
    local c = src > 0 and pedCoords(src)
    if not c then return end
    local kind = args[1] == 'beach' and 'beach' or 'water'
    local heading = GetEntityHeading(GetPlayerPed(src))
    local line = kind == 'water' and ('vector4(%.2f, %.2f, %.2f, %.2f),'):format(c.x, c.y, c.z, heading)
        or ('vector3(%.2f, %.2f, %.2f),'):format(c.x, c.y, c.z)
    local file = LoadResourceFile(GetCurrentResourceName(), 'spots.txt') or ''
    SaveResourceFile(GetCurrentResourceName(), 'spots.txt', file .. kind .. ': ' .. line .. '\n', -1)
    TriggerClientEvent('chat:addMessage', src, { args = { 'Lifeguard', ('Saved %s spot %s'):format(kind, line) } })
end, true)

-- /lgcall [drowning|floating|unconscious|jellyfish|shark] [near] : send your crew a call right now (testing)
RegisterCommand('lgcall', function(src, args)
    local function reply(msg, kind)
        if src == 0 then print('[baasha_lifeguard] ' .. msg)
        else TriggerClientEvent('ox_lib:notify', src, { title = 'Lifeguard', description = msg, type = kind or 'error' }) end
    end
    if src == 0 then return reply('/lgcall works in-game only (F8 or chat): it uses your position and crew.') end
    if not onShift(src) then return reply('Start a lifeguard shift first (tablet at the HQ), then /lgcall.') end
    local crewId = Core:GetPlayerCrew(src)
    if not crewId then return reply('You are not in a lifeguard crew.') end
    if args[1] and not Config.Calls[args[1]] then
        return reply(('Unknown call "%s". Use: drowning, floating, unconscious, jellyfish, shark (add "near" for your closest tower).'):format(args[1]))
    end
    if Calls[crewId] then closeCall(crewId, { ok = false, msg = 'Call cancelled.' }, 0) end
    local here = pedCoords(src)
    local c = newCall(crewId, args[1], args[2] == 'near' and nearestTower(here) or nil, false)
    if c then reply(('Test call: %s at %s'):format(c.type, Config.Towers[c.tower].label), 'success')
    else reply('Could not start a call (is your crew on the lifeguard job?).') end
end, true)

--- Automation (test / showcase tools)
--- ForceCall(src, type, nearMe, opts) : opts.needsCpr = true / false forces whether a swimmer needs CPR
exports('ForceCall', function(src, callType, nearMe, opts)
    local crewId = Core:GetPlayerCrew(src)
    if not crewId then return false end
    if Calls[crewId] then closeCall(crewId, { ok = false, msg = 'Call cancelled.' }, 0) end
    return newCall(crewId, callType, nearMe and nearestTower(pedCoords(src)) or nil, false, opts) ~= nil
end)

--- PauseDispatch(src, true) : no radio calls for this player's crew until resumed (or the shift ends)
exports('PauseDispatch', function(src, on)
    local crewId = Core:GetPlayerCrew(src)
    if not crewId then return false end
    Paused[crewId] = on == true or nil
    if not on then Next[crewId] = now() + 5 end
    return true
end)

--- NextCallOpts(src, opts) : options for the crew's next call, also one spotted from a tower
--- (e.g. { needsCpr = false, watchTarget = 'drowning' })
exports('NextCallOpts', function(src, opts)
    local crewId = Core:GetPlayerCrew(src)
    if not crewId then return false end
    NextOpts[crewId] = opts
    return true
end)

--- CancelCall(src) : drop the crew's current call without pay
exports('CancelCall', function(src)
    local crewId = Core:GetPlayerCrew(src)
    if crewId and Calls[crewId] then closeCall(crewId, { ok = false, msg = 'Call cancelled.' }, 0) end
    return true
end)
