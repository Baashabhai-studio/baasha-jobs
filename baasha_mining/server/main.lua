-- ── Baasha Mining — Server ───────────────────────────────────────────────
-- The server owns the rocks, decides every reward and checks the minigame timing, so nothing can be faked.
-- The core handles crews, XP, pay and levels.

local JOB = 'mining'
local Core = exports.baasha_jobcore

local Rocks = {}      -- id -> { area, coords, ore, uses, respawnAt }
local Boulders = {}   -- id -> { coords, readyAt, armedUntil }
local Sessions = {}   -- src -> current Rock Breaker session
local Charges = {}    -- src -> dynamite charges left this shift
local Blasts = {}     -- src -> planted charge

local function register() Core:RegisterJob(JOB, Config.Job) end
CreateThread(register)
AddEventHandler('onResourceStart', function(res)
    if res == 'baasha_jobcore' then SetTimeout(500, register) end
end)

-- ── Helpers ───────────────────────────────────────────────────────────────
local function pedCoords(src)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and GetEntityCoords(ped) or nil
end

local function now() return GetGameTimer() / 1000.0 end -- real seconds (os.clock is CPU time on the server)
local function onShift(src) return Core:IsOnShift(src, JOB) end
local function level(src) return Core:GetLevel(src, JOB) or 1 end
local function dist(a, b) return #(vector3(a.x, a.y, a.z) - vector3(b.x, b.y, b.z)) end
--- Rock spots are ground-snapped on the client, so compare on the map (with a sanity limit on height)
local function reach(a, b) return math.abs(a.z - b.z) < 25.0 and #(vector2(a.x, a.y) - vector2(b.x, b.y)) or 999.0 end
local function rand(a, b) return a + math.random() * (b - a) end
local function round1(n) return math.floor(n * 10 + 0.5) / 10 end

--- Everything that can be in a bag: ores, gems and ingots
local Materials = {}
for id, o in pairs(Config.Ores) do Materials[id] = { label = o.label, rarity = o.rarity, value = o.value, item = id, xp = o.xp, kind = 'ore' } end
for id, g in pairs(Config.Gems) do Materials[id] = { label = g.label, rarity = g.rarity, value = g.value, item = id, xp = g.xp, kind = 'gem' } end
for id, i in pairs(Config.Ingots) do Materials[id] = { label = i.label, rarity = i.rarity, value = i.value, item = i.item, kind = 'ingot' } end

local function weightedPick(weights, lvl, levelOf)
    local list, total = {}, 0
    for id, w in pairs(weights) do
        if not lvl or (levelOf[id] and levelOf[id].level <= lvl) then
            list[#list + 1] = { id = id, w = w }
            total = total + w
        end
    end
    if total == 0 then return nil end
    table.sort(list, function(a, b) return a.id < b.id end) -- stable order
    local r = math.random() * total
    for _, e in ipairs(list) do
        r = r - e.w
        if r <= 0 then return e.id end
    end
    return list[#list].id
end

-- ── Ore bag: used when an item isn't installed (persists per character) ──
local function bagKey(src)
    local id = Core:GetIdentifier(src)
    return id and ('bag:%s'):format(id) or nil
end
local function getBag(src)
    local key = bagKey(src)
    local raw = key and GetResourceKvpString(key)
    return raw and json.decode(raw) or {}
end
local function setBag(src, bag)
    local key = bagKey(src)
    if key then SetResourceKvp(key, json.encode(bag)) end
end

--- Give a material: a real item when installed, otherwise the ore bag
local function give(src, id, n)
    if n <= 0 then return end
    local m = Materials[id]
    if Config.Storage == 'items' and Core:GiveItem(src, m.item, n) then return end
    local bag = getBag(src)
    bag[id] = (bag[id] or 0) + n
    setBag(src, bag)
end

local function count(src, id)
    local n = getBag(src)[id] or 0
    if Config.Storage == 'items' then n = n + Core:CountItem(src, Materials[id].item) end
    return n
end

--- Take a material out of the bag first, then the inventory. All or nothing.
local function take(src, id, n)
    if count(src, id) < n then return false end
    local bag = getBag(src)
    local fromBag = math.min(bag[id] or 0, n)
    if fromBag > 0 then
        bag[id] = bag[id] - fromBag
        if bag[id] <= 0 then bag[id] = nil end
        setBag(src, bag)
    end
    local rest = n - fromBag
    if rest > 0 and not Core:RemoveItem(src, Materials[id].item, rest) then return false end
    return true
end

-- ── Collection (what this character has found; gems keep the biggest carat) ──
local function colKey(src)
    local id = Core:GetIdentifier(src)
    return id and ('collection:%s'):format(id) or nil
end
local function getCollection(src)
    local key = colKey(src)
    local raw = key and GetResourceKvpString(key)
    return raw and json.decode(raw) or {}
end
local function record(src, id, n, carats)
    local key = colKey(src)
    if not key then return end
    local col = getCollection(src)
    local e = col[id] or { count = 0, best = 0 }
    e.count = e.count + n
    if carats then e.best = math.max(e.best, carats) end
    col[id] = e
    SetResourceKvp(key, json.encode(col))
end

--- Hand out a list of finds: { { id, n, carats? } } → catch card rows + XP
local function payOut(src, finds)
    local rows, xp = {}, 0
    for _, f in ipairs(finds) do
        local m = Materials[f.id]
        give(src, f.id, f.n)
        record(src, f.id, f.n, f.carats)
        xp = xp + (m.xp or 0) * f.n
        rows[#rows + 1] = { id = f.id, item = m.item, label = m.label, rarity = m.rarity, count = f.n, carats = f.carats, value = m.value * f.n }
    end
    if xp > 0 then Core:RewardPlayer(src, 0, xp) end
    return rows, xp
end

local function rollGem(area, lvl)
    local id = weightedPick(area.gems, lvl, Config.Gems)
    if not id then return nil end
    local c = Config.Gems[id].carats
    return { id = id, n = 1, carats = round1(c[1] + (c[2] - c[1]) * math.random() ^ 2) }
end

-- ── Rocks (shared by everyone, synced with GlobalState) ───────────────────
local function publish()
    local out = {}
    for id, r in pairs(Rocks) do out[id] = r.uses > 0 and { ore = r.ore, uses = r.uses } or false end
    for id, b in pairs(Boulders) do
        local armed = now() < (b.armedUntil or 0)
        out[id] = { boulder = true, armed = armed, ready = not armed and now() >= b.readyAt, readyIn = math.max(0, math.ceil(b.readyAt - now())) }
    end
    GlobalState.baasha_mining_rocks = out
end

local function spawnRock(id)
    local r = Rocks[id]
    r.ore = weightedPick(r.area.ores, nil, Config.Ores)
    r.uses = Config.Rocks.uses
    r.respawnAt = nil
end

CreateThread(function()
    for _, area in ipairs(Config.Areas) do
        for i, c in ipairs(area.spots) do
            local id = ('%s_%d'):format(area.id, i)
            Rocks[id] = { area = area, coords = c }
            spawnRock(id)
        end
    end
    for _, b in ipairs(Config.Dynamite.boulders) do Boulders[b.id] = { coords = b.coords, readyAt = 0 } end
    publish()
    -- grow broken rocks back, refresh boulder timers
    while true do
        Wait(5000)
        local changed = false
        for id, r in pairs(Rocks) do
            if r.uses <= 0 and r.respawnAt and now() >= r.respawnAt then spawnRock(id) changed = true end
        end
        for _, b in pairs(Boulders) do
            if b.readyAt > 0 then changed = true end
            if b.readyAt > 0 and now() >= b.readyAt then b.readyAt = 0 end
        end
        if changed then publish() end
    end
end)

-- ── Rock Breaker: start → (client plays) → finish ─────────────────────────
local function ringSeconds(lvl)
    local R = Config.Breaker.ring
    return math.max(R.min, R.start - (lvl - 1) * R.perLevel)
end

lib.callback.register('baasha_mining:start', function(src, rockId)
    if not onShift(src) then return false end
    if Sessions[src] and now() - Sessions[src].startAt < 60 then return false, L('busy') end
    local r = Rocks[rockId]
    local here = pedCoords(src)
    if not r or not here then return false end
    if r.uses <= 0 then return false, L('rock_gone') end
    if reach(here, r.coords) > 4.0 then return false, L('not_near_rock') end
    local lvl = level(src)
    local ore = Config.Ores[r.ore]
    if lvl < ore.level then return false, L('level_needed', ore.label, ore.level) end
    if lvl < r.area.level then return false, L('level_needed', r.area.label, r.area.level) end

    local B = Config.Breaker
    local hits = B.hits[r.ore] or 5
    local jackhammer = lvl >= B.jackhammer.level
    if jackhammer then hits = math.max(3, hits - B.jackhammer.hitsLess) end
    -- gem vein: the server decides up front which strike (if any) is a gem
    local gemAt = math.random() < r.area.gemChance * (lvl >= B.hardFromLevel and 1.4 or 1.0) and math.random(2, hits) or nil

    local params = {
        rock = rockId, ore = r.ore, label = ore.label, rarity = ore.rarity, color = ore.color,
        hits = hits, ring = ringSeconds(lvl), misses = lvl >= B.hardFromLevel and B.misses - 1 or B.misses,
        gemAt = gemAt, tool = jackhammer and 'jackhammer' or 'pickaxe',
    }
    Sessions[src] = { rock = rockId, startAt = now(), params = params }
    return true, params
end)

--- result = { perfects, goods, misses, gem = true if the gem strike landed }
lib.callback.register('baasha_mining:finish', function(src, result)
    local s = Sessions[src]
    Sessions[src] = nil
    if not s or type(result) ~= 'table' then return false end
    local p, r = s.params, Rocks[s.rock]
    local perfects, goods, misses = tonumber(result.perfects) or 0, tonumber(result.goods) or 0, tonumber(result.misses) or 0
    local took = now() - s.startAt

    -- Every strike needs its ring to (nearly) close, plus a short gap before the next spot
    if took < (perfects + goods) * (p.ring * 0.55 + 0.15) then return false end
    if misses >= p.misses then return false, L('tired') end
    if perfects + goods < p.hits then return false end
    if not r or r.uses <= 0 then return false, L('rock_gone') end

    r.uses = r.uses - 1
    if r.uses <= 0 then r.respawnAt = now() + Config.Rocks.respawn end
    publish()

    local Y, lvl = Config.Breaker.yield, level(src)
    local bonus = math.min(Y.maxBonus, math.floor(perfects / Y.perfectsPerBonus))
    local finds = { { id = p.ore, n = math.random(Y.main[1], Y.main[2]) + bonus } }
    local stone = math.random(Y.stone[1], Y.stone[2])
    if stone > 0 and p.ore ~= 'ore_stone' then finds[#finds + 1] = { id = 'ore_stone', n = stone } end
    if p.ore ~= 'ore_coal' and math.random() < Y.coalChance then finds[#finds + 1] = { id = 'ore_coal', n = 1 } end
    if p.gemAt and result.gem == true then
        local g = rollGem(r.area, lvl)
        if g then finds[#finds + 1] = g end
    end
    local rows, xp = payOut(src, finds)
    return true, { finds = rows, xp = xp, perfects = perfects, rockLeft = r.uses }
end)

lib.callback.register('baasha_mining:cancel', function(src)
    Sessions[src] = nil
    return true
end)

-- ── Dynamite ──────────────────────────────────────────────────────────────
lib.callback.register('baasha_mining:plant', function(src, boulderId)
    if not onShift(src) then return false end
    local D, b, here = Config.Dynamite, Boulders[boulderId], pedCoords(src)
    if not b or not here or reach(here, b.coords) > 5.0 then return false, L('not_near_rock') end
    if level(src) < D.level then return false, L('level_needed', 'Dynamite', D.level) end
    if now() < b.readyAt then return false, L('boulder_cd') end
    if Blasts[src] then return false, L('busy') end
    Charges[src] = Charges[src] or D.perShift
    if Charges[src] <= 0 then return false, L('no_charges') end

    Charges[src] = Charges[src] - 1
    b.readyAt = now() + D.fuse + D.cooldown
    b.armedUntil = now() + D.fuse
    Blasts[src] = boulderId
    publish()
    -- everyone nearby sees the charge and the blast
    TriggerClientEvent('baasha_mining:client:charge', -1, boulderId, D.fuse, here) -- here: the charge goes on the planter's side
    SetTimeout(D.fuse * 1000, function()
        Blasts[src] = nil
        b.armedUntil = 0
        publish()
        TriggerClientEvent('baasha_mining:client:blast', -1, boulderId)
        if not onShift(src) then return end
        local lvl, area = level(src), Config.Areas[1]
        for _, a in ipairs(Config.Areas) do if lvl >= a.level then area = a end end
        -- a pile of ore from the best area this miner can work
        local finds, total = {}, math.random(D.yield[1], D.yield[2])
        local byOre = {}
        for _ = 1, total do
            local id = weightedPick(area.ores, lvl, Config.Ores) or 'ore_stone'
            byOre[id] = (byOre[id] or 0) + 1
        end
        for id, n in pairs(byOre) do finds[#finds + 1] = { id = id, n = n } end
        table.sort(finds, function(x, y) return Materials[x.id].value > Materials[y.id].value end)
        if math.random() < D.gemChance then
            local g = rollGem(area, lvl)
            if g then finds[#finds + 1] = g end
        end
        local rows, xp = payOut(src, finds)
        TriggerClientEvent('baasha_mining:client:blastLoot', src, { finds = rows, xp = xp, blast = true })
    end)
    return true, Charges[src]
end)

--- Admin / test tools: every boulder ready again, every rock regrown
exports('ResetQuarry', function()
    for _, b in pairs(Boulders) do b.readyAt, b.armedUntil = 0, 0 end
    for id in pairs(Rocks) do spawnRock(id) end -- full rocks, fresh ore types
    publish()
    return true
end)

lib.callback.register('baasha_mining:charges', function(src)
    if not onShift(src) then return 0 end
    Charges[src] = Charges[src] or Config.Dynamite.perShift
    return Charges[src], level(src)
end)

-- ── Mining Office: bag, smelter, collection ───────────────────────────────
local function nearOffice(src, r)
    local here = pedCoords(src)
    return here and reach(here, Config.Office.coords) <= (r or 8.0)
end

local function smeltKey(src)
    local id = Core:GetIdentifier(src)
    return id and ('smelter:%s'):format(id) or nil
end
local function getSmelter(src)
    local key = smeltKey(src)
    local raw = key and GetResourceKvpString(key)
    return raw and json.decode(raw) or nil
end
local function setSmelter(src, job)
    local key = smeltKey(src)
    if not key then return end
    if job then SetResourceKvp(key, json.encode(job)) else DeleteResourceKvp(key) end
end

local function officeData(src)
    local lvl = level(src)
    local bag, total = {}, 0
    for id, m in pairs(Materials) do
        local n = count(src, id)
        if n > 0 then
            bag[#bag + 1] = { id = id, item = m.item, label = m.label, rarity = m.rarity, count = n, value = m.value * n, each = m.value, kind = m.kind }
            total = total + m.value * n
        end
    end
    table.sort(bag, function(a, b) return a.value > b.value end)

    local recipes = {}
    for i, rc in ipairs(Config.Smelter.recipes) do
        local ore, fuel, ingot = Materials[rc.ore], Materials[rc.fuel], Materials[rc.ingot]
        local have, fuelHave = count(src, rc.ore), count(src, rc.fuel)
        recipes[#recipes + 1] = {
            index = i, ore = rc.ore, oreItem = ore.item, oreLabel = ore.label, amount = rc.amount,
            fuelLabel = fuel.label, fuelAmount = rc.fuelAmount, ingot = rc.ingot, ingotItem = ingot.item,
            ingotLabel = ingot.label, ingotValue = ingot.value, rarity = ingot.rarity, level = rc.level, locked = lvl < rc.level,
            max = math.min(Config.Smelter.maxBatch, math.floor(have / rc.amount), math.floor(fuelHave / rc.fuelAmount)),
        }
    end
    local job = getSmelter(src)
    if job then
        job.left = math.max(0, math.ceil(job.readyAt - os.time()))
        job.ingotLabel = Materials[job.ingot].label
        job.ingotItem = Materials[job.ingot].item
    end

    local col = getCollection(src)
    local collection, found = {}, 0
    local function add(id, src2, kind)
        local e = col[id]
        if e then found = found + 1 end
        collection[#collection + 1] = { id = id, item = id, label = src2.label, rarity = src2.rarity, value = src2.value, level = src2.level,
                                        kind = kind, count = e and e.count or 0, best = e and e.best or 0 }
    end
    local order = { 'ore_stone', 'ore_coal', 'ore_copper', 'ore_iron', 'ore_silver', 'ore_gold' }
    for _, id in ipairs(order) do if Config.Ores[id] then add(id, Config.Ores[id], 'ore') end end
    local gems = {}
    for id in pairs(Config.Gems) do gems[#gems + 1] = id end
    table.sort(gems, function(a, b) return Config.Gems[a].value < Config.Gems[b].value end)
    for _, id in ipairs(gems) do add(id, Config.Gems[id], 'gem') end

    return {
        level = lvl, bag = bag, total = total, recipes = recipes, smelter = job,
        collection = collection, found = found, secondsPerIngot = Config.Smelter.secondsPerIngot,
    }
end

lib.callback.register('baasha_mining:office', function(src)
    if not nearOffice(src) then return nil end
    return officeData(src)
end)

--- HUD summary (anywhere): how many items and what they're worth
lib.callback.register('baasha_mining:bag', function(src)
    local n, value = 0, 0
    for id, m in pairs(Materials) do
        local c = count(src, id)
        n, value = n + c, value + m.value * c
    end
    return { count = n, value = value }
end)

lib.callback.register('baasha_mining:sell', function(src)
    if not nearOffice(src) then return false, L('too_far') end
    local total, n = 0, 0
    for id, m in pairs(Materials) do
        local c = count(src, id)
        if c > 0 and take(src, id, c) then
            total = total + m.value * c
            n = n + c
        end
    end
    if n == 0 then return false, L('nothing_to_sell') end
    Core:RewardPlayer(src, total, 0)
    return true, L('sold', n), total
end)

lib.callback.register('baasha_mining:smelt', function(src, index, amount)
    if not onShift(src) or not nearOffice(src) then return false, L('too_far') end
    if getSmelter(src) then return false, L('smelt_busy') end
    local rc = Config.Smelter.recipes[tonumber(index) or 0]
    amount = math.floor(tonumber(amount) or 0)
    if not rc or amount < 1 or amount > Config.Smelter.maxBatch then return false end
    if level(src) < rc.level then return false, L('level_needed', Materials[rc.ingot].label, rc.level) end
    if count(src, rc.ore) < rc.amount * amount or count(src, rc.fuel) < rc.fuelAmount * amount then return false, L('smelt_missing') end
    if not take(src, rc.ore, rc.amount * amount) then return false, L('smelt_missing') end
    if not take(src, rc.fuel, rc.fuelAmount * amount) then
        give(src, rc.ore, rc.amount * amount) -- put the ore back
        return false, L('smelt_missing')
    end
    local seconds = Config.Smelter.secondsPerIngot * amount
    setSmelter(src, { ingot = rc.ingot, amount = amount, readyAt = os.time() + seconds, seconds = seconds })
    return true, L('smelt_started', amount)
end)

lib.callback.register('baasha_mining:collect', function(src)
    if not nearOffice(src) then return false, L('too_far') end
    local job = getSmelter(src)
    if not job or os.time() < job.readyAt then return false, L('nothing_ready') end
    setSmelter(src, nil)
    payOut(src, { { id = job.ingot, n = job.amount } })
    return true, L('smelt_collected', job.amount)
end)

-- ── Admin: record rock spots while walking the quarry ─────────────────────
RegisterCommand('miningspot', function(src)
    local c = src > 0 and pedCoords(src)
    if not c then return end
    local line = ('vector3(%.2f, %.2f, %.2f),'):format(c.x, c.y, c.z)
    local file = LoadResourceFile(GetCurrentResourceName(), 'spots.txt') or ''
    SaveResourceFile(GetCurrentResourceName(), 'spots.txt', file .. line .. '\n', -1)
    TriggerClientEvent('chat:addMessage', src, { args = { 'Mining', 'Saved ' .. line .. ' to baasha_mining/spots.txt' } })
    print('[baasha_mining] spot ' .. line)
end, true)

-- ── Cleanup ───────────────────────────────────────────────────────────────
-- fresh dynamite charges every shift
AddEventHandler('baasha_jobcore:server:shiftStarted', function(jobId, _, crew)
    if jobId ~= JOB then return end
    for _, m in ipairs(crew and crew.members or {}) do Sessions[m], Charges[m] = nil, Config.Dynamite.perShift end
end)
AddEventHandler('playerDropped', function() Sessions[source], Charges[source], Blasts[source] = nil, nil, nil end)
