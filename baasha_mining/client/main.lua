-- ── Baasha Mining — Client ───────────────────────────────────────────────

local JOB = 'mining'
local Core = exports.baasha_jobcore

local onShift = false
local state = 'idle'          -- idle | mining | planting
local auto = false            -- test / showcase tools play the minigame themselves
local hudText = nil
local bag = { count = 0, value = 0 }
local charges = 0
local myLevel = 1               -- this character's mining level (locked rocks show it on screen)
local lastResult = nil
local history = {}
local blips = {}
local tabletHint

local Rocks = {}              -- id -> { coords, area, entity, ore, uses, boulder, ready, readyIn, seenAt }
local CHARGES = {}            -- boulder id -> charge prop
local fuseEnd = 0             -- when the nearby charge goes off (HUD countdown)

local function notify(msg, type) lib.notify({ title = Config.Job.label, description = msg, type = type or 'inform' }) end
local function setState(new, why)
    state = new
    history[#history + 1] = why and ('%s(%s)'):format(new, why) or new
    if #history > 14 then table.remove(history, 1) end
    if Config.Debug then print(('[baasha_mining] state -> %s %s'):format(new, why or '')) end
end

local function setHud(text)
    if text == hudText then return end
    hudText = text
    if text then lib.showTextUI(text, { position = 'left-center', icon = 'gem' }) else lib.hideTextUI() end
end

local function refreshBag()
    bag = lib.callback.await('baasha_mining:bag', false) or bag
end

-- ── Rock list from the config + live state from the server ───────────────
for _, area in ipairs(Config.Areas) do
    for i, c in ipairs(area.spots) do
        Rocks[('%s_%d'):format(area.id, i)] = { coords = c, area = area }
    end
end
for _, b in ipairs(Config.Dynamite.boulders) do Rocks[b.id] = { coords = b.coords, boulder = true } end

local function applyState(s)
    for id, r in pairs(Rocks) do
        local v = s and s[id]
        if r.boulder then
            r.ready = v and v.ready or false
            r.armed = v and v.armed or false
            r.readyIn = v and v.readyIn or 0
            r.seenAt = GetGameTimer()
        else
            r.ore = v and v.ore or nil
            r.uses = v and v.uses or 0
        end
    end
end
applyState(GlobalState.baasha_mining_rocks)
AddStateBagChangeHandler('baasha_mining_rocks', 'global', function(_, _, value) applyState(value) end)

-- ── Props ────────────────────────────────────────────────────────────────
local function groundZ(c)
    local ok, z = GetGroundZFor_3dCoord(c.x, c.y, c.z + 10.0, false)
    return ok and z or c.z
end

local function spawnProp(model, c)
    model = type(model) == 'string' and joaat(model) or model
    if not IsModelInCdimage(model) then return nil end
    lib.requestModel(model, 5000)
    local z = groundZ(c)
    local obj = CreateObject(model, c.x, c.y, z, false, false, false)
    SetEntityHeading(obj, (c.x * 37 + c.y * 11) % 360.0) -- a different angle per rock, the same every time
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(model)
    return obj
end

local function removeProp(r)
    if r.entity and DoesEntityExist(r.entity) then DeleteEntity(r.entity) end
    r.entity = nil
end

--- Level needed for this rock (its ore, and the area it's in)
local function rockLevel(r)
    local need = r.ore and Config.Ores[r.ore] and Config.Ores[r.ore].level or 1
    if r.area and r.area.level > need then need = r.area.level end
    return need
end

local function rockAlive(r)
    if r.boulder then return r.ready or r.armed end  -- armed: the charge is burning, the boulder is still there
    return r.ore ~= nil and (r.uses or 0) > 0
end

--- Spawn rocks near the player, remove broken / far ones
local function syncProps()
    local here = GetEntityCoords(cache.ped)
    for _, r in pairs(Rocks) do
        local near = #(here.xy - vector2(r.coords.x, r.coords.y)) < 150.0
        if onShift and near and rockAlive(r) then
            if not r.entity or not DoesEntityExist(r.entity) then
                r.entity = spawnProp(r.boulder and Config.Dynamite.model or Config.Rocks.model, r.coords)
            end
        else
            removeProp(r)
        end
    end
end

local function rockPos(r)
    if r.entity and DoesEntityExist(r.entity) then return GetEntityCoords(r.entity) end
    return r.coords
end

--- Nearest live rock / boulder within reach (boulders are bigger, so they reach further)
local function nearestRock()
    local here, best, bestD = GetEntityCoords(cache.ped), nil, 99.0
    for id, r in pairs(Rocks) do
        if r.entity and rockAlive(r) then
            local d = #(here.xy - rockPos(r).xy) - (r.boulder and 0.9 or 0.0)
            if d < 2.6 and d < bestD then best, bestD = id, d end
        end
    end
    return best, best and Rocks[best]
end

-- ── Tools: hard hat on shift, pickaxe while mining ───────────────────────
local hardhat, pickaxe

local function attach(spec)
    local model = joaat(spec.model)
    if not IsModelInCdimage(model) then return nil end
    lib.requestModel(model, 5000)
    local ped = cache.ped
    local obj = CreateObject(model, GetEntityCoords(ped), true, true, false)
    AttachEntityToEntity(obj, ped, GetPedBoneIndex(ped, spec.bone), spec.pos.x, spec.pos.y, spec.pos.z,
        spec.rot.x, spec.rot.y, spec.rot.z, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(model)
    return obj
end

local function drop(obj)
    if obj and DoesEntityExist(obj) then DeleteEntity(obj) end
    return nil
end

local SWING = { dict = 'melee@large_wpn@streamed_core', anim = 'ground_attack_on_spot' }
local DRILL = 'WORLD_HUMAN_CONST_DRILL'

local function equip(tool)
    if tool == 'jackhammer' then
        pickaxe = drop(pickaxe)
        TaskStartScenarioInPlace(cache.ped, DRILL, 0, true)
    elseif not pickaxe then
        pickaxe = attach(Config.Tools.pickaxe)
        lib.requestAnimDict(SWING.dict)
    end
end

local function unequip()
    FreezeEntityPosition(cache.ped, false)
    pickaxe = drop(pickaxe)
    if IsPedUsingScenario(cache.ped, DRILL) then ClearPedTasks(cache.ped) end
    -- the drill scenario leaves its jackhammer lying around
    SetTimeout(1200, function()
        local here = GetEntityCoords(cache.ped)
        for _, obj in ipairs(GetGamePool('CObject')) do
            if GetEntityModel(obj) == `prop_tool_jackham` and #(GetEntityCoords(obj) - here) < 4.0 and not IsEntityAttached(obj) then
                SetEntityAsMissionEntity(obj, true, true)
                DeleteEntity(obj)
            end
        end
    end)
end

local function rockFx(r)
    local c = rockPos(r)
    lib.requestNamedPtfxAsset('core', 2000)
    UseParticleFxAssetNextCall('core')
    StartParticleFxNonLoopedAtCoord('ent_dst_rocks', c.x, c.y, c.z + 0.6, 0.0, 0.0, 0.0, 0.8, false, false, false)
end

-- ── Rock Breaker ─────────────────────────────────────────────────────────
local mining = nil  -- { id, rock, tool }

local function mine(id)
    if state ~= 'idle' then return false, 'busy: ' .. state end
    local r = Rocks[id]
    if not r or r.boulder or not rockAlive(r) then return false, 'no rock' end
    setState('mining', id) -- busy from the first press, so a second E press can't start another session
    local ped = cache.ped
    local c = rockPos(r)
    TaskTurnPedToFaceCoord(ped, c.x, c.y, c.z, 800)
    Wait(700)
    local ok, params = lib.callback.await('baasha_mining:start', false, id)
    if not ok then
        setState('idle', 'start rejected')
        if params then notify(params, 'error') end
        return false, params or 'rejected'
    end
    -- The swing animation walks the ped back a little every strike: lock them on this spot while mining
    mining = { id = id, rock = r, tool = params.tool, pos = GetEntityCoords(ped), heading = GetEntityHeading(ped) }
    FreezeEntityPosition(ped, true)
    equip(params.tool)
    params.auto = auto
    if not auto then SetNuiFocus(true, false) end
    SendNUIMessage({ action = 'breaker', data = params })
    return true
end

RegisterNUICallback('breakerHit', function(body, cb)
    cb(1)
    if not mining then return end
    if body.quality ~= 'miss' then rockFx(mining.rock) end
    if mining.tool == 'pickaxe' then
        local ped = cache.ped
        -- back on the exact spot and facing the rock before every swing
        local p = mining.pos
        if #(GetEntityCoords(ped) - p) > 0.05 then SetEntityCoordsNoOffset(ped, p.x, p.y, p.z, false, false, false) end
        SetEntityHeading(ped, mining.heading)
        TaskPlayAnim(ped, SWING.dict, SWING.anim, 8.0, -8.0, 1100, 0, 0.0, false, false, false)
    end
end)

RegisterNUICallback('breakerDone', function(body, cb)
    cb(1)
    SetNuiFocus(false, false)
    if state ~= 'mining' then return end
    local m = mining
    mining = nil
    if body.aborted then
        lib.callback.await('baasha_mining:cancel', false)
        lastResult = false
        unequip()
        setState('idle', 'aborted')
        return
    end
    local ok, result = lib.callback.await('baasha_mining:finish', false, body)
    if ok and type(result) == 'table' then
        lastResult = result
        SendNUIMessage({ action = 'result', data = result })
        PlaySoundFrontend(-1, 'PICK_UP', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
        if m then
            m.rock.uses = result.rockLeft
            if result.rockLeft == 0 then rockFx(m.rock) removeProp(m.rock) end
        end
        for _, f in ipairs(result.finds) do bag.count, bag.value = bag.count + f.count, bag.value + f.value end
        setState('idle', ('mined %d'):format(#result.finds))
    else
        lastResult = false
        SendNUIMessage({ action = 'closeBreaker' })
        if result then notify(result, 'error') end
        setState('idle', 'finish rejected')
    end
    SetTimeout(600, unequip)
end)

-- ── Dynamite ─────────────────────────────────────────────────────────────
local function boom(c, strength)
    local dist = #(GetEntityCoords(cache.ped) - c)
    if dist > 250.0 then return end
    lib.requestNamedPtfxAsset('scr_trevor1', 2000)
    UseParticleFxAssetNextCall('scr_trevor1')
    StartParticleFxNonLoopedAtCoord('scr_trev1_trailer_boosh', c.x, c.y, c.z + 0.5, 0.0, 0.0, 0.0, 1.0, false, false, false)
    lib.requestNamedPtfxAsset('core', 2000)
    UseParticleFxAssetNextCall('core')
    StartParticleFxNonLoopedAtCoord('ent_dst_rocks', c.x, c.y, c.z + 0.8, 0.0, 0.0, 0.0, 3.0, false, false, false)
    ShakeGameplayCam('LARGE_EXPLOSION_SHAKE', math.max(0.15, (strength or 1.0) * (1.0 - dist / 250.0)))
    SendNUIMessage({ action = 'boom', volume = math.max(0.1, 1.0 - dist / 200.0) })
end

local function plant(id)
    if state ~= 'idle' then return false, 'busy: ' .. state end
    local r = Rocks[id]
    if not r or not r.boulder or not r.ready then return false, 'boulder not ready' end
    setState('planting', id)
    local c = rockPos(r)
    TaskTurnPedToFaceCoord(cache.ped, c.x, c.y, c.z, 800)
    Wait(700)
    local done = lib.progressBar({
        duration = 2500, label = 'Planting the charge...', canCancel = false, disable = { move = true, combat = true },
        anim = { dict = 'anim@heists@ornate_bank@thermal_charge', clip = 'thermal_charge' },
    })
    local ok, left = lib.callback.await('baasha_mining:plant', false, id)
    if not ok then
        setState('idle', 'plant rejected')
        if left then notify(left, 'error') end
        return false, left
    end
    charges = left
    notify(L('planted'), 'warning')
    setState('idle', 'planted')
    return true
end

RegisterNetEvent('baasha_mining:client:charge', function(id, fuse, from)
    local r = Rocks[id]
    if not r or not r.entity then return end
    r.armed = true
    local c = rockPos(r)
    CHARGES[id] = drop(CHARGES[id])
    local model = joaat(Config.Dynamite.charge)
    if IsModelInCdimage(model) then
        lib.requestModel(model, 3000)
        -- stick the charge on the boulder's face, on the side the planter stood
        local min, max = GetModelDimensions(GetEntityModel(r.entity))
        local radius = math.max(max.x - min.x, max.y - min.y) * 0.42
        local dir = from and vector3(from.x - c.x, from.y - c.y, 0.0) or vector3(1.0, 0.0, 0.0)
        dir = #dir > 0.01 and dir / #dir or vector3(1.0, 0.0, 0.0)
        local p = c + dir * radius
        local _, z = GetGroundZFor_3dCoord(p.x, p.y, p.z + 3.0, false)
        CHARGES[id] = CreateObject(model, p.x, p.y, math.max(z or c.z, c.z) + 0.7, false, false, false)
        SetEntityHeading(CHARGES[id], GetHeadingFromVector_2d(dir.x, dir.y))
        FreezeEntityPosition(CHARGES[id], true)
    end
    -- countdown beeps for everyone close by
    CreateThread(function()
        local t = GetGameTimer() + fuse * 1000
        while GetGameTimer() < t do
            local left = math.ceil((t - GetGameTimer()) / 1000)
            if #(GetEntityCoords(cache.ped) - c) < 60.0 then
                PlaySoundFrontend(-1, 'Beep_Red', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', true)
                fuseEnd = t
            end
            Wait(left <= 2 and 350 or 1000)
        end
    end)
end)

RegisterNetEvent('baasha_mining:client:blast', function(id)
    local r = Rocks[id]
    if not r then return end
    local c = rockPos(r)
    CHARGES[id] = drop(CHARGES[id])
    boom(vector3(c.x, c.y, c.z), 1.0)
    r.ready = false
    removeProp(r)
end)

RegisterNetEvent('baasha_mining:client:blastLoot', function(result)
    lastResult = result
    SendNUIMessage({ action = 'result', data = result })
    for _, f in ipairs(result.finds) do bag.count, bag.value = bag.count + f.count, bag.value + f.value end
    notify(L('blasted'), 'success')
end)

-- ── Main loop: props, glow, HUD and keys ─────────────────────────────────
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

local function mainLoop()
    CreateThread(function()
        local nextSync, hintAt = 0, 0
        while onShift do
          local okTick, sleep = pcall(function()
            local sleep = 250
            local now = GetGameTimer()
            if now > nextSync then syncProps() nextSync = now + 1500 end
            if now > hintAt then tabletHint, hintAt = Core:TabletHint(), now + 5000 end
            local here = GetEntityCoords(cache.ped)

            -- ore glow + labels on nearby rocks
            for _, r in pairs(Rocks) do
                if r.entity and not r.boulder and r.ore then
                    local c = rockPos(r)
                    local d = #(here - c)
                    if d < 40.0 then
                        sleep = 0
                        local col = Config.Ores[r.ore].color
                        DrawLightWithRange(c.x, c.y, c.z + 1.2, col[1], col[2], col[3], 3.5, 2.5)
                        if d < 9.0 then
                            local need = rockLevel(r)
                            if myLevel < need then
                                drawText3D(c + vector3(0.0, 0.0, 1.5), ('%s · LV %d'):format(Config.Ores[r.ore].label:upper(), need), 0.38, { 160, 160, 170 })
                            else
                                drawText3D(c + vector3(0.0, 0.0, 1.5), Config.Ores[r.ore].label:upper(), 0.38, col)
                            end
                        end
                    end
                elseif r.entity and r.boulder and #(here - rockPos(r)) < 25.0 then
                    sleep = 0
                    local c = rockPos(r)
                    DrawMarker(2, c.x, c.y, c.z + 3.2, 0.0, 0.0, 0.0, 180.0, 0.0, 0.0, 0.5, 0.5, 0.5, 239, 68, 68, 200, true, true, 2, false, nil, nil, false)
                    drawText3D(c + vector3(0.0, 0.0, 3.8), 'DYNAMITE BOULDER', 0.38, { 239, 68, 68 })
                end
            end

            if state == 'idle' then
                local lines = { L('hud_bag', bag.count, bag.value) }
                if now < fuseEnd then lines[1] = L('hud_fuse', math.ceil((fuseEnd - now) / 1000)) end
                local id, r = nearestRock()
                if id and r.boulder and r.armed then
                    sleep = 0 -- the countdown line is already on top
                elseif id and r.boulder then
                    sleep = 0
                    lines[#lines + 1] = L('hud_blast', charges)
                    if IsControlJustPressed(0, Config.MineKey) then CreateThread(function() plant(id) end) end
                elseif id then
                    sleep = 0
                    local ore, need = Config.Ores[r.ore], rockLevel(r)
                    if myLevel < need then
                        lines[#lines + 1] = L('hud_locked', ore.label, need)
                    else
                        lines[#lines + 1] = L('hud_mine', ore.label, r.uses, Config.Rocks.uses)
                        if IsControlJustPressed(0, Config.MineKey) then CreateThread(function() mine(id) end) end
                    end
                else
                    lines[#lines + 1] = L('hud_hint_rocks')
                end
                if tabletHint then lines[#lines + 1] = tabletHint end
                setHud(table.concat(lines, '  \n'))
            elseif state == 'mining' then
                setHud(nil)
            end
            return sleep
          end)
          if not okTick then
              print(('^1[baasha_mining] HUD loop error (recovered): %s^7'):format(tostring(sleep)))
              sleep = 500
          end
            Wait(sleep)
        end
        setHud(nil)
    end)
end

-- ── Signs: "MINING JOB" over the foreman, "MINING OFFICE" during a shift ──
if Config.Signs then
    CreateThread(function()
        local d, o = Config.Job.depot.coords, Config.Office.coords
        local foreman = vector3(d.x, d.y, d.z - 1.0)
        local office = vector3(o.x, o.y, o.z - 1.0)
        while true do
            local sleep = 1000
            local at = onShift and office or foreman
            local dist = #(GetEntityCoords(cache.ped) - at)
            if dist < Config.Signs.distance and not IsPauseMenuActive() then
                sleep = 0
                if onShift then
                    DrawMarker(29, at.x, at.y, at.z + 2.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.5, 0.5, 234, 179, 8, 210, true, true, 2, true, nil, nil, false)
                else
                    DrawMarker(0, at.x, at.y, at.z + 2.4, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 0.3, 0.3, 234, 179, 8, 210, true, true, 2, false, nil, nil, false)
                end
                if dist < Config.Signs.textDistance then
                    local top = onShift and 2.8 or 2.95
                    drawText3D(at + vector3(0.0, 0.0, top), onShift and L('sign_office') or L('sign_job'), 0.5, { 234, 179, 8 })
                    drawText3D(at + vector3(0.0, 0.0, top - 0.15), onShift and L('sign_office_sub') or L('sign_job_sub'), 0.32, { 255, 255, 255 })
                end
            end
            Wait(sleep)
        end
    end)
end

-- ── Mining Office screen ─────────────────────────────────────────────────
local function officeData() return lib.callback.await('baasha_mining:office', false) end

local function openOffice()
    local data = officeData()
    if not data then notify(L('too_far'), 'error') return false end
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'office', data = data })
    return true
end

local function closeOffice()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeOffice' })
end

local function sell()
    local ok, msg = lib.callback.await('baasha_mining:sell', false)
    notify(msg, ok and 'success' or 'error')
    if ok then bag = { count = 0, value = 0 } end
    return ok
end

local function smelt(index, amount)
    local ok, msg = lib.callback.await('baasha_mining:smelt', false, index, amount)
    if msg then notify(msg, ok and 'success' or 'error') end
    refreshBag()
    return ok
end

local function collect()
    local ok, msg = lib.callback.await('baasha_mining:collect', false)
    if msg then notify(msg, ok and 'success' or 'error') end
    refreshBag()
    return ok
end

RegisterNUICallback('officeClose', function(_, cb) SetNuiFocus(false, false) cb(1) end)
RegisterNUICallback('officeSell', function(_, cb) sell() cb(officeData() or {}) end)
RegisterNUICallback('officeClosed', function(_, cb) refreshBag() cb(1) end)
RegisterNUICallback('officeSmelt', function(body, cb) smelt(body.index, body.amount) cb(officeData() or {}) end)
RegisterNUICallback('officeCollect', function(_, cb) collect() cb(officeData() or {}) end)
RegisterNUICallback('officeRefresh', function(_, cb) cb(officeData() or {}) end)

local function addBlip(c, sprite, color, label)
    local b = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(b, sprite)
    SetBlipColour(b, color)
    SetBlipScale(b, 0.75)
    SetBlipAsShortRange(b, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(b)
    blips[#blips + 1] = b
end

local function setupWorld()
    for _, a in ipairs(Config.Areas) do
        local c = a.spots[1]
        addBlip(c, Config.Job.depot.blip.sprite, a.level > 1 and 46 or 5, ('%s · %s'):format(L('blip_area'), a.label))
    end
    local o = Config.Office.coords
    Bridge.AddTargetZone('baasha_mining_office', vector3(o.x, o.y, o.z), vector3(2.2, 2.2, 2.6), o.w, {
        { name = 'baasha_mining_office', label = L('open_office'), icon = 'fa-solid fa-gem', distance = 3.0,
          canInteract = function() return onShift end, onSelect = function() openOffice() end },
    })
    if Config.Tools.hardhat.enabled then hardhat = attach(Config.Tools.hardhat) end
end

local function cleanupWorld()
    for _, b in ipairs(blips) do RemoveBlip(b) end
    blips = {}
    Bridge.RemoveTargetZone('baasha_mining_office')
    hardhat = drop(hardhat)
    for _, r in pairs(Rocks) do removeProp(r) end
    for id in pairs(CHARGES) do CHARGES[id] = drop(CHARGES[id]) end
end

-- level ups while mining (the core sends the new level with every reward)
RegisterNetEvent('baasha_jobcore:client:paid', function(jobId, _, _, newLevel)
    if jobId == JOB and newLevel then myLevel = newLevel end
end)

-- ── Shift events ─────────────────────────────────────────────────────────
RegisterNetEvent('baasha_jobcore:client:shiftStarted', function(jobId)
    if jobId ~= JOB or onShift then return end
    onShift = true
    setState('idle', 'shift start')
    local c, lvl = lib.callback.await('baasha_mining:charges', false)
    charges, myLevel = c or 0, lvl or 1
    refreshBag()
    setupWorld()
    syncProps()
    mainLoop()
end)

local function cleanup()
    SendNUIMessage({ action = 'closeOffice' })
    SendNUIMessage({ action = 'closeBreaker' })
    SetNuiFocus(false, false)
    if state == 'mining' then lib.callback.await('baasha_mining:cancel', false) end
    mining = nil
    onShift = false
    unequip()
    cleanupWorld()
    setState('idle', 'shift end')
    setHud(nil)
end

RegisterNetEvent('baasha_jobcore:client:shiftEnded', function(jobId)
    if jobId == JOB and onShift then cleanup() end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    if mining then FreezeEntityPosition(cache.ped, false) end
    if onShift then lib.hideTextUI() end
    pickaxe = drop(pickaxe)
    cleanupWorld()
end)

-- ── Automation hooks (test / showcase tools). The server still validates everything. ──
exports('GetState', function()
    return { state = state, onShift = onShift, bag = bag, charges = charges, lastResult = lastResult, history = table.concat(history, ' > ') }
end)
exports('ClearHistory', function() history = {} lastResult = nil end)
exports('SetAuto', function(on) auto = on == true end)
exports('GetRocks', function()
    local list = {}
    for id, r in pairs(Rocks) do
        list[#list + 1] = { id = id, coords = rockPos(r), ore = r.ore, uses = r.uses, boulder = r.boulder == true,
                            ready = r.ready, area = r.area and r.area.id, spawned = r.entity ~= nil }
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end)
exports('MineRock', function(id) return mine(id) end)
exports('PlantDynamite', function(id) return plant(id) end)
exports('RefreshBag', refreshBag)
exports('Sell', sell)
exports('Smelt', smelt)
exports('Collect', collect)
exports('OpenOffice', function() return openOffice() end)
exports('CloseOffice', function() closeOffice() end)
exports('SetOfficeTab', function(tab, scrollMs) SendNUIMessage({ action = 'officeTab', tab = tab, scroll = scrollMs }) end)
exports('PressOfficeButton', function(act, arg) SendNUIMessage({ action = 'officePress', act = act, arg = arg }) end)
--- For prop tuning tools: the hard hat (default) or the pickaxe, as it's attached now
exports('GetCarry', function(which)
    local t = Config.Tools[which or 'hardhat']
    if not t then return nil end
    return { model = t.model, bone = t.bone, pos = t.pos, rot = t.rot,
             dict = which == 'pickaxe' and SWING.dict or nil, anim = which == 'pickaxe' and SWING.anim or nil }
end)
exports('OfficeCoords', function() local o = Config.Office.coords return vector3(o.x, o.y, o.z) end)
--- First recipe the player has enough ore + coal for (index), or nil
exports('SmeltableRecipe', function()
    local d = officeData()
    for _, rc in ipairs(d and d.recipes or {}) do
        if not rc.locked and rc.max > 0 then return rc.index end
    end
end)
--- Current smelter job ({ ingot, amount, left, ... }) or nil
exports('SmelterState', function()
    local d = officeData()
    return d and d.smelter or nil
end)
