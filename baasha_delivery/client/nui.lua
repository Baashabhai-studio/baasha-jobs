-- ── Baasha Delivery — NUI ────────────────────────────────────────────────
-- Opens/closes the three views and wires the NUI callbacks.

Delivery = Delivery or {}

local JOB = 'delivery'

Delivery._view = nil          -- 'load' | 'sign' (the focus-taking views)
Delivery.signAwaiting = false

local function setFocus(on)
    SetNuiFocus(on, on)
end

local function openFocus(view, data)
    Delivery._view = view
    setFocus(true)
    SendNUIMessage({ action = 'open', view = view, data = data })
end

local function closeFocus(view)
    if Delivery._view ~= view then return end
    Delivery._view = nil
    setFocus(false)
    SendNUIMessage({ action = 'close', view = view })
end

Delivery.openLoading = function()
    if not Delivery.onShift or not Delivery.S or Delivery.S.stage ~= 'loading' then return false end
    if Delivery._view then return false end
    local ok, data = lib.callback.await('baasha_delivery:getManifest', false)
    if not ok then
        if data then Delivery.notify(data, 'error') end
        return false
    end
    openFocus('load', data)
    return true
end

Delivery.closeLoading = function()
    closeFocus('load')
end

Delivery.openSignature = function(data)
    Delivery.signAwaiting = true
    data.padTime = Config.Signature.padTime
    openFocus('sign', data)
end

Delivery.closeSignature = function()
    closeFocus('sign')
end

Delivery.showRating = function(data)
    if not data then return end
    SendNUIMessage({ action = 'open', view = 'rate', data = data })
end

Delivery.hideRating = function()
    SendNUIMessage({ action = 'close', view = 'rate' })
end

--- animated = true while the puzzle is open: the NUI drops the parcels in one by one, then confirms itself.
Delivery.autoLoad = function(animated)
    if not Delivery.onShift or not Delivery.S or Delivery.S.stage ~= 'loading' then return false end
    local ok, placements = lib.callback.await('baasha_delivery:autoPack', false)
    if not ok then return false end
    if animated and Delivery._view == 'load' then
        SendNUIMessage({ action = 'demoPack', placements = placements, delay = 450 })
        local deadline = GetGameTimer() + 20000
        while Delivery.S and Delivery.S.stage == 'loading' and GetGameTimer() < deadline do Wait(100) end
        return Delivery.S ~= nil and Delivery.S.stage == 'driving'
    end
    local ok2, result = lib.callback.await('baasha_delivery:loadDone', false, placements)
    if not ok2 then return false, result end
    Delivery.closeLoading()
    return true, result
end

-- ── NUI callbacks ─────────────────────────────────────────────────────────
local function finishSign()
    Delivery.closeSignature()
    if not Delivery.signAwaiting then return end
    Delivery.signAwaiting = false
    local ok, result = lib.callback.await('baasha_delivery:signDone', false)
    if not ok then return end
    Delivery.showRating(result)
    Delivery.despawnCustomer()
end

RegisterNUICallback('loadDone', function(body, cb)
    cb(1)
    if Delivery._view ~= 'load' then return end
    local placements = body and body.placements
    local ok, result = lib.callback.await('baasha_delivery:loadDone', false, placements)
    if not ok then
        if result then Delivery.notify(result, 'error') end
        SendNUIMessage({ action = 'loadError', msg = result or 'failed' })
        return
    end
    Delivery.closeLoading()
    Delivery.notify(L('packed_score', result.score), 'success')
end)

RegisterNUICallback('autoPack', function(_, cb)
    local ok, placements = lib.callback.await('baasha_delivery:autoPack', false)
    cb({ ok = ok == true, placements = placements })
end)

RegisterNUICallback('signDone', function(_, cb)
    cb(1)
    finishSign()
end)

RegisterNUICallback('close', function(_, cb)
    cb(1)
    if Delivery._view == 'sign' then
        finishSign()          -- ESC on the signature pad = confirm
    elseif Delivery._view == 'load' then
        Delivery.closeLoading()
    end
end)
