Config = {}

Config.Locale = 'en'
Config.Debug  = false

-- ── Job definition (shown in the job center tablet) ──────────────────────
Config.Job = {
    label       = 'Mining',
    icon        = 'fa-solid fa-gem',
    description = 'Break rocks at the Davis Quartz quarry for coal, copper, iron, silver and gold. Hit the weak spots, find gem veins, blast boulders with dynamite and smelt your ore into ingots.',
    maxCrew     = 4,

    depot = {
        coords   = vector4(2941.0, 2746.0, 43.3, 290.0),   -- foreman at the quarry (start/end the shift)
        ped      = 's_m_y_construct_01',
        scenario = 'WORLD_HUMAN_CLIPBOARD',
        blip     = { sprite = 527, color = 5, scale = 0.8 },
    },

    -- No work vehicle: the quarry is the workplace
    vehicle = nil,
    uniform = nil,

    perks = {
        { level = 1, text = 'Coal, copper and iron at the Davis Quartz quarry' },
        { level = 2, text = 'The Gold Vein Ridge: silver ore and emeralds' },
        { level = 3, text = 'Dynamite: blast the big boulders' },
        { level = 4, text = 'Gold ore and sapphires on the ridge' },
        { level = 5, text = 'Jackhammer: one hit less per rock, rubies' },
        { level = 6, text = 'Better gem chance (the rocks fight back harder)' },
        { level = 7, text = 'Diamonds' },
    },
}

-- ── Mining Office: sell, smelt and the collection (a counter next to the foreman) ──
Config.Office = {
    coords = vector4(2944.0, 2742.5, 43.3, 290.0),
}

-- Floating signs (false = off): "MINING JOB" over the foreman before a shift, "MINING OFFICE" during it
Config.Signs = { distance = 30.0, textDistance = 12.0 }

-- Where catches go: 'items' = real inventory items (install/ has the item lists + images).
-- If an item isn't installed, it goes into the built-in ore bag instead (sold / smelted at the office).
Config.Storage = 'items'

-- ── Materials ─────────────────────────────────────────────────────────────
-- value = sell price per item. level = needed to mine / find it. xp = per item.
Config.Ores = {
    ore_stone  = { label = 'Stone',       rarity = 'common',   value = 2,  level = 1, xp = 1, color = { 150, 150, 150 } },
    ore_coal   = { label = 'Coal',        rarity = 'common',   value = 5,  level = 1, xp = 2, color = { 60, 60, 70 } },
    ore_copper = { label = 'Copper Ore',  rarity = 'uncommon', value = 9,  level = 1, xp = 3, color = { 230, 120, 50 } },
    ore_iron   = { label = 'Iron Ore',    rarity = 'uncommon', value = 11, level = 1, xp = 3, color = { 190, 80, 60 } },
    ore_silver = { label = 'Silver Ore',  rarity = 'rare',     value = 20, level = 2, xp = 5, color = { 220, 225, 235 } },
    ore_gold   = { label = 'Gold Ore',    rarity = 'epic',     value = 38, level = 4, xp = 8, color = { 250, 200, 40 } },
}

-- Gems drop from gem veins. carats = size range, the bigger the better for your collection.
Config.Gems = {
    gem_amethyst = { label = 'Amethyst', rarity = 'rare',      value = 45,  level = 1, xp = 8,  carats = { 0.5, 3.0 } },
    gem_emerald  = { label = 'Emerald',  rarity = 'rare',      value = 75,  level = 2, xp = 10, carats = { 0.5, 3.0 } },
    gem_sapphire = { label = 'Sapphire', rarity = 'epic',      value = 120, level = 4, xp = 15, carats = { 0.5, 4.0 } },
    gem_ruby     = { label = 'Ruby',     rarity = 'epic',      value = 150, level = 5, xp = 18, carats = { 0.5, 4.0 } },
    gem_diamond  = { label = 'Diamond',  rarity = 'legendary', value = 300, level = 7, xp = 30, carats = { 0.3, 3.0 } },
}

-- Ingots (smelted at the office). Want them for qb-crafting? Change `item` to 'iron', 'copper', 'steel' ...
Config.Ingots = {
    ingot_copper = { label = 'Copper Ingot', rarity = 'uncommon', value = 30,  item = 'ingot_copper' },
    ingot_iron   = { label = 'Iron Ingot',   rarity = 'uncommon', value = 34,  item = 'ingot_iron' },
    ingot_silver = { label = 'Silver Ingot', rarity = 'rare',     value = 62,  item = 'ingot_silver' },
    ingot_gold   = { label = 'Gold Ingot',   rarity = 'epic',     value = 115, item = 'ingot_gold' },
}

Config.Rarities = {
    common    = { color = '#a1a1aa', label = 'Common' },
    uncommon  = { color = '#22c55e', label = 'Uncommon' },
    rare      = { color = '#3b82f6', label = 'Rare' },
    epic      = { color = '#a855f7', label = 'Epic' },
    legendary = { color = '#eab308', label = 'Legendary' },
}

-- ── Mining areas ──────────────────────────────────────────────────────────
-- Every rock spot gets an ore type from `ores` (weights). Rocks are shared by everyone:
-- each rock can be mined `uses` times, then it crumbles and grows back after `respawn` seconds.
-- Add your own spots with /miningspot (admins): it prints and saves your position.
Config.Rocks = { uses = 3, respawn = 120, model = 'prop_rock_4_c' }

Config.Areas = {
    {
        -- Starter quarry: only ores a level 1 miner can break, so new players never run out of rocks
        id = 'quarry', label = 'Davis Quartz Quarry', level = 1,
        ores = { ore_stone = 3, ore_coal = 3, ore_copper = 4, ore_iron = 4 },
        gems = { gem_amethyst = 1 }, gemChance = 0.12,
        spots = {
            vector3(2936.07, 2777.09, 39.09), vector3(2930.72, 2789.88, 40.06), vector3(2973.56, 2795.39, 40.91),
            vector3(2978.12, 2784.55, 39.42), vector3(2965.64, 2769.22, 39.36), vector3(2955.96, 2783.02, 40.99),
            vector3(2937.22, 2806.19, 41.82), vector3(2947.36, 2792.98, 40.62), vector3(2958.55, 2800.69, 41.46),
            vector3(2951.05, 2775.24, 39.24), vector3(2966.10, 2784.38, 39.34),
        },
    },
    {
        -- The ridge around the quarry: silver from level 2, gold rocks need level 4 (shown on the rock)
        id = 'goldvein', label = 'Gold Vein Ridge', level = 2,
        ores = { ore_silver = 4, ore_iron = 2, ore_gold = 3, ore_coal = 1 },
        gems = { gem_emerald = 3, gem_sapphire = 3, gem_ruby = 2, gem_diamond = 1 }, gemChance = 0.22,
        spots = {
            vector3(2923.83, 2808.83, 43.30), vector3(2946.42, 2817.88, 42.57), vector3(2957.27, 2823.18, 42.96),
            vector3(3002.91, 2777.78, 43.20), vector3(2994.17, 2799.32, 43.92), vector3(2982.46, 2819.50, 45.12),
            vector3(2968.44, 2842.43, 45.86), vector3(2951.64, 2850.44, 48.02),
        },
    },
}

-- ── Rock Breaker minigame ─────────────────────────────────────────────────
-- Weak spots appear on the rock with a ring closing in. Strike when the ring meets the spot.
-- Easy at level 1, harder every level: the ring closes faster and fewer misses are allowed.
Config.Breaker = {
    ring          = { start = 1.15, perLevel = 0.05, min = 0.6 },  -- seconds the ring takes to close
    misses        = 3,                                              -- misses before your arms give out
    hardFromLevel = 6,                                              -- from this level one miss less
    hits = { ore_stone = 4, ore_coal = 4, ore_copper = 5, ore_iron = 5, ore_silver = 6, ore_gold = 7 },
    jackhammer    = { level = 5, hitsLess = 1 },                    -- the jackhammer breaks rocks faster
    yield         = { main = { 2, 3 }, stone = { 0, 2 }, coalChance = 0.25, perfectsPerBonus = 2, maxBonus = 3 },
}

-- ── Dynamite: plant a charge on a big boulder, step back, BOOM: a pile of ore ──
-- (A visual blast only: no real explosion, so it's safe with anti-cheats)
Config.Dynamite = {
    level    = 3,
    perShift = 2,        -- charges you get every shift
    fuse     = 5,        -- seconds
    cooldown = 600,      -- seconds before a boulder is back
    yield    = { 6, 10 },
    gemChance = 0.5,
    model    = 'prop_rock_4_big',
    charge   = 'prop_c4_final_green',
    boulders = {
        { id = 'b1', coords = vector3(2968.0, 2768.0, 41.0) },
        { id = 'b2', coords = vector3(2934.0, 2784.0, 41.0) },
    },
}

-- ── Smelter (in the Mining Office) ────────────────────────────────────────
-- Put ore in, come back when it's done. 2 ore + 1 coal = 1 ingot.
Config.Smelter = {
    secondsPerIngot = 4,
    maxBatch        = 20,
    recipes = {
        { ore = 'ore_copper', amount = 2, fuel = 'ore_coal', fuelAmount = 1, ingot = 'ingot_copper', level = 1 },
        { ore = 'ore_iron',   amount = 2, fuel = 'ore_coal', fuelAmount = 1, ingot = 'ingot_iron',   level = 1 },
        { ore = 'ore_silver', amount = 2, fuel = 'ore_coal', fuelAmount = 1, ingot = 'ingot_silver', level = 2 },
        { ore = 'ore_gold',   amount = 2, fuel = 'ore_coal', fuelAmount = 1, ingot = 'ingot_gold',   level = 4 },
    },
}

-- ── Tools (attached props). Fine-tune positions with your favourite prop tool if needed. ──
Config.Tools = {
    pickaxe = { model = 'prop_tool_pickaxe', bone = 57005, pos = vector3(0.09, -0.53, -0.22), rot = vector3(252.0, 180.0, 0.0) },
    hardhat = { model = 'prop_tool_hardhat', bone = 31086, pos = vector3(0.07, 0.01, 0.0), rot = vector3(180.0, -90.0, 0.0), enabled = true },
}

Config.MineKey = 38   -- E
