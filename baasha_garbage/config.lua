Config = {}

Config.Locale = 'en'
Config.Debug  = false

-- ── Job definition (shown in the job center tablet) ──────────────────────
Config.Job = {
    label       = 'Garbage Collector',
    icon        = 'fa-solid fa-trash-can',
    description = 'Run city routes in a garbage truck: collect bags, run the compactor and bring the truck home. Find recyclables on the way.',
    maxCrew     = 4,

    depot = {
        coords   = vector4(-321.11, -1532.73, 27.58, 3.5),      -- ped / job center (beside the depot entrance, facing the trucks)
        ped      = 's_m_y_garbage',
        scenario = 'WORLD_HUMAN_CLIPBOARD',
        blip     = { sprite = 318, color = 25, scale = 0.8 },
    },

    vehicle = {
        model   = 'trash',
        deposit = 250,
        spawns  = {
            vector4(-333.84, -1527.28, 27.28, 1.97),
            vector4(-327.55, -1527.69, 27.25, 359.43),
        },
    },

    -- Uniform while on shift (component/prop ids are GTA freemode ids).
    -- components = { { componentId, drawable, texture } }, props = { { propId, drawable (-1 = remove), texture } }
    -- Set to nil to keep players' own clothes.
    uniform = nil,
    --[[ example:
    uniform = {
        male   = { components = { { 11, 56, 0 }, { 8, 59, 0 }, { 4, 36, 0 }, { 6, 25, 0 }, { 3, 0, 0 } }, props = { { 0, -1 } } },
        female = { components = { { 11, 49, 0 }, { 8, 36, 0 }, { 4, 35, 0 }, { 6, 26, 0 }, { 3, 14, 0 } }, props = { { 0, -1 } } },
    },
    ]]

    -- Shown in the tablet. Keep in sync with Config.Route.StopsByLevel / Config.Recyclables below.
    perks = {
        { level = 1, text = '4-stop routes' },
        { level = 3, text = '6-stop routes' },
        { level = 4, text = 'Find copper in bags' },
        { level = 5, text = '8-stop routes' },
        { level = 7, text = 'Find aluminium & steel' },
    },
}

-- ── Route ─────────────────────────────────────────────────────────────────
Config.Route = {
    StopsByLevel  = { [1] = 4, [3] = 6, [5] = 8 },  -- crew leader's level decides route length
    BagsPerStop   = { 2, 5 },
    TruckCapacity = 15,          -- bags before the compactor must run
    CompactTime   = 6000,        -- ms
    PickupRadius  = 25.0,        -- how close to the stop you must be to grab bags
    RearDistance  = 2.5,         -- how close to the back of the truck to throw / compact

    PayPerBag     = { 25, 40 },  -- random per bag (before crew/level bonus)
    XpPerBag      = 6,
    RouteBonus    = 60,          -- per stop, paid when the route is finished at the depot
    RouteXpPerStop = 15,
}

-- How the carried bag sits in the hand (bone + offset + rotation)
Config.Carry = {
    bone = 57005,                           -- SKEL_R_Hand
    pos  = vector3(0.12, 0.0, -0.05),
    rot  = vector3(220.0, 120.0, 0.0),
}

-- Chance per bag thrown. Items that don't exist in your inventory are skipped automatically.
Config.Recyclables = {
    { item = 'plastic',    chance = 25, min = 1, max = 3, level = 1 },
    { item = 'glass',      chance = 15, min = 1, max = 2, level = 1 },
    { item = 'rubber',     chance = 12, min = 1, max = 2, level = 1 },
    { item = 'metalscrap', chance = 15, min = 1, max = 2, level = 2 },
    { item = 'copper',     chance = 8,  min = 1, max = 2, level = 4 },
    { item = 'aluminum',   chance = 8,  min = 1, max = 2, level = 7 },
    { item = 'steel',      chance = 6,  min = 1, max = 2, level = 7 },
}

-- ── Stops (dumpsters around the city) ─────────────────────────────────────
-- Optional exact bag spots per stop (index into Config.Stops). Bags are spread in a small group
-- centred on this point instead of being placed automatically. Use it where the automatic spot
-- lands on a container or planter. Stand where the bags should go and copy your coords (x, y, z, heading).
Config.BagSpots = {
    [3] = vector4(294.63, -2017.56, 19.85, 65.24),
}

Config.Stops = {
    vector4(-168.07, -1662.8, 33.31, 137.5),
    vector4(118.06, -1943.96, 20.43, 179.5),
    vector4(297.94, -2018.26, 20.49, 119.5),
    vector4(424.98, -1523.57, 29.28, 120.08),
    vector4(488.49, -1284.1, 29.24, 138.5),
    vector4(307.47, -1033.6, 29.03, 46.5),
    vector4(239.19, -681.5, 37.15, 178.5),
    vector4(543.51, -204.41, 54.16, 199.5),
    vector4(268.72, -25.92, 73.36, 90.5),
    vector4(267.03, 276.01, 105.54, 332.5),
    vector4(21.65, 375.44, 112.67, 323.5),
    vector4(-546.9, 286.57, 82.85, 127.5),
    vector4(-683.23, -169.62, 37.74, 267.5),
    vector4(-771.02, -218.06, 37.05, 277.5),
    vector4(-1057.06, -515.45, 35.83, 61.5),
    vector4(-1558.64, -478.22, 35.18, 179.5),
    vector4(-1350.0, -895.64, 13.36, 17.5),
    vector4(-1243.73, -1359.72, 3.93, 287.5),
    vector4(-845.87, -1113.07, 6.91, 253.5),
    vector4(-635.21, -1226.45, 11.8, 143.5),
    vector4(-587.74, -1739.13, 22.47, 339.5),
}
