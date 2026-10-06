-- ── Baasha Garbage — Client ──────────────────────────────────────────────

local JOB = 'garbage'
local Core = exports.baasha_jobcore

local S = nil              -- latest route state from the server
local onShift = false
local bags = {}            -- slot -> local bag prop
local stopPoint, stopBlip, stopKey = nil, nil, nil
local truck = nil          -- truck entity we put targets on
local carrying, carryObj = false, nil
local hudText = nil

local BAG_GROUND = `prop_rub_binbag_01`
local BAG_HAND   = `prop_cs_rub_binbag_01`
local ANIM_DICT  = 'missfbi4prepp1'

local function notify(msg, type) lib.notify({ title = Config.Job.label, description = msg, type = type or 'inform' }) end

-- ── HUD ───────────────────────────────────────────────────────────────────
local function updateHud()
    local text
    if S then
        if S.done then text = L('hud_return')
        elseif S.inTruck >= S.capacity then text = L('hud_full')
        else text = L('hud_stop', S.index, S.total, S.bagsLeft, S.inTruck, S.capacity) end
        if carrying then text = text .. '  \n' .. L('drop_hint') end
    end
    if text == hudText then return end
    hudText = text
    if text then lib.showTextUI(text, { position = 'left-center', icon = 'trash-can' }) else lib.hideTextUI() end
end

-- ── Bags at the stop (local props, spawned only when nearby) ─────────────
local function bagSlotCoords(stop, slot, stopId)
    local col, row = (slot - 1) % 3, math.floor((slot - 1) / 3)
    local spot = stopId and Config.BagSpots and Config.BagSpots[stopId]
    if spot then
        -- Hand-placed spot: a small group centred on it, trusted as-is
        local ox, oy = col * 0.7 - 0.7, row * 0.7 - 0.35
        local h = math.rad(spot.w)
        return vector3(spot.x + ox * math.cos(h) - oy * math.sin(h), spot.y + ox * math.sin(h) + oy * math.cos(h), spot.z)
    end
    local ox, oy = col * 0.7 - 0.7, -1.3 - row * 0.7
    local h = math.rad(stop.w)
    local x = stop.x + ox * math.cos(h) - oy * math.sin(h)
    local y = stop.y + ox * math.sin(h) + oy * math.cos(h)
    local raw = vector3(x, y, stop.z)
    -- Snap to the nearest spot a ped can walk to, so bags never end up on props, planters or walls
    local found, safe = GetSafeCoordForPed(x, y, stop.z + 1.0, false, 16)
    if found and #(vector2(safe.x, safe.y) - vector2(x, y)) < 4.0 then return safe end
    return raw
end

local function deleteBag(slot)
    local obj = bags[slot]
    if not obj then return end
    Bridge.RemoveTargetEntity(obj, { 'baasha_garbage_pickup' })
    if DoesEntityExist(obj) then DeleteEntity(obj) end
    bags[slot] = nil
end

local function clearBags()
    for slot in pairs(bags) do deleteBag(slot) end
end

local startCarry -- forward declaration

local function pickupBag(slot)
    local ok, err = lib.callback.await('baasha_garbage:pickup', false)
    if not ok then if err then notify(err, 'error') end return false, err end
    -- Bend down and grab it: the bag swaps from the ground to the hand at the low point of the animation
    lib.requestAnimDict('pickup_object')
    TaskPlayAnim(cache.ped, 'pickup_object', 'pickup_low', 8.0, -8.0, 1000, 0, 0, false, false, false)
    Wait(550)
    deleteBag(slot)
    startCarry()
    return true
end

local function spawnBag(slot)
    local c = bagSlotCoords(S.stop, slot, S.stopId)
    lib.requestModel(BAG_GROUND)
    local obj = CreateObject(BAG_GROUND, c.x, c.y, c.z, false, false, false)
    SetModelAsNoLongerNeeded(BAG_GROUND)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    bags[slot] = obj
    Bridge.AddTargetEntity(obj, {
        {
            name = 'baasha_garbage_pickup', label = L('pickup_bag'), icon = 'fa-solid fa-trash', distance = 2.0,
            canInteract = function() return not carrying end,
            onSelect = function() pickupBag(slot) end,
        },
    })
end

local function syncBags()
    if not S or S.done or not stopPoint or not stopPoint.inside then clearBags() return end
    local count = 0
    for _ in pairs(bags) do count = count + 1 end
    -- Too many (a crewmate picked one up): remove from the highest slot
    for slot = 12, 1, -1 do
        if count <= S.bagsLeft then break end
        if bags[slot] then deleteBag(slot) count = count - 1 end
    end
    -- Too few (a bag was dropped back): fill the first free slots
    for slot = 1, 12 do
        if count >= S.bagsLeft then break end
        if not bags[slot] then spawnBag(slot) count = count + 1 end
    end
end

-- ── Stop / depot blip + proximity point ──────────────────────────────────
local function clearStop()
    clearBags()
    if stopPoint then stopPoint:remove() stopPoint = nil end
    if stopBlip then RemoveBlip(stopBlip) stopBlip = nil end
    stopKey = nil
end

local function setBlip(coords, sprite, color, label)
    stopBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(stopBlip, sprite)
    SetBlipColour(stopBlip, color)
    SetBlipRoute(stopBlip, true)
    SetBlipRouteColour(stopBlip, color)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(stopBlip)
end

local function syncStop()
    -- Key on the stop's location too: a forced route can keep the same index/total but move the stop
    local key = S and (S.done and 'depot' or ('%s:%s:%.1f:%.1f'):format(S.index, S.total, S.stop.x, S.stop.y)) or nil
    if key ~= stopKey then
        clearStop()
        stopKey = key
        if S and S.done then
            setBlip(Config.Job.depot.coords, 318, 25, L('blip_depot'))
        elseif S then
            setBlip(S.stop, 318, 5, L('blip_stop'))
            stopPoint = lib.points.new({
                coords = vector3(S.stop.x, S.stop.y, S.stop.z),
                distance = 60.0,
                onEnter = syncBags,
                onExit = clearBags,
            })
        end
    end
    syncBags()
end

-- ── Carrying a bag ────────────────────────────────────────────────────────
local function deleteObject(obj)
    if obj and DoesEntityExist(obj) then
        SetEntityAsMissionEntity(obj, true, true)
        DetachEntity(obj, true, false)
        DeleteEntity(obj)
    end
end

local function removeHandBag()
    deleteObject(carryObj)
    carryObj = nil
end

local function stopCarry(dropToServer)
    if not carrying then return end
    carrying = false
    StopAnimTask(cache.ped, ANIM_DICT, '_bag_walk_garbage_man', 1.0)
    removeHandBag()
    updateHud()
    if dropToServer then lib.callback.await('baasha_garbage:drop', false) end
end

startCarry = function()
    carrying = true
    local ped = cache.ped
    lib.requestAnimDict(ANIM_DICT)
    lib.requestModel(BAG_HAND)
    carryObj = CreateObject(BAG_HAND, 0.0, 0.0, 0.0, true, true, false)
    SetModelAsNoLongerNeeded(BAG_HAND)
    local c = Config.Carry
    AttachEntityToEntity(carryObj, ped, GetPedBoneIndex(ped, c.bone), c.pos.x, c.pos.y, c.pos.z, c.rot.x, c.rot.y, c.rot.z, true, true, false, true, 1, true)
    updateHud()

    CreateThread(function()
        local lastHeld = GetGameTimer()
        while carrying do
            ped = cache.ped
            if IsEntityPlayingAnim(ped, ANIM_DICT, '_bag_walk_garbage_man', 3) or IsEntityPlayingAnim(ped, ANIM_DICT, '_bag_throw_garbage_man', 3) then
                lastHeld = GetGameTimer()
            elseif GetGameTimer() - lastHeld > 750 then
                -- Another animation took the arms (hands up, emote, phone…): drop the bag instead of waving it around
                stopCarry(true)
                notify(L('dropped_bag'), 'error')
                break
            else
                TaskPlayAnim(ped, ANIM_DICT, '_bag_walk_garbage_man', 6.0, -6.0, -1, 49, 0, false, false, false)
            end
            DisableControlAction(0, 21, true)  -- sprint
            DisableControlAction(0, 22, true)  -- jump
            DisableControlAction(0, 23, true)  -- enter vehicle
            DisableControlAction(0, 24, true)  -- attack
            DisableControlAction(0, 25, true)  -- aim
            if IsControlJustPressed(0, 47) or IsPedDeadOrDying(ped, true) or IsPedInAnyVehicle(ped, false) then
                stopCarry(true)
            end
            Wait(0)
        end
    end)
end

-- ── Truck targets ─────────────────────────────────────────────────────────
local function atRear(veh)
    local rear = GetOffsetFromEntityInWorldCoords(veh, 0.0, -4.5, 0.0)
    return #(GetEntityCoords(cache.ped) - rear) <= Config.Route.RearDistance
end

local function throwBag()
    local ok, result = lib.callback.await('baasha_garbage:throw', false)
    if not ok then if result then notify(result, 'error') end return false, result end
    carrying = false
    TaskPlayAnim(cache.ped, ANIM_DICT, '_bag_throw_garbage_man', 8.0, 8.0, 1100, 48, 0.0, false, false, false)
    -- Delete THIS bag after the throw anim, even if a new one is picked up before the timer fires
    local thrown = carryObj
    carryObj = nil
    SetTimeout(700, function() deleteObject(thrown) end)
    for _, f in ipairs(result or {}) do
        notify(L('found_item', f.count, (f.item:gsub('^%l', string.upper))), 'success')
    end
    updateHud()
    return true, result
end

local function runCompactor()
    if not lib.callback.await('baasha_garbage:compactStart', false) then return false end
    if not lib.progressBar({
        duration = Config.Route.CompactTime, label = L('compacting'), canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'mini@repair', clip = 'fixing_a_ped' },
    }) then return false end
    return lib.callback.await('baasha_garbage:compact', false)
end

local function finishRoute()
    local ok, err = lib.callback.await('baasha_garbage:finish', false)
    if not ok and err then notify(err, 'error') end
    return ok, err
end

local function addTruckTargets(veh)
    Bridge.AddTargetEntity(veh, {
        {
            name = 'baasha_garbage_throw', label = L('throw_bag'), icon = 'fa-solid fa-dumpster', distance = 6.0,
            canInteract = function(ent) return carrying and atRear(ent) end,
            onSelect = function() throwBag() end,
        },
        {
            name = 'baasha_garbage_compact', label = L('compact'), icon = 'fa-solid fa-compress', distance = 6.0,
            canInteract = function(ent) return not carrying and S and S.inTruck > 0 and atRear(ent) end,
            onSelect = function() runCompactor() end,
        },
        {
            name = 'baasha_garbage_finish', label = L('finish_route'), icon = 'fa-solid fa-flag-checkered', distance = 6.0,
            canInteract = function() return not carrying and S and S.done end,
            onSelect = function() finishRoute() end,
        },
    })
end

local function removeTruckTargets()
    if truck then Bridge.RemoveTargetEntity(truck, { 'baasha_garbage_throw', 'baasha_garbage_compact', 'baasha_garbage_finish' }) end
    truck = nil
end

-- The truck's entity handle changes when it leaves and re-enters our scope, so keep re-attaching
local function watchTruck()
    CreateThread(function()
        while onShift do
            local veh = Core:GetWorkVehicle()
            if veh ~= truck then
                removeTruckTargets()
                if veh then truck = veh addTruckTargets(veh) end
            end
            Wait(1000)
        end
        removeTruckTargets()
    end)
end

-- ── Events ────────────────────────────────────────────────────────────────
RegisterNetEvent('baasha_jobcore:client:shiftStarted', function(jobId)
    if jobId ~= JOB or onShift then return end
    onShift = true
    watchTruck()
end)

RegisterNetEvent('baasha_garbage:client:state', function(state)
    if not onShift then
        onShift = true
        watchTruck()
    end
    S = state
    if S.msg then notify(S.msg, 'inform') end
    syncStop()
    updateHud()
end)

local function cleanup()
    onShift = false
    stopCarry(false)
    clearStop()
    removeTruckTargets()
    S = nil
    updateHud()
end

RegisterNetEvent('baasha_jobcore:client:shiftEnded', function(jobId)
    if jobId == JOB then cleanup() end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then cleanup() end
end)

-- ── Automation hooks (test / showcase tools). The server still validates everything. ──
exports('GetState', function()
    if not S then return nil end
    local copy = {}
    for k, v in pairs(S) do copy[k] = v end
    copy.carrying = carrying
    return copy
end)

exports('GetBags', function()
    local list = {}
    for slot, obj in pairs(bags) do
        if DoesEntityExist(obj) then list[#list + 1] = { slot = slot, coords = GetEntityCoords(obj) } end
    end
    table.sort(list, function(a, b) return a.slot < b.slot end)
    return list
end)

exports('PickupBag', function(slot)
    if not slot then slot = next(bags) end
    if not slot or not bags[slot] then return false, 'no bag spawned' end
    return pickupBag(slot)
end)
exports('ThrowBag', throwBag)
exports('GetCarry', function() return { model = 'prop_cs_rub_binbag_01', dict = ANIM_DICT, anim = '_bag_walk_garbage_man', bone = Config.Carry.bone, pos = Config.Carry.pos, rot = Config.Carry.rot } end)
exports('RunCompactor', runCompactor)
exports('FinishRoute', finishRoute)
exports('DropBag', function() stopCarry(true) end)
exports('GetStops', function() return Config.Stops end)
