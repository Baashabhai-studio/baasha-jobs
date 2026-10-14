Config = {}

Config.Locale = 'en'
Config.Debug  = false

-- ── Job definition (shown in the job center tablet) ──────────────────────
Config.Job = {
    label       = 'Delivery Driver',
    icon        = 'fa-solid fa-box',
    description = 'Load a parcel van, run delivery routes across the city and drop every parcel at the right door. Handle fragile cargo, signatures and business bulk stops.',
    maxCrew     = 2,

    depot = {
        coords   = vector4(66.07, 127.88, 79.19, 159.6),   -- GoPostal depot, Vinewood (3 m beside qb-shops' 3x3 m delivery start zone)
        ped      = 's_m_m_postal_01',
        scenario = 'WORLD_HUMAN_CLIPBOARD',
        blip     = { sprite = 478, color = 5, scale = 0.8 },
    },

    vehicle = {
        model   = 'boxville4',   -- Post OP box van. Not boxville2: stock qb-shops deletes every boxville2 in its GoPostal deposit zone
        deposit = 250,
        spawns  = {
            vector4(63.80, 121.28, 79.14, 159.0),
            vector4(70.83, 118.37, 79.15, 159.9),
        },
    },

    -- Uniform while on shift (component/prop ids are GTA freemode ids).
    -- components = { { componentId, drawable, texture } }, props = { { propId, drawable (-1 = remove), texture } }
    -- Set to nil to keep players' own clothes.
    uniform = nil,

    -- Shown in the tablet. Keep in sync with Config.Route / Config.ParcelTypes below.
    perks = {
        { level = 1, text = '5-stop routes, standard parcels' },
        { level = 2, text = 'Bigger van manifests' },
        { level = 3, text = 'Signature parcels, 7-stop routes' },
        { level = 4, text = 'Fragile parcels' },
        { level = 5, text = 'Express parcels, 9-stop routes' },
        { level = 6, text = 'Large parcels' },
        { level = 7, text = 'Hand truck + business bulk stops' },
        { level = 8, text = '11-stop routes, higher tip cap' },
    },
}

-- ── Loading (van loading puzzle) ──────────────────────────────────────────
Config.Loading = {
    mode          = 'puzzle',   -- 'puzzle' = drag & drop minigame · 'quick' = just a progress bar
    allowAutoPack = true,       -- show the Auto-pack button in the puzzle (valid, but a lower score)
    autoPackMaxScore = 60,      -- an untouched auto-pack (or quick mode) scores at most this
    -- You load at the back of the van while it is parked at the depot (Config.Delivery.returnDistance).
    grid          = { w = 8, h = 5 },   -- box van cargo bay (the mule would be 10×6, see README)
    maxFill       = 0.85,       -- a manifest never uses more than this share of the grid (extra parcels are dropped)
    quickTime     = 6000,       -- ms progress bar when mode = 'quick'
    packBonusMax  = 0.15,       -- up to +15% of the route bonus for a perfect packing score
}

-- ── Route ─────────────────────────────────────────────────────────────────
Config.Route = {
    StopsByLevel         = { [1] = 5, [3] = 7, [5] = 9, [8] = 11 },  -- crew leader's level decides route length
    BiggerManifestLevel  = 2,        -- from this level a house stop may get a second parcel (bigger manifest)
    BiggerManifestChance = 25,       -- % chance per house stop for that extra parcel
    RouteBonusPerStop    = 40,       -- per stop, paid when the route is finished at the depot
    RouteXpPerStop       = 15,
    Spread               = 250.0,    -- metres of randomness when picking a neighbourhood (0 = always the closest stops)
}

-- Parcel types: `weight` = how often it is rolled, `level` = leader level needed,
-- `pay` = { min, max } per parcel (before crew/level bonus), `xp` = XP per parcel,
-- `shapes` = pool of Config.Shapes keys the parcel can be.
Config.ParcelTypes = {
    standard  = { level = 1, weight = 60, pay = { 30, 45 }, xp = 8,  shapes = { '1x2', '2x1', '2x2', '2x3' } },
    signature = { level = 3, weight = 20, pay = { 45, 60 }, xp = 12, shapes = { '1x2', '2x2' } },
    fragile   = { level = 4, weight = 10, pay = { 55, 75 }, xp = 16, shapes = { '1x2', '2x1' } },
    express   = { level = 5, weight = 15, pay = { 50, 70 }, xp = 14, shapes = { '1x2', '2x2' } },
    large     = { level = 6, weight = 10, pay = { 60, 80 }, xp = 20, shapes = { '2x3', '3x3', 'L' } },
}

-- Shapes are top-down cell lists (x = width, y = depth from the DOORS side). Rotation is applied at runtime.
Config.Shapes = {
    ['1x2'] = { cells = { { 0, 0 }, { 0, 1 } } },
    ['2x1'] = { cells = { { 0, 0 }, { 1, 0 } } },
    ['2x2'] = { cells = { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } },
    ['2x3'] = { cells = { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 }, { 0, 2 }, { 1, 2 } } },
    ['3x3'] = { cells = { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 0, 1 }, { 1, 1 }, { 2, 1 }, { 0, 2 }, { 1, 2 }, { 2, 2 } } },
    ['L']   = { cells = { { 0, 0 }, { 1, 0 }, { 0, 1 } } },
}

-- ── Delivery ──────────────────────────────────────────────────────────────
Config.Delivery = {
    doorDistance      = 2.5,      -- how close to the door you must be to deliver
    doorHeight        = 3.0,      -- allowed height difference to the door spot (steps, porches)
    wrongDoorDistance = 4.0,      -- "wrong address" if you're this close to a *different* route stop's door
    takeDistance      = 3.0,      -- how close to the back of the van to take / stow a parcel
    rearOffset        = vector3(0.0, -4.2, 0.0),   -- VERIFY · rear doors of the boxville
    rearDoors         = { 2, 3 },                  -- boxville rear doors (opened on take / stow / loading)
    doorCloseDelay    = 2500,     -- ms after taking a parcel before the rear doors shut again
    placeTime         = 1600,     -- ms put-down animation (pickup_object / putdown_low) when leaving a parcel
    releaseAt         = 850,      -- ms the box takes to slide from the hands to the ground (lands as the hands reach it)
    dropAhead         = 0.6,      -- metres in front of the courier the box is set down
    expressTime       = { 90, 150 },   -- seconds allowed per express stop
    expressBonus      = 0.25,     -- +25% on-time bonus
    returnPay         = 0.25,     -- returns pay 25% of base at the depot
    tipPerStar        = 0.08,     -- % of base pay per star above 3
    tipCap            = 250,      -- max tip per stop
    tipCapLvl8        = 500,      -- higher tip cap at level 8
    bulkLevel         = 7,        -- hand truck + business bulk stops (multiple large boxes)
    rating            = { good = 60, ok = 120, late = 180 },  -- seconds at a stop → star thresholds
    returnDistance    = 40.0,     -- the van must be this close to the depot to finish a route
}

-- ── Carrying ──────────────────────────────────────────────────────────────
Config.Carry = {
    -- Box held in front of the chest with anim@heists@box_carry@ (left hand bone, classic offsets)
    bone = 60309,                           -- SKEL_L_Hand
    pos  = vector3(0.025, 0.08, 0.255),
    rot  = vector3(-145.0, 290.0, 0.0),

    -- Box props by size class (first is preferred, the rest are fallbacks). All sizes use the same
    -- carry box by default: the hand offsets above are made for prop_cs_cardbox_01.
    models = {
        small  = { 'prop_cs_cardbox_01' },
        medium = { 'prop_cs_cardbox_01' },
        large  = { 'prop_cs_cardbox_01' },
    },

    handTruckModel  = 'prop_sacktruck_02a',
    handTruckOffset = vector3(0.35, 0.9, -0.15),   -- VERIFY · in front of the ped
}

-- ── Fragile parcels (condition 100 → 0) ───────────────────────────────────
Config.Fragile = {
    maxLossPerReport = 12,      -- clamp per damage report (the client never sets the real loss)
    maxReportsPerMin = 30,      -- reports beyond this are dropped
    dropLoss         = 35,      -- dropping the box while carrying
    impactSpeed      = 7.0,     -- m/s speed drop in one frame = hard impact
    impactLoss       = 6,       -- condition lost per hard impact
    ragdollLoss      = 10,      -- condition lost when you ragdoll with the box
    sprintLossPerSec = 1,       -- condition lost per second of sprinting
    vanDamageScale   = 0.03,    -- vehicle body health (0..1000) → condition loss
    vanDamageReport  = 30,      -- accumulate this much body health before reporting
    damagedBelow     = 20,      -- below this = "Damaged": base pay only, no tip
}

-- ── Signature parcels ─────────────────────────────────────────────────────
Config.Signature = {
    homeChance = 75,                 -- % someone is home to sign
    ringDelay  = { 2000, 6000 },     -- ms knock before the door opens
    padTime    = 6,                  -- seconds before the signature pad auto-confirms
    -- Hand-over spacing along the door heading (metres from the door spot, which is ~0.5 m from the door)
    courierGap   = 0.8,    -- courier steps back this far from the door spot, facing the door
    handoverGap  = 0.2,    -- customer appears this far towards the door from the door spot
}

Config.Customers = {
    'Amelia Hart', 'Marcus Webb', 'Sofia Reyes', 'Ethan Cole', 'Nadia Patel',
    'Lucas Moore', 'Isabella Cruz', 'Omar Haddad', 'Grace Kim', 'Derek Stone',
}

Config.CustomerPeds = {
    'a_f_m_business_02', 'a_m_m_business_01', 'a_f_y_hipster_01', 'a_m_y_hipster_01',
    'a_f_m_beach_01', 'a_m_m_beach_01', 'a_f_o_soucent_01', 'a_m_o_soucent_01',
}

-- ── Optional items (off by default) ───────────────────────────────────────
Config.Items = {
    enabled = false,
    -- Rolled per crew member when a route is finished. Items that don't exist are skipped.
    rewards = {
        { item = 'lost_parcel', chance = 8, min = 1, max = 2, level = 1 },
    },
}

-- ── HUD pill ──────────────────────────────────────────────────────────────
Config.Hud = {
    position = 'top-center',   -- 'top-center' | 'top-left' | 'top-right'
}

-- ── Admin ─────────────────────────────────────────────────────────────────
Config.Admin = {
    ace = 'command',   -- who may use /deliveryspot
}

-- ── Stops (house / shop doors around the city) ────────────────────────────
-- door = where the player stands to deliver, heading FACING the door (into the house), so the doorway is
-- just in front of it. van = optional where to park (vector3),
-- type = 'house' | 'business', area = neighbourhood shown on the label.
-- Each route picks one neighbourhood (a random stop + the stops closest to it), so add as many as you like.
-- House doors come from qb-houserobbery, business back doors from qb-shops deliveries. Record more with /deliveryspot.
local function house(n, area, x, y, z, h) return { label = ('%s · House %s'):format(area, n), door = vector4(x, y, z, h), type = 'house', area = area } end
local function shop(name, x, y, z, h) return { label = name, door = vector4(x, y, z, h), type = 'business', area = name } end

Config.Stops = {
    -- Vinewood Hills
    house(1,  'Vinewood Hills', -784.72, 459.77, 100.39, 34.89),
    house(2,  'Vinewood Hills', -762.21, 430.96, 100.2, 198.27),
    house(3,  'Vinewood Hills', -678.01, 512.13, 113.53, 12.05),
    house(4,  'Vinewood Hills', -640.92, 520.61, 109.88, 9.94),
    house(5,  'Vinewood Hills', -622.84, 488.88, 108.88, 186.87),
    house(6,  'Vinewood Hills', -595.55, 530.28, 107.75, 13.0),
    house(7,  'Vinewood Hills', -536.67, 477.36, 103.19, 235.55),
    house(8,  'Vinewood Hills', -526.64, 516.97, 112.94, 226.17),
    house(9,  'Vinewood Hills', -554.48, 541.26, 110.71, 338.6),
    house(10, 'Vinewood Hills', -500.82, 551.92, 120.6, 159.51),
    house(11, 'Vinewood Hills', -418.09, 568.99, 125.06, 333.59),
    house(12, 'Vinewood Hills', -411.06, 529.18, 122.18, 167.27),
    house(13, 'Vinewood Hills', -348.73, 514.95, 120.65, 316.96),
    house(14, 'Vinewood Hills', -355.93, 469.76, 112.65, 104.28),
    house(15, 'Vinewood Hills', 80.09, 486.26, 148.2, 25.28),
    house(16, 'Vinewood Hills', 57.56, 449.68, 147.03, 147.72),
    house(17, 'Vinewood Hills', -110.05, 501.83, 143.38, 171.41),
    -- Richman Glen
    house(1,  'Richman Glen', -908.66, 693.67, 151.44, 104.28),
    house(2,  'Richman Glen', -951.28, 682.65, 153.58, 177.85),
    house(3,  'Richman Glen', -1056.34, 761.34, 167.32, 92.27),
    house(4,  'Richman Glen', -1130.87, 784.44, 163.89, 56.39),
    house(5,  'Richman Glen', -1117.77, 761.48, 164.29, 205.7),
    house(6,  'Richman Glen', -1065.02, 772.17, 170.06, 179.03),
    house(7,  'Richman Glen', -962.7, 814.09, 177.57, 0.44),
    house(8,  'Richman Glen', -867.34, 785.0, 191.93, 182.44),
    -- South Los Santos
    house(1,  'Davis', 385.18, -1881.78, 26.03, 40.83),
    house(2,  'Davis', 412.47, -1856.38, 27.32, 129.24),
    house(3,  'Davis', 427.21, -1842.09, 28.46, 134.19),
    house(4,  'Davis', 348.77, -1820.95, 28.89, 135.8),
    house(5,  'Davis', 329.42, -1845.8, 27.75, 228.98),
    house(6,  'Davis', 320.27, -1854.06, 27.51, 225.09),
    house(7,  'Davis', 192.29, -1883.23, 25.06, 326.47),
    house(8,  'Davis', 171.52, -1871.53, 24.4, 245.19),
    house(9,  'Davis', 128.24, -1897.02, 23.67, 239.54),
    house(10, 'Davis', 130.6, -1853.22, 25.23, 329.64),
    house(1,  'Grove Street', 76.36, -1948.1, 21.17, 44.97),
    house(2,  'Grove Street', 101.03, -1912.16, 21.41, 331.84),
    house(3,  'Grove Street', 126.73, -1930.12, 21.38, 210.98),
    house(4,  'Grove Street', 114.25, -1961.19, 21.33, 198.18),
    -- Vespucci Canals
    house(1,  'Vespucci Canals', -1076.33, -1026.96, 4.54, 118.14),
    house(2,  'Vespucci Canals', -1064.64, -1057.42, 6.41, 115.35),
    house(3,  'Vespucci Canals', -1063.77, -1054.99, 2.15, 120.47),
    house(4,  'Vespucci Canals', -1054.07, -1000.2, 6.41, 296.69),
    house(5,  'Vespucci Canals', -985.89, -1121.74, 4.55, 297.63),
    house(6,  'Vespucci Canals', -1024.42, -1140.0, 2.75, 213.84),
    house(7,  'Vespucci Canals', -1074.13, -1152.73, 2.16, 118.65),
    house(8,  'Vespucci Canals', -1063.57, -1160.35, 2.75, 210.36),
    house(9,  'Vespucci Canals', -869.53, -1103.41, 6.45, 29.2),
    house(10, 'Vespucci Canals', -869.07, -1105.48, 2.49, 25.76),
    -- Businesses (back doors)
    shop('24/7 Strawberry',        26.45, -1315.51, 29.62, 0.07),
    shop('24/7 Clinton Ave',       379.97, 357.3, 102.56, 26.42),
    shop('LTD Grove Street',       -40.51, -1747.45, 29.29, 326.39),
    shop('LTD Little Seoul',       -702.89, -917.44, 19.21, 181.96),
    shop('LTD Mirror Park',        1160.62, -312.06, 69.28, 3.77),
    shop("Rob's Liquor Vespucci", -1226.92, -901.82, 12.28, 213.26),
    shop("Rob's Liquor Morningwood", -1468.29, -387.61, 38.79, 220.13),
    shop("Rob's Liquor El Rancho", 1129.73, -989.27, 45.97, 280.98),
    shop('Hardware Store Davis',   89.15, -1745.29, 30.09, 315.25),
    shop('Ammu-Nation Little Seoul', -660.61, -938.14, 21.83, 167.22),
    shop('Ammu-Nation Cypress Flats', 820.97, -2146.7, 28.71, 359.98),
    shop('Ammu-Nation Hawick',     249.0, -50.64, 69.94, 60.71),
    shop('Ammu-Nation Downtown',   -5.82, -1107.48, 29.0, 164.32),
    shop('Ammu-Nation La Mesa',    847.83, -1020.36, 27.88, 88.29),
    shop('Ammu-Nation Morningwood', -1302.44, -385.23, 36.62, 303.79),
    shop('Smoke On The Water',     -1162.13, -1568.57, 4.39, 328.52),
}
