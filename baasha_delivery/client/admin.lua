-- ── Baasha Delivery — Admin (client) ─────────────────────────────────────
-- /deliveryspot records the player's position (server writes stops_recorded.lua),
-- /deliveryspots toggles debug markers for every configured stop.

Delivery = Delivery or {}

local JOB = 'delivery'

RegisterCommand('deliveryspot', function(_, args)
    local spotType = args[1] or 'house'
    if spotType ~= 'house' and spotType ~= 'business' then
        lib.notify({ title = Config.Job.label, description = L('admin_badtype'), type = 'error' })
        return
    end
    table.remove(args, 1)
    local label = table.concat(args, ' ')
    if label == '' then label = ('Recorded %s'):format(spotType) end

    local ped = cache.ped
    local c = GetEntityCoords(ped)
    -- Stand at the door FACING it: stops store that heading (pointing into the house)
    local door = { x = c.x, y = c.y, z = c.z, w = GetEntityHeading(ped) }

    local van = nil
    local veh = GetLastDrivenVehicle()
    if veh and veh ~= 0 and DoesEntityExist(veh) then
        local v = GetEntityCoords(veh)
        van = { x = v.x, y = v.y, z = v.z }
    end

    local ok, msg = lib.callback.await('baasha_delivery:recordStop', false, { type = spotType, label = label, door = door, van = van })
    lib.notify({ title = Config.Job.label, description = msg, type = ok and 'success' or 'error' })
end, false)

TriggerEvent('chat:addSuggestion', '/deliveryspot', L('admin_spot_help'))

local debugSpots = false

RegisterCommand('deliveryspots', function()
    debugSpots = not debugSpots
    lib.notify({ title = Config.Job.label, description = debugSpots and L('admin_debug_on') or L('admin_debug_off'), type = 'inform' })
end, false)

TriggerEvent('chat:addSuggestion', '/deliveryspots', 'Toggle delivery stop markers')

CreateThread(function()
    while true do
        if debugSpots then
            for _, s in ipairs(Config.Stops) do
                local d = s.door
                if #(GetEntityCoords(cache.ped) - vector3(d.x, d.y, d.z)) < 80.0 then
                    DrawMarker(1, d.x, d.y, d.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.7, 0.7, 0.5,
                        0, 255, 0, 200, true, true, 2, false, nil, nil, false)
                end
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)
