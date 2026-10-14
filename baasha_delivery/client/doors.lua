-- ── Baasha Delivery — Doors ──────────────────────────────────────────────
-- Door marker + target, leave-at-door, ring-doorbell, customer ped, signature flow.

Delivery = Delivery or {}

local DOOR_ZONE = 'baasha_delivery_door'
local doorZoneAdded = false
local customerPed = nil

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

-- ── Door target zone (rebuilt whenever the stop or the carry state changes) ──
Delivery.syncDoorZone = function()
    if doorZoneAdded then
        Bridge.RemoveTargetZone(DOOR_ZONE)
        doorZoneAdded = false
    end
    local S = Delivery.S
    if not S or S.stage ~= 'driving' or not S.stop then return end
    local c = S.stop
    local label = L('no_parcel')
    if Delivery.carrying and Delivery.carryParcel and not Delivery.returning then
        if Delivery.carryParcel.type == 'signature' then
            label = L('ring_doorbell')
        else
            label = L('leave_door')
        end
    end
    Bridge.AddTargetZone(DOOR_ZONE, vector3(c.x, c.y, c.z), vector3(1.6, 1.6, 2.4), c.w, {
        {
            name = 'baasha_delivery_door', label = label, icon = 'fa-solid fa-door-open', distance = 2.2,
            canInteract = function()
                if not Delivery.carrying or not Delivery.carryParcel or Delivery.returning then return false end
                local p = GetEntityCoords(cache.ped)
                return math.abs(p.z - c.z) <= Config.Delivery.doorHeight and #(vector2(p.x, p.y) - vector2(c.x, c.y)) <= Config.Delivery.doorDistance
            end,
            onSelect = function() Delivery.deliverParcel() end,
        },
    })
    doorZoneAdded = true
end

Delivery.syncStop = function()
    Delivery.syncDoorZone()
end

Delivery.clearDoor = function()
    if doorZoneAdded then
        Bridge.RemoveTargetZone(DOOR_ZONE)
        doorZoneAdded = false
    end
    if customerPed and DoesEntityExist(customerPed) then DeleteEntity(customerPed) end
    customerPed = nil
end

-- ── Ground marker + floating address label ────────────────────────────────
Delivery.startDoorLoop = function()
    CreateThread(function()
        while Delivery.onShift do
            local S = Delivery.S
            if S and S.stage == 'driving' and S.stop and not IsPauseMenuActive() then
                local c = vector3(S.stop.x, S.stop.y, S.stop.z)
                if #(GetEntityCoords(cache.ped) - c) < 25.0 then
                    DrawMarker(1, c.x, c.y, c.z - 0.9, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.6, 0.6, 0.5,
                        245, 179, 1, 200, true, true, 2, false, nil, nil, false)
                    drawText3D(vector3(c.x, c.y, c.z + 1.0), S.stopLabel or '', 0.4, { 245, 179, 1 })
                    Wait(0)
                else
                    Wait(250)
                end
            else
                Wait(500)
            end
        end
    end)
end

-- ── Deliver at the door (dispatches by parcel type) ───────────────────────
Delivery.deliverParcel = function()
    if not Delivery.carrying or not Delivery.carryParcel then return false end
    if Delivery.carryParcel.type == 'signature' then
        if Delivery.returning then return false end
        return Delivery.ringDoorbell()
    end
    return Delivery.leaveAtDoor()
end

Delivery.leaveAtDoor = function()
    local door = Delivery.S and Delivery.S.stop   -- read now: the server moves the route on when it accepts
    -- Server first: a wrong door / too far away never plays the put-down
    Delivery.animHold = GetGameTimer() + 5000      -- keeps the box in hand if the route update arrives first
    local ok, result = lib.callback.await('baasha_delivery:deliver', false)
    if not ok then
        Delivery.animHold = 0
        if result then Delivery.notify(result, 'error') end
        return false, result
    end

    local ped = cache.ped
    if door then SetEntityHeading(ped, door.w) end   -- face the door, so the box lands in front of it
    lib.requestAnimDict('pickup_object')
    Delivery.animHold = GetGameTimer() + Config.Delivery.placeTime + 500
    ClearPedTasks(ped)
    TaskPlayAnim(ped, 'pickup_object', 'putdown_low', 4.0, -4.0, Config.Delivery.placeTime, 0, 0, false, false, false)
    Delivery.finishCarry(Config.Delivery.releaseAt)   -- box slides down with the hands and lands as they reach the ground
    Wait(math.max(0, Config.Delivery.placeTime - Config.Delivery.releaseAt))
    Delivery.animHold = 0
    Delivery.showRating(result)
    return true, result
end

-- ── Signature ─────────────────────────────────────────────────────────────
-- Unit vector pointing out of the house. Door spots face the door (into the house), so it's the reverse.
local function outDir(door)
    local r = math.rad(door.w or 0.0)
    return vector3(math.sin(r), -math.cos(r), 0.0)
end

Delivery.ringDoorbell = function()
    -- Step up to the door and face it, so the customer hand-over lines up
    local door = Delivery.S and Delivery.S.stop
    if door then
        local spot = vector3(door.x, door.y, door.z) + outDir(door) * Config.Signature.courierGap
        local face = door.w   -- facing the door
        TaskGoStraightToCoord(cache.ped, spot.x, spot.y, spot.z, 1.0, 2500, face, 0.15)
        local t = GetGameTimer() + 2500
        while GetGameTimer() < t and #(GetEntityCoords(cache.ped).xy - spot.xy) > 0.3 do Wait(50) end
        SetEntityHeading(cache.ped, face)
    end
    lib.requestAnimDict('timetable@jimmy@doorknock@')
    Delivery.animHold = GetGameTimer() + 2300
    TaskPlayAnim(cache.ped, 'timetable@jimmy@doorknock@', 'knockdoor_idle', 8.0, -8.0, 2200, 0, 0, false, false, false)

    local ok, result = lib.callback.await('baasha_delivery:ring', false)
    if not ok then
        if result then Delivery.notify(result, 'error') end
        return false, result
    end

    if not result.home then
        Wait(1200)
        Delivery.returning = true
        Delivery.updateHud()
        Delivery.syncDoorZone()
        local ok2, card = lib.callback.await('baasha_delivery:missed', false)
        if ok2 then Delivery.showRating(card) end
        Delivery.notify(L('nobody_home'), 'inform')
        return true
    end

    return Delivery.signatureFlow(result)
end

Delivery.signatureFlow = function(result)
    local p = Delivery.carryParcel
    local label = '#' .. p.id
    local ped = cache.ped
    local door = Delivery.S.stop

    Wait(math.random(Config.Signature.ringDelay[1], Config.Signature.ringDelay[2]))
    if not Delivery.carrying then return false end

    -- door.w faces the door, and the door spot is only ~half a metre from the door itself. The customer
    -- "opens up" right on the doorstep (fading in, facing the courier) instead of walking through a wall.
    local out = outDir(door)
    local base = vector3(door.x, door.y, door.z - 0.98)       -- door spots are recorded at standing-ped height
    local threshold = base - out * Config.Signature.handoverGap

    lib.requestModel(result.model)
    customerPed = CreatePed(4, result.model, threshold.x, threshold.y, threshold.z, (door.w + 180.0) % 360.0, false, true)
    SetModelAsNoLongerNeeded(result.model)
    SetEntityInvincible(customerPed, true)
    SetBlockingOfNonTemporaryEvents(customerPed, true)
    FreezeEntityPosition(customerPed, true)
    SetEntityAlpha(customerPed, 0, false)
    for a = 0, 255, 17 do SetEntityAlpha(customerPed, a, false) Wait(30) end
    ResetEntityAlpha(customerPed)
    Wait(400)

    lib.requestAnimDict('mp_common')
    Delivery.animHold = GetGameTimer() + 2600
    TaskPlayAnim(ped, 'mp_common', 'givetake1_a', 8.0, -8.0, 2500, 0, 0, false, false, false)
    TaskPlayAnim(customerPed, 'mp_common', 'givetake1_b', 8.0, -8.0, 2500, 0, 0, false, false, false)
    Wait(2000)

    Delivery.handOverBox(customerPed)
    Delivery.openSignature({ label = label, customer = result.customer })
    return true
end

Delivery.despawnCustomer = function()
    local ped = customerPed
    customerPed = nil
    if not ped or not DoesEntityExist(ped) then return end
    -- Turn back to the door and fade out ("goes back inside"); the door is right behind them, so no walking.
    CreateThread(function()
        SetEntityHeading(ped, (GetEntityHeading(ped) + 180.0) % 360.0)
        Wait(500)
        for a = 255, 0, -15 do
            if not DoesEntityExist(ped) then return end
            SetEntityAlpha(ped, a, false)
            Wait(40)
        end
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end)
end
