-- ── Baasha Delivery — Client ─────────────────────────────────────────────
-- Shift state, blips/GPS, HUD, van targets and finishing the route.

Delivery = Delivery or {}

local JOB = 'delivery'
local Core = exports.baasha_jobcore

Delivery.S = nil
Delivery.onShift = false
Delivery.carrying = false
Delivery.carryParcel = nil
Delivery.returning = false
Delivery.condition = nil
Delivery.expressDeadline = nil   -- game timer (ms)
Delivery.tabletHint = nil

Delivery.blips = {}
Delivery.truck = nil
Delivery._hudSent = false

local function notify(msg, type)
    lib.notify({ title = Config.Job.label, description = msg, type = type or 'inform' })
end
Delivery.notify = notify

-- ── HUD pill ──────────────────────────────────────────────────────────────
local function hudData()
    if not Delivery.S then return { visible = false } end
    local S = Delivery.S
    local pos = Config.Hud.position
    local d = {
        visible = true, stage = S.stage, index = S.index, total = S.total, returns = S.returns, hint = Delivery.tabletHint,
        position = pos == 'top-left' and 'left' or (pos == 'top-right' and 'right' or 'center'),
    }

    if S.stage == 'loading' then
        d.state, d.title = 'loading', L('hud_loading')
    elseif S.stage == 'done' then
        d.state, d.title = 'done', L('hud_return')
    elseif S.stage == 'driving' then
        d.title = L('hud_stop', S.index, S.total)
        d.address = S.stopLabel
        if Delivery.carrying and Delivery.carryParcel then
            local p = Delivery.carryParcel
            d.state = Delivery.returning and 'return' or 'carry'
            d.parcel = '#' .. p.id
            d.type = p.type
            d.stack = p.stack or 1
            if Delivery.returning then
                d.line = L('hud_returning')
            else
                d.line = ('%s · %s'):format('#' .. p.id, L('type_' .. p.type))
            end
            if p.express and Delivery.expressDeadline then
                d.express = math.max(0, math.ceil((Delivery.expressDeadline - GetGameTimer()) / 1000))
            end
            if p.fragile then
                d.condition = Delivery.condition ~= nil and Delivery.condition or 100
            end
        else
            d.state = 'drive'
            d.line = L('hud_take')
        end
    end
    return d
end

Delivery.updateHud = function()
    SendNUIMessage({ action = 'hud', data = hudData() })
end

-- ── Blips / GPS ───────────────────────────────────────────────────────────
local function makeBlip(c, sprite, color, label, route)
    local b = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(b, sprite)
    SetBlipColour(b, color)
    if route then SetBlipRoute(b, true) SetBlipRouteColour(b, color) end
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(b)
    return b
end

Delivery.syncBlips = function()
    local S = Delivery.S
    local key = S and ('%s:%s:%s'):format(S.stage, S.index, S.total) or 'none'
    if key == Delivery._blipKey then return end
    Delivery._blipKey = key
    for _, b in ipairs(Delivery.blips) do RemoveBlip(b) end
    Delivery.blips = {}
    if not S then return end

    if S.stage == 'loading' then
        local d = Config.Job.depot.coords
        Delivery.blips[#Delivery.blips + 1] = makeBlip(vector3(d.x, d.y, d.z), 478, 5, L('blip_depot'), true)
    elseif S.stage == 'driving' and S.stop then
        Delivery.blips[#Delivery.blips + 1] = makeBlip(vector3(S.stop.x, S.stop.y, S.stop.z), 1, 5, L('blip_stop'), true)
        for i = S.index + 1, S.total do
            local st = S.stops and S.stops[i]
            if st then
                local b = makeBlip(vector3(st.x, st.y, st.z), 478, 25, st.label, false)
                SetBlipScale(b, 0.6)
                SetBlipAsShortRange(b, true)
                SetBlipNumber(b, i)
                Delivery.blips[#Delivery.blips + 1] = b
            end
        end
    elseif S.stage == 'done' then
        local d = Config.Job.depot.coords
        Delivery.blips[#Delivery.blips + 1] = makeBlip(vector3(d.x, d.y, d.z), 478, 5, L('blip_depot'), true)
    end
end

-- ── Van targets ───────────────────────────────────────────────────────────
local function atRear(veh)
    local o = Config.Delivery.rearOffset
    local rear = GetOffsetFromEntityInWorldCoords(veh, o.x, o.y, o.z)
    return #(GetEntityCoords(cache.ped) - rear) <= Config.Delivery.takeDistance
end

local function openVanDoors()
    local veh = Core:GetWorkVehicle()
    if veh then
        for _, d in ipairs(Config.Delivery.rearDoors) do SetVehicleDoorOpen(veh, d, false, false) end
    end
end

local function closeVanDoors()
    local veh = Core:GetWorkVehicle()
    if veh then
        for _, d in ipairs(Config.Delivery.rearDoors) do SetVehicleDoorShut(veh, d, false) end
    end
end
Delivery.closeVanDoors = closeVanDoors

Delivery.takeParcel = function()
    if Delivery.carrying then return false, L('already_carrying') end
    if not Delivery.S or Delivery.S.stage ~= 'driving' then return false end
    local ok, info = lib.callback.await('baasha_delivery:takeParcel', false)
    if not ok then
        if info then notify(info, 'error') end
        return false, info
    end
    openVanDoors()
    Delivery.startCarry(info)
    -- Grab and shut: never drive off with the cargo doors swinging open
    SetTimeout(Config.Delivery.doorCloseDelay, function()
        if Delivery.S and Delivery.S.stage == 'driving' then closeVanDoors() end
    end)
    return true, info
end

Delivery.stowReturn = function()
    if not Delivery.carrying or not Delivery.returning then return false end
    local ok, err = lib.callback.await('baasha_delivery:stowReturn', false)
    if not ok then
        if err then notify(err, 'error') end
        return false, err
    end
    Delivery.stopCarry(false)
    closeVanDoors()
    return true
end

Delivery.finishRoute = function()
    local ok, result = lib.callback.await('baasha_delivery:finishRoute', false)
    if not ok then
        if result then notify(result, 'error') end
        return false, result
    end
    if type(result) == 'table' then
        notify(L('route_finished', result.total), 'success')
    end
    closeVanDoors()
    return true, result
end

-- ── Loading (at the back of the van, parked at the depot) ─────────────────
Delivery.startLoading = function()
    if not Delivery.S or Delivery.S.stage ~= 'loading' then return false end
    openVanDoors()
    if Config.Loading.mode == 'quick' then
        if not lib.progressBar({
            duration = Config.Loading.quickTime, label = L('loading_progress'), canCancel = true,
            disable = { move = true, car = true, combat = true },
            anim = { dict = 'anim@heists@box_carry@', clip = 'idle' },
        }) then return false end
        local ok, result = lib.callback.await('baasha_delivery:loadDone', false, nil)
        if not ok then
            if result then notify(result, 'error') end
            return false, result
        end
        notify(L('packed_score', result.score), 'success')
        return true, result
    end
    return Delivery.openLoading()
end

local function addTruckTargets(veh)
    Bridge.AddTargetEntity(veh, {
        {
            name = 'baasha_delivery_load', label = L('open_loading'), icon = 'fa-solid fa-boxes-stacked', distance = 6.0,
            canInteract = function() return not Delivery.carrying and Delivery.S and Delivery.S.stage == 'loading' and atRear(veh) end,
            onSelect = function() Delivery.startLoading() end,
        },
        {
            name = 'baasha_delivery_take', label = L('take_parcel'), icon = 'fa-solid fa-box-open', distance = 6.0,
            canInteract = function() return not Delivery.carrying and Delivery.S and Delivery.S.stage == 'driving' and Delivery.S.parcelsLeft > 0 and atRear(veh) end,
            onSelect = function() Delivery.takeParcel() end,
        },
        {
            name = 'baasha_delivery_stow', label = L('stow_return'), icon = 'fa-solid fa-box-archive', distance = 6.0,
            canInteract = function() return Delivery.carrying and Delivery.returning and atRear(veh) end,
            onSelect = function() Delivery.stowReturn() end,
        },
        {
            name = 'baasha_delivery_finish', label = L('finish_route'), icon = 'fa-solid fa-flag-checkered', distance = 6.0,
            canInteract = function() return not Delivery.carrying and Delivery.S and Delivery.S.stage == 'done' end,
            onSelect = function() Delivery.finishRoute() end,
        },
    })
end

local function removeTruckTargets()
    if Delivery.truck then
        Bridge.RemoveTargetEntity(Delivery.truck, { 'baasha_delivery_load', 'baasha_delivery_take', 'baasha_delivery_stow', 'baasha_delivery_finish' })
    end
    Delivery.truck = nil
end

-- The van's entity handle changes when it leaves and re-enters scope, so keep re-attaching.
local function watchTruck()
    CreateThread(function()
        while Delivery.onShift do
            local veh = Core:GetWorkVehicle()
            if veh ~= Delivery.truck then
                removeTruckTargets()
                if veh then Delivery.truck = veh addTruckTargets(veh) end
            end
            Wait(1000)
        end
        removeTruckTargets()
    end)
end

-- ── State / lifecycle ─────────────────────────────────────────────────────
Delivery.syncState = function(state)
    if Delivery.S and Delivery.S.stage == 'loading' and state.stage == 'driving' then closeVanDoors() end
    Delivery.S = state
    if state.msg then notify(state.msg, 'inform') end
    if state.stage == 'loading' or state.stage == 'done' then
        -- not while a put-down / hand-over animation is still using the box
        if Delivery.carrying and (Delivery.animHold or 0) < GetGameTimer() then Delivery.stopCarry(false) end
    end
    Delivery.syncStop()
    Delivery.syncBlips()
    Delivery.updateHud()
end

Delivery.startShiftClient = function()
    Delivery.hudLoop()
    watchTruck()
    Delivery.startFragileSampling()
    Delivery.startDoorLoop()
end

Delivery.hudLoop = function()
    CreateThread(function()
        local hintAt = 0
        while Delivery.onShift do
            if GetGameTimer() > hintAt then
                Delivery.tabletHint = Core:TabletHint()
                hintAt = GetGameTimer() + 5000
            end
            Delivery.updateHud()
            Wait(250)
        end
        Delivery.updateHud()
    end)
end

Delivery.clearBlips = function()
    for _, b in ipairs(Delivery.blips) do RemoveBlip(b) end
    Delivery.blips = {}
end

local function cleanup()
    Delivery.onShift = false
    Delivery.stopCarry(false)
    Delivery.clearDoor()
    Delivery.clearBlips()
    removeTruckTargets()
    Delivery.S = nil
    Delivery._blipKey = nil
    Delivery.carrying = false
    Delivery.carryParcel = nil
    Delivery.returning = false
    Delivery.condition = nil
    Delivery.expressDeadline = nil
    Delivery.updateHud()
    Delivery.closeLoading()
    Delivery.closeSignature()
    Delivery.hideRating()
    SetNuiFocus(false, false)
end
Delivery.cleanup = cleanup

-- ── Events ────────────────────────────────────────────────────────────────
RegisterNetEvent('baasha_jobcore:client:shiftStarted', function(jobId)
    if jobId ~= JOB or Delivery.onShift then return end
    Delivery.onShift = true
    Delivery.startShiftClient()
end)

RegisterNetEvent('baasha_jobcore:client:shiftEnded', function(jobId)
    if jobId == JOB and Delivery.onShift then Delivery.cleanup() end
end)

RegisterNetEvent('baasha_delivery:client:state', function(state)
    if not Delivery.onShift then
        Delivery.onShift = true
        Delivery.startShiftClient()
    end
    Delivery.syncState(state)
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then Delivery.cleanup() end
end)

-- ── Automation hooks (test / showcase tools). The server still validates everything. ──
exports('GetState', function()
    if not Delivery.S then return nil end
    local copy = {}
    for k, v in pairs(Delivery.S) do copy[k] = v end
    copy.carrying = Delivery.carrying
    copy.returning = Delivery.returning
    copy.parcel = Delivery.carryParcel and Delivery.carryParcel.type or nil
    return copy
end)
exports('GetStops', function() return Config.Stops end)
exports('OpenLoading', function() return Delivery.openLoading() end)
exports('AutoLoad', function(animated) return Delivery.autoLoad(animated) end)
exports('TakeParcel', function() return Delivery.takeParcel() end)
exports('DeliverParcel', function() return Delivery.deliverParcel() end)
exports('DropParcel', function() return Delivery.stopCarry(true) end)
exports('StowReturn', function() return Delivery.stowReturn() end)
exports('FinishRoute', function() return Delivery.finishRoute() end)
exports('GetCarry', function()
    if not Delivery.carrying then return nil end
    return { model = Delivery.carryModel, dict = Delivery.carryDict, anim = Delivery.carryAnim, bone = Delivery.carryBone, pos = Delivery.carryPos, rot = Delivery.carryRot }
end)
