Config = {}

-- ── Framework / resources ─────────────────────────────────────────────────
-- 'auto' detects the started resource. Or force one:
-- Framework : 'qbox' | 'qbcore' | 'esx'
-- Target    : 'ox_target' | 'qb-target'
-- Inventory : 'ox_inventory' | 'qb-inventory' | 'esx'   (used for job items/rewards)
Config.Framework = 'auto'
Config.Target    = 'auto'
Config.Inventory = 'auto'

Config.Locale = 'en'
Config.Debug  = false

-- ── Job tablet ────────────────────────────────────────────────────────────
Config.TabletCommand = 'jobs'   -- /jobs opens the job center tablet (false = disable)
Config.TabletKey     = ''       -- e.g. 'F6' (players can rebind in GTA settings). '' = no keybind

-- ── Pay ───────────────────────────────────────────────────────────────────
Config.PayAccount = 'bank'      -- 'bank' | 'cash'
Config.LevelPayBonus = 0.05     -- +5% pay per level above 1 (level 10 = +45%)

-- Crew bonus: multiplier on the WHOLE crew's earnings, split between members.
-- A crew of 3 works ~3x faster, so each member earns solo-rate * 1.15
Config.MaxCrewSize = 4
Config.CrewBonus = { [1] = 1.0, [2] = 1.10, [3] = 1.15, [4] = 1.20 }

-- ── Levels (total XP needed for each level) ───────────────────────────────
Config.Levels = { 0, 500, 1200, 2200, 3500, 5200, 7400, 10000, 13500, 18000 }

-- ── Work vehicles ─────────────────────────────────────────────────────────
Config.ReturnDistance = 40.0    -- vehicle must be this close to the depot to refund the deposit
Config.DamageRefund   = true    -- refund scales with body health (a wrecked truck refunds less)
Config.VehiclePlatePrefix = 'WORK'

-- ── Uniforms ──────────────────────────────────────────────────────────────
Config.UseUniforms = true

-- ── Anti-exploit ──────────────────────────────────────────────────────────
Config.MaxRewardsPerMinute = 40 -- per crew; extra reward calls are dropped and logged
Config.MaxDepotDistance    = 10.0

-- ── Leaderboard ───────────────────────────────────────────────────────────
Config.LeaderboardSize = 10

-- ── Discord logs (leave empty to disable) ─────────────────────────────────
Config.Webhook = ''

-- ── Branding ──────────────────────────────────────────────────────────────
Config.DepotBlips = true
