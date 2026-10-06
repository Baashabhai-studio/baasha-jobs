-- ── Baasha Job Core — Server Bridge ──────────────────────────────────────
-- One Bridge table for every framework. Open file: edit freely if your
-- server uses a custom framework or inventory.

Bridge = {}

local function started(res)
    local state = GetResourceState(res)
    return state == 'started' or state == 'starting'
end

local function detect(setting, options)
    if setting ~= 'auto' then return setting end
    for _, opt in ipairs(options) do
        if started(opt[1]) then return opt[2] end
    end
end

Bridge.Framework = detect(Config.Framework, { { 'qbx_core', 'qbox' }, { 'qb-core', 'qbcore' }, { 'es_extended', 'esx' } })
Bridge.Inventory = detect(Config.Inventory, { { 'ox_inventory', 'ox_inventory' }, { 'qb-inventory', 'qb-inventory' }, { 'es_extended', 'esx' } })

if not Bridge.Framework then
    print('^1[baasha_jobcore] No supported framework found (qbx_core / qb-core / es_extended).^7')
end

-- ── Framework objects (lazy, survives restarts) ──────────────────────────
local QBCore, ESX
local function QB()
    if not QBCore then QBCore = exports['qb-core']:GetCoreObject() end
    return QBCore
end
local function EX()
    if not ESX then ESX = exports['es_extended']:getSharedObject() end
    return ESX
end

local function getPlayer(src)
    if Bridge.Framework == 'qbox' then return exports.qbx_core:GetPlayer(src) end
    if Bridge.Framework == 'qbcore' then return QB().Functions.GetPlayer(src) end
    if Bridge.Framework == 'esx' then return EX().GetPlayerFromId(src) end
end

local function esxAccount(account)
    return account == 'cash' and 'money' or account
end

-- ── Player ────────────────────────────────────────────────────────────────
function Bridge.GetIdentifier(src)
    local p = getPlayer(src)
    if not p then return nil end
    if Bridge.Framework == 'esx' then return p.identifier end
    return p.PlayerData.citizenid
end

function Bridge.GetName(src)
    local p = getPlayer(src)
    if not p then return GetPlayerName(src) or ('Player ' .. src) end
    if Bridge.Framework == 'esx' then return p.getName() end
    local info = p.PlayerData.charinfo
    return ('%s %s'):format(info.firstname, info.lastname)
end

-- ── Money ─────────────────────────────────────────────────────────────────
function Bridge.GetMoney(src, account)
    local p = getPlayer(src)
    if not p then return 0 end
    if Bridge.Framework == 'esx' then
        local acc = p.getAccount(esxAccount(account))
        return acc and acc.money or 0
    end
    return p.PlayerData.money[account] or 0
end

function Bridge.AddMoney(src, account, amount, reason)
    if amount <= 0 then return end
    if Bridge.Framework == 'qbox' then
        exports.qbx_core:AddMoney(src, account, amount, reason)
    elseif Bridge.Framework == 'qbcore' then
        local p = getPlayer(src)
        if p then p.Functions.AddMoney(account, amount, reason) end
    elseif Bridge.Framework == 'esx' then
        local p = getPlayer(src)
        if p then p.addAccountMoney(esxAccount(account), amount, reason) end
    end
end

--- Removes money only if the player can afford it. Returns true on success.
function Bridge.RemoveMoney(src, account, amount, reason)
    if amount <= 0 then return true end
    if Bridge.GetMoney(src, account) < amount then return false end
    if Bridge.Framework == 'qbox' then
        return exports.qbx_core:RemoveMoney(src, account, amount, reason)
    elseif Bridge.Framework == 'qbcore' then
        local p = getPlayer(src)
        return p and p.Functions.RemoveMoney(account, amount, reason) or false
    elseif Bridge.Framework == 'esx' then
        local p = getPlayer(src)
        if not p then return false end
        p.removeAccountMoney(esxAccount(account), amount, reason)
        return true
    end
    return false
end

-- ── Items ─────────────────────────────────────────────────────────────────
function Bridge.ItemExists(item)
    if Bridge.Inventory == 'ox_inventory' then return exports.ox_inventory:Items(item) ~= nil end
    if Bridge.Framework == 'qbcore' then return QB().Shared.Items[item] ~= nil end
    if Bridge.Framework == 'esx' then return EX().GetItemLabel(item) ~= nil end
    return false
end

--- Gives an item. Returns false if the item doesn't exist or doesn't fit.
function Bridge.AddItem(src, item, count)
    if not Bridge.ItemExists(item) then return false end
    if Bridge.Inventory == 'ox_inventory' then
        if not exports.ox_inventory:CanCarryItem(src, item, count) then return false end
        return exports.ox_inventory:AddItem(src, item, count) and true or false
    end
    local p = getPlayer(src)
    if not p then return false end
    if Bridge.Framework == 'qbcore' then
        local ok = p.Functions.AddItem(item, count)
        if ok then TriggerClientEvent('qb-inventory:client:ItemBox', src, QB().Shared.Items[item], 'add', count) end
        return ok
    elseif Bridge.Framework == 'esx' then
        if p.canCarryItem and not p.canCarryItem(item, count) then return false end
        p.addInventoryItem(item, count)
        return true
    end
    return false
end

-- ── Character logout (multicharacter) ────────────────────────────────────
function Bridge.OnPlayerUnload(cb)
    AddEventHandler('playerDropped', function() cb(source) end)
    if Bridge.Framework == 'qbcore' or Bridge.Framework == 'qbox' then
        AddEventHandler('QBCore:Server:OnPlayerUnload', function(src) cb(src) end)
    elseif Bridge.Framework == 'esx' then
        AddEventHandler('esx:playerLogout', function(src) cb(src) end)
    end
end
