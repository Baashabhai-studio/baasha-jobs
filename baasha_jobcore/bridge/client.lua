-- ── Baasha Job Core — Client Bridge ──────────────────────────────────────
-- Target abstraction (ox_target / qb-target). Open file: edit freely.

Bridge = {}

local function started(res)
    local state = GetResourceState(res)
    return state == 'started' or state == 'starting'
end

-- Job resources include this file too ('@baasha_jobcore/bridge/client.lua'), so Config.Target may be nil there
local targetRes = Config.Target
if not targetRes or targetRes == 'auto' then
    targetRes = started('ox_target') and 'ox_target' or started('qb-target') and 'qb-target' or nil
end
Bridge.TargetResource = targetRes

if not targetRes then
    print('^1[baasha_jobcore] No target resource found (ox_target / qb-target).^7')
end

-- options: { { name, label, icon, distance, onSelect = function(entity), canInteract = function(entity) } }
local labelsByEntity = {}

function Bridge.AddTargetEntity(entity, options)
    if targetRes == 'ox_target' then
        local ox = {}
        for i, o in ipairs(options) do
            ox[i] = {
                name = o.name, label = o.label, icon = o.icon, distance = o.distance or 2.5,
                onSelect = function(data) o.onSelect(data.entity) end,
                canInteract = o.canInteract and function(ent) return o.canInteract(ent) end or nil,
            }
        end
        exports.ox_target:addLocalEntity(entity, ox)
    elseif targetRes == 'qb-target' then
        local qb, dist = {}, 2.5
        labelsByEntity[entity] = labelsByEntity[entity] or {}
        for i, o in ipairs(options) do
            labelsByEntity[entity][o.name] = o.label
            dist = o.distance or dist
            qb[i] = {
                icon = o.icon, label = o.label,
                action = function(ent) o.onSelect(ent) end,
                canInteract = o.canInteract and function(ent) return o.canInteract(ent) end or nil,
            }
        end
        exports['qb-target']:AddTargetEntity(entity, { options = qb, distance = dist })
    end
end

function Bridge.RemoveTargetEntity(entity, names)
    if targetRes == 'ox_target' then
        exports.ox_target:removeLocalEntity(entity, names)
    elseif targetRes == 'qb-target' then
        local labels = {}
        for _, n in ipairs(names) do
            local l = labelsByEntity[entity] and labelsByEntity[entity][n]
            if l then labels[#labels + 1] = l; labelsByEntity[entity][n] = nil end
        end
        if #labels > 0 then exports['qb-target']:RemoveTargetEntity(entity, labels) end
    end
end

local oxZones = {}

-- size = vec3(length, width, height)
function Bridge.AddTargetZone(name, coords, size, heading, options)
    if targetRes == 'ox_target' then
        local ox = {}
        for i, o in ipairs(options) do
            ox[i] = {
                name = o.name, label = o.label, icon = o.icon, distance = o.distance or 2.5,
                onSelect = function() o.onSelect() end,
                canInteract = o.canInteract and function() return o.canInteract() end or nil,
            }
        end
        oxZones[name] = exports.ox_target:addBoxZone({ coords = coords, size = size, rotation = heading, debug = Config.Debug, options = ox })
    elseif targetRes == 'qb-target' then
        local qb, dist = {}, 2.5
        for i, o in ipairs(options) do
            dist = o.distance or dist
            qb[i] = {
                icon = o.icon, label = o.label,
                action = function() o.onSelect() end,
                canInteract = o.canInteract and function() return o.canInteract() end or nil,
            }
        end
        exports['qb-target']:AddBoxZone(name, coords, size.x, size.y, {
            name = name, heading = heading, debugPoly = Config.Debug,
            minZ = coords.z - size.z / 2, maxZ = coords.z + size.z / 2,
        }, { options = qb, distance = dist })
    end
end

function Bridge.RemoveTargetZone(name)
    if targetRes == 'ox_target' then
        if oxZones[name] then exports.ox_target:removeZone(oxZones[name]); oxZones[name] = nil end
    elseif targetRes == 'qb-target' then
        exports['qb-target']:RemoveZone(name)
    end
end
