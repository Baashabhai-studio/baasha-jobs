-- ── Baasha Fishing — Client ──────────────────────────────────────────────

local JOB = 'fishing'
local Core = exports.baasha_jobcore

local onShift = false
local state = 'idle'          -- idle | waiting | bite | reeling
local blips = {}
local hudText = nil
local cooler = { count = 0, value = 0 }
local autoReel = false        -- showcase tools let the minigame play itself
local lastCatch = nil

local function notify(msg, type) lib.notify({ title = Config.Job.label, description = msg, type = type or 'inform' }) end

local history = {}
local function setState(new, why)
    state = new
    history[#history + 1] = why and ('%s(%s)'):format(new, why) or new
    if #history > 12 then table.remove(history, 1) end
    if Config.Debug then print(('[baasha_fishing] state -> %s %s'):format(new, why or '')) end
end

-- ── HUD ───────────────────────────────────────────────────────────────────
local function setHud(text)
    if text == hudText then return end
    hudText = text
    if text then lib.showTextUI(text, { position = 'left-center', icon = 'fish' }) else lib.hideTextUI() end
end

local function refreshCooler()
    cooler = lib.callback.await('baasha_fishing:cooler', false) or cooler
end

-- ── Where am I? (mirrors the server's check, just for the HUD hint) ──────
local function dist(a, b) return #(vector3(a.x, a.y, a.z) - vector3(b.x, b.y, b.z)) end

local function myBoat()
    local here = GetEntityCoords(cache.ped)
    for _, r in ipairs(Core:GetRentedVehicles()) do
        if GetVehicleClass(r.entity) == 14 and #(GetEntityCoords(r.entity) - here) < 8.0 then return r end
    end
end

local function currentSpot()
    local here = GetEntityCoords(cache.ped)
    local boat = myBoat()
    if boat then
        local far = dist(here, Config.Job.depot.coords) >= Config.DeepSea.minDistance
        for _, s in ipairs(Config.Spots) do
            if dist(here, s.coords) < Config.DeepSea.minDistance then far = false break end
        end
        if far then return { label = Config.DeepSea.label, deep = true }, boat end
    end
    for _, s in ipairs(Config.Spots) do
        if dist(here, s.coords) <= s.radius then return s, boat end
    end
    return nil, boat
end

--- Is there water in front of the player? Probes ahead and steeply down (piers stand ~8m above
--- the sea, so a shallow probe can end above the waves), straight and slightly left/right.
local function facingWater()
    local ped = cache.ped
    local from = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.5, 0.8)
    for _, side in ipairs({ 0.0, -7.0, 7.0 }) do
        local to = GetOffsetFromEntityInWorldCoords(ped, side, 20.0, -25.0)
        if TestProbeAgainstWater(from.x, from.y, from.z, to.x, to.y, to.z) then return true end
    end
    return false
end

-- ── Fishing flow ──────────────────────────────────────────────────────────
local RODS = { [`prop_fishing_rod_01`] = true, [`prop_fishing_rod_02`] = true }

local SCENARIO = 'WORLD_HUMAN_STAND_FISHING'
local inPose = false

--- The fishing scenario brings its own rod and DROPS it on the ground when it ends.
--- Remove rods still in the hand, and rods left lying next to the player.
local function removeRods()
    local ped = cache.ped
    local here = GetEntityCoords(ped)
    for _, obj in ipairs(GetGamePool('CObject')) do
        if RODS[GetEntityModel(obj)] then
            local inHand = IsEntityAttachedToEntity(obj, ped)
            local dropped = not IsEntityAttached(obj) and #(GetEntityCoords(obj) - here) < 5.0
            if inHand or dropped then
                SetEntityAsMissionEntity(obj, true, true)
                DetachEntity(obj, true, false)
                DeleteEntity(obj)
            end
        end
    end
end

local function stopFishingAnim()
    if not inPose then return end
    inPose = false
    ClearPedTasks(cache.ped)
    -- the scenario's exit animation drops the rod: clean it up once it has
    SetTimeout(1500, removeRods)
end

local function resetLine(msg, type, why, keepPose)
    setState('idle', why)
    SendNUIMessage({ action = 'hideBite' })
    if not keepPose then stopFishingAnim() end
    if msg then notify(msg, type) end
end

local function refuse(why, msg)
    history[#history + 1] = ('cast refused (%s)'):format(why)
    if msg then notify(msg, 'error') end
    return false, why
end

local function cast()
    if state ~= 'idle' then return refuse('busy: ' .. state) end
    local ped = cache.ped
    if IsPedInAnyVehicle(ped, false) then return refuse('in a vehicle seat', L('in_vehicle')) end
    local spot, boat = currentSpot()
    if not spot then return refuse('not at a spot', L('not_spot')) end
    if not spot.deep and not facingWater() then return refuse('no water ahead', L('no_water')) end

    if not (inPose and IsPedUsingScenario(ped, SCENARIO)) then
        removeRods()
        TaskStartScenarioInPlace(ped, SCENARIO, 0, true)
        inPose = true
    end
    setState('waiting', 'cast')
    local ok, err, drop = lib.callback.await('baasha_fishing:cast', false, boat and boat.netId or nil)
    if not ok then resetLine(err, 'error', 'cast rejected') return false end
    if drop then
        -- Deep Drop: let the cast animation play, then the line goes in
        setState('dropping', drop.spot)
        SetTimeout(1200, function()
            if state ~= 'dropping' then return end
            drop.auto = autoReel
            if not autoReel then SetNuiFocus(true, true) end
            SendNUIMessage({ action = 'drop', data = drop })
        end)
    end
    return true
end

RegisterNUICallback('dropDone', function(body, cb)
    cb(1)
    SetNuiFocus(false, false)
    if state ~= 'dropping' then return end
    if body.aborted then
        lib.callback.await('baasha_fishing:cancel', false)
        resetLine(nil, nil, 'drop aborted', true)
        return
    end
    local ok, result = lib.callback.await('baasha_fishing:dropDone', false, body)
    if ok and type(result) == 'table' then
        SendNUIMessage({ action = 'dropResult', data = result })
        local best
        for _, c in ipairs(result.catches) do
            if not best or c.value > best.value then best = c end
        end
        -- lastCatch: the best fish of this drop (+ all of them), false when nothing came up
        -- (a plain copy: exports can't carry metatables to other resources)
        if best then
            lastCatch = { all = result.catches }
            for k, v in pairs(best) do lastCatch[k] = v end
        else
            lastCatch = false
        end
        if best then PlaySoundFrontend(-1, 'PICK_UP', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true) end
        refreshCooler()
        resetLine(not best and L('drop_empty') or nil, 'inform', ('landed %d'):format(#result.catches), true)
    else
        lastCatch = false
        SendNUIMessage({ action = 'stopDrop' })
        resetLine(L('snapped'), 'error', 'drop rejected', true)
    end
end)

local function hook()
    if state ~= 'bite' then return false end
    local params = lib.callback.await('baasha_fishing:hook', false)
    if not params then resetLine(L('escaped'), 'error', 'hook rejected') return false end
    setState('reeling', params.rarity)
    params.auto = autoReel
    if not autoReel then SetNuiFocus(true, false) end
    SendNUIMessage({ action = 'reel', data = params })
    return true
end

RegisterNUICallback('reelSound', function(body, cb)
    cb(1)
    PlaySoundFrontend(-1, body.hit and 'SELECT' or 'ERROR', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
end)

RegisterNUICallback('reelDone', function(body, cb)
    cb(1)
    SetNuiFocus(false, false)
    if state ~= 'reeling' then return end
    local ok, result = lib.callback.await('baasha_fishing:land', false, body.success == true)
    if ok and type(result) == 'table' then
        lastCatch = result
        SendNUIMessage({ action = 'catch', data = result })
        PlaySoundFrontend(-1, 'PICK_UP', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
        refreshCooler()
        resetLine(result.junk and L('junk', result.label) or nil, 'inform', 'landed', true)
    else
        lastCatch = false
        resetLine(L('snapped'), 'error', body.success and 'land rejected' or 'line snapped', true)
    end
end)

RegisterNetEvent('baasha_fishing:client:bite', function()
    if state ~= 'waiting' then
        history[#history + 1] = ('bite ignored (state %s)'):format(state)
        return
    end
    setState('bite')
    PlaySoundFrontend(-1, 'Beep_Red', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', true)
    SendNUIMessage({ action = 'bite', seconds = Config.BiteWindow })
    if autoReel then SetTimeout(500, hook) end
end)

RegisterNetEvent('baasha_fishing:client:escaped', function()
    if state == 'bite' or state == 'waiting' then resetLine(L('escaped'), 'error', 'escaped') end
end)

-- ── Main loop: HUD + keys ─────────────────────────────────────────────────
local tabletHint

local function mainLoop()
    CreateThread(function()
        local hintAt = 0
        while onShift do
            local sleep = 250
            local ped = cache.ped
            -- "[J] Job tablet · End shift" (re-read now and then, in case the player rebinds the key)
            if GetGameTimer() > hintAt then
                tabletHint, hintAt = Core:TabletHint(), GetGameTimer() + 5000
            end
            if state == 'idle' then
                if inPose and not IsPedUsingScenario(ped, SCENARIO) then
                    inPose = false
                    SetTimeout(1500, removeRods)
                end
                local spot, boat = currentSpot()
                local line = L('hud_idle', cooler.count, cooler.value)
                if spot and not IsPedInAnyVehicle(ped, false) then
                    line = line .. '  \n' .. L('hud_cast', spot.label)
                    sleep = 0
                    if IsControlJustPressed(0, Config.CastKey) then cast() end
                elseif boat then
                    line = line .. '  \n' .. L('hud_deep')
                end
                -- Still holding the rod between catches: X puts it away
                if inPose then
                    line = line .. '  \n' .. L('hud_stop')
                    sleep = 0
                    if IsControlJustPressed(0, Config.CancelKey) then stopFishingAnim() end
                end
                if tabletHint then line = line .. '  \n' .. tabletHint end
                setHud(line)
            elseif state == 'waiting' then
                setHud(L('hud_waiting'))
                sleep = 0
                -- Reel in on X, or if the player walks away
                local cancelled = IsControlJustPressed(0, Config.CancelKey)
                local walkedOff = GetEntitySpeed(ped) > 2.5
                if cancelled or walkedOff then
                    lib.callback.await('baasha_fishing:cancel', false)
                    resetLine(nil, nil, cancelled and 'cancel key' or 'moved')
                end
            elseif state == 'bite' then
                sleep = 0
                if IsControlJustPressed(0, Config.CastKey) then hook() end
            elseif state == 'dropping' then
                setHud(nil) -- the Deep Drop panel has its own HUD
            end
            Wait(sleep)
        end
        setHud(nil)
    end)
end

-- ── Map + market ──────────────────────────────────────────────────────────
local function addBlip(c, sprite, color, label, scale)
    local b = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(b, sprite)
    SetBlipColour(b, color)
    SetBlipScale(b, scale or 0.75)
    SetBlipAsShortRange(b, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(b)
    blips[#blips + 1] = b
end

local function rentBoat()
    local netId, err = lib.callback.await('baasha_fishing:rentBoat', false)
    if not netId then if err then notify(err, 'error') end return false end
    notify(L('boat_rented'), 'success')
    return netId
end

local function returnBoat()
    -- By net id: the boat may be out of this client's streaming range; the server knows where it is
    local netId = Core:GetRentalNetIds()[1]
    if not netId then return false end
    local ok = lib.callback.await('baasha_fishing:returnBoat', false, netId)
    if ok then notify(L('boat_returned'), 'success') end
    return ok
end

local function sell()
    local ok, msg = lib.callback.await('baasha_fishing:sell', false)
    notify(msg, ok and 'success' or 'error')
    refreshCooler()
    return ok
end

local openMarket -- defined below with the Fish Market screen

-- ── Market sign: floating marker + label over the worker, so players find the menu ──
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

if Config.MarketSign then
    CreateThread(function()
        local d, m = Config.Job.depot.coords, Config.Market.coords
        local worker = vector3(d.x, d.y, d.z - 1.0)   -- depot coords are player height, the worker stands on the ground
        local counter = vector3(m.x, m.y, m.z)
        while true do
            local sleep = 1000
            -- before a shift: the worker (start the job) · during a shift: the market counter
            local at = onShift and counter or worker
            local dist = #(GetEntityCoords(cache.ped) - at)
            if dist < Config.MarketSign.distance and not IsPauseMenuActive() then
                sleep = 0
                if onShift then
                    DrawMarker(29, at.x, at.y, at.z + 2.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.5, 0.5,
                        234, 179, 8, 210, true, true, 2, true, nil, nil, false)
                else
                    DrawMarker(0, at.x, at.y, at.z + 2.4, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 0.3, 0.3,
                        234, 179, 8, 210, true, true, 2, false, nil, nil, false)
                end
                if dist < Config.MarketSign.textDistance then
                    local title = onShift and L('sign_market') or L('sign_job')
                    local sub = onShift and L('sign_market_sub') or L('sign_job_sub')
                    local top = onShift and 2.6 or 2.95
                    drawText3D(at + vector3(0.0, 0.0, top), title, 0.5, { 234, 179, 8 })
                    drawText3D(at + vector3(0.0, 0.0, top - 0.15), sub, 0.32, { 255, 255, 255 })
                end
            end
            Wait(sleep)
        end
    end)
end

local function setupWorld()
    for _, s in ipairs(Config.Spots) do addBlip(s.coords, 68, 3, ('%s · %s'):format(L('blip_spot'), s.label)) end
    local m = Config.Market.coords
    Bridge.AddTargetZone('baasha_fishing_market', vector3(m.x, m.y, m.z + 1.1), vector3(2.2, 1.8, 2.4), m.w, {
        { name = 'baasha_fishing_market', label = L('open_market'), icon = 'fa-solid fa-store', distance = 3.0,
          canInteract = function() return onShift end, onSelect = function() openMarket() end },
    })
end

-- ── Fish Market screen ────────────────────────────────────────────────────
local function marketData()
    local data = lib.callback.await('baasha_fishing:market', false)
    if data then data.boatRented = #Core:GetRentalNetIds() > 0 end
    return data
end

openMarket = function()
    local data = marketData()
    if not data then notify(L('too_far'), 'error') return false end
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'market', data = data })
    return true
end

local function closeMarket()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeMarket' })
end

RegisterNUICallback('marketClose', function(_, cb) SetNuiFocus(false, false) cb(1) end)

-- Each button runs the action, then sends the refreshed market back to the screen
RegisterNUICallback('marketSell', function(_, cb) sell() cb(marketData() or {}) end)
RegisterNUICallback('marketRent', function(_, cb)
    if rentBoat() then closeMarket() cb({}) return end -- go to the boat right away
    cb(marketData() or {})
end)
RegisterNUICallback('marketReturn', function(_, cb) returnBoat() cb(marketData() or {}) end)

local function cleanupWorld()
    for _, b in ipairs(blips) do RemoveBlip(b) end
    blips = {}
    Bridge.RemoveTargetZone('baasha_fishing_market')
end

-- ── Shift events ──────────────────────────────────────────────────────────
RegisterNetEvent('baasha_jobcore:client:shiftStarted', function(jobId)
    if jobId ~= JOB or onShift then return end
    onShift = true
    setState('idle', 'shift start')
    refreshCooler()
    setupWorld()
    mainLoop()
end)

local function cleanup()
    SendNUIMessage({ action = 'closeMarket' })
    SetNuiFocus(false, false)
    if state == 'reeling' then SendNUIMessage({ action = 'stopReel' }) end
    if state == 'dropping' then SendNUIMessage({ action = 'stopDrop' }) end
    if state ~= 'idle' then lib.callback.await('baasha_fishing:cancel', false) end
    onShift = false
    resetLine()
    cleanupWorld()
    setHud(nil)
end

RegisterNetEvent('baasha_jobcore:client:shiftEnded', function(jobId)
    if jobId == JOB and onShift then cleanup() end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and onShift then
        SetNuiFocus(false, false)
        lib.hideTextUI()
        cleanupWorld()
    end
end)

-- ── Automation hooks (test / showcase tools). The server still validates everything. ──
exports('GetState', function() return { state = state, onShift = onShift, cooler = cooler, lastCatch = lastCatch, history = table.concat(history, ' > ') } end)
exports('ClearHistory', function() history = {} lastCatch = nil end)
exports('Cast', cast)
exports('Hook', hook)
exports('SetAutoReel', function(on) autoReel = on == true end)
exports('Sell', sell)
exports('OpenMarket', function() return openMarket() end)
exports('SetMarketTab', function(tab, scrollMs) SendNUIMessage({ action = 'marketTab', tab = tab, scroll = scrollMs }) end)
exports('PutAwayRod', function() stopFishingAnim() end)
exports('PressMarketButton', function(act) SendNUIMessage({ action = 'marketPress', act = act }) end)
exports('CloseMarket', function() closeMarket() end)
exports('RentBoat', rentBoat)
exports('ReturnBoat', returnBoat)
exports('GetSpots', function() return Config.Spots end)
exports('CurrentSpot', function() local s = currentSpot() return s and s.label or nil end)
