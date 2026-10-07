-- ── Baasha Fishing — Server ──────────────────────────────────────────────
-- The server decides what bites and when, and checks reel timing, so catches can't be faked.
-- The core handles crews, XP, pay, levels and the rented boat.

local JOB = 'fishing'
local Core = exports.baasha_jobcore
local Lines = {}      -- src -> current cast { habitat, fish, stage, biteAt, hookedAt }

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

-- Cooler (catch log) persists per character in the resource KVP store
local function coolerKey(src)
    local id = Core:GetIdentifier(src)
    return id and ('cooler:%s'):format(id) or nil
end

local function getCooler(src)
    local key = coolerKey(src)
    local raw = key and GetResourceKvpString(key)
    return raw and json.decode(raw) or {}
end

local function setCooler(src, list)
    local key = coolerKey(src)
    if key then SetResourceKvp(key, json.encode(list)) end
end

local function coolerSummary(list)
    local value = 0
    for _, f in ipairs(list) do value = value + f.value end
    return #list, value
end

--- All sellable items: { item, label, rarity, value per item }
local function sellableItems()
    local list = {}
    for _, f in ipairs(Config.Fish) do
        if f.item then
            list[#list + 1] = { item = f.item, label = f.label, rarity = f.rarity, value = math.max(1, math.floor((f.weight[1] + f.weight[2]) / 2 * f.price)) }
        end
    end
    for _, j in ipairs(Config.Junk) do
        if j.item then list[#list + 1] = { item = j.item, label = j.label, rarity = 'common', value = j.value } end
    end
    return list
end

-- Fish Guide: which species this character has caught, how many, and the biggest one
local function collectionKey(src)
    local id = Core:GetIdentifier(src)
    return id and ('collection:%s'):format(id) or nil
end

local function getCollection(src)
    local key = collectionKey(src)
    local raw = key and GetResourceKvpString(key)
    return raw and json.decode(raw) or {}
end

local function recordCatch(src, fish)
    local key = collectionKey(src)
    if not key or fish.junk then return end
    local col = getCollection(src)
    local entry = col[fish.id] or { count = 0, best = 0 }
    entry.count = entry.count + 1
    entry.best = math.max(entry.best, fish.weight)
    col[fish.id] = entry
    SetResourceKvp(key, json.encode(col))
end

--- Where is this player fishing? Returns habitat, label — or nil, error
local function habitatAt(src, boatNetId)
    local here = pedCoords(src)
    if not here then return nil, L('not_spot') end
    local lvl = level(src)

    -- Deep sea: standing on a rented fishing boat, far from every shore spot
    if boatNetId then
        local boat = NetworkGetEntityFromNetworkId(boatNetId)
        if boat ~= 0 and DoesEntityExist(boat) and Entity(boat).state.baashaJobVehicle == JOB and #(GetEntityCoords(boat) - here) < 8.0 then
            local far = dist(here, Config.Job.depot.coords) >= Config.DeepSea.minDistance
            for _, s in ipairs(Config.Spots) do
                if dist(here, s.coords) < Config.DeepSea.minDistance then far = false break end
            end
            if far then return 'deep', Config.DeepSea.label end
        end
    end

    for _, s in ipairs(Config.Spots) do
        if dist(here, s.coords) <= s.radius then
            if lvl < s.level then return nil, L('spot_locked', s.label, s.level) end
            return s.habitat, s.label
        end
    end
    return nil, L('not_spot')
end

--- Rolls what bites: junk, or a fish of a rarity the player's level allows
local function rollCatch(src, habitat)
    if math.random(100) <= Config.JunkChance then
        local j = Config.Junk[math.random(#Config.Junk)]
        return { junk = true, id = j.id, label = j.label, rarity = 'common', value = j.value, weight = 0.0, item = j.item }
    end

    local lvl = level(src)
    local bonus = 1 + lvl * Config.RareBonusPerLevel * (lvl >= 6 and 2 or 1)
    local pool, total = {}, 0
    for name, r in pairs(Config.Rarities) do
        if lvl >= r.level then
            local w = r.weight * ((name == 'common' or name == 'uncommon') and 1 or bonus)
            pool[#pool + 1] = { name = name, w = w }
            total = total + w
        end
    end

    -- Pick a rarity, then a species of that rarity living here (falling back to commoner ones)
    local order = { 'legendary', 'epic', 'rare', 'uncommon', 'common' }
    local roll, pick = math.random() * total, 'common'
    for _, p in ipairs(pool) do
        roll = roll - p.w
        if roll <= 0 then pick = p.name break end
    end
    local start = 1
    for i, n in ipairs(order) do if n == pick then start = i end end
    for i = start, #order do
        local candidates = {}
        for _, f in ipairs(Config.Fish) do
            if f.rarity == order[i] then
                for _, h in ipairs(f.habitat) do
                    if h == habitat then candidates[#candidates + 1] = f break end
                end
            end
        end
        if #candidates > 0 then
            local f = candidates[math.random(#candidates)]
            local weight = f.weight[1] + math.random() * (f.weight[2] - f.weight[1])
            weight = math.floor(weight * 10 + 0.5) / 10
            return { id = f.id, label = f.label, rarity = f.rarity, weight = weight, value = math.max(1, math.floor(weight * f.price)), item = f.item }
        end
    end
end

--- Puts a landed catch in the inventory (or the cooler) and the Fish Guide. Returns what the catch card shows.
local function giveCatch(src, fish)
    -- Real inventory item when it's installed (GiveItem fails if not, or if the inventory is full)
    local asItem = Config.Storage == 'items' and fish.item and Core:GiveItem(src, fish.item, 1)
    if not asItem then
        local cooler = getCooler(src)
        cooler[#cooler + 1] = { id = fish.id, label = fish.label, rarity = fish.rarity, weight = fish.weight, value = fish.value }
        setCooler(src, cooler)
    end
    recordCatch(src, fish)
    local xp = fish.junk and 1 or Config.Rarities[fish.rarity].xp
    return { label = fish.label, rarity = fish.rarity, weight = fish.weight, value = fish.value, junk = fish.junk, xp = xp, item = fish.item }
end

-- ── Deep Drop: the server builds the water, the client plays it, the server checks the result ──
local fishById
local function speciesById()
    if fishById then return fishById end
    fishById = {}
    for _, f in ipairs(Config.Fish) do fishById[f.id] = f end
    for _, j in ipairs(Config.Junk) do fishById[j.id] = { id = j.id, label = j.label, junk = true, value = j.value, item = j.item } end
    return fishById
end

local function rand(a, b) return a + math.random() * (b - a) end
local function round1(n) return math.floor(n * 10 + 0.5) / 10 end

local function weightedPick(mix, lvl)
    local all, list, total = speciesById(), {}, 0
    for id, w in pairs(mix) do
        local f = all[id]
        if f and (f.junk or lvl >= Config.Rarities[f.rarity].level) then
            list[#list + 1] = { f = f, w = w }
            total = total + w
        end
    end
    if total == 0 then return nil end
    local r = math.random() * total
    for _, e in ipairs(list) do
        r = r - e.w
        if r <= 0 then return e.f end
    end
    return list[#list].f
end

local function buildDrop(src, habitat)
    local D, lvl = Config.DeepDrop, level(src)
    local H = D.habitats[habitat]
    if not H then return nil end
    local line = math.min(H.line.max, H.line.base + (lvl - 1) * H.line.perLevel)
    local speed = 1 + (lvl - 1) * D.speedPerLevel
    local ents = {}

    local function addFish(f, depth)
        local e = { i = #ents + 1, kind = 'fish', id = f.id, item = f.item, label = f.label, y = round1(depth),
                    x = rand(0.0, 1.0), dir = math.random() < 0.5 and -1 or 1 }
        if f.junk then
            e.rarity, e.junk, e.kg, e.value, e.speed = 'junk', true, 0.0, f.value, 0.0
        else
            -- most fish are on the small side, a few are trophies
            local kg = round1(f.weight[1] + (f.weight[2] - f.weight[1]) * math.random() ^ 2)
            e.rarity, e.kg, e.value, e.speed = f.rarity, kg, math.max(1, math.floor(kg * f.price)), round1(rand(0.75, 1.2) * speed)
        end
        ents[#ents + 1] = e
    end

    for _, b in ipairs(H.bands) do
        local n = math.floor((b.to - b.from) / 10 * b.density * D.density + 0.5)
        for _ = 1, n do
            local f = weightedPick(b.mix, lvl)
            if f then addFish(f, rand(b.from, b.to)) end
        end
    end
    if H.floor and H.junk then
        for _, id in ipairs(H.junk) do
            local j = speciesById()[id]
            if j then addFish(j, H.floor - 0.6) end
        end
    end
    local hazard = habitat == 'lake' and 'snag' or 'jelly'
    for _ = 1, math.floor(D.hazards.base + lvl * D.hazards.perLevel) do
        ents[#ents + 1] = { i = #ents + 1, kind = hazard, x = rand(0.08, 0.88), size = math.random(30, 44),
                            y = round1(rand(H.hazardDepth[1], math.min(H.hazardDepth[2], line - 2))) }
    end
    for _ = 1, D.rings do
        ents[#ents + 1] = { i = #ents + 1, kind = 'ring', x = rand(0.12, 0.8), y = round1(rand(8, line * 0.85)) }
    end

    return {
        habitat = habitat, level = lvl, line = line, floor = H.floor,
        hooks = D.hooks.base + math.floor(lvl / D.hooks.everyLevels), ents = ents,
    }
end

--- Deep Drop result: { caught = { entity index, ... }, deepest = metres, rings = gold rings picked up }
lib.callback.register('baasha_fishing:dropDone', function(src, result)
    local line = Lines[src]
    Lines[src] = nil
    if not line or line.stage ~= 'dropping' or type(result) ~= 'table' then return false end
    local drop, took = line.drop, now() - line.castAt
    if took > Config.DeepDrop.maxTime then return false end

    -- The hook can't go deeper than the line, and can't travel faster than the game lets it
    local deepest = tonumber(result.deepest) or 0
    if deepest < 0 or deepest > drop.line + 0.5 then return false end
    if took < (deepest / 14.5 + deepest / 17.5) * 0.85 then return false end

    -- Gold rings only count if they were within reach
    local reachable = 0
    for _, e in ipairs(drop.ents) do
        if e.kind == 'ring' and e.y <= deepest + 2.5 then reachable = reachable + 1 end
    end
    local hooks = drop.hooks + math.max(0, math.min(math.floor(tonumber(result.rings) or 0), reachable))

    local catches, xp, seen = {}, 0, {}
    for _, i in ipairs(type(result.caught) == 'table' and result.caught or {}) do
        local e = drop.ents[tonumber(i) or 0]
        if #catches >= hooks then break end
        if e and e.kind == 'fish' and not seen[e.i] and e.y <= deepest + 2.5 then
            seen[e.i] = true
            local c = giveCatch(src, { id = e.id, label = e.label, rarity = e.junk and 'common' or e.rarity, weight = e.kg,
                                       value = e.value, junk = e.junk, item = e.item })
            xp = xp + c.xp
            catches[#catches + 1] = c
        end
    end
    if xp > 0 then Core:RewardPlayer(src, 0, xp) end
    return true, { catches = catches, xp = xp, deepest = deepest }
end)

-- ── Fishing flow: cast → bite → hook → land ──────────────────────────────
lib.callback.register('baasha_fishing:cast', function(src, boatNetId)
    if not onShift(src) then return false end
    if Lines[src] and now() - Lines[src].castAt < 90 then return false end -- one line at a time (stale casts expire)
    local habitat, label = habitatAt(src, boatNetId)
    if not habitat then return false, label end

    if Config.Minigame == 'deepdrop' then
        local drop = buildDrop(src, habitat)
        if not drop then return false, L('not_spot') end
        Lines[src] = { habitat = habitat, drop = drop, stage = 'dropping', castAt = now() }
        drop.spot = label
        return true, label, drop
    end

    local catch = rollCatch(src, habitat)
    if not catch then return false, L('not_spot') end
    local line = { habitat = habitat, fish = catch, stage = 'waiting', castAt = now() }
    Lines[src] = line

    local delay = math.random(Config.BiteTime[1] * 1000, Config.BiteTime[2] * 1000)
    SetTimeout(delay, function()
        if Lines[src] ~= line or line.stage ~= 'waiting' then return end
        line.stage, line.biteAt = 'bite', now()
        TriggerClientEvent('baasha_fishing:client:bite', src)
        SetTimeout(math.floor(Config.BiteWindow * 1000) + 300, function()
            if Lines[src] == line and line.stage == 'bite' then
                Lines[src] = nil
                TriggerClientEvent('baasha_fishing:client:escaped', src)
            end
        end)
    end)
    return true, label
end)

lib.callback.register('baasha_fishing:hook', function(src)
    local line = Lines[src]
    if not line or line.stage ~= 'bite' or now() - line.biteAt > Config.BiteWindow + 0.3 then return false end
    line.stage, line.hookedAt = 'reeling', now()
    local R, lvl = Config.Reel, level(src)
    local r = line.fish.junk and R.junk or Config.Rarities[line.fish.rarity]
    -- Only the difficulty is revealed now; what it is stays a surprise until it's landed
    return {
        rarity = line.fish.junk and 'junk' or line.fish.rarity,
        hits   = r.hits,
        zone   = math.max(R.zone.min, R.zone.start - (lvl - 1) * R.zone.perLevel),
        speed  = math.min(R.speed.max, R.speed.start + (lvl - 1) * R.speed.perLevel) * r.pace,
        misses = lvl >= R.hardFromLevel and R.misses - 1 or R.misses,
    }
end)

lib.callback.register('baasha_fishing:land', function(src, success)
    local line = Lines[src]
    Lines[src] = nil
    if not line or line.stage ~= 'reeling' then return false end
    local took = now() - line.hookedAt
    if took < Config.MinReelTime or took > Config.MaxReelTime then return false end
    if not success then return false, 'snapped' end

    local result = giveCatch(src, line.fish)
    Core:RewardPlayer(src, 0, result.xp)
    return true, result
end)

lib.callback.register('baasha_fishing:cancel', function(src)
    Lines[src] = nil
    return true
end)

lib.callback.register('baasha_fishing:cooler', function(src)
    local count, value = coolerSummary(getCooler(src))
    if Config.Storage == 'items' then
        for _, it in ipairs(sellableItems()) do
            local n = Core:CountItem(src, it.item)
            count, value = count + n, value + it.value * n
        end
    end
    return { count = count, value = value }
end)

-- ── Market ────────────────────────────────────────────────────────────────
--- Everything the Fish Market screen shows: cooler, boat info, and the Fish Guide collection
lib.callback.register('baasha_fishing:market', function(src)
    local here = pedCoords(src)
    if not here or dist(here, Config.Market.coords) > 8.0 then return nil end

    local cooler = getCooler(src)
    local _, total = coolerSummary(cooler)
    if Config.Storage == 'items' then
        for _, it in ipairs(sellableItems()) do
            local n = Core:CountItem(src, it.item)
            if n > 0 then
                cooler[#cooler + 1] = { label = it.label, rarity = it.rarity, count = n, value = it.value * n, item = it.item }
                total = total + it.value * n
            end
        end
    end
    -- icon for catches kept in the cooler
    local itemOf = {}
    for _, f in ipairs(Config.Fish) do itemOf[f.id] = f.item end
    for _, j in ipairs(Config.Junk) do itemOf[j.id] = j.item end
    for _, c in ipairs(cooler) do c.item = c.item or itemOf[c.id] end
    local col = getCollection(src)

    local habitatLabel = { coast = 'Piers & coast', lake = 'Alamo Sea', deep = 'Deep sea (boat)' }
    local species, found = {}, 0
    for _, f in ipairs(Config.Fish) do
        local c = col[f.id]
        if c then found = found + 1 end
        species[#species + 1] = {
            id = f.id, label = f.label, rarity = f.rarity, habitat = habitatLabel[f.habitat[1]] or f.habitat[1],
            level = Config.Rarities[f.rarity].level, count = c and c.count or 0, best = c and c.best or 0,
            item = f.item,
            -- sell price range: smallest and biggest possible fish of this species
            min = math.max(1, math.floor(f.weight[1] * f.price)), max = math.max(1, math.floor(f.weight[2] * f.price)),
        }
    end

    return {
        cooler = cooler, total = total, level = level(src),
        boat = { deposit = Config.Boat.deposit, model = Config.Boat.model },
        species = species, found = found,
    }
end)
lib.callback.register('baasha_fishing:sell', function(src)
    local here = pedCoords(src)
    if not here or dist(here, Config.Market.coords) > 8.0 then return false, L('too_far') end

    local total, count = 0, 0
    local cooler = getCooler(src)
    for _, f in ipairs(cooler) do total, count = total + f.value, count + 1 end
    setCooler(src, {})

    if Config.Storage == 'items' then
        for _, it in ipairs(sellableItems()) do
            local n = Core:CountItem(src, it.item)
            if n > 0 and Core:RemoveItem(src, it.item, n) then
                total = total + it.value * n
                count = count + n
            end
        end
    end

    if count == 0 then return false, L('nothing_to_sell') end
    Core:RewardPlayer(src, total, 0)
    return true, L('sold', count)
end)

-- ── Boat rental ───────────────────────────────────────────────────────────
lib.callback.register('baasha_fishing:rentBoat', function(src)
    if not onShift(src) then return nil end
    local here = pedCoords(src)
    if not here or dist(here, Config.Market.coords) > 10.0 then return nil, L('too_far') end
    local b = Config.Boat
    return Core:RentVehicle(src, {
        model = b.model, type = 'boat', spot = b.spawn, deposit = b.deposit,
        returnTo = vector3(b.spawn.x, b.spawn.y, b.spawn.z), returnDistance = b.returnDistance, max = 1,
    })
end)

lib.callback.register('baasha_fishing:returnBoat', function(src, netId)
    return Core:ReturnVehicle(src, netId)
end)

-- ── Cleanup ───────────────────────────────────────────────────────────────
AddEventHandler('baasha_jobcore:server:shiftEnded', function(jobId)
    if jobId ~= JOB then return end
    for src in pairs(Lines) do
        if not onShift(src) then Lines[src] = nil end
    end
end)

AddEventHandler('playerDropped', function() Lines[source] = nil end)
