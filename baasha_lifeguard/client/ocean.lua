-- ── Beach life + tower binoculars ────────────────────────────────────────
-- People enjoying the water off the towers (swimming, treading water, wading). They're local to each
-- player (pure ambience, no network cost). From a tower you scan them through real binoculars: one of
-- them gets into trouble and you have to spot who. The one you mark becomes the drowning call, right there.

Ocean = {}

local O = Config.Ocean
local groups = {}      -- [towerIdx] = { list of swimmers }
local running = false
local held = nil       -- the swimmer you spotted, kept drowning until the real (networked) call ped replaces them
local shark = nil      -- a local shark fin for a shark watch

local SWIM_DROWN = { 'random@mugging3', 'handsup_standing_base', 49 }
local SWIM_WAVE  = { 'friends@frj@ig_1', 'wave_a', 49 }

local function forward(h)
    local r = math.rad(h)
    return vector3(-math.sin(r), math.cos(r), 0.0)
end

local function anim(ped, a)
    lib.requestAnimDict(a[1], 3000)
    TaskPlayAnim(ped, a[1], a[2], 4.0, -4.0, -1, a[3], 0.0, false, false, false)
end

--- Splashes on the water: someone thrashing around
function Ocean.Splash(pos)
    if not HasNamedPtfxAssetLoaded('core') then RequestNamedPtfxAsset('core') return end
    local ok, w = GetWaterHeight(pos.x, pos.y, pos.z + 3.0)
    UseParticleFxAsset('core')
    StartParticleFxNonLoopedAtCoord('water_splash_ped', pos.x + math.random(-5, 5) / 10, pos.y + math.random(-5, 5) / 10,
        ok and w or pos.z, 0.0, 0.0, 0.0, 1.0 + math.random() * 0.6, false, false, false)
end

--- Water surface and sea floor at a point (floor nil when that bit of the map isn't loaded)
local function waterAt(x, y)
    local okW, w = GetWaterHeight(x, y, 5.0)
    if not okW then return nil end
    local okG, g = GetGroundZFor_3dCoord(x, y, w + 0.5, false)
    return w, okG and g or nil
end

--- A random spot in front of a tower: deep enough to swim, or shallow enough to stand.
--- 'far' swimmers are the strong ones way out (where people get into trouble).
local function findSpot(tower, kind)
    local c, f = tower.coords, forward(tower.coords.w)
    local right = vector3(f.y, -f.x, 0.0)
    local near, out = 10, math.floor(O.maxOut)
    if kind == 'far' then near, out = math.floor(O.maxOut), math.floor(O.farOut) end
    for _ = 1, 30 do
        local p = vector3(c.x, c.y, 0.0) + f * math.random(near, out) + right * math.random(-O.spread, O.spread)
        local w, g = waterAt(p.x, p.y)
        if w then
            local depth = g and (w - g) or 99.0
            if kind == 'wade' then
                if g and depth > 0.35 and depth < 1.0 then return vector3(p.x, p.y, g) end
            elseif depth >= O.minDepth then
                return vector3(p.x, p.y, w)
            end
        end
    end
end

local function newPed(kind, at)
    local name = Config.VictimModels[math.random(#Config.VictimModels)]
    local model = joaat(name)
    if not IsModelInCdimage(model) or not pcall(lib.requestModel, model, 3000) then return end
    local ped = CreatePed(4, model, at.x, at.y, at.z, math.random(0, 359) + 0.0, false, true)
    SetModelAsNoLongerNeeded(model)
    if not DoesEntityExist(ped) then return end
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetEntityInvincible(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedDiesInWater(ped, false)
    SetPedMaxTimeUnderwater(ped, 600.0)
    SetPedFleeAttributes(ped, 0, false)
    ClearAllPedProps(ped)
    for _, comp in ipairs(Config.StripComponents) do
        if GetNumberOfPedDrawableVariations(ped, comp) > 0 then SetPedComponentVariation(ped, comp, 0, 0, 0) end
    end
    return { ped = ped, kind = kind, home = at, model = name, nextAt = 0 }
end

local function deletePed(p)
    if p and p.ped and DoesEntityExist(p.ped) then DeleteEntity(p.ped) end
end

local function spawnGroup(i)
    local t, list = Config.Towers[i], {}
    groups[i] = list
    local S, F = O.perTower.swimmers, O.perTower.far
    for n = 1, S + F + O.perTower.waders do
        local kind = n > S + F and 'wade' or n > S and 'far' or (math.random() < 0.45 and 'tread' or 'swim')
        local at = findSpot(t, kind)
        local p = at and newPed(kind, at)
        if p then list[#list + 1] = p end
        Wait(0)
    end
end

local function clearGroup(i)
    for _, p in ipairs(groups[i] or {}) do if p ~= held then deletePed(p) end end
    groups[i] = nil
end

--- What each person does: wading around, swimming laps near their spot, treading water, waving to friends
local function behave(p, now)
    if p.role == 'drown' or now < p.nextAt or not DoesEntityExist(p.ped) then return end
    local ped = p.ped
    if p.role == 'wave' then
        anim(ped, SWIM_WAVE)
        p.nextAt = now + math.random(2500, 4500)
    elseif p.kind == 'wade' then
        TaskWanderInArea(ped, p.home.x, p.home.y, p.home.z, 6.0, 2.0, 6.0)
        p.nextAt = now + 60000
    elseif p.kind == 'swim' or p.kind == 'far' then
        local a, r = math.random() * math.pi * 2, math.random(4, 18)
        local tx, ty = p.home.x + math.cos(a) * r, p.home.y + math.sin(a) * r
        local ok, w = GetWaterHeight(tx, ty, 5.0)
        if ok then TaskGoStraightToCoord(ped, tx, ty, w, 1.0, 20000, 0.0, 0.5) end
        p.nextAt = now + math.random(9000, 16000)
    else
        TaskStandStill(ped, -1)
        p.nextAt = now + 60000
    end
end

local function calm(p)
    if not p or not DoesEntityExist(p.ped) then return end
    p.role, p.nextAt = nil, 0
    ClearPedTasks(p.ped)
end

function Ocean.Start()
    if running or not O.enabled then return end
    running = true
    CreateThread(function()
        local checkAt = 0
        while running do
            local now = GetGameTimer()
            if now > checkAt then
                checkAt = now + 2000
                local here = GetEntityCoords(PlayerPedId())
                -- the nearest towers get people in front of them, far ones are cleared
                local order = {}
                for i, t in ipairs(Config.Towers) do order[#order + 1] = { i = i, d = #(here.xy - t.coords.xy) } end
                table.sort(order, function(a, b) return a.d < b.d end)
                for rank, o in ipairs(order) do
                    local want = rank <= O.towers and o.d < O.range
                    if want and not groups[o.i] then spawnGroup(o.i)
                    elseif not want and groups[o.i] and o.d > O.range + 60.0 then clearGroup(o.i) end
                end
            end
            for _, list in pairs(groups) do
                for _, p in ipairs(list) do behave(p, now) end
            end
            -- the swimmer you spotted keeps struggling until help arrives
            if held and DoesEntityExist(held.ped) then
                Ocean.Splash(GetEntityCoords(held.ped))
                if not IsEntityPlayingAnim(held.ped, SWIM_DROWN[1], SWIM_DROWN[2], 3) then anim(held.ped, SWIM_DROWN) end
            end
            Wait(500)
        end
    end)
end

function Ocean.Stop()
    running = false
    for i in pairs(groups) do clearGroup(i) end
    deletePed(held)
    held = nil
    if shark then deletePed(shark) shark = nil end
end

--- The real call ped has spawned: the local swimmer it replaces goes away
function Ocean.Release()
    if held then deletePed(held) held = nil end
    if shark then deletePed(shark) shark = nil end
end

-- ── The binoculars ───────────────────────────────────────────────────────
local function text(s, x, y, scale, r, g, b)
    SetTextFont(4)
    SetTextScale(0.0, scale)
    SetTextColour(r or 255, g or 255, b or 255, 235)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(s)
    EndTextCommandDisplayText(x, y)
end

local function angleDiff(a, b) return ((a - b + 540.0) % 360.0) - 180.0 end

local function spawnShark(group, tower)
    local model = joaat(Config.Shark.model)
    if not IsModelInCdimage(model) or not pcall(lib.requestModel, model, 3000) then return end
    local base = group[math.random(#group)].home
    local at = vector3(base.x, base.y, 0.0) + forward(tower.coords.w) * 18.0
    local ok, w = GetWaterHeight(at.x, at.y, 5.0)
    local ped = CreatePed(28, model, at.x, at.y, (ok and w or 0.0) - 0.4, tower.coords.w, false, true)
    SetModelAsNoLongerNeeded(model)
    if not DoesEntityExist(ped) then return end
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetEntityInvincible(ped, true)
    return { ped = ped, kind = 'shark', home = vector3(at.x, at.y, (ok and w or 0.0) - 0.4), model = Config.Shark.model, nextAt = 0 }
end

--- Runs the binocular view (blocks the calling thread). Returns { found, falseAlarms, spot, model }.
function Ocean.Watch(towerIdx, params, isAuto)
    local W = Config.Watch
    local tower = Config.Towers[towerIdx]
    if not groups[towerIdx] then spawnGroup(towerIdx) end
    local group = groups[towerIdx]
    local swimmers = {}
    for _, p in ipairs(group) do
        if p.kind ~= 'wade' and DoesEntityExist(p.ped) then swimmers[#swimmers + 1] = p end
    end
    if #swimmers == 0 then return { found = false, falseAlarms = 0 } end

    -- who gets into trouble, and who just waves to their friends (from the decoy level)
    local victim
    if params.target == 'shark' then
        shark = spawnShark(swimmers, tower)
        victim = shark
    else
        -- someone way out at sea (out of their depth), if anyone is out there
        local far = {}
        for n, p in ipairs(swimmers) do if p.kind == 'far' then far[#far + 1] = n end end
        victim = table.remove(swimmers, #far > 0 and far[math.random(#far)] or math.random(#swimmers))
    end
    if not victim then return { found = false, falseAlarms = 0 } end
    for n = 1, math.min(params.decoys or 0, #swimmers) do
        local p = table.remove(swimmers, math.random(#swimmers))
        p.role, p.nextAt = 'wave', GetGameTimer() + math.random(0, 2500)
    end

    local me = PlayerPedId()
    local head = GetPedBoneCoords(me, 31086, 0.0, 0.0, 0.0)
    local base = tower.coords.w
    -- just in front of your eyes, past your own hands and the binoculars
    local camPos = vector3(head.x, head.y, head.z + 0.12) + forward(base) * 0.45
    local heading, pitch, fov, fovTarget = base, -4.0, W.fov.wide, W.fov.wide
    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', camPos.x, camPos.y, camPos.z, pitch, 0.0, heading, fov, false, 2)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 400, true, true)
    local sf = RequestScaleformMovie('BINOCULARS')
    local t = GetGameTimer() + 2000
    while not HasScaleformMovieLoaded(sf) and GetGameTimer() < t do Wait(0) end
    RequestNamedPtfxAsset('core')

    local start = GetGameTimer()
    local endAt = start + params.time * 1000
    local troubleAt = start + math.random(W.troubleAfter[1] * 1000, W.troubleAfter[2] * 1000)
    local trouble, found, falseAlarms, quit = false, false, 0, false
    local splashAt, shoutAt, swimAt, msg, msgUntil = 0, 0, 0, nil, 0
    local props, propsAt = {}, 0
    local aspect = GetAspectRatio(false)

    local function say(s, ms) msg, msgUntil = s, GetGameTimer() + (ms or 1800) end

    --- the person in the middle of the binoculars, if any
    local function aimed()
        local best, bestD = nil, W.markRadius
        local list = {}
        for _, p in ipairs(group) do list[#list + 1] = p end
        if shark then list[#list + 1] = shark end
        for _, p in ipairs(list) do
            if DoesEntityExist(p.ped) then
                local c = GetEntityCoords(p.ped)
                local on, sx, sy = GetScreenCoordFromWorldCoord(c.x, c.y, c.z + 0.3)
                if on then
                    local d = math.sqrt(((sx - 0.5) * aspect) ^ 2 + (sy - 0.5) ^ 2)
                    if d < bestD then best, bestD = p, d end
                end
            end
        end
        return best
    end

    while not found and not quit do
        local now = GetGameTimer()
        if now > endAt then break end
        -- another camera (e.g. a cutscene tool) took over: take the view back
        if GetRenderingCam() ~= cam then
            SetCamActive(cam, true)
            RenderScriptCams(true, false, 0, true, true)
        end
        DisableAllControlActions(0)
        EnableControlAction(0, 249, true) -- push to talk
        HideHudAndRadarThisFrame()
        -- only the sea: hide yourself and the binoculars in your hands (on your screen only, others still see you)
        SetEntityLocallyInvisible(me)
        if now > (propsAt or 0) then
            propsAt, props = now + 1000, {}
            for _, obj in ipairs(GetGamePool('CObject')) do
                if IsEntityAttachedToEntity(obj, me) then props[#props + 1] = obj end
            end
        end
        for _, obj in ipairs(props) do if DoesEntityExist(obj) then SetEntityLocallyInvisible(obj) end end

        -- the person in trouble
        if not trouble and now > troubleAt then
            trouble = true
            if victim ~= shark then
                victim.role = 'drown'
                ClearPedTasks(victim.ped)
                TaskStandStill(victim.ped, -1)
                anim(victim.ped, SWIM_DROWN)
            end
        end
        if trouble and DoesEntityExist(victim.ped) then
            local vp = GetEntityCoords(victim.ped)
            if victim == shark then
                if now > swimAt then
                    swimAt = now + 5000
                    local a = math.random() * math.pi * 2
                    local tx, ty = victim.home.x + math.cos(a) * 10.0, victim.home.y + math.sin(a) * 10.0
                    TaskGoStraightToCoord(victim.ped, tx, ty, victim.home.z, 1.0, 6000, 0.0, 0.5)
                end
            else
                if now > splashAt then splashAt = now + 420 Ocean.Splash(vp) end
                if now > shoutAt then
                    shoutAt = now + 3000
                    PlayPedAmbientSpeechNative(victim.ped, 'GENERIC_FRIGHTENED_HIGH', 'SPEECH_PARAMS_FORCE_SHOUTED')
                    if not IsEntityPlayingAnim(victim.ped, SWIM_DROWN[1], SWIM_DROWN[2], 3) then anim(victim.ped, SWIM_DROWN) end
                end
            end
        end

        if isAuto then
            -- test / showcase: pan over to them and zoom in, like a lifeguard would
            if trouble and now > troubleAt + 1500 and DoesEntityExist(victim.ped) then
                local d = GetEntityCoords(victim.ped) - camPos
                local wantH = GetHeadingFromVector_2d(d.x, d.y)
                local wantP = math.deg(math.atan(d.z + 0.3, math.sqrt(d.x * d.x + d.y * d.y)))
                heading = heading + angleDiff(wantH, heading) * 0.04
                pitch = pitch + (wantP - pitch) * 0.04
                fovTarget = W.fov.close + 4.0
                if math.abs(angleDiff(wantH, heading)) < 0.8 and math.abs(wantP - pitch) < 0.8 and fov <= W.markFov then
                    Wait(700)
                    found = true
                end
            end
        else
            local k = fov / W.fov.wide * 7.0
            heading = heading - GetDisabledControlNormal(0, 1) * k
            pitch = math.max(-30.0, math.min(10.0, pitch - GetDisabledControlNormal(0, 2) * k))
            if IsDisabledControlJustPressed(0, 241) then fovTarget = math.max(W.fov.close, fovTarget - 5.0) end
            if IsDisabledControlJustPressed(0, 242) then fovTarget = math.min(W.fov.wide, fovTarget + 5.0) end
            if IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 25) or IsDisabledControlJustPressed(0, 200) then quit = true end
            if IsDisabledControlJustPressed(0, 24) or IsDisabledControlJustPressed(0, 38) then
                if fov > W.markFov then
                    say(L('bino_zoom'))
                else
                    local p = aimed()
                    if p and p == victim and trouble then
                        found = true
                    elseif p then
                        falseAlarms = falseAlarms + 1
                        endAt = endAt - (params.falseAlarm or 3) * 1000
                        say(L(p.role == 'wave' and 'bino_waving' or 'bino_fine'), 2200)
                        PlaySoundFrontend(-1, 'ERROR', 'HUD_AMMO_SHOP_SOUNDSET', true)
                    end
                end
            end
        end
        heading = base + math.max(-W.maxTurn, math.min(W.maxTurn, angleDiff(heading, base)))
        fov = fov + (fovTarget - fov) * 0.15
        SetCamRot(cam, pitch, 0.0, heading, 2)
        SetCamFov(cam, fov)

        DrawScaleformMovieFullscreen(sf, 255, 255, 255, 255, 0)
        -- crosshair
        DrawRect(0.5, 0.5, 0.012 / aspect * 1.0, 0.0015, 255, 255, 255, 160)
        DrawRect(0.5, 0.5, 0.0015 / aspect * 1.0, 0.012, 255, 255, 255, 160)
        text(L('bino_title', tower.label), 0.5, 0.06, 0.55)
        text(('%s   ·   %d s'):format(L(isAuto and 'bino_auto' or 'bino_help'), math.max(0, math.ceil((endAt - now) / 1000))), 0.5, 0.9, 0.42)
        if msg and now < msgUntil then text(msg, 0.5, 0.82, 0.5, 250, 204, 21) end
        Wait(0)
    end

    if found then PlaySoundFrontend(-1, 'CHECKPOINT_PERFECT', 'HUD_MINI_GAME_SOUNDSET', true) end
    RenderScriptCams(false, true, 500, true, true)
    DestroyCam(cam, false)
    SetScaleformMovieAsNoLongerNeeded(sf)
    for _, p in ipairs(group) do if p.role == 'wave' then calm(p) end end

    local result = { found = found, falseAlarms = falseAlarms }
    if found and DoesEntityExist(victim.ped) then
        local c = GetEntityCoords(victim.ped)
        local ok, w = GetWaterHeight(c.x, c.y, c.z + 3.0)
        result.spot = { x = c.x, y = c.y, z = ok and w or c.z, w = GetEntityHeading(victim.ped) }
        result.model = victim.model
        -- keep them in trouble (out of the crowd) until the real call ped takes their place
        if victim ~= shark then
            for n, p in ipairs(group) do if p == victim then table.remove(group, n) break end end
            held = victim
        end
    else
        if victim == shark then deletePed(shark) shark = nil else calm(victim) end
    end
    return result
end
