-- ── Baasha Delivery — Carry ──────────────────────────────────────────────
-- Box carry, hand truck, dropping, and fragile-damage sampling.

Delivery = Delivery or {}

local CARRY_DICT = 'anim@heists@box_carry@'
local CARRY_ANIM = 'idle'

Delivery.carryDict = CARRY_DICT
Delivery.carryAnim = CARRY_ANIM
Delivery.carryBone = Config.Carry.bone
Delivery.carryPos  = Config.Carry.pos
Delivery.carryRot  = Config.Carry.rot
Delivery.carryModel = nil
Delivery.carryObj = nil
Delivery.handTruckObj = nil
Delivery.handTruckMode = false

local function deleteObject(obj)
    if obj and DoesEntityExist(obj) then
        SetEntityAsMissionEntity(obj, true, true)
        DetachEntity(obj, true, false)
        DeleteEntity(obj)
    end
end

local function carryModel(p)
    local list
    if p.heavy then list = Config.Carry.models.large
    elseif (p.size or 2) >= 4 then list = Config.Carry.models.medium
    else list = Config.Carry.models.small end
    for _, m in ipairs(list or {}) do
        if IsModelInCdimage(joaat(m)) then return m end
    end
    return 'prop_cs_cardbox_01'
end

local function reportImpact(value)
    if not Delivery.carrying or not Delivery.carryParcel or not Delivery.carryParcel.fragile then return end
    -- async: the carry loop runs every frame and must not wait on the server
    lib.callback('baasha_delivery:reportImpact', false, function(ok, cond)
        if ok and cond ~= nil and Delivery.carryParcel then
            Delivery.condition = cond
            Delivery.carryParcel.condition = cond
            Delivery.updateHud()
        end
    end, value)
end

Delivery.clearCarryState = function()
    Delivery.carrying = false
    Delivery.carryParcel = nil
    Delivery.returning = false
    Delivery.condition = nil
    Delivery.expressDeadline = nil
    Delivery.carryModel = nil
    Delivery.handTruckMode = false
    deleteObject(Delivery.handTruckObj)
    Delivery.handTruckObj = nil
end

Delivery.startCarry = function(p)
    if Delivery.carrying then Delivery.stopCarry(false) end
    Delivery.carrying = true
    Delivery.carryParcel = p
    Delivery.returning = false
    Delivery.condition = p.fragile and (p.condition or 100) or nil
    Delivery.expressDeadline = p.express and (GetGameTimer() + (p.expressSeconds or 0) * 1000) or nil

    local ped = cache.ped
    lib.requestAnimDict(CARRY_DICT)

    local model = carryModel(p)
    lib.requestModel(model)
    local obj = CreateObject(model, 0.0, 0.0, 0.0, true, true, false)
    SetModelAsNoLongerNeeded(model)
    Delivery.carryObj = obj
    Delivery.carryModel = model
    local c = Config.Carry
    AttachEntityToEntity(obj, ped, GetPedBoneIndex(ped, c.bone), c.pos.x, c.pos.y, c.pos.z, c.rot.x, c.rot.y, c.rot.z, true, true, false, true, 1, true)

    -- Level 7+: heavy parcels ride on a hand truck (push walk, no jump).
    if p.handTruck then
        Delivery.handTruckMode = true
        local htModel = Config.Carry.handTruckModel
        lib.requestModel(htModel)
        local ht = CreateObject(htModel, 0.0, 0.0, 0.0, true, true, false)
        SetModelAsNoLongerNeeded(htModel)
        Delivery.handTruckObj = ht
        local o = Config.Carry.handTruckOffset
        AttachEntityToEntity(ht, ped, GetPedBoneIndex(ped, 0), o.x, o.y, o.z, 0.0, 0.0, 90.0, true, true, false, true, 1, true)
        AttachEntityToEntity(obj, ht, 0, 0.0, 0.35, 0.45, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
    end

    Delivery.updateHud()
    Delivery.syncDoorZone()

    CreateThread(function()
        local lastHeld = GetGameTimer()
        local lastSpeed = GetEntitySpeed(ped)
        local wasRagdoll = false
        local sprintAcc = 0
        while Delivery.carrying do
            ped = cache.ped
            local now = GetGameTimer()

            if (Delivery.animHold or 0) > now or IsEntityPlayingAnim(ped, CARRY_DICT, CARRY_ANIM, 3) then
                lastHeld = now   -- animHold: knock / hand-over anims play without the carry pose fighting them
            elseif now - lastHeld > 750 then
                Delivery.stopCarry(true)
                Delivery.notify(L('dropped_parcel'), 'error')
                break
            else
                TaskPlayAnim(ped, CARRY_DICT, CARRY_ANIM, 6.0, -6.0, -1, 49, 0, false, false, false)
            end

            DisableControlAction(0, 21, true)  -- sprint
            DisableControlAction(0, 22, true)  -- jump
            DisableControlAction(0, 23, true)  -- enter vehicle
            DisableControlAction(0, 24, true)  -- attack
            DisableControlAction(0, 25, true)  -- aim

            -- Fragile: hard impacts / sprint / ragdoll (measured client-side, clamped server-side)
            if Delivery.carryParcel and Delivery.carryParcel.fragile then
                local speed = GetEntitySpeed(ped)
                if lastSpeed - speed > Config.Fragile.impactSpeed then
                    reportImpact(Config.Fragile.impactLoss)
                end
                lastSpeed = speed

                local ragdoll = IsPedRagdoll(ped)
                if ragdoll and not wasRagdoll then
                    reportImpact(Config.Fragile.ragdollLoss)
                end
                wasRagdoll = ragdoll

                if IsControlPressed(0, 21) then
                    sprintAcc = sprintAcc + 1
                    if sprintAcc >= 60 then  -- ~1s at 60fps; clamped server-side anyway
                        reportImpact(Config.Fragile.sprintLossPerSec)
                        sprintAcc = 0
                    end
                else
                    sprintAcc = 0
                end
            end

            if IsControlJustPressed(0, 47) or IsPedDeadOrDying(ped, true) or IsPedInAnyVehicle(ped, false) then
                Delivery.stopCarry(true)
            end
            Wait(0)
        end
    end)
end

--- Drops the box (G key / DropParcel export): returns it to the van, minus fragile condition.
Delivery.stopCarry = function(drop)
    if not Delivery.carrying then return end
    StopAnimTask(cache.ped, CARRY_DICT, CARRY_ANIM, 1.0)
    deleteObject(Delivery.carryObj)
    Delivery.carryObj = nil
    Delivery.clearCarryState()
    Delivery.updateHud()
    Delivery.syncDoorZone()
    if drop then lib.callback.await('baasha_delivery:dropParcel', false) end
end

--- Successful leave-at-door: place the box on the ground and fade it out later.
--- glideMs: instead of popping onto the ground, the box is detached right away and slides from the hands
--- to its resting spot over glideMs (matching the put-down animation), so it never clips through the body.
Delivery.finishCarry = function(glideMs)
    if not Delivery.carrying then return end
    local ped = cache.ped
    local obj = Delivery.carryObj
    Delivery.carryObj = nil
    if obj and DoesEntityExist(obj) then
        local fromPos, fromRot = GetEntityCoords(obj), GetEntityRotation(obj, 2)
        DetachEntity(obj, true, false)
        FreezeEntityPosition(obj, true)
        SetEntityNoCollisionEntity(obj, ped, false)

        -- Resting spot in front of the courier, never at their own position (they'd end up standing on it)
        local spot = GetOffsetFromEntityInWorldCoords(ped, 0.0, Config.Delivery.dropAhead, 0.0)
        local feet = GetEntityCoords(ped).z - 1.0
        local found, z = GetGroundZFor_3dCoord(spot.x, spot.y, spot.z + 0.5, false)
        if not found or math.abs(z - feet) > 1.0 then z = feet end   -- a step or a drop in front: keep it level with the feet
        SetEntityCoords(obj, spot.x, spot.y, z, false, false, false, false)
        SetEntityHeading(obj, GetEntityHeading(ped))
        PlaceObjectOnGroundProperly(obj)
        local toPos, toRot = GetEntityCoords(obj), GetEntityRotation(obj, 2)

        if glideMs and glideMs > 0 then
            -- same frame as the measuring above, so the test placement is never drawn
            SetEntityCoordsNoOffset(obj, fromPos.x, fromPos.y, fromPos.z, false, false, false)
            SetEntityRotation(obj, fromRot.x, fromRot.y, fromRot.z, 2, false)
            local function angle(a, b, t) return a + ((((b - a) + 180.0) % 360.0) - 180.0) * t end
            local t0 = GetGameTimer()
            while true do
                local t = math.min(1.0, (GetGameTimer() - t0) / glideMs)
                local e = t * t * (3.0 - 2.0 * t)   -- smoothstep
                local p = fromPos + (toPos - fromPos) * e
                SetEntityCoordsNoOffset(obj, p.x, p.y, p.z, false, false, false)
                SetEntityRotation(obj, angle(fromRot.x, toRot.x, e), angle(fromRot.y, toRot.y, e), angle(fromRot.z, toRot.z, e), 2, false)
                if t >= 1.0 then break end
                Wait(0)
            end
        end
        SetTimeout(60000, function() deleteObject(obj) end)
    end
    StopAnimTask(ped, CARRY_DICT, CARRY_ANIM, 1.0)
    Delivery.clearCarryState()
    Delivery.updateHud()
    Delivery.syncDoorZone()
end

--- Hands the box over to the customer (signature flow).
Delivery.handOverBox = function(customer)
    StopAnimTask(cache.ped, CARRY_DICT, CARRY_ANIM, 1.0)
    local obj = Delivery.carryObj
    Delivery.carryObj = nil
    if obj and DoesEntityExist(obj) and customer and DoesEntityExist(customer) then
        DetachEntity(obj, true, false)
        AttachEntityToEntity(obj, customer, GetPedBoneIndex(customer, 57005), 0.1, 0.0, -0.05, 220.0, 120.0, 0.0, true, true, false, true, 1, true)
        SetTimeout(1500, function() deleteObject(obj) end)
    else
        deleteObject(obj)
    end
    Delivery.clearCarryState()
    Delivery.updateHud()
    Delivery.syncDoorZone()
end

-- ── Fragile: van body-health damage while the parcel is still in the van ──
Delivery.startFragileSampling = function()
    CreateThread(function()
        local lastHealth = nil
        local acc = 0
        while Delivery.onShift do
            local veh = Core:GetWorkVehicle()
            if veh then
                local health = GetVehicleBodyHealth(veh)
                if lastHealth then
                    local delta = lastHealth - health
                    if delta > 0 then
                        acc = acc + delta
                        if acc >= Config.Fragile.vanDamageReport then
                            local loss = math.floor(acc * Config.Fragile.vanDamageScale)
                            acc = 0
                            -- only the driver reports, so a 2-player crew doesn't count the same crash twice
                            if loss > 0 and GetPedInVehicleSeat(veh, -1) == cache.ped then
                                lib.callback('baasha_delivery:reportVanDamage', false, function() end, loss)
                            end
                        end
                    end
                end
                lastHealth = health
            else
                lastHealth, acc = nil, 0
            end
            Wait(500)
        end
    end)
end
