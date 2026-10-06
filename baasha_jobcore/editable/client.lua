-- ── Editable client hooks ────────────────────────────────────────────────
-- Change these to match your server's notify / fuel / vehicle keys scripts.

Editable = {}

function Editable.Notify(msg, type)
    lib.notify({ title = 'Job Center', description = msg, type = type or 'inform' })
end

--- Called on every crew member when the work vehicle spawns.
function Editable.GiveVehicleKeys(vehicle, plate)
    if GetResourceState('qb-vehiclekeys') == 'started' then
        TriggerEvent('vehiclekeys:client:SetOwner', plate)
    elseif GetResourceState('qbx_vehiclekeys') == 'started' then
        TriggerServerEvent('qb-vehiclekeys:server:AcquireVehicleKeys', plate)
    elseif GetResourceState('wasabi_carlock') == 'started' then
        exports.wasabi_carlock:GiveKey(plate)
    end
end

function Editable.SetFuel(vehicle, amount)
    if GetResourceState('LegacyFuel') == 'started' then
        exports.LegacyFuel:SetFuel(vehicle, amount)
    elseif GetResourceState('ox_fuel') == 'started' then
        Entity(vehicle).state.fuel = amount
    elseif GetResourceState('cdn-fuel') == 'started' then
        exports['cdn-fuel']:SetFuel(vehicle, amount)
    else
        SetVehicleFuelLevel(vehicle, amount + 0.0)
    end
end

--- Called when a shift starts / ends for this player.
function Editable.OnShiftStart(jobId) end
function Editable.OnShiftEnd(jobId) end
