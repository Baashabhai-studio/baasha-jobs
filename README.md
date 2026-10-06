# Baasha Jobs: Free Civilian Job Pack for FiveM

**By [Baasha Bhai Studio](https://www.baashabhai.com)** · Support: [discord.gg/5XjyX44FQs](https://discord.gg/5XjyX44FQs)

Free and open source civilian jobs with **crews, XP levels, a job center tablet and weekly leaderboards**.
Works on **ESX, QBCore and Qbox**, with **ox_target or qb-target**, and **ox_inventory, qb-inventory or ESX inventory**. All of these are detected automatically.

| Resource | What it is |
|---|---|
| `baasha_jobcore` | Required. Crews, XP and levels, pay, work vehicles, uniforms, job tablet (`/jobs`), leaderboards, framework bridge |
| `baasha_garbage` | Garbage Collector: crew truck routes, bag carrying, compactor, recyclables |

More jobs coming. They all plug into the same core.

🎬 **Showcase video:** _coming soon_

| | |
|---|---|
| ![Job Center tablet](media/job-center-tablet.jpg) | ![Depot](media/depot.jpg) |
| ![Throwing a bag into the truck](media/throw-bag.jpg) | ![Running the compactor](media/compactor.jpg) |

---

## Features

**Job core**
- 📱 **Job center tablet** (`/jobs` or the depot ped): level, XP bar, perks, stats, crew, leaderboard
- 👥 **Crews of up to 4.** Invite nearby players. Pay is shared with a crew bonus of up to +20%.
- ⭐ **10 levels per job.** Pay goes up with level (+5% per level), and perks unlock as you level.
- 🚛 **Work vehicles** are spawned server-side so the whole crew sees the same one. Deposits are refunded based on damage, and keys and fuel are handled for you.
- 👕 **Optional uniforms**, restored when the shift ends
- 🏆 **Weekly leaderboards** for each job
- 🛡️ **Server-side validation** on every action, plus a reward rate limit
- 🔔 **Discord webhook** shift logs
- 🧩 **Open bridge and editable files** for notify, fuel, keys and pay hooks
- 🏷️ **Job vehicles are flagged** with the state bag `baashaJobVehicle`, so car theft, impound and garage scripts can leave them alone

**Garbage Collector**
- Random city routes. Higher levels get longer routes and better finds.
- Bags you can see at each stop, synced across the crew. Bend down to pick one up, carry it, and throw it into the back of the truck.
- Bags are always placed on walkable ground. You can also hand-place them for any stop with `Config.BagSpots`.
- Limited truck capacity, so someone has to **run the compactor**
- **Recyclables** (plastic, glass, rubber, scrap, copper, aluminium, steel) that feed into crafting
- Finish the route at the depot for a route bonus and a new route, without ending the shift

## Requirements
- [ox_lib](https://github.com/overextended/ox_lib)
- [oxmysql](https://github.com/overextended/oxmysql)
- qbx_core, qb-core **or** es_extended
- ox_target **or** qb-target

## Installation
1. Drop the `[baasha_jobs]` folder into your `resources` folder.
2. Add this to `server.cfg` **after** your framework, ox_lib, oxmysql and target:
   ```cfg
   ensure baasha_jobcore
   ensure baasha_garbage
   ```
3. Running `qb-garbagejob`? Stop it, because it uses the same depot:
   ```cfg
   stop qb-garbagejob
   ```
4. Restart the server. The database table is created automatically.

## Configuration
| File | What to change |
|---|---|
| `baasha_jobcore/config.lua` | Framework, pay account, crew bonus, level XP, tablet command and key, webhook |
| `baasha_jobcore/editable/*.lua` | Notifications, vehicle keys, fuel, hooks for pay and level-ups |
| `baasha_garbage/config.lua` | Depot, truck, deposit, uniform, carried bag position, pay per bag, route length by level, recyclables, stops, hand-placed bag spots |

## For developers: adding a job
Register your job from a server script and the core handles the rest: the depot ped, blip, tablet, crew and truck.

```lua
exports.baasha_jobcore:RegisterJob('myjob', {
    label = 'My Job', icon = 'fa-solid fa-briefcase', description = '...', maxCrew = 2,
    depot = { coords = vector4(...), ped = 's_m_m_dockwork_01', blip = { sprite = 280, color = 5 } },
    vehicle = { model = 'boxville2', deposit = 200, spawns = { vector4(...) } },
    perks = { { level = 1, text = '...' } },
})

AddEventHandler('baasha_jobcore:server:shiftStarted', function(jobId, crewId, crew) end)
AddEventHandler('baasha_jobcore:server:shiftEnded', function(jobId, crewId, reason) end)

exports.baasha_jobcore:RewardCrew(crewId, amount, xp)   -- split between crew members
exports.baasha_jobcore:RewardPlayer(src, amount, xp)    -- one member's own task
exports.baasha_jobcore:GiveItem(src, item, count)
exports.baasha_jobcore:GetCrew(crewId) / GetPlayerCrew(src) / IsOnShift(src, jobId) / GetLevel(src, jobId) / EndShift(crewId)
```

Client exports: `GetShift()`, `IsOnShift(jobId)`, `GetWorkVehicle()`, `OpenTablet(jobId)`.

Other scripts can skip job vehicles with:
```lua
if Entity(vehicle).state.baashaJobVehicle then return end
```

## License
Free to use and modify on your own server. **Do not resell, reupload or remove credits.** See [LICENSE](LICENSE).

---
Want more? Premium jobs and MLOs are at **[baashabhai.com](https://www.baashabhai.com)**.
