Config = {}

Config.Locale = 'en'
Config.Debug  = false

-- ── Job definition (shown in the job center tablet) ──────────────────────
Config.Job = {
    label       = 'Lifeguard',
    icon        = 'fa-solid fa-life-ring',
    description = 'Keep Vespucci Beach safe. Watch the water from the towers, pull drowning swimmers out by swimming or jet ski, bring people back with CPR, treat jellyfish stings and clear the water when a shark shows up.',
    maxCrew     = 4,

    depot = {
        coords   = vector4(-1521.03, -1271.51, 1.94, 101.57),  -- lifeguard HQ boss (start / end the shift)
        ped      = 's_m_y_baywatch_01',
        scenario = 'WORLD_HUMAN_CLIPBOARD',
        blip     = { sprite = 280, color = 1, scale = 0.85 },
    },

    -- The lifeguard ATV, spawned on the sand when the shift starts
    vehicle = {
        model   = 'blazer2',
        deposit = 150,
        spawns  = { vector4(-1520.58, -1267.9, 2.0, 113.76) },
    },

    -- Uniform while on shift (GTA freemode component ids), nil = players keep their own clothes.
    -- components = { { componentId, drawable, texture } }, props = { { propId, drawable (-1 = remove), texture } }
    uniform = nil,

    perks = {
        { level = 1, text = 'Tower watch, jet ski rescues, floating swimmers and CPR' },
        { level = 2, text = 'Jellyfish stings' },
        { level = 3, text = 'Shark alerts' },
        { level = 4, text = 'Bigger bonus for calls you spot yourself' },
        { level = 5, text = 'Busier beach: calls come in faster' },
    },
}

-- ── Lifeguard towers (stand on the platform). Watch the water here and bring rescued swimmers here. ──
Config.Towers = {
    { label = 'Tower 1', coords = vector4(-1560.3, -1155.18, 3.91, 134.17) },
    { label = 'Tower 2', coords = vector4(-1466.07, -1388.85, 4.14, 106.53) },
    { label = 'Tower 3', coords = vector4(-1431.59, -1509.9, 3.71, 109.44) },
    { label = 'Tower 4', coords = vector4(-1372.39, -1624.2, 3.73, 114.35) },
}

-- Lay a rescued swimmer down anywhere on the sand: on the beach (within `beach` metres of a tower),
-- out of the water, and not right at a tower (its ramp and railings get in the way)
Config.Shore = { beach = 300.0, awayFromTower = 9.0, skiDepth = 1.4 }  -- skiDepth: stop the jet ski where the water is shallower than this and they climb off

-- The person / shark of a call appears when a crew member is this close (metres). Big enough to see them from the towers.
Config.SpawnDistance = 260.0

-- Where swimmers get into trouble (in the water). Add more with /lgspot water (admins).
Config.WaterSpots = {
    vector4(-1427.29, -1653.47, -0.47, 345.98),
    vector4(-1432.19, -1633.48, -0.47, 18.91),
    vector4(-1469.44, -1575.51, -0.17, 7.53),
    vector4(-1485.25, -1535.39, 0.73, 19.86),
    vector4(-1529.91, -1434.62, 0.5, 1.99),
    vector4(-1535.68, -1386.73, 0.19, 11.02),
    vector4(-1575.39, -1303.33, 0.21, 353.4),
}

-- Beach spots (on the sand) for unconscious people and jellyfish stings. Add more with /lgspot beach.
Config.BeachSpots = {
    vector3(-1571.65, -1157.84, 2.41), vector3(-1547.53, -1152.54, 2.41),
    vector3(-1477.36, -1385.94, 2.64), vector3(-1453.53, -1392.43, 2.64),
    vector3(-1443.02, -1507.57, 2.21), vector3(-1418.89, -1512.84, 2.21),
    vector3(-1383.97, -1622.86, 2.23), vector3(-1359.48, -1626.04, 2.23),
}

-- ── Calls ─────────────────────────────────────────────────────────────────
-- pay / xp per call (split over the crew, the core adds crew + level bonuses). weight = how often it comes in.
-- timeout = seconds to get there before bystanders handle it (no pay).
Config.Calls = {
    -- Awake and waving, further out at sea: take the jet ski. On the beach they thank you and go.
    drowning = {
        label = 'Drowning swimmer', icon = 'fa-solid fa-person-swimming', water = true,
        level = 1, weight = 5, pay = 170, xp = 40, timeout = 210,
        farther = 85.0,       -- metres further out than the water spots (from the nearest tower)
    },
    -- Face down and not moving, close to the beach: swim out, tow them in, CPR on the sand.
    -- (No jet ski: you can't sit an unconscious person on a seat.)
    floating = {
        label = 'Floating swimmer', icon = 'fa-solid fa-water', water = true,
        level = 1, weight = 3, pay = 150, xp = 38, timeout = 210,
    },
    unconscious = {
        label = 'Unconscious person', icon = 'fa-solid fa-heart-pulse',
        level = 1, weight = 2, pay = 120, xp = 30, timeout = 240,
    },
    jellyfish = {
        label = 'Jellyfish sting', icon = 'fa-solid fa-kit-medical',
        level = 2, weight = 3, pay = 90, xp = 22, timeout = 240,
    },
    shark = {
        label = 'Shark sighting', icon = 'fa-solid fa-triangle-exclamation', water = true,
        level = 3, weight = 2, pay = 200, xp = 45, timeout = 150,
    },
}

-- Radio calls come in by themselves while nobody spots anything from a tower
Config.Dispatch = {
    first        = 25,            -- seconds after the shift starts
    interval     = { 70, 130 },   -- seconds between calls
    fasterFrom   = 5,             -- level: calls come in 25% faster
}

-- ── Tower watch: the binoculars minigame ─────────────────────────────────
-- Scan the water, click the swimmer in trouble (or the shark fin). Spotted calls pay a bonus.
Config.Watch = {
    mode         = 'binoculars',  -- 'binoculars': real binoculars over the real sea · 'scope': the old 2D minigame screen
    fov          = { wide = 40.0, close = 6.0 },  -- binocular zoom range (scroll wheel)
    markFov      = 18.0,          -- zoom in at least this far before you can mark someone
    markRadius   = 0.06,          -- how close to the crosshair they must be (part of the screen)
    troubleAfter = { 3, 8 },      -- seconds before someone gets into trouble
    maxTurn      = 85.0,          -- how far you can turn left/right from the tower's view
    cooldown     = 15,                                   -- seconds between watches
    time         = { start = 26, perLevel = 1.0, min = 15 },
    swimmers     = { start = 8,  perLevel = 1,   max = 16 },
    decoysFrom   = 2,             -- level: friendly wavers start to show up (they're NOT in trouble)
    sharkChance  = 0.3,           -- from the shark level: chance the watch finds a fin instead
    falseAlarm   = 3,             -- seconds lost for marking the wrong thing
    bonus        = 0.25,          -- +25% pay and XP for calls you spot yourself
    bigBonusFrom = 4,             -- level: +50% instead
    bigBonus     = 0.5,
}

-- ── Beach life ────────────────────────────────────────────────────────────
-- People enjoying the water in front of the towers closest to you (swimming, treading water, wading).
-- Only you see your own (no network or server cost). The swimmer you spot from a tower comes from them.
Config.Ocean = {
    enabled  = true,
    perTower = { swimmers = 12, far = 3, waders = 4 },  -- far = strong swimmers way out: the drowning person is one of them
    towers   = 2,       -- the nearest N towers get people
    range    = 300.0,   -- ...when you're this close to them (metres)
    maxOut   = 75.0,    -- how far out to sea from the tower they swim (metres)
    farOut   = 150.0,   -- ...and the 'far' swimmers, between maxOut and this
    spread   = 70,      -- metres left / right of the tower
    minDepth = 1.6,     -- swimmers stay where the water is at least this deep
}

-- ── CPR minigame ──────────────────────────────────────────────────────────
-- Compressions on the beat (bpm), then 2 rescue breaths. pass = rhythm needed to bring them back.
Config.Cpr = {
    cycles = 2, compressions = 30, bpm = 110, perfect = 0.07, good = 0.15, pass = 0.6, maxExtra = 1,
    savePay  = 120, saveXp  = 35,    -- extra when the heart restarts
    lostPay  = 40,  lostXp  = 10,    -- paramedics take over: something for trying
}

-- ── First aid (jellyfish) ─────────────────────────────────────────────────
Config.FirstAid = {
    steps = {
        { label = 'Rinse the sting with vinegar', check = 'easy' },
        { label = 'Pull out the tentacles',       check = 'medium' },
        { label = 'Clean the skin',               check = 'easy' },
    },
    keys    = { 'e' },
    packTime = 3500,   -- ms: cold pack at the end
    minTime  = 5,      -- seconds (server check)
}

-- ── Shark sighting ────────────────────────────────────────────────────────
Config.Shark = {
    model     = 'a_c_sharktiger',
    clearTime = 10,     -- seconds blowing the whistle at the tower to clear the water
}

-- ── Lifeguard jet ski (rented at HQ) ──────────────────────────────────────
Config.JetSki = {
    level          = 1,
    model          = 'seashark2',
    spawn          = vector4(-1543.83, -1282.07, 0.69, 118.97),
    deposit        = 0,
    returnDistance = 60.0,
    atTowers       = true,    -- also get one on the sand next to any tower (it appears in the water in front of it)
    outFromShore   = 14.0,    -- metres past the waterline, so it floats instead of sitting on the sand
}

-- ── People ────────────────────────────────────────────────────────────────
-- Outfit parts taken off every rescued person: 5 = bags / backpacks, 9 = vests and gear.
-- (Hats and glasses are always removed too.)
Config.StripComponents = { 5, 9 }

-- People who get into trouble. Don't add a_m_y_beach_02: its backpack can't be taken off.
Config.VictimModels = {
    'a_m_y_beach_01', 'a_m_y_beach_03', 'a_m_m_beach_01', 'a_m_m_beach_02', 'a_f_y_beach_01', 'a_f_m_beach_01', 'a_m_y_musclbeac_01',
}

-- How the victim hangs on while you swim (attached to you) and on your shoulder on land.
-- Fine-tune with your favourite prop / attach tool if they look off.
-- Where you kneel for CPR: metres beside the patient's chest (side), towards their head (along),
-- up/down (height) and an extra turn in degrees. breathAlong / breathSide: extra move for the rescue
-- breaths (towards the head / further out) so your mouth meets theirs. Tune live with /lgcprpos.
-- kneel = 'anim': always the side the CPR animations were made for (the ending reaches for the head),
--         'other': the opposite of 'anim' (if the ending ever reaches for the legs on every CPR),
--         'near': whichever side you walk up on.
Config.CprPosition = { side = 0.72, along = 0.0, height = 0.0, turn = 0.0, breathAlong = 0.32, breathSide = -0.12, kneel = 'anim' }

-- Where you kneel for jellyfish first aid: metres beside the patient's stung leg (side) and along the
-- leg (along: + towards the foot, - towards the hip)
Config.FirstAidPosition = { side = 0.75, along = 0.0 }

-- Equipment laid out around the patient while you treat them (fades in, removed when done).
-- side = metres from the patient towards YOU (negative = their other side), along = metres along their body
-- (cpr: + towards the head from the chest; firstaid: + towards the foot from the stung knee),
-- turn = degrees. models = first one that exists in the game is used.
Config.TreatProps = {
    enabled = true,
    cpr = {
        { models = { 'xm_prop_x17_bag_med_01a', 'prop_med_bag_01b', 'prop_med_bag_01' }, side = 0.80, along = -0.85, turn = 25.0 },  -- medical bag by the hips
        { models = { 'prop_medic_defibrillator', 'prop_ld_health_pack' }, side = 0.55, along = 0.95, turn = 90.0 },                      -- defibrillator by the head
        { models = { 'prop_ld_health_pack', 'v_ret_ta_firstaid' }, side = -0.70, along = -0.20, turn = -15.0 },                          -- open kit on their other side
    },
    firstaid = {
        { models = { 'prop_ld_health_pack', 'v_ret_ta_firstaid' }, side = 0.85, along = -0.60, turn = 10.0 },                            -- first aid kit
        { models = { 'prop_ld_flow_bottle' }, side = 0.50, along = 0.45, turn = 0.0 },                                                   -- vinegar for the sting
        { models = { 'xm_prop_x17_bag_med_01a', 'prop_med_bag_01b', 'prop_med_bag_01' }, side = 1.00, along = 0.65, turn = -30.0 },    -- medical bag
    },
}

-- How high a floating (unconscious) swimmer lies: body at the surface, face in the water
Config.FloatHeight = 0.85


-- Towing a swimmer: pos.x/pos.y = metres right/forward of you, pos.z = height above the WATER SURFACE
-- (they float on the waves, they don't follow you under), rot.z = their heading relative to yours
Config.Tow   = { pos = vector3(0.0, 1.05, 0.85), rot = vector3(0.0, 0.0, 180.0) }
Config.Carry = { pos = vector3(0.27, 0.15, 0.63), rot = vector3(0.0, 0.0, 0.0) }

Config.ActionKey = 38   -- E
