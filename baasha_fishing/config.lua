Config = {}

Config.Locale = 'en'
Config.Debug  = false

-- ── Job definition (shown in the job center tablet) ──────────────────────
Config.Job = {
    label       = 'Fishing',
    icon        = 'fa-solid fa-fish',
    description = 'Fish from piers and lakes, or rent a boat for deep-sea monsters. Land fish in the reeling minigame, fill your cooler and sell at Del Perro Pier.',
    maxCrew     = 4,

    depot = {
        coords   = vector4(-1839.92, -1235.39, 13.02, 320.7),  -- fishing shop + market + boat rental (Del Perro Pier)
        ped      = 's_m_m_cntrybar_01',
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
        blip     = { sprite = 68, color = 3, scale = 0.8 },
    },

    -- No work vehicle on shift start: boats are rented separately (see Config.Boat)
    vehicle = nil,
    uniform = nil,

    perks = {
        { level = 1, text = 'Del Perro Pier & LSYMC Marina, boat rental' },
        { level = 2, text = 'Alamo Sea unlocked (lake fish)' },
        { level = 3, text = 'Paleto Bay pier unlocked' },
        { level = 4, text = 'Epic fish can bite' },
        { level = 6, text = 'Better rare chance (the reel gets tougher too)' },
        { level = 7, text = 'Legendary fish can bite' },
    },
}

-- ── Fishing ───────────────────────────────────────────────────────────────
Config.CastKey      = 38            -- E
Config.CancelKey    = 73            -- X
Config.BiteTime     = { 4, 11 }     -- seconds until something bites
Config.BiteWindow   = 2.5           -- seconds to react to a bite
Config.MinReelTime  = 2.0           -- anti-cheat: a fish can't be landed faster than this (a perfect strike game takes ~3s)
Config.MaxReelTime  = 45.0
Config.JunkChance   = 8             -- % chance to hook junk instead of a fish (strike game)

-- Fishing game:  'deepdrop' = drop the hook, dodge fish on the way down, hook fish on the way up (several per cast)
--                'strike'   = wait for a bite, then hit the green zone on a spinning ring (one fish per cast)
Config.Minigame = 'deepdrop'

-- Deep Drop: the server builds the water for every cast (which fish, where, how heavy) and checks the result.
-- Depths are metres. mix = fish id (Config.Fish / Config.Junk) → how common it is in that band.
-- Epic and legendary fish only appear from the level set in Config.Rarities.
Config.DeepDrop = {
    hooks       = { base = 3, everyLevels = 3 },     -- 3 hooks, +1 every 3 levels (6 at level 9)
    hazards     = { base = 3, perLevel = 0.8 },      -- jellyfish (sea) / sunken branches (lake)
    speedPerLevel = 0.06,                            -- fish swim 6% faster every level
    rings       = 2,                                 -- gold rings on the way down: +1 hook each
    density     = 1.35,                              -- more or fewer fish everywhere
    maxTime     = 120,                               -- seconds before a drop expires
    habitats = {
        coast = {
            floor = 60, line = { base = 30, perLevel = 4, max = 59 }, hazardDepth = { 12, 50 }, junk = { 'boot', 'can', 'tire' },
            bands = {
                { from = 4,  to = 18, density = 3.0, mix = { anchovy = 5, sardine = 5, mackerel = 3 } },
                { from = 15, to = 34, density = 2.8, mix = { mackerel = 3, seabass = 4, snapper = 3, stingray = 1 } },
                { from = 30, to = 50, density = 2.4, mix = { seabass = 2, snapper = 2, halibut = 3, stingray = 3, octopus = 1 } },
                { from = 45, to = 58, density = 2.2, mix = { halibut = 2, octopus = 3, moray = 3, stingray = 1 } },
            },
        },
        lake = {
            floor = 40, line = { base = 24, perLevel = 3, max = 39 }, hazardDepth = { 8, 36 }, junk = { 'boot', 'tire' },
            bands = {
                { from = 4,  to = 14, density = 3.0, mix = { bluegill = 5, carp = 3, bass = 2 } },
                { from = 10, to = 26, density = 2.8, mix = { carp = 3, catfish = 3, bass = 3, trout = 2 } },
                { from = 22, to = 39, density = 2.4, mix = { catfish = 2, pike = 3, trout = 2, sturgeon = 2, goldcarp = 1 } },
            },
        },
        deep = {
            floor = nil, line = { base = 50, perLevel = 17, max = 205 }, hazardDepth = { 20, 190 },
            bands = {
                { from = 4,   to = 30,  density = 2.4, mix = { mackerel2 = 5, mahi = 3 } },
                { from = 25,  to = 80,  density = 2.0, mix = { mahi = 3, tuna = 4, mackerel2 = 2, barracuda = 2 } },
                { from = 70,  to = 140, density = 1.7, mix = { tuna = 2, barracuda = 3, swordfish = 2, marlin = 2 } },
                { from = 130, to = 215, density = 1.3, mix = { marlin = 2, swordfish = 2, hammerhead = 3, greatwhite = 2 } },
            },
        },
    },
}

-- Strike minigame: a needle spins around a ring, press when it's in the green zone.
-- Easy at level 1, harder every level: smaller zone, faster needle, fewer misses allowed.
-- Rarer fish need more hits and spin faster (see hits/pace in Config.Rarities).
Config.Reel = {
    zone          = { start = 80,  perLevel = 4,  min = 36 },   -- green zone size in degrees
    speed         = { start = 160, perLevel = 15, max = 360 },  -- needle speed in degrees per second
    misses        = 3,                                           -- misses allowed before the fish gets away
    hardFromLevel = 6,                                           -- from this level one miss less is allowed
    junk          = { hits = 2, pace = 0.9 },
}

-- Rarity: weight (chance), level needed, XP, strike hits needed, needle speed multiplier, colour on the catch card
Config.Rarities = {
    common    = { weight = 60, level = 1, xp = 4,  hits = 3, pace = 1.0, color = '#a1a1aa', label = 'Common' },
    uncommon  = { weight = 25, level = 1, xp = 7,  hits = 3, pace = 1.08, color = '#22c55e', label = 'Uncommon' },
    rare      = { weight = 10, level = 1, xp = 12, hits = 4, pace = 1.15, color = '#3b82f6', label = 'Rare' },
    epic      = { weight = 4,  level = 4, xp = 20, hits = 5, pace = 1.25, color = '#a855f7', label = 'Epic' },
    legendary = { weight = 1,  level = 7, xp = 40, hits = 6, pace = 1.35, color = '#eab308', label = 'Legendary' },
}
Config.RareBonusPerLevel = 0.06     -- +6% weight per level to rare/epic/legendary (from level 6: double)

-- Fish caught: 'items'  = real inventory items with icons (install/ has the item lists + images).
--              If an item isn't installed on your server, that catch goes into the cooler instead.
--              'cooler' = always use the built-in catch log (sold at the fish market)
Config.Storage = 'items'

-- Fish Market counter (the kiosk window next to the worker). Used while on a shift:
-- sell, rent a boat, Fish Guide. coords = ground level in front of the window, heading = facing out.
Config.Market = {
    coords = vector4(-1841.20, -1234.45, 12.02, 323.28),
}

-- Floating signs (false = off): "FISHING JOB" over the worker before a shift,
-- "FISH MARKET" at the counter window during a shift
Config.MarketSign = { distance = 30.0, textDistance = 12.0 }

-- ── Spots ─────────────────────────────────────────────────────────────────
-- habitat decides which fish bite. You must face water to cast from the shore.
Config.Spots = {
    { id = 'marina',   label = 'LSYMC Marina',    coords = vector3(-785.95, -1497.84, 1.0),  radius = 35.0, level = 1, habitat = 'coast' },
    { id = 'delperro', label = 'Del Perro Pier',  coords = vector3(-1862.37, -1240.26, 8.62), radius = 40.0, level = 1, habitat = 'coast' },
    { id = 'alamo',    label = 'Alamo Sea',       coords = vector3(1298.56, 4212.42, 33.25), radius = 45.0, level = 2, habitat = 'lake' },
    { id = 'paleto',   label = 'Paleto Bay Pier', coords = vector3(-278.21, 6638.13, 7.55),  radius = 40.0, level = 3, habitat = 'coast' },
}

-- Deep sea: stand on your rented boat at least this far from every spot above and the marina
Config.DeepSea = { minDistance = 350.0, label = 'Deep Sea' }

-- ── Boat rental (at the marina) ───────────────────────────────────────────
Config.Boat = {
    model          = 'dinghy',
    spawn          = vector4(-1797.93, -1229.64, -0.48, 132.8),
    deposit        = 300,
    returnDistance = 60.0,          -- bring it back this close to the spawn for the refund
}

-- ── Fish ──────────────────────────────────────────────────────────────────
-- weight in kg, price per kg. item = inventory item name (only used when Config.Storage = 'items')
Config.Fish = {
    -- Coast (piers, marina)
    { id = 'anchovy',    label = 'Anchovy',          rarity = 'common',    habitat = { 'coast' }, weight = { 0.05, 0.2 }, price = 40, item = 'fish_anchovy' },
    { id = 'sardine',    label = 'Sardine',          rarity = 'common',    habitat = { 'coast' }, weight = { 0.1, 0.3 },  price = 35, item = 'fish_sardine' },
    { id = 'mackerel',   label = 'Mackerel',         rarity = 'common',    habitat = { 'coast' }, weight = { 0.3, 1.2 },  price = 18, item = 'fish_mackerel' },
    { id = 'seabass',    label = 'Sea Bass',         rarity = 'uncommon',  habitat = { 'coast' }, weight = { 1.0, 5.0 },  price = 11, item = 'fish_seabass' },
    { id = 'snapper',    label = 'Red Snapper',      rarity = 'uncommon',  habitat = { 'coast' }, weight = { 1.0, 6.0 },  price = 12, item = 'fish_snapper' },
    { id = 'halibut',    label = 'Halibut',          rarity = 'rare',      habitat = { 'coast' }, weight = { 5.0, 25.0 }, price = 7, item = 'fish_halibut' },
    { id = 'stingray',   label = 'Stingray',         rarity = 'rare',      habitat = { 'coast' }, weight = { 3.0, 15.0 }, price = 9, item = 'fish_stingray' },
    { id = 'octopus',    label = 'Octopus',          rarity = 'epic',      habitat = { 'coast' }, weight = { 2.0, 9.0 },  price = 30, item = 'fish_octopus' },
    { id = 'moray',      label = 'Moray Eel',        rarity = 'epic',      habitat = { 'coast' }, weight = { 2.0, 12.0 }, price = 24, item = 'fish_moray' },

    -- Lake (Alamo Sea)
    { id = 'bluegill',   label = 'Bluegill',         rarity = 'common',    habitat = { 'lake' },  weight = { 0.1, 0.5 },  price = 30, item = 'fish_bluegill' },
    { id = 'carp',       label = 'Carp',             rarity = 'common',    habitat = { 'lake' },  weight = { 1.0, 8.0 },  price = 4, item = 'fish_carp' },
    { id = 'catfish',    label = 'Catfish',          rarity = 'uncommon',  habitat = { 'lake' },  weight = { 2.0, 15.0 }, price = 6, item = 'fish_catfish' },
    { id = 'bass',       label = 'Largemouth Bass',  rarity = 'uncommon',  habitat = { 'lake' },  weight = { 1.0, 5.0 },  price = 12, item = 'fish_bass' },
    { id = 'trout',      label = 'Rainbow Trout',    rarity = 'rare',      habitat = { 'lake' },  weight = { 1.0, 4.0 },  price = 24, item = 'fish_trout' },
    { id = 'pike',       label = 'Northern Pike',    rarity = 'rare',      habitat = { 'lake' },  weight = { 2.0, 10.0 }, price = 10, item = 'fish_pike' },
    { id = 'sturgeon',   label = 'Sturgeon',         rarity = 'epic',      habitat = { 'lake' },  weight = { 10.0, 60.0 }, price = 6, item = 'fish_sturgeon' },
    { id = 'goldcarp',   label = 'Golden Carp',      rarity = 'legendary', habitat = { 'lake' },  weight = { 3.0, 10.0 }, price = 110, item = 'fish_goldcarp' },

    -- Deep sea (boat)
    { id = 'tuna',       label = 'Bluefin Tuna',     rarity = 'uncommon',  habitat = { 'deep' },  weight = { 20.0, 120.0 }, price = 3, item = 'fish_tuna' },
    { id = 'mahi',       label = 'Mahi-Mahi',        rarity = 'uncommon',  habitat = { 'deep' },  weight = { 5.0, 20.0 },   price = 7, item = 'fish_mahi' },
    { id = 'mackerel2',  label = 'King Mackerel',    rarity = 'common',    habitat = { 'deep' },  weight = { 2.0, 10.0 },   price = 6, item = 'fish_kingmackerel' },
    { id = 'barracuda',  label = 'Barracuda',        rarity = 'rare',      habitat = { 'deep' },  weight = { 5.0, 25.0 },   price = 9, item = 'fish_barracuda' },
    { id = 'swordfish',  label = 'Swordfish',        rarity = 'epic',      habitat = { 'deep' },  weight = { 50.0, 250.0 }, price = 3, item = 'fish_swordfish' },
    { id = 'marlin',     label = 'Blue Marlin',      rarity = 'epic',      habitat = { 'deep' },  weight = { 80.0, 400.0 }, price = 2, item = 'fish_marlin' },
    { id = 'hammerhead', label = 'Hammerhead Shark', rarity = 'legendary', habitat = { 'deep' },  weight = { 80.0, 300.0 }, price = 4, item = 'fish_hammerhead' },
    { id = 'greatwhite', label = 'Great White Shark', rarity = 'legendary', habitat = { 'deep' }, weight = { 300.0, 900.0 }, price = 2, item = 'fish_greatwhite' },
}

-- Junk you can hook instead (small XP, tiny value)
Config.Junk = {
    { id = 'boot',  label = 'Old Boot',     value = 2, item = 'junk_boot' },
    { id = 'can',   label = 'Rusty Tin Can', value = 1, item = 'junk_can' },
    { id = 'tire',  label = 'Bike Tire',    value = 3, item = 'junk_tire' },
}
