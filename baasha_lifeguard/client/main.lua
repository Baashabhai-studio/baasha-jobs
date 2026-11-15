-- ── Baasha Lifeguard — Client ────────────────────────────────────────────

local JOB = 'lifeguard'
local Core = exports.baasha_jobcore

local onShift = false
local myLevel = 1
local busy = false            -- in a minigame / action
local auto = false            -- test / showcase tools play the minigames themselves
local hudText = nil
local hudLocked = false      -- an action shows its own HUD line (first aid steps)
local tabletHint
local blips = {}
local call = nil              -- the crew's active call (from the server) + local bits (blips, ped)
local carry = nil             -- the swimmer I'm bringing in: { ped, mode = 'tow' | 'carry' | 'ski', since }
local cpr = nil               -- running CPR scene: { ped, id, origin, heading }
local watching = false
local jetski = nil            -- netId of the jet ski I rented
local skiBlip = nil
local spawning = false
local lastResult = nil
local history = {}

local function me() return GetPlayerServerId(PlayerId()) end
local function notify(msg, type) lib.notify({ title = Config.Job.label, description = msg, type = type or 'inform' }) end
local function log(what)
    history[#history + 1] = what
    if #history > 16 then table.remove(history, 1) end
    if Config.Debug then print('[baasha_lifeguard] ' .. what) end
end

local hudAt = 0

local function hudShape(text)
    return (text:gsub('%d+', '#'))
end

local function setHud(text)
    if text == hudText then return end
    -- only the numbers changed (distance, timer): refresh once a second, or the box flickers
    local now = GetGameTimer()
    if text and hudText and now < hudAt and hudShape(text) == hudShape(hudText) then return end
    hudAt = now + 1000
    hudText = text
    if text then lib.showTextUI(text, { position = 'left-center', icon = 'life-ring' }) else lib.hideTextUI() end
end

local function drawText3D(c, text, scale, color)
    SetTextScale(0.0, scale)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(color[1], color[2], color[3], 255)
    SetTextCentre(true)
    SetTextOutline()
    SetDrawOrigin(c.x, c.y, c.z, 0)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

-- ── Small helpers ────────────────────────────────────────────────────────
local function groundAt(x, y, z)
    local ok, gz = GetGroundZFor_3dCoord(x, y, z + 15.0, false)
    return ok and gz or z
end

local function fromNet(net)
    if not net or not NetworkDoesNetworkIdExist(net) then return nil end
    local ent = NetworkGetEntityFromNetworkId(net)
    return ent ~= 0 and DoesEntityExist(ent) and ent or nil
end

--- Network control of a ped (crew mates hand the victim to each other)
local function control(ent)
    if not ent or not DoesEntityExist(ent) then return false end
    if NetworkHasControlOfEntity(ent) then return true end
    local t = GetGameTimer() + 1500
    while not NetworkHasControlOfEntity(ent) and GetGameTimer() < t do
        NetworkRequestControlOfEntity(ent)
        Wait(0)
    end
    return NetworkHasControlOfEntity(ent)
end

local function play(ped, dict, anim, flag, duration)
    lib.requestAnimDict(dict, 3000)
    TaskPlayAnim(ped, dict, anim, 8.0, -8.0, duration or -1, flag or 1, 0.0, false, false, false)
end

local POSE = {
    drown = { 'random@mugging3', 'handsup_standing_base', 49 },  -- upper body only, over the real swim
    lying = { 'mini@cpr@char_b@cpr_def', 'cpr_pumpchest_idle', 1 }, -- on their back, ready for CPR
    sit_m = { 'amb@world_human_picnic@male@base', 'base', 1 },
    sit_f = { 'amb@world_human_picnic@female@base', 'base', 1 },
    tow   = { 'amb@world_human_sunbathe@male@back@base', 'base', 1 },
    float = { 'dead', 'dead_a', 1 },
    carry = { 'nm', 'firemans_carry', 33 },
}
local CARRIER = { 'missfinale_c2mcs_1', 'fin_c2_mcs_1_camman', 49 }
local MEDIC   = { 'amb@medic@standing@tendtodead@idle_a', 'idle_a', 1 }
local WHISTLE = { 'rcmnigel1c', 'hailing_whistle_waive_a', 49 }
local CPR_A, CPR_B = 'mini@cpr@char_a@cpr_str', 'mini@cpr@char_b@cpr_str'
local CPR_B_IDLE = { 'mini@cpr@char_b@cpr_def', 'cpr_pumpchest_idle' }

local function pose(ped, name)
    local p = POSE[name]
    play(ped, p[1], p[2], p[3])
end

local function nearestTower(here)
    local best, bestD = nil, 1e9
    for i, t in ipairs(Config.Towers) do
        local d = #(here.xy - vector2(t.coords.x, t.coords.y))
        if d < bestD then best, bestD = i, d end
    end
    return best, bestD
end

local function clock(s)
    s = math.max(0, math.floor(s))
    return ('%d:%02d'):format(s // 60, s % 60)
end

--- Height for a drowning swimmer: sunk so only the head and raised arms are above the water
--- The sea surface right at this spot, waves included (read every frame so people ride the waves
--- instead of hanging in the air when a wave drops). Falls back to the spot's height.
local function surface(c)
    local ok, h = GetWaterHeight(c.coords.x, c.coords.y, c.coords.z + 5.0)
    return ok and h or c.coords.z
end

local function floatZ(c) return surface(c) + Config.FloatHeight end

-- ── The call's ped (victim or shark): the first crew member close by spawns it ──
local function spawnCallPed(c)
    spawning = true
    local ok = lib.callback.await('baasha_lifeguard:claimPed', false, c.id)
    local model = joaat(c.model)
    if not IsModelInCdimage(model) and c.type ~= 'shark' then model = joaat('a_m_y_beach_01') end -- typo / missing model in the config
    if not ok or call ~= c or not IsModelInCdimage(model) then spawning = false return end
    lib.requestModel(model, 5000)
    local s = c.coords
    local z = c.type == 'drowning' and surface(c) or c.type == 'floating' and floatZ(c) or c.water and s.z or groundAt(s.x, s.y, s.z)
    local ped = CreatePed(c.type == 'shark' and 28 or 4, model, s.x, s.y, z, s.w or 0.0, true, true)
    SetModelAsNoLongerNeeded(model)
    local t = GetGameTimer() + 3000
    while not DoesEntityExist(ped) and GetGameTimer() < t do Wait(0) end
    if not DoesEntityExist(ped) then spawning = false return end

    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetEntityInvincible(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    SetPedDiesWhenInjured(ped, false)
    SetPedKeepTask(ped, true)
    if c.type ~= 'shark' then
        -- plain beachwear: no backpacks or bags (in the sea!), no hats or glasses
        ClearAllPedProps(ped)
        for _, comp in ipairs(Config.StripComponents) do
            if GetNumberOfPedDrawableVariations(ped, comp) > 0 then SetPedComponentVariation(ped, comp, 0, 0, 0) end
        end
    end
    if c.type == 'shark' then
        TaskWanderInArea(ped, s.x, s.y, s.z, 18.0, 0.0, 0.0)
    elseif c.type == 'drowning' then
        -- a real swimmer: the game treads water and rides the waves, the arms flail on top of that
        SetPedDiesInWater(ped, false)
        SetPedMaxTimeUnderwater(ped, 600.0)
        TaskStandStill(ped, -1)
        pose(ped, 'drown')
    else
        FreezeEntityPosition(ped, true)
        if c.type == 'floating' then pose(ped, 'float')
        elseif c.type == 'unconscious' then pose(ped, 'lying')
        else pose(ped, IsPedMale(ped) and 'sit_m' or 'sit_f') end
    end
    local net = NetworkGetNetworkIdFromEntity(ped)
    SetNetworkIdCanMigrate(net, true)
    lib.callback.await('baasha_lifeguard:pedSpawned', false, c.id, net)
    if call == c then c.ped, c.pedEnt = net, ped end
    Ocean.Release() -- the local swimmer you spotted from the tower (if any) makes way for the real one
    spawning = false
    log('ped ' .. c.type)
end

-- ── Calls ────────────────────────────────────────────────────────────────
local function clearCall()
    if call then
        if call.blip then RemoveBlip(call.blip) end
        if call.area then RemoveBlip(call.area) end
        Ocean.Release() -- call over (or cancelled) before the real swimmer spawned
    end
    call = nil
    SendNUIMessage({ action = 'callCard' })
end

RegisterNetEvent('baasha_lifeguard:client:call', function(c)
    if not onShift then return end
    clearCall()
    c.endsAt = GetGameTimer() + c.expiresIn * 1000
    -- shark: go to the tower and sound the alarm. Everything else: go to the person.
    local target = c.type == 'shark' and Config.Towers[c.tower].coords or c.coords
    c.blip = AddBlipForCoord(target.x, target.y, target.z)
    SetBlipSprite(c.blip, 1)
    SetBlipColour(c.blip, 1)
    SetBlipScale(c.blip, 1.0)
    SetBlipFlashes(c.blip, true)
    SetBlipRoute(c.blip, true)
    SetBlipRouteColour(c.blip, 1)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(L('blip_call'))
    EndTextCommandSetBlipName(c.blip)
    c.area = AddBlipForRadius(c.coords.x, c.coords.y, c.coords.z, 30.0)
    SetBlipColour(c.area, 1)
    SetBlipAlpha(c.area, 110)
    call = c
    log(('call %s #%s'):format(c.type, c.id))
    notify(c.spotted and L('call_spotted', c.label, c.towerLabel) or L('call_in', c.label, c.towerLabel), 'warning')
    PlaySoundFrontend(-1, 'CHECKPOINT_PERFECT', 'HUD_MINI_GAME_SOUNDSET', true)
    SendNUIMessage({ action = 'callCard', data = { type = c.type, label = c.label, icon = c.icon, where = c.towerLabel, left = c.expiresIn, spotted = c.spotted } })
end)

RegisterNetEvent('baasha_lifeguard:client:pedReady', function(id, net)
    if call and call.id == id then call.ped = net end
end)

RegisterNetEvent('baasha_lifeguard:client:stage', function(id, stage, rescuer)
    if not call or call.id ~= id then return end
    call.stage, call.rescuer = stage, rescuer
    SendNUIMessage({ action = 'callStage', stage = stage })
end)

-- ── Carrying the swimmer: towed while swimming, on the shoulder on land, on the back seat of the jet ski ──
local function setCarry(mode, veh)
    local ped = carry and carry.ped
    if not ped or not control(ped) then return end
    local prev = carry.mode
    if prev == 'carry' then StopAnimTask(cache.ped, CARRIER[1], CARRIER[2], 1.0) end
    DetachEntity(ped, true, false)
    FreezeEntityPosition(ped, false)
    ClearPedTasksImmediately(ped) -- also takes them off the jet ski
    if mode == 'ski' then
        SetPedIntoVehicle(ped, veh, 0)
    elseif mode == 'tow' then
        -- not attached: towFollow() keeps them on the water surface next to the rescuer every frame,
        -- so they float instead of being dragged under when the rescuer dips or dives
        FreezeEntityPosition(ped, true)
        pose(ped, 'tow')
    else
        local C = Config.Carry
        AttachEntityToEntity(ped, cache.ped, 0, C.pos.x, C.pos.y, C.pos.z, C.rot.x, C.rot.y, C.rot.z, false, false, false, false, 2, false)
        pose(ped, 'carry')
        play(cache.ped, CARRIER[1], CARRIER[2], CARRIER[3])
    end
    carry.mode, carry.since = mode, GetGameTimer()
    log('carry ' .. mode)
end

--- Every frame while towing: glide to the spot beside the rescuer, riding the waves on the surface
--- (or the sea floor in the shallows, so they never sink into the sand)
local function towFollow()
    local ped = carry and carry.mode == 'tow' and carry.ped
    if not ped or not DoesEntityExist(ped) or not NetworkHasControlOfEntity(ped) then return end
    local T = Config.Tow
    local at = GetOffsetFromEntityInWorldCoords(cache.ped, T.pos.x, T.pos.y, 0.0)
    local okW, water = GetWaterHeight(at.x, at.y, at.z + 5.0)
    local okG, ground = GetGroundZFor_3dCoord(at.x, at.y, at.z + 5.0, false)
    local base = okW and water or at.z
    if okG and ground > base then base = ground end
    local z = base + T.pos.z + math.sin(GetGameTimer() / 700) * 0.04
    local cur = GetEntityCoords(ped)
    local k = 1.0 - math.exp(-GetFrameTime() * 10.0)
    if #(cur.xy - at.xy) > 4.0 then k = 1.0 end -- fell far behind (teleport, lag): snap
    SetEntityCoordsNoOffset(ped, cur.x + (at.x - cur.x) * k, cur.y + (at.y - cur.y) * k, cur.z + (z - cur.z) * k, false, false, false)
    SetEntityHeading(ped, GetEntityHeading(cache.ped) + T.rot.z)
    SetEntityNoCollisionEntity(ped, cache.ped, true)
end

--- Jet ski in the shallows: the (awake) swimmer climbs off by themselves, wades onto the sand and thanks you
local function skiDropOff()
    if busy or not call or not carry or carry.mode ~= 'ski' then return end
    busy = true
    local c, ped = call, carry.ped
    local ok, kind = lib.callback.await('baasha_lifeguard:deliver', false, c.id, 'ski')
    if not ok then
        busy = false
        if carry then carry.shallowSince = GetGameTimer() + 4000 end -- don't ask again right away
        if kind then notify(kind, 'error') end
        return
    end
    carry = nil -- they're on their own feet now
    lastResult = { rescued = true, ski = true }
    busy = false
    log('ski drop off')
    if not ped or not control(ped) then return end
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 then TaskLeaveVehicle(ped, veh, 0) end
    local t = GetGameTimer() + 4000
    while GetVehiclePedIsIn(ped, false) ~= 0 and GetGameTimer() < t do Wait(100) end
    -- wade towards the beach (towards the nearest tower, which stands on the sand)
    local p = GetEntityCoords(ped)
    local i = nearestTower(p)
    local tc = Config.Towers[i].coords
    local dir = vector3(tc.x - p.x, tc.y - p.y, 0.0)
    dir = #dir > 0.1 and dir / #dir or vector3(0.0, 1.0, 0.0)
    local to = p + dir * 9.0
    TaskGoStraightToCoord(ped, to.x, to.y, groundAt(to.x, to.y, p.z), 1.0, 9000, 0.0, 0.5)
    Wait(4500)
    if not DoesEntityExist(ped) then return end
    TaskTurnPedToFaceEntity(ped, cache.ped, 1500)
    Wait(1200)
    PlayPedAmbientSpeechNative(ped, 'GENERIC_THANKS', 'SPEECH_PARAMS_FORCE')
    play(ped, 'friends@frj@ig_1', 'wave_a', 48)
    Wait(2800)
    if DoesEntityExist(ped) and control(ped) then TaskWanderStandard(ped, 10.0, 10) end
end

local function updateCarry()
    local ped = carry and carry.ped
    if not ped or not DoesEntityExist(ped) then carry = nil return end
    local veh = GetVehiclePedIsIn(cache.ped, false)
    local swimming = IsPedSwimming(cache.ped) or IsPedSwimmingUnderWater(cache.ped)
    if carry.mode == 'ski' then
        if veh == 0 then setCarry(swimming and 'tow' or 'carry') return end
        -- stopped in the shallows for a second: let them off
        local p = GetEntityCoords(veh)
        local okW, w = GetWaterHeight(p.x, p.y, p.z + 2.0)
        local okG, g = GetGroundZFor_3dCoord(p.x, p.y, p.z + 2.0, false)
        local shallow = okG and (not okW or w - g < Config.Shore.skiDepth)
        if shallow and GetEntitySpeed(veh) < 2.5 and not busy then
            carry.shallowSince = carry.shallowSince or GetGameTimer()
            if GetGameTimer() - carry.shallowSince > 1000 then CreateThread(skiDropOff) end
        elseif not shallow then
            carry.shallowSince = nil
        end
    elseif veh ~= 0 then
        if IsVehicleSeatFree(veh, 0) and not carry.unconscious then setCarry('ski', veh) end
    elseif carry.mode == 'tow' and not swimming and GetGameTimer() - carry.since > 1200 then
        setCarry('carry')
    elseif carry.mode == 'carry' and swimming then
        setCarry('tow')
    elseif carry.mode == 'carry' and not IsEntityPlayingAnim(cache.ped, CARRIER[1], CARRIER[2], 3) then
        play(cache.ped, CARRIER[1], CARRIER[2], CARRIER[3])
    end
end

local function dropCarry()
    if not carry then return end
    local ped = carry.ped
    if carry.mode == 'carry' then StopAnimTask(cache.ped, CARRIER[1], CARRIER[2], 1.0) end
    if ped and DoesEntityExist(ped) and control(ped) then
        DetachEntity(ped, true, false)
        if carry.mode == 'tow' then FreezeEntityPosition(ped, false) end
    end
    carry = nil
end

--- A rescued person gets up, says thanks and walks off (the server removes them later)
local function thanks(ped)
    if not ped or not control(ped) then return end
    FreezeEntityPosition(ped, false)
    ClearPedTasks(ped)
    PlayPedAmbientSpeechNative(ped, 'GENERIC_THANKS', 'SPEECH_PARAMS_FORCE')
    SetTimeout(2500, function()
        if DoesEntityExist(ped) and control(ped) then TaskWanderStandard(ped, 10.0, 10) end
    end)
end

-- ── Drowning swimmer ─────────────────────────────────────────────────────
local function grab()
    if busy or not call then return false, 'busy' end
    busy = true
    local c = call
    if c.type == 'floating' and GetVehiclePedIsIn(cache.ped, false) ~= 0 then
        busy = false
        notify(L('need_swim'), 'error')
        return false, 'on a vehicle'
    end
    local ok, msg = lib.callback.await('baasha_lifeguard:grab', false, c.id)
    if not ok then
        busy = false
        if msg then notify(msg, 'error') end
        return false, msg
    end
    -- unconscious people are towed and carried, never put on a seat
    carry = { ped = c.pedEnt, mode = nil, unconscious = c.type == 'floating' }
    local veh = GetVehiclePedIsIn(cache.ped, false)
    setCarry(veh ~= 0 and 'ski' or ((IsPedSwimming(cache.ped) or IsPedSwimmingUnderWater(cache.ped)) and 'tow' or 'carry'), veh)
    -- new route: the nearest sand
    local here, best, bestD = GetEntityCoords(cache.ped), nil, 1e9
    for _, b in ipairs(Config.BeachSpots) do
        local d = #(here.xy - vector2(b.x, b.y))
        if d < bestD then best, bestD = b, d end
    end
    if c.blip and best then SetBlipCoords(c.blip, best.x, best.y, best.z) SetBlipRoute(c.blip, true) end
    busy = false
    return true
end

-- ── CPR (unconscious person, or a swimmer who stopped breathing) ─────────
-- ── Treatment kit: bag, defibrillator, first aid kit laid out around the patient ──
local kit = {}

local function clearKit(fade)
    local objs = kit
    kit = {}
    local function delete()
        for _, o in ipairs(objs) do if DoesEntityExist(o) then DeleteEntity(o) end end
    end
    if not fade then return delete() end
    CreateThread(function()
        for a = 255, 0, -51 do
            for _, o in ipairs(objs) do if DoesEntityExist(o) then SetEntityAlpha(o, a, false) end end
            Wait(40)
        end
        delete()
    end)
end

local function kitModel(list)
    for _, m in ipairs(list) do
        local h = joaat(m)
        if IsModelInCdimage(h) and pcall(lib.requestModel, h, 2000) then return h end
    end
    if Config.Debug then print('[baasha_lifeguard] no kit model found: ' .. table.concat(list, ', ')) end
end

--- Lays out Config.TreatProps[kind] around a patient. origin: a point on the patient, axis: along their body,
--- side: towards the rescuer, z: the rescuer's height (ground is looked up below it). Props fade in one by one.
local function spawnKit(kind, origin, axis, side, z)
    clearKit()
    local set = Config.TreatProps.enabled and Config.TreatProps[kind]
    if not set then return end
    local heading = GetHeadingFromVector_2d(axis.x, axis.y)
    for i, p in ipairs(set) do
        local model = kitModel(p.models)
        if model then
            local pos = origin + side * p.side + axis * p.along
            local found, gz = GetGroundZFor_3dCoord(pos.x, pos.y, z + 0.6, false)
            local obj = CreateObject(model, pos.x, pos.y, found and gz or z - 0.95, true, true, false)
            SetModelAsNoLongerNeeded(model)
            SetEntityHeading(obj, heading + (p.turn or 0.0))
            PlaceObjectOnGroundProperly(obj)
            FreezeEntityPosition(obj, true)
            SetEntityCollision(obj, false, false)
            SetEntityAlpha(obj, 0, false)
            kit[#kit + 1] = obj
            CreateThread(function()
                Wait((i - 1) * 220)
                for a = 0, 255, 51 do
                    if not DoesEntityExist(obj) then return end
                    SetEntityAlpha(obj, a, false)
                    Wait(35)
                end
                ResetEntityAlpha(obj)
            end)
        end
    end
end

--- Kneel beside the patient: at the chest for compressions, up by the head for rescue breaths
local function kneel(phase)
    if not cpr or not cpr.chest then return end
    local P = Config.CprPosition
    local breath = phase == 'breath'
    local spot = cpr.chest + cpr.side * (P.side + (breath and P.breathSide or 0.0)) + cpr.axis * (P.along + (breath and P.breathAlong or 0.0))
    SetEntityCoordsNoOffset(cache.ped, spot.x, spot.y, cpr.z + P.height, false, false, false)
    SetEntityHeading(cache.ped, GetHeadingFromVector_2d(-cpr.side.x, -cpr.side.y) + P.turn)
end

local function cprAnim(phase)
    if not cpr then return end
    local victim = cpr.ped and DoesEntityExist(cpr.ped) and cpr.ped or nil
    local anim = ({ compress = 'cpr_pumpchest', breath = 'cpr_kol', success = 'cpr_success', fail = 'cpr_fail' })[phase]
    if not anim then return end
    local flag = (phase == 'compress' or phase == 'breath') and 1 or 2
    cpr.phase = phase == 'breath' and 'breath' or 'compress'
    kneel(cpr.phase) -- the ending (pulse back / no pulse) plays from the chest spot
    -- plain anims on the spot: we place both people ourselves
    play(cache.ped, CPR_A, anim, flag)
    if victim then play(victim, CPR_B, anim, flag) end
end

--- Which side of the patient the CPR animations were made for: 1 = `side`, -1 = the other side, nil = unknown.
--- Reads where each animation starts in the original scene and turns that around this patient's heading.
local function authoredSide(victim, chest, side)
    lib.requestAnimDict(CPR_A, 3000)
    lib.requestAnimDict(CPR_B, 3000)
    local pa = GetAnimInitialOffsetPosition(CPR_A, 'cpr_pumpchest', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2)
    local pb = GetAnimInitialOffsetPosition(CPR_B, 'cpr_pumpchest', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2)
    local rb = GetAnimInitialOffsetRotation(CPR_B, 'cpr_pumpchest', 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2)
    if not pa or not pb or #(pa - pb) < 0.1 then return nil end
    -- the rescuer's start, seen from the patient (patient's own frame)
    local d = pa - pb
    local r = math.rad(-(rb and rb.z or 0.0))
    local lx, ly = d.x * math.cos(r) - d.y * math.sin(r), d.x * math.sin(r) + d.y * math.cos(r)
    -- the same spot next to this patient
    local h = math.rad(GetEntityHeading(victim))
    local v = GetEntityCoords(victim)
    local wx, wy = v.x + lx * math.cos(h) - ly * math.sin(h), v.y + lx * math.sin(h) + ly * math.cos(h)
    local dot = (wx - chest.x) * side.x + (wy - chest.y) * side.y
    if Config.Debug then print(('[baasha_lifeguard] cpr side from anim: %.2f'):format(dot)) end
    if math.abs(dot) < 0.05 then return nil end
    return dot > 0 and 1 or -1
end

--- Patient on their back; works out where their chest is and which way they lie (any direction)
local function placeForCpr(victim)
    lib.requestAnimDict(CPR_B_IDLE[1], 3000)
    if not IsEntityPlayingAnim(victim, CPR_B_IDLE[1], CPR_B_IDLE[2], 3) then
        -- a carried swimmer: drop that pose for the CPR one (people found on the sand already lie like this,
        -- so they don't move at all when CPR starts)
        ClearPedTasksImmediately(victim)
        TaskPlayAnim(victim, CPR_B_IDLE[1], CPR_B_IDLE[2], 8.0, -8.0, -1, 1, 0.0, false, false, false)
        Wait(600) -- let the pose settle before reading the bones
    end
    local chest = GetPedBoneCoords(victim, 24818, 0.0, 0.0, 0.0)   -- SKEL_Spine3
    local head = GetPedBoneCoords(victim, 31086, 0.0, 0.0, 0.0)    -- SKEL_Head
    local pelvis = GetPedBoneCoords(victim, 11816, 0.0, 0.0, 0.0)  -- SKEL_Pelvis
    local axis = vector3(head.x - pelvis.x, head.y - pelvis.y, 0.0)
    axis = #axis > 0.05 and axis / #axis or vector3(0.0, 1.0, 0.0)
    local side = vector3(-axis.y, axis.x, 0.0)
    local me = GetEntityCoords(cache.ped)
    -- The CPR animations were made with the rescuer on ONE side of the patient. On the other side the
    -- ending ("wake up", helping them up) reaches towards the legs. Kneel on the side they were made for;
    -- only if that can't be read, the side you're standing on.
    local made = Config.CprPosition.kneel ~= 'near' and authoredSide(victim, chest, side) or nil
    if made and Config.CprPosition.kneel == 'other' then made = -made end
    if made then
        side = side * made
    elseif (me.x - chest.x) * side.x + (me.y - chest.y) * side.y < 0 then
        side = -side
    end
    cpr.chest, cpr.axis, cpr.side, cpr.z = vector3(chest.x, chest.y, chest.z), axis, side, me.z
    FreezeEntityPosition(cache.ped, true)
    kneel('compress')
end

local function startCprScene(ped, id, label, params)
    if not ped or not DoesEntityExist(ped) then busy = false return false end
    control(ped)
    FreezeEntityPosition(ped, true)
    SetEntityNoCollisionEntity(ped, cache.ped, false) -- don't push each other while kneeling over them
    cpr = { ped = ped, id = id }
    placeForCpr(ped)
    spawnKit('cpr', cpr.chest, cpr.axis, cpr.side, cpr.z)
    cprAnim('compress')
    params.title, params.auto = label, auto
    if not auto then SetNuiFocus(true, false) end
    SendNUIMessage({ action = 'cpr', data = params })
    log('cpr start')
    return true
end

local function beginCpr()
    if busy or not call then return false, 'busy' end
    busy = true
    local c = call
    local ok, params = lib.callback.await('baasha_lifeguard:startCpr', false, c.id)
    if not ok then
        busy = false
        if params then notify(params, 'error') end
        return false, params
    end
    return startCprScene(c.pedEnt, c.id, c.label, params)
end

RegisterNUICallback('cprPhase', function(body, cb) cb(1) cprAnim(body.phase) end)
RegisterNUICallback('cprPress', function(_, cb) cb(1) end)
RegisterNUICallback('cprBreath', function(_, cb) cb(1) end)
RegisterNUICallback('cprDone', function(body, cb)
    cb(1)
    SetNuiFocus(false, false)
    local s = cpr
    if not s then return end
    local _, saved = lib.callback.await('baasha_lifeguard:cprDone', false, s.id, body)
    lastResult = { cpr = saved == true, accuracy = body.accuracy }
    log(saved and 'cpr saved' or 'cpr lost')
    cprAnim(saved and 'success' or 'fail')
    SetTimeout(saved and 5500 or 4500, function()
        FreezeEntityPosition(cache.ped, false)
        ClearPedTasks(cache.ped)
        if saved then thanks(s.ped) end
        clearKit(true)
        cpr = nil
        busy = false
    end)
end)

local function deliver()
    if busy or not call or not carry then return false, 'busy' end
    busy = true
    local c = call
    -- keep the ped now: when no CPR is needed the server closes the call straight away, and the
    -- "call ended" event (which drops the carry) can arrive before this callback returns
    local ped = carry.ped
    local ok, kind, params = lib.callback.await('baasha_lifeguard:deliver', false, c.id)
    if not ok then
        busy = false
        if kind then notify(kind, 'error') end
        return false, kind
    end
    dropCarry()
    if ped and control(ped) then
        -- lay them on the sand in front of you
        local p = GetOffsetFromEntityInWorldCoords(cache.ped, 0.0, 1.1, 0.0)
        ClearPedTasksImmediately(ped) -- drop the shoulder-carry pose completely, or it keeps playing
        -- the ground at your feet' height (looking down from above could land them on a roof or ramp)
        local found, gz = GetGroundZFor_3dCoord(p.x, p.y, GetEntityCoords(cache.ped).z + 0.5, false)
        SetEntityCoords(ped, p.x, p.y, found and gz or p.z - 1.0, false, false, false, false)
        SetEntityHeading(ped, GetEntityHeading(cache.ped) + 90.0)
    end
    if kind == 'cpr' then
        pose(ped, 'lying')
        Wait(700)
        return startCprScene(ped, c.id, c.label, params)
    end
    lastResult = { rescued = true }
    thanks(ped)
    busy = false
    return true
end

-- ── Jellyfish sting: first aid ───────────────────────────────────────────
local function treat()
    if busy or not call then return false, 'busy' end
    busy = true
    local c = call
    local ok, fa = lib.callback.await('baasha_lifeguard:treatStart', false, c.id)
    if not ok then
        busy = false
        if fa then notify(fa, 'error') end
        return false, fa
    end
    local ped = c.pedEnt
    if ped then
        -- kneel beside the stung leg, facing it
        local knee = GetPedBoneCoords(ped, 36864, 0.0, 0.0, 0.0)   -- SKEL_R_Calf
        local pelvis = GetPedBoneCoords(ped, 11816, 0.0, 0.0, 0.0) -- SKEL_Pelvis
        local leg = vector3(knee.x - pelvis.x, knee.y - pelvis.y, 0.0)
        leg = #leg > 0.05 and leg / #leg or vector3(0.0, 1.0, 0.0)
        local side = vector3(-leg.y, leg.x, 0.0)
        local me = GetEntityCoords(cache.ped)
        if (me.x - knee.x) * side.x + (me.y - knee.y) * side.y < 0 then side = -side end
        local F = Config.FirstAidPosition
        local spot = vector3(knee.x, knee.y, 0.0) + side * F.side + leg * F.along
        SetEntityCoordsNoOffset(cache.ped, spot.x, spot.y, me.z, false, false, false)
        SetEntityHeading(cache.ped, GetHeadingFromVector_2d(knee.x - spot.x, knee.y - spot.y))
        spawnKit('firstaid', vector3(knee.x, knee.y, knee.z), leg, side, me.z)
        Wait(300)
    end
    play(cache.ped, MEDIC[1], MEDIC[2], MEDIC[3])
    local good = true
    hudLocked = true
    for _, step in ipairs(fa.steps) do
        setHud(L('fa_step', step.label))
        if auto then Wait(1500)
        elseif not lib.skillCheck(step.check, fa.keys) then good = false break end
        Wait(350)
    end
    hudLocked = false
    setHud(nil)
    if good then
        good = lib.progressBar({ duration = fa.packTime, label = L('fa_pack'), canCancel = false, disable = { move = true, combat = true } })
    end
    ClearPedTasks(cache.ped)
    local done, msg = lib.callback.await('baasha_lifeguard:treatDone', false, c.id, good == true)
    lastResult = { treated = done == true }
    clearKit(true)
    if done then thanks(ped) elseif msg then notify(msg, 'error') end
    busy = false
    return done == true
end

-- ── Shark: sound the alarm from the tower ────────────────────────────────
local function alarm()
    if busy or not call then return false, 'busy' end
    busy = true
    local c = call
    local ok, secs = lib.callback.await('baasha_lifeguard:alarm', false, c.id)
    if not ok then
        busy = false
        if secs then notify(secs, 'error') end
        return false, secs
    end
    -- face the water where the shark is
    local here = GetEntityCoords(cache.ped)
    SetEntityHeading(cache.ped, GetHeadingFromVector_2d(c.coords.x - here.x, c.coords.y - here.y))
    play(cache.ped, WHISTLE[1], WHISTLE[2], WHISTLE[3])
    local blowing = true
    CreateThread(function()
        while blowing do
            SendNUIMessage({ action = 'whistle' })
            Wait(2600)
        end
    end)
    lib.progressBar({ duration = secs * 1000, label = L('clearing'), canCancel = false, disable = { move = true, combat = true } })
    blowing = false
    StopAnimTask(cache.ped, WHISTLE[1], WHISTLE[2], 1.0)
    local done = lib.callback.await('baasha_lifeguard:alarmDone', false, c.id)
    lastResult = { cleared = done == true }
    busy = false
    return done == true
end

-- ── Tower watch: binoculars ──────────────────────────────────────────────
local finishWatch

local function watch(i)
    if busy or call then return false, 'busy' end
    busy = true
    local ok, params = lib.callback.await('baasha_lifeguard:watchStart', false, i)
    if not ok then
        busy = false
        if params then notify(params, 'error') end
        return false, params
    end
    watching = true
    SetEntityHeading(cache.ped, Config.Towers[i].coords.w)
    TaskStartScenarioInPlace(cache.ped, 'WORLD_HUMAN_BINOCULARS', 0, true)
    log('watch ' .. params.target)
    if Config.Watch.mode == 'scope' then
        Wait(1800)
        params.auto = auto
        if not auto then SetNuiFocus(true, true) end
        SendNUIMessage({ action = 'scope', data = params })
        return true
    end
    -- real binoculars over the real sea (own thread: automation calls this through an export)
    CreateThread(function()
        Wait(1500)
        finishWatch(Ocean.Watch(i, params, auto))
    end)
    return true
end

finishWatch = function(body)
    ClearPedTasks(cache.ped)
    local ok, msg = lib.callback.await('baasha_lifeguard:watchDone', false, body)
    -- result first, then "done watching" (automation reads the result as soon as watching ends)
    lastResult = { watch = body.found == true, falseAlarms = body.falseAlarms }
    watching = false
    if not ok and msg then notify(msg) end
    if not ok then Ocean.Release() end
    busy = false
end

RegisterNUICallback('watchDone', function(body, cb)
    cb(1)
    SetNuiFocus(false, false)
    finishWatch(body)
end)

-- ── Jet ski ──────────────────────────────────────────────────────────────
--- A spot in the water in front of a tower: from the tower towards its nearest drowning spot,
--- the first water we hit, then a bit further out so the jet ski floats instead of beaching
local function towerWaterSpot(i)
    local t = Config.Towers[i]
    if t.jetski then return t.jetski end
    local c = t.coords
    local target, best = nil, 1e9
    for _, w in ipairs(Config.WaterSpots) do
        local d = #(vector2(w.x, w.y) - vector2(c.x, c.y))
        if d < best then target, best = w, d end
    end
    if not target then return nil end
    local dir = vector3(target.x - c.x, target.y - c.y, 0.0)
    dir = dir / #dir
    for d = 10.0, math.min(best, 160.0), 4.0 do
        local p = vector3(c.x, c.y, 0.0) + dir * d
        local wet, h = GetWaterHeight(p.x, p.y, 20.0)
        if wet then
            local q = p + dir * Config.JetSki.outFromShore
            return vector4(q.x, q.y, h + 0.3, GetHeadingFromVector_2d(dir.x, dir.y))
        end
    end
    return nil
end

local function rentJetski(towerIdx)
    if busy then return false end
    local spot
    if towerIdx then
        spot = towerWaterSpot(towerIdx)
        if not spot then notify(L('no_water'), 'error') return false end
    end
    busy = true
    local net, err = lib.callback.await('baasha_lifeguard:rentJetski', false, towerIdx,
        spot and { x = spot.x, y = spot.y, z = spot.z, w = spot.w } or nil)
    busy = false
    if not net then
        if err then notify(err, 'error') end
        return false, err
    end
    jetski = net
    notify(towerIdx and L('jetski_out_tower') or L('jetski_out'), 'success')
    -- a map marker on the jet ski, with a route until you're on it
    CreateThread(function()
        local veh, t = nil, GetGameTimer() + 8000
        while jetski == net and not veh and GetGameTimer() < t do
            veh = fromNet(net)
            Wait(200)
        end
        if not veh or jetski ~= net then return end
        if skiBlip then RemoveBlip(skiBlip) end
        skiBlip = AddBlipForEntity(veh)
        SetBlipSprite(skiBlip, 471)
        SetBlipColour(skiBlip, 1)
        SetBlipScale(skiBlip, 0.85)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(L('blip_jetski'))
        EndTextCommandSetBlipName(skiBlip)
        SetBlipRoute(skiBlip, true)
        while jetski == net and DoesBlipExist(skiBlip) do
            if GetVehiclePedIsIn(cache.ped, false) == veh then SetBlipRoute(skiBlip, false) end
            Wait(1000)
        end
    end)
    return true
end

local function clearSkiBlip()
    if skiBlip and DoesBlipExist(skiBlip) then RemoveBlip(skiBlip) end
    skiBlip = nil
end

local function returnJetski()
    if not jetski then notify(L('no_jetski'), 'error') return false end
    local ok = lib.callback.await('baasha_lifeguard:returnJetski', false, jetski)
    jetski = nil
    clearSkiBlip()
    if ok then notify(L('jetski_back'), 'success') end
    return ok
end

RegisterNetEvent('baasha_jobcore:client:vehicleReturned', function(netId)
    if netId == jetski then jetski = nil clearSkiBlip() end
end)

-- ── Main loop: markers, HUD and keys ─────────────────────────────────────
local function pressed() return IsControlJustPressed(0, Config.ActionKey) end

local function tick(now, here)
    local sleep = 250
    local lines = {}
    local acted = false
    local inVeh = GetVehiclePedIsIn(cache.ped, false)
    local prompted = false
    local function prompt(text, fn)
        lines[#lines + 1] = text
        sleep = 0
        prompted = true
        if not acted and not busy and pressed() then
            acted = true
            CreateThread(fn)
        end
    end

    -- towers
    local onTower
    for i, t in ipairs(Config.Towers) do
        local c = t.coords
        local d = #(here - vector3(c.x, c.y, c.z))
        if d < 45.0 then
            sleep = 0
            DrawMarker(1, c.x, c.y, c.z - 0.98, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.3, 1.3, 0.35, 239, 68, 68, 110, false, false, 2, false, nil, nil, false)
            if d < 16.0 then drawText3D(vector3(c.x, c.y, c.z + 1.4), L('sign_tower', t.label:upper()), 0.4, { 239, 68, 68 }) end
            if d < 2.2 and inVeh == 0 then onTower = i end
        end
    end

    local c = call
    if c then
        local ped = (c.pedEnt and DoesEntityExist(c.pedEnt)) and c.pedEnt or fromNet(c.ped)
        c.pedEnt = ped
        local pos = ped and GetEntityCoords(ped) or vector3(c.coords.x, c.coords.y, c.coords.z)
        local dist = #(here - pos)
        if not c.ped and not spawning and dist < Config.SpawnDistance then CreateThread(function() spawnCallPed(c) end) end
        local left = (c.endsAt - now) / 1000

        if c.stage == 'open' then
            local where = c.type == 'shark' and #(here - Config.Towers[c.tower].coords.xyz) or dist
            lines[1] = L('hud_call', c.label, c.towerLabel, math.floor(where)) .. ' · ' .. clock(left)
        end
        -- marker over the person (not while they're on your shoulder)
        if ped and dist < 70.0 and not carry and c.type ~= 'shark' then
            sleep = 0
            DrawMarker(2, pos.x, pos.y, pos.z + 1.25, 0.0, 0.0, 0.0, 180.0, 0.0, 0.0, 0.35, 0.35, 0.35, 239, 68, 68, 210, true, true, 2, false, nil, nil, false)
        end

        if c.type == 'drowning' and c.stage == 'open' then
            if ped and dist < 120.0 and NetworkHasControlOfEntity(ped) then
                sleep = 0
                if now > (c.flailAt or 0) then
                    c.flailAt = now + 1500
                    if not IsEntityPlayingAnim(ped, POSE.drown[1], POSE.drown[2], 3) then pose(ped, 'drown') end
                    -- drifted away with the waves: swim back to the spot (they don't get far, they're panicking)
                    if #(GetEntityCoords(ped).xy - vector2(c.coords.x, c.coords.y)) > 5.0 then
                        TaskGoStraightToCoord(ped, c.coords.x, c.coords.y, surface(c), 1.0, 6000, 0.0, 1.0)
                    end
                end
                if now > (c.splashAt or 0) then
                    c.splashAt = now + 450
                    Ocean.Splash(GetEntityCoords(ped))
                end
                if now > (c.shoutAt or 0) then
                    c.shoutAt = now + 3500
                    PlayPedAmbientSpeechNative(ped, 'GENERIC_FRIGHTENED_HIGH', 'SPEECH_PARAMS_FORCE_SHOUTED')
                end
            end
            if ped and dist < 35.0 then drawText3D(pos + vector3(0.0, 0.0, 1.7), 'HELP!', 0.5, { 239, 68, 68 }) end
            if ped and dist < (inVeh ~= 0 and 5.5 or 3.2) then prompt(L('hud_grab'), grab)
            else lines[#lines + 1] = L(jetski and 'hint_swim_have' or myLevel >= Config.JetSki.level and 'hint_swim_ski' or 'hint_swim') end
        elseif c.type == 'floating' and c.stage == 'open' then
            if ped and dist < 120.0 and NetworkHasControlOfEntity(ped) then
                sleep = 0
                -- face down, rocking gently on the waves
                SetEntityCoordsNoOffset(ped, c.coords.x, c.coords.y, floatZ(c) + math.sin(now / 700) * 0.05, false, false, false)
            end
            if ped and dist < 3.2 then
                if inVeh ~= 0 then lines[#lines + 1] = L('need_swim') else prompt(L('hud_grab_float'), grab) end
            else
                lines[#lines + 1] = L('hint_float')
            end
        elseif c.stage == 'rescuing' then
            if c.rescuer == me() and carry then
                if carry.mode == 'tow' then
                    sleep = 0
                    towFollow()
                end
                if carry.unconscious then
                    sleep = 0
                    DisableControlAction(0, 23, true) -- no jumping on a vehicle with an unconscious person
                end
                lines[#lines + 1] = L(carry.mode == 'ski' and not carry.unconscious and 'hud_bring_ski' or 'hud_bring')
                -- anywhere on the sand: out of the water, on foot, not at a tower
                local _, td = nearestTower(here)
                if carry.mode == 'carry' and inVeh == 0 and not IsEntityInWater(cache.ped) then
                    if td < Config.Shore.awayFromTower then lines[#lines + 1] = L('hint_open_sand')
                    elseif td <= Config.Shore.beach then prompt(L('hud_lay'), deliver) end
                end
            else
                lines[#lines + 1] = L('hud_rescuing')
            end
        elseif c.type == 'unconscious' and c.stage == 'open' then
            if ped and dist < 2.6 and inVeh == 0 then prompt(L('hud_cpr'), beginCpr) else lines[#lines + 1] = L('hint_person') end
        elseif c.type == 'jellyfish' and c.stage == 'open' then
            if ped and dist < 2.6 and inVeh == 0 then prompt(L('hud_treat'), treat) else lines[#lines + 1] = L('hint_person') end
        elseif c.type == 'shark' and c.stage == 'open' then
            local t = Config.Towers[c.tower]
            if #(here - t.coords.xyz) < 5.0 and inVeh == 0 then
                prompt(L('hud_alarm', t.label), alarm)
            else
                lines[#lines + 1] = L('hud_go_tower', t.label)
            end
        end
        if now > (c.tickAt or 0) then
            c.tickAt = now + 500
            SendNUIMessage({ action = 'callTick', left = math.floor(left), dist = math.floor(dist) })
        end
    elseif onTower then
        prompt(L('hud_watch', Config.Towers[onTower].label), function() watch(onTower) end)
    else
        lines[#lines + 1] = L('hud_idle')
    end

    -- The jet ski: at HQ, and on the sand next to any tower (never over another E prompt, never while carrying)
    if inVeh == 0 and not carry and not prompted and myLevel >= Config.JetSki.level then
        local hq = Config.Job.depot.coords
        if #(here - vector3(hq.x, hq.y, hq.z)) < 4.0 then
            if jetski then prompt(L('hud_jetski_ret'), returnJetski) else prompt(L('hud_jetski_get'), function() rentJetski() end) end
        elseif Config.JetSki.atTowers then
            local i, d = nearestTower(here)
            if i and d < 9.0 and not onTower then
                if jetski then prompt(L('hud_jetski_ret'), returnJetski)
                else prompt(L('hud_jetski_tower'), function() rentJetski(i) end) end
            end
        end
    end

    if carry and now > (carry.checkAt or 0) then
        carry.checkAt = now + 250
        updateCarry()
    end

    if not busy then
        if tabletHint then lines[#lines + 1] = tabletHint end
        setHud(#lines > 0 and table.concat(lines, '  \n') or nil)
    elseif not hudLocked then
        setHud(nil)
    end
    return sleep
end

local function mainLoop()
    CreateThread(function()
        local hintAt = 0
        while onShift do
            local now = GetGameTimer()
            if now > hintAt then tabletHint, hintAt = Core:TabletHint(), now + 5000 end
            local ok, sleep = pcall(tick, now, GetEntityCoords(cache.ped))
            if not ok then
                print(('^1[baasha_lifeguard] HUD loop error (recovered): %s^7'):format(tostring(sleep)))
                sleep = 500
            end
            Wait(sleep)
        end
        setHud(nil)
    end)
end

-- ── Signs: "LIFEGUARD JOB" over the boss, "LIFEGUARD HQ" during a shift ──
CreateThread(function()
    local d = Config.Job.depot.coords
    local at = vector3(d.x, d.y, d.z - 1.0)
    while true do
        local sleep = 1000
        local dist = #(GetEntityCoords(cache.ped) - at)
        if dist < 30.0 and not IsPauseMenuActive() then
            sleep = 0
            DrawMarker(onShift and 29 or 0, at.x, at.y, at.z + 2.4, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.4, 0.4, 0.4, 239, 68, 68, 210, true, true, 2, onShift, nil, nil, false)
            if dist < 12.0 then
                drawText3D(at + vector3(0.0, 0.0, 2.95), onShift and L('sign_hq') or L('sign_job'), 0.5, { 239, 68, 68 })
                drawText3D(at + vector3(0.0, 0.0, 2.8), onShift and L('sign_hq_sub') or L('sign_job_sub'), 0.32, { 255, 255, 255 })
            end
        end
        Wait(sleep)
    end
end)

-- ── World setup ──────────────────────────────────────────────────────────
local function setupWorld()
    for _, t in ipairs(Config.Towers) do
        local c = t.coords
        local b = AddBlipForCoord(c.x, c.y, c.z)
        SetBlipSprite(b, 280)
        SetBlipColour(b, 1)
        SetBlipScale(b, 0.6)
        SetBlipAsShortRange(b, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(('%s · %s'):format(L('blip_tower'), t.label))
        EndTextCommandSetBlipName(b)
        blips[#blips + 1] = b
    end
end

local function cleanup()
    SendNUIMessage({ action = 'closeCpr' })
    SendNUIMessage({ action = 'closeScope' })
    SetNuiFocus(false, false)
    dropCarry()
    clearCall()
    clearKit()
    Ocean.Stop()
    if watching or cpr then FreezeEntityPosition(cache.ped, false) ClearPedTasks(cache.ped) end
    watching, cpr, busy, jetski = false, nil, false, nil
    clearSkiBlip()
    for _, b in ipairs(blips) do RemoveBlip(b) end
    blips = {}
    onShift = false
    setHud(nil)
end

RegisterNetEvent('baasha_jobcore:client:paid', function(jobId, _, _, newLevel)
    if jobId == JOB and newLevel then myLevel = newLevel end
end)

RegisterNetEvent('baasha_lifeguard:client:callEnded', function(id, result)
    if not call or call.id ~= id then return end
    dropCarry()
    clearCall()
    lastResult = result
    log('call ended ' .. tostring(result and result.kind))
    if result and result.msg then notify(result.msg, result.ok and 'success' or 'inform') end
    SendNUIMessage({ action = 'callResult', data = result })
end)

RegisterNetEvent('baasha_jobcore:client:shiftStarted', function(jobId)
    if jobId ~= JOB or onShift then return end
    onShift = true
    local info = lib.callback.await('baasha_lifeguard:info', false)
    myLevel = info and info.level or 1
    log('shift start')
    setupWorld()
    mainLoop()
    Ocean.Start()
end)

RegisterNetEvent('baasha_jobcore:client:shiftEnded', function(jobId)
    if jobId == JOB and onShift then cleanup() log('shift end') end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    if onShift then lib.hideTextUI() end
    dropCarry()
    clearKit()
    Ocean.Stop()
    if watching or cpr then FreezeEntityPosition(cache.ped, false) ClearPedTasks(cache.ped) end
end)

-- /lgcprpos side along height turn breathAlong breathSide : move yourself during CPR to line up your hands with the chest.
-- Only changes how it looks on your screen; copy the printed line into Config.CprPosition.
RegisterCommand('lgcprpos', function(_, args)
    local P = Config.CprPosition
    P.side, P.along = tonumber(args[1]) or P.side, tonumber(args[2]) or P.along
    P.height, P.turn = tonumber(args[3]) or P.height, tonumber(args[4]) or P.turn
    P.breathAlong, P.breathSide = tonumber(args[5]) or P.breathAlong, tonumber(args[6]) or P.breathSide
    if cpr and cpr.chest then kneel(cpr.phase) end
    local line = ('Config.CprPosition = { side = %.2f, along = %.2f, height = %.2f, turn = %.1f, breathAlong = %.2f, breathSide = %.2f }')
        :format(P.side, P.along, P.height, P.turn, P.breathAlong, P.breathSide)
    print(line)
    notify(line)
end, false)

-- ── Automation hooks (test / showcase tools). The server still validates everything. ──
exports('GetState', function()
    local c = call
    return {
        onShift = onShift, busy = busy, watching = watching, level = myLevel, carry = carry and carry.mode or nil,
        cpr = cpr ~= nil, jetski = jetski, lastResult = lastResult, history = table.concat(history, ' > '),
        call = c and { id = c.id, type = c.type, stage = c.stage, tower = c.tower, coords = vector3(c.coords.x, c.coords.y, c.coords.z),
                       ped = c.pedEnt, rescuer = c.rescuer } or nil,
    }
end)
exports('ClearHistory', function() history = {} lastResult = nil end)
exports('SetAuto', function(on) auto = on == true end)
exports('Watch', function(i) return watch(i) end)
exports('Grab', function() return grab() end)
exports('Deliver', function() return deliver() end)
exports('StartCpr', function() return beginCpr() end)
exports('Treat', function() return treat() end)
exports('Alarm', function() return alarm() end)
exports('RentJetski', function(towerIdx) return rentJetski(towerIdx) end)
exports('ReturnJetski', function() return returnJetski() end)
exports('GetCarry', function(which)
    local t = which == 'tow' and Config.Tow or Config.Carry
    return { pos = t.pos, rot = t.rot }
end)
--- Places for test / showcase tools: HQ, towers, jet ski spawn, call spots
exports('GetPlaces', function()
    return { hq = Config.Job.depot.coords, atv = Config.Job.vehicle.spawns[1], jetski = Config.JetSki.spawn, towers = Config.Towers,
             water = Config.WaterSpots, beach = Config.BeachSpots, shore = Config.Shore }
end)
