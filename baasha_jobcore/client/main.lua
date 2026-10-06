-- ── Baasha Job Core — Client ─────────────────────────────────────────────

local Shift = nil          -- { jobId, crew }
local tabletOpen = false
local depots = {}          -- jobId -> { blip, point, ped }
local savedOutfit = nil

local function notify(msg, type) Editable.Notify(msg, type) end

-- ── Tablet ────────────────────────────────────────────────────────────────
local function refreshTablet()
    if not tabletOpen then return end
    local data = lib.callback.await('baasha_jobcore:getTablet', false)
    SendNUIMessage({ action = 'update', data = data })
end

local function openTablet(focusJob)
    if tabletOpen then return end
    local data = lib.callback.await('baasha_jobcore:getTablet', false)
    tabletOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = data, focus = focusJob })
end

local function closeTablet()
    tabletOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

RegisterNUICallback('close', function(_, cb) closeTablet() cb(1) end)

local function startShift(jobId)
    local job = GlobalState.baasha_jobs and GlobalState.baasha_jobs[jobId]
    if not job then return false, L('job_unavailable') end

    -- Pick the first clear parking spot
    local spawnIndex
    for i, s in ipairs(job.spawns or {}) do
        if not IsAnyVehicleNearPoint(s.x, s.y, s.z, 3.0) then spawnIndex = i break end
    end
    if #(job.spawns or {}) > 0 and not spawnIndex then
        notify(L('no_spawn_spot'), 'error')
        return false, L('no_spawn_spot')
    end

    local ok, err = lib.callback.await('baasha_jobcore:startShift', false, jobId, spawnIndex)
    if not ok and err then notify(err, 'error') end
    if ok then closeTablet() end
    return ok, err
end

local function endShift()
    local ok, err = lib.callback.await('baasha_jobcore:endShift', false)
    if not ok and err then notify(err, 'error') end
    return ok, err
end

RegisterNUICallback('startShift', function(body, cb)
    cb({ ok = startShift(body.jobId) })
end)

RegisterNUICallback('endShift', function(_, cb)
    cb({ ok = endShift() })
    refreshTablet()
end)

RegisterNUICallback('invite', function(body, cb)
    local ok, msg = lib.callback.await('baasha_jobcore:invite', false, body.id)
    if msg then notify(msg, ok and 'success' or 'error') end
    cb({ ok = ok })
end)

RegisterNUICallback('leave', function(_, cb)
    lib.callback.await('baasha_jobcore:leaveCrew', false)
    cb(1)
    refreshTablet()
end)

RegisterNUICallback('kick', function(body, cb)
    local ok, err = lib.callback.await('baasha_jobcore:kick', false, body.id)
    if not ok and err then notify(err, 'error') end
    cb(1)
end)

RegisterNUICallback('leaderboard', function(body, cb)
    cb(lib.callback.await('baasha_jobcore:leaderboard', false, body.jobId) or {})
end)

if Config.TabletCommand then
    RegisterCommand(Config.TabletCommand, function() openTablet() end, false)
    TriggerEvent('chat:addSuggestion', '/' .. Config.TabletCommand, L('tablet_cmd_help'))
end

if Config.TabletKey ~= '' then
    lib.addKeybind({ name = 'baasha_jobs_tablet', description = L('tablet_cmd_help'), defaultKey = Config.TabletKey, onPressed = function() openTablet() end })
end

-- ── Depots (blip + ped + target), rebuilt whenever jobs register ─────────
local function removeDepot(id)
    local d = depots[id]
    if not d then return end
    if d.blip then RemoveBlip(d.blip) end
    if d.point then d.point:remove() end
    if d.ped and DoesEntityExist(d.ped) then DeleteEntity(d.ped) end
    depots[id] = nil
end

local function createDepot(job)
    local c = job.depot.coords
    local d = {}

    if Config.DepotBlips and job.depot.blip then
        d.blip = AddBlipForCoord(c.x, c.y, c.z)
        SetBlipSprite(d.blip, job.depot.blip.sprite or 280)
        SetBlipColour(d.blip, job.depot.blip.color or 5)
        SetBlipScale(d.blip, job.depot.blip.scale or 0.8)
        SetBlipAsShortRange(d.blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(job.label)
        EndTextCommandSetBlipName(d.blip)
    end

    d.point = lib.points.new({
        coords = vector3(c.x, c.y, c.z),
        distance = 60.0,
        onEnter = function()
            local model = lib.requestModel(job.depot.ped or 's_m_m_dockwork_01')
            RequestCollisionAtCoord(c.x, c.y, c.z)
            local found, groundZ = GetGroundZFor_3dCoord(c.x, c.y, c.z + 0.5, false)
            d.ped = CreatePed(4, model, c.x, c.y, found and groundZ or (c.z - 1.0), c.w, false, true)
            SetModelAsNoLongerNeeded(model)
            FreezeEntityPosition(d.ped, true)
            SetEntityInvincible(d.ped, true)
            SetBlockingOfNonTemporaryEvents(d.ped, true)
            if job.depot.scenario then TaskStartScenarioInPlace(d.ped, job.depot.scenario, 0, true) end
            Bridge.AddTargetEntity(d.ped, {
                { name = 'baasha_jobs_open', label = L('open_tablet') .. ' · ' .. job.label, icon = job.icon or 'fa-solid fa-briefcase', onSelect = function() openTablet(job.id) end },
            })
        end,
        onExit = function()
            if d.ped and DoesEntityExist(d.ped) then
                Bridge.RemoveTargetEntity(d.ped, { 'baasha_jobs_open' })
                DeleteEntity(d.ped)
            end
            d.ped = nil
        end,
    })

    depots[job.id] = d
end

local function rebuildDepots(jobs)
    for id in pairs(depots) do removeDepot(id) end
    for _, job in pairs(jobs or {}) do createDepot(job) end
end

AddStateBagChangeHandler('baasha_jobs', 'global', function(_, _, value)
    rebuildDepots(value)
end)

CreateThread(function()
    rebuildDepots(GlobalState.baasha_jobs)
end)

-- ── Uniforms ──────────────────────────────────────────────────────────────
local function applyUniform(uniform)
    if not Config.UseUniforms or not uniform then return end
    local ped = cache.ped
    local outfit = GetEntityModel(ped) == `mp_f_freemode_01` and uniform.female or uniform.male
    if not outfit then return end

    savedOutfit = { components = {}, props = {} }
    for id = 1, 11 do
        savedOutfit.components[id] = { GetPedDrawableVariation(ped, id), GetPedTextureVariation(ped, id), GetPedPaletteVariation(ped, id) }
    end
    for id = 0, 7 do
        savedOutfit.props[id] = { GetPedPropIndex(ped, id), GetPedPropTextureIndex(ped, id) }
    end

    for _, c in ipairs(outfit.components or {}) do SetPedComponentVariation(ped, c[1], c[2], c[3] or 0, 0) end
    for _, p in ipairs(outfit.props or {}) do
        if p[2] < 0 then ClearPedProp(ped, p[1]) else SetPedPropIndex(ped, p[1], p[2], p[3] or 0, true) end
    end
end

local function restoreOutfit()
    if not savedOutfit then return end
    local ped = cache.ped
    for id, c in pairs(savedOutfit.components) do SetPedComponentVariation(ped, id, c[1], c[2], c[3]) end
    for id, p in pairs(savedOutfit.props) do
        if p[1] < 0 then ClearPedProp(ped, id) else SetPedPropIndex(ped, id, p[1], p[2], true) end
    end
    savedOutfit = nil
end

-- ── Shift events ──────────────────────────────────────────────────────────
RegisterNetEvent('baasha_jobcore:client:shiftStarted', function(jobId, crew)
    Shift = { jobId = jobId, crew = crew }
    local job = GlobalState.baasha_jobs and GlobalState.baasha_jobs[jobId]
    applyUniform(job and job.uniform)

    if crew.vehicle then
        CreateThread(function()
            -- Wait for the truck to exist on this client (a netId can exist before the entity has streamed in)
            local veh, timeout = 0, GetGameTimer() + 10000
            repeat
                if NetworkDoesNetworkIdExist(crew.vehicle) then veh = NetworkGetEntityFromNetworkId(crew.vehicle) end
                if veh == 0 then Wait(100) end
            until veh ~= 0 or GetGameTimer() > timeout
            -- Keys work by plate, so hand them out even if the truck never streamed in
            Editable.GiveVehicleKeys(veh ~= 0 and veh or nil, crew.plate)
            if veh ~= 0 and crew.leader == cache.serverId then Editable.SetFuel(veh, 100.0) end
        end)
    end
    Editable.OnShiftStart(jobId)
end)

RegisterNetEvent('baasha_jobcore:client:shiftEnded', function(jobId)
    Shift = nil
    restoreOutfit()
    Editable.OnShiftEnd(jobId)
    refreshTablet()
end)

RegisterNetEvent('baasha_jobcore:client:paid', function(jobId, amount, xp, level, totalXp, from, to)
    lib.notify({ title = ('Lv.%s'):format(level), description = L('paid', amount, xp), type = 'success', duration = 2500, position = 'top-right' })
    SendNUIMessage({ action = 'paid', jobId = jobId, level = level, xp = totalXp, from = from, to = to })
end)

RegisterNetEvent('baasha_jobcore:client:crewUpdated', function()
    refreshTablet()
end)

RegisterNetEvent('baasha_jobcore:client:invite', function(fromName)
    local answer = lib.alertDialog({
        header = L('invite_header'),
        content = L('invite_body', fromName),
        centered = true,
        cancel = true,
    })
    lib.callback.await('baasha_jobcore:respondInvite', false, answer == 'confirm')
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if tabletOpen then SetNuiFocus(false, false) end
    restoreOutfit()
    for id in pairs(depots) do removeDepot(id) end
end)

-- ── Exports (used by job resources) ──────────────────────────────────────
exports('GetShift', function() return Shift end)
exports('IsOnShift', function(jobId) return Shift ~= nil and (jobId == nil or Shift.jobId == jobId) end)
exports('GetWorkVehicle', function()
    if not Shift or not Shift.crew.vehicle or not NetworkDoesNetworkIdExist(Shift.crew.vehicle) then return nil end
    local veh = NetworkGetEntityFromNetworkId(Shift.crew.vehicle)
    return veh ~= 0 and veh or nil
end)
exports('OpenTablet', openTablet)
exports('CloseTablet', closeTablet)
exports('IsTabletOpen', function() return tabletOpen end)

-- Automation hooks (used by test / showcase tools). The server still validates everything.
exports('StartShift', startShift)
exports('EndShift', endShift)
