-- ── Baasha Job Core — Server ─────────────────────────────────────────────
-- Job registry, crews, shifts, work vehicles, pay, XP and leaderboards.
-- Job resources talk to this through the exports at the bottom of the file.

local Jobs = {}          -- jobId -> definition (from RegisterJob)
local Crews = {}         -- crewId -> crew
local PlayerCrew = {}    -- src -> crewId
local Invites = {}       -- target src -> { crewId, from, expires }
local StatsCache = {}    -- 'identifier:job' -> row
local Identifiers = {}   -- src -> identifier (for cache cleanup)
local nextCrewId = 0

-- ── Helpers ───────────────────────────────────────────────────────────────
local function notify(src, msg, type) Editable.Notify(src, msg, type) end

local function currentWeek() return tonumber(os.date('%Y%W')) end

local function pedCoords(src)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and GetEntityCoords(ped) or nil
end

local function distTo(src, coords)
    local c = pedCoords(src)
    return c and #(c - vector3(coords.x, coords.y, coords.z)) or math.huge
end

local function webhook(title, description, color)
    if Config.Webhook == '' then return end
    PerformHttpRequest(Config.Webhook, function() end, 'POST', json.encode({
        username = 'Baasha Jobs',
        embeds = { { title = title, description = description, color = color or 15844367, footer = { text = 'baashabhai.com' } } },
    }), { ['Content-Type'] = 'application/json' })
end

local function syncJobs()
    local list = {}
    for id, job in pairs(Jobs) do
        list[id] = {
            id = id, label = job.label, icon = job.icon, description = job.description,
            depot = job.depot, maxCrew = job.maxCrew, deposit = job.vehicle and job.vehicle.deposit or 0,
            spawns = job.vehicle and job.vehicle.spawns or {}, uniform = job.uniform, perks = job.perks,
        }
    end
    GlobalState.baasha_jobs = list
end

-- ── Database ──────────────────────────────────────────────────────────────
CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `baasha_job_stats` (
            `identifier` VARCHAR(64) NOT NULL,
            `job` VARCHAR(32) NOT NULL,
            `name` VARCHAR(64) DEFAULT NULL,
            `xp` INT NOT NULL DEFAULT 0,
            `total_earned` INT NOT NULL DEFAULT 0,
            `weekly_earned` INT NOT NULL DEFAULT 0,
            `week` INT NOT NULL DEFAULT 0,
            `tasks` INT NOT NULL DEFAULT 0,
            `shifts` INT NOT NULL DEFAULT 0,
            PRIMARY KEY (`identifier`, `job`)
        )
    ]])
end)

-- cachedOnly: exports can't yield across resources, so they never hit the DB.
-- Stats are loaded for every crew member when a shift starts.
local function getStats(src, jobId, cachedOnly)
    local identifier = Bridge.GetIdentifier(src)
    if not identifier then return nil end
    Identifiers[src] = identifier
    local key = identifier .. ':' .. jobId
    local row = StatsCache[key]
    if not row then
        if cachedOnly then return nil end
        row = MySQL.single.await('SELECT * FROM baasha_job_stats WHERE identifier = ? AND job = ?', { identifier, jobId })
            or { identifier = identifier, job = jobId, xp = 0, total_earned = 0, weekly_earned = 0, week = currentWeek(), tasks = 0, shifts = 0 }
        StatsCache[key] = row
    end
    if row.week ~= currentWeek() then
        row.week, row.weekly_earned = currentWeek(), 0
    end
    row.name = Bridge.GetName(src)
    return row
end

local function saveStats(row)
    MySQL.prepare([[
        INSERT INTO baasha_job_stats (identifier, job, name, xp, total_earned, weekly_earned, week, tasks, shifts)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE name = VALUES(name), xp = VALUES(xp), total_earned = VALUES(total_earned),
            weekly_earned = VALUES(weekly_earned), week = VALUES(week), tasks = VALUES(tasks), shifts = VALUES(shifts)
    ]], { row.identifier, row.job, row.name, row.xp, row.total_earned, row.weekly_earned, row.week, row.tasks, row.shifts })
end

-- ── Crews ─────────────────────────────────────────────────────────────────
local function ensureCrew(src)
    local id = PlayerCrew[src]
    if id and Crews[id] then return Crews[id] end
    nextCrewId = nextCrewId + 1
    local crew = { id = nextCrewId, leader = src, members = { src }, earned = {} }
    Crews[crew.id] = crew
    PlayerCrew[src] = crew.id
    return crew
end

local function crewUpdated(crew)
    for _, m in ipairs(crew.members) do
        TriggerClientEvent('baasha_jobcore:client:crewUpdated', m)
    end
end

local function publicCrew(crew)
    local members = {}
    for i, m in ipairs(crew.members) do members[i] = m end
    return {
        id = crew.id, leader = crew.leader, members = members,
        jobId = crew.jobId, vehicle = crew.vehicle, plate = crew.plate,
    }
end

-- ── Shifts ────────────────────────────────────────────────────────────────
local function endShift(crewId, reason)
    local crew = Crews[crewId]
    if not crew or not crew.jobId then return end
    local job, jobId = Jobs[crew.jobId], crew.jobId

    -- Work vehicle: refund deposit if it's back at the depot
    if crew.vehicle then
        local veh = NetworkGetEntityFromNetworkId(crew.vehicle)
        local payer = GetPlayerName(crew.depositPayer) and crew.depositPayer or crew.leader
        if veh ~= 0 and DoesEntityExist(veh) then
            local depot = job and job.depot.coords
            local atDepot = depot and #(GetEntityCoords(veh) - vector3(depot.x, depot.y, depot.z)) <= Config.ReturnDistance
            if atDepot and (crew.deposit or 0) > 0 then
                local health = Config.DamageRefund and math.max(0.0, math.min(1.0, GetVehicleBodyHealth(veh) / 1000.0)) or 1.0
                local refund = math.floor(crew.deposit * health)
                Bridge.AddMoney(payer, 'bank', refund, 'baasha-job-deposit')
                notify(payer, L('deposit_refund', refund), 'success')
            elseif (crew.deposit or 0) > 0 then
                notify(payer, L('deposit_lost'), 'error')
            end
            DeleteEntity(veh)
        elseif (crew.deposit or 0) > 0 then
            notify(payer, L('deposit_lost'), 'error')
        end
    end

    local summary = {}
    for _, m in ipairs(crew.members) do
        local earned = crew.earned[m] or 0
        TriggerClientEvent('baasha_jobcore:client:shiftEnded', m, jobId, earned)
        notify(m, L('shift_ended', earned), 'inform')
        summary[#summary + 1] = ('%s — $%s'):format(Bridge.GetName(m), earned)
    end

    TriggerEvent('baasha_jobcore:server:shiftEnded', jobId, crewId, reason)
    webhook('Shift ended · ' .. (job and job.label or jobId),
        ('**Reason:** %s\n**Duration:** %s min\n%s'):format(reason or 'finished', math.floor((os.time() - (crew.startedAt or os.time())) / 60), table.concat(summary, '\n')))

    crew.jobId, crew.vehicle, crew.plate, crew.deposit, crew.depositPayer, crew.earned = nil, nil, nil, nil, nil, {}
    crewUpdated(crew)
end

local function startShift(src, jobId, spawnIndex)
    local job = Jobs[jobId]
    if not job then return false, L('job_unavailable') end
    local crew = ensureCrew(src)
    if crew.leader ~= src then return false, L('not_leader') end
    if crew.jobId then return false, L('already_on_shift') end
    if #crew.members > (job.maxCrew or 1) then return false, L('crew_full') end
    if distTo(src, job.depot.coords) > Config.MaxDepotDistance then return false, L('not_near_depot', job.label) end

    -- Deposit (bank first, then cash)
    local deposit = job.vehicle and job.vehicle.deposit or 0
    if deposit > 0 then
        local paid = Bridge.RemoveMoney(src, 'bank', deposit, 'baasha-job-deposit')
            or Bridge.RemoveMoney(src, 'cash', deposit, 'baasha-job-deposit')
        if not paid then return false, L('not_enough_money', deposit) end
        notify(src, L('deposit_paid', deposit), 'inform')
    end

    -- Work vehicle (server-side spawn so every crew member sees the same truck)
    local netId, plate
    if job.vehicle then
        local spot = job.vehicle.spawns[tonumber(spawnIndex) or 1]
        if not spot then
            Bridge.AddMoney(src, 'bank', deposit, 'baasha-job-deposit')
            return false, L('no_spawn_spot')
        end
        local veh = CreateVehicleServerSetter(joaat(job.vehicle.model), job.vehicle.type or 'automobile', spot.x, spot.y, spot.z, spot.w)
        local timeout = GetGameTimer() + 5000
        while not DoesEntityExist(veh) and GetGameTimer() < timeout do Wait(0) end
        if not DoesEntityExist(veh) then
            Bridge.AddMoney(src, 'bank', deposit, 'baasha-job-deposit')
            return false, L('no_spawn_spot')
        end
        plate = ('%s%04d'):format(Config.VehiclePlatePrefix:sub(1, 4), math.random(0, 9999))
        SetVehicleNumberPlateText(veh, plate)
        -- Public flag so other scripts (car theft, impound, garages…) can ignore job vehicles
        Entity(veh).state:set('baashaJobVehicle', jobId, true)
        netId = NetworkGetNetworkIdFromEntity(veh)
    end

    crew.jobId, crew.vehicle, crew.plate = jobId, netId, plate
    crew.deposit, crew.depositPayer = deposit, src
    crew.startedAt, crew.earned, crew.window = os.time(), {}, { start = os.time(), n = 0 }

    for _, m in ipairs(crew.members) do
        local row = getStats(m, jobId)
        if row then row.shifts = row.shifts + 1; saveStats(row) end
        TriggerClientEvent('baasha_jobcore:client:shiftStarted', m, jobId, publicCrew(crew))
        notify(m, L('shift_started', job.label), 'success')
    end

    TriggerEvent('baasha_jobcore:server:shiftStarted', jobId, crew.id, publicCrew(crew))
    crewUpdated(crew)
    return true
end

-- Removes a player from their crew (leave, kick, disconnect)
local function removeFromCrew(src, silent)
    local crewId = PlayerCrew[src]
    local crew = crewId and Crews[crewId]
    PlayerCrew[src] = nil
    if not crew then return end

    if #crew.members == 1 then
        endShift(crew.id, 'left')
        Crews[crew.id] = nil
        return
    end

    for i, m in ipairs(crew.members) do
        if m == src then table.remove(crew.members, i) break end
    end

    if crew.jobId then
        TriggerClientEvent('baasha_jobcore:client:shiftEnded', src, crew.jobId, crew.earned[src] or 0)
        TriggerEvent('baasha_jobcore:server:memberLeft', crew.jobId, crew.id, src)
    end

    local name = Bridge.GetName(src)
    if crew.leader == src then
        crew.leader = crew.members[1]
        for _, m in ipairs(crew.members) do notify(m, L('new_leader', Bridge.GetName(crew.leader)), 'inform') end
    end
    if not silent then
        for _, m in ipairs(crew.members) do notify(m, L('crew_left', name), 'inform') end
    end
    crewUpdated(crew)
    TriggerClientEvent('baasha_jobcore:client:crewUpdated', src)
end

-- ── Pay ───────────────────────────────────────────────────────────────────
local function rateLimited(crew)
    local now = os.time()
    if now - crew.window.start >= 60 then crew.window.start, crew.window.n = now, 0 end
    crew.window.n = crew.window.n + 1
    if crew.window.n > Config.MaxRewardsPerMinute then
        print(('^3[baasha_jobcore] Crew %s (%s) hit the reward rate limit — possible exploit.^7'):format(crew.id, crew.jobId))
        return true
    end
    return false
end

local function payMember(src, crew, amount, xp)
    local row = getStats(src, crew.jobId, true)
    if not row then return end
    local oldLevel = GetLevelFromXp(row.xp)
    amount = math.floor(amount * (1 + (oldLevel - 1) * Config.LevelPayBonus))
    xp = math.floor(xp)

    if amount > 0 then Bridge.AddMoney(src, Config.PayAccount, amount, 'baasha-job-' .. crew.jobId) end
    row.xp = row.xp + xp
    row.total_earned = row.total_earned + amount
    row.weekly_earned = row.weekly_earned + amount
    row.tasks = row.tasks + 1
    saveStats(row)
    crew.earned[src] = (crew.earned[src] or 0) + amount

    local newLevel, from, to = GetLevelFromXp(row.xp)
    TriggerClientEvent('baasha_jobcore:client:paid', src, crew.jobId, amount, xp, newLevel, row.xp, from, to)
    if newLevel > oldLevel then
        notify(src, L('level_up', Jobs[crew.jobId].label, newLevel), 'success')
        Editable.OnLevelUp(src, crew.jobId, newLevel)
    end
    Editable.OnPaid(src, crew.jobId, amount, xp)
end

--- Splits a task reward between the whole crew (with crew bonus).
local function rewardCrew(crewId, amount, xp)
    local crew = Crews[crewId]
    if not crew or not crew.jobId or rateLimited(crew) then return false end
    local n = #crew.members
    local bonus = Config.CrewBonus[n] or 1.0
    for _, m in ipairs(crew.members) do
        payMember(m, crew, amount * bonus / n, (xp or 0) * bonus / n)
    end
    return true
end

--- Pays one crew member for their own task (fishing catch, etc.).
local function rewardPlayer(src, amount, xp)
    local crew = Crews[PlayerCrew[src]]
    if not crew or not crew.jobId or rateLimited(crew) then return false end
    payMember(src, crew, amount, xp or 0)
    return true
end

-- ── Tablet data ───────────────────────────────────────────────────────────
local function tabletData(src)
    local crew = ensureCrew(src)
    local jobs, nearDepot = {}, nil
    for id, job in pairs(Jobs) do
        local row = getStats(src, id) or { xp = 0, total_earned = 0, tasks = 0, shifts = 0 }
        local level, from, to = GetLevelFromXp(row.xp)
        if distTo(src, job.depot.coords) <= Config.MaxDepotDistance then nearDepot = id end
        jobs[#jobs + 1] = {
            id = id, label = job.label, description = job.description, icon = job.icon,
            maxCrew = job.maxCrew, deposit = job.vehicle and job.vehicle.deposit or 0, perks = job.perks,
            level = level, xp = row.xp, levelFrom = from, levelTo = to,
            totalEarned = row.total_earned, tasks = row.tasks, shifts = row.shifts,
        }
    end
    table.sort(jobs, function(a, b) return a.label < b.label end)

    local members = {}
    for _, m in ipairs(crew.members) do members[#members + 1] = { id = m, name = Bridge.GetName(m) } end

    return {
        me = src, jobs = jobs, nearDepot = nearDepot, maxLevel = #Config.Levels,
        crew = { leader = crew.leader, members = members, jobId = crew.jobId, max = Config.MaxCrewSize },
    }
end

local leaderboardCache = {}

-- ── Callbacks (client → server) ───────────────────────────────────────────
lib.callback.register('baasha_jobcore:getTablet', function(src) return tabletData(src) end)

lib.callback.register('baasha_jobcore:startShift', function(src, jobId, spawnIndex)
    return startShift(src, jobId, spawnIndex)
end)

lib.callback.register('baasha_jobcore:endShift', function(src)
    local crew = Crews[PlayerCrew[src]]
    if not crew or not crew.jobId then return false end
    if crew.leader ~= src then return false, L('not_leader') end
    endShift(crew.id, 'ended by leader')
    return true
end)

lib.callback.register('baasha_jobcore:leaveCrew', function(src)
    removeFromCrew(src)
    return true
end)

lib.callback.register('baasha_jobcore:kick', function(src, target)
    target = tonumber(target)
    local crew = Crews[PlayerCrew[src]]
    if not crew or crew.leader ~= src or target == src or PlayerCrew[target] ~= crew.id then return false, L('not_leader') end
    removeFromCrew(target)
    notify(target, L('crew_kicked'), 'error')
    return true
end)

lib.callback.register('baasha_jobcore:invite', function(src, target)
    target = tonumber(target)
    local crew = ensureCrew(src)
    if crew.leader ~= src then return false, L('not_leader') end
    if crew.jobId then return false, L('crew_busy') end
    if #crew.members >= Config.MaxCrewSize then return false, L('crew_full') end
    if not target or not GetPlayerName(target) then return false, L('invite_far') end
    if target == src then return false, L('invite_self') end
    local other = Crews[PlayerCrew[target]]
    if other and (#other.members > 1 or other.jobId) then return false, L('invite_in_crew') end
    local a, b = pedCoords(src), pedCoords(target)
    if not a or not b or #(a - b) > 10.0 then return false, L('invite_far') end

    Invites[target] = { crewId = crew.id, from = src, expires = os.time() + 30 }
    TriggerClientEvent('baasha_jobcore:client:invite', target, Bridge.GetName(src))
    return true, L('invite_sent')
end)

lib.callback.register('baasha_jobcore:respondInvite', function(src, accept)
    local inv = Invites[src]
    Invites[src] = nil
    if not inv or inv.expires < os.time() then return false end
    if not accept then
        notify(inv.from, L('invite_declined', Bridge.GetName(src)), 'error')
        return false
    end
    local crew = Crews[inv.crewId]
    if not crew or crew.jobId or #crew.members >= Config.MaxCrewSize then return false end
    local own = Crews[PlayerCrew[src]]
    if own and (#own.members > 1 or own.jobId) then return false end
    if own then Crews[own.id] = nil end

    crew.members[#crew.members + 1] = src
    PlayerCrew[src] = crew.id
    for _, m in ipairs(crew.members) do notify(m, L('crew_joined', Bridge.GetName(src)), 'success') end
    crewUpdated(crew)
    return true
end)

lib.callback.register('baasha_jobcore:leaderboard', function(_, jobId)
    local cached = leaderboardCache[jobId]
    if cached and cached.at > os.time() - 60 then return cached.rows end
    local rows = MySQL.query.await('SELECT name, weekly_earned, xp FROM baasha_job_stats WHERE job = ? AND week = ? ORDER BY weekly_earned DESC LIMIT ?',
        { jobId, currentWeek(), Config.LeaderboardSize }) or {}
    for _, r in ipairs(rows) do r.level = GetLevelFromXp(r.xp) end
    leaderboardCache[jobId] = { at = os.time(), rows = rows }
    return rows
end)

-- ── Cleanup ───────────────────────────────────────────────────────────────
Bridge.OnPlayerUnload(function(src)
    Invites[src] = nil
    removeFromCrew(src, false)
    local identifier = Identifiers[src]
    if identifier then
        for id in pairs(Jobs) do StatsCache[identifier .. ':' .. id] = nil end
        Identifiers[src] = nil
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        for id in pairs(Crews) do endShift(id, 'core restart') end
        return
    end
    local changed = false
    for id, job in pairs(Jobs) do
        if job.resource == res then
            for crewId, crew in pairs(Crews) do
                if crew.jobId == id then endShift(crewId, 'job resource stopped') end
            end
            Jobs[id] = nil
            changed = true
        end
    end
    if changed then syncJobs() end
end)

-- ── Exports (used by job resources) ──────────────────────────────────────
exports('RegisterJob', function(id, def)
    def.resource = GetInvokingResource()
    def.maxCrew = math.min(def.maxCrew or 1, Config.MaxCrewSize)
    Jobs[id] = def
    syncJobs()
    print(('^2[baasha_jobcore] Registered job "%s" from %s^7'):format(id, def.resource or '?'))
end)

exports('RewardCrew', rewardCrew)
exports('RewardPlayer', rewardPlayer)
exports('EndShift', endShift)
exports('GetCrew', function(crewId) local c = Crews[crewId] return c and publicCrew(c) end)
exports('GetPlayerCrew', function(src) return PlayerCrew[src] end)
exports('IsOnShift', function(src, jobId)
    local crew = Crews[PlayerCrew[src]]
    return crew ~= nil and crew.jobId ~= nil and (jobId == nil or crew.jobId == jobId)
end)
exports('GetLevel', function(src, jobId)
    local row = getStats(src, jobId, true)
    return row and GetLevelFromXp(row.xp) or 1
end)
--- Wipes job progress (XP, earnings, leaderboard). identifier = nil → everyone.
exports('ResetStats', function(jobId, identifier)
    if identifier then
        MySQL.query.await('DELETE FROM baasha_job_stats WHERE job = ? AND identifier = ?', { jobId, identifier })
        StatsCache[identifier .. ':' .. jobId] = nil
    else
        MySQL.query.await('DELETE FROM baasha_job_stats WHERE job = ?', { jobId })
        for key in pairs(StatsCache) do
            if key:sub(-(#jobId + 1)) == ':' .. jobId then StatsCache[key] = nil end
        end
    end
    leaderboardCache[jobId] = nil
    return true
end)

exports('GetIdentifier', function(src) return Bridge.GetIdentifier(src) end)

exports('GiveItem', function(src, item, count)
    local crew = Crews[PlayerCrew[src]]
    if not crew or not crew.jobId then return false end
    return Bridge.AddItem(src, item, count or 1)
end)
