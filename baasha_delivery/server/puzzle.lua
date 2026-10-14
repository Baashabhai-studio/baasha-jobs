-- ── Baasha Delivery — Puzzle (server) ─────────────────────────────────────
-- Layout validation, scoring and the auto-pack solver. The server is the only
-- source of truth for a layout's score; the client and NUI only preview it.

Puzzle = Puzzle or {}

local function rotateCell(x, y) return -y, x end

--- Rotate a cell list `rot` times (90° each), normalised to (0,0).
function Puzzle.RotateCells(cells, rot)
    local c = {}
    for _, p in ipairs(cells) do c[#c + 1] = { p[1], p[2] } end
    for _ = 1, (rot % 4) do
        local nextCells, minX, minY = {}, math.huge, math.huge
        for _, p in ipairs(c) do
            local x, y = rotateCell(p[1], p[2])
            nextCells[#nextCells + 1] = { x, y }
            minX, minY = math.min(minX, x), math.min(minY, y)
        end
        for _, p in ipairs(nextCells) do p[1], p[2] = p[1] - minX, p[2] - minY end
        c = nextCells
    end
    return c
end

--- Validates a layout. Returns ok, resolved (placement + rotated cells), error.
function Puzzle.Validate(manifest, grid, placements)
    if type(placements) ~= 'table' then return false, nil, 'invalid layout' end
    local byId = {}
    for _, p in ipairs(manifest.parcels) do byId[p.id] = p end

    local seen, occ, resolved = {}, {}, {}
    for _, pl in ipairs(placements) do
        if type(pl) ~= 'table' or type(pl.id) ~= 'string' then return false, nil, 'invalid layout' end
        local parcel = byId[pl.id]
        if not parcel then return false, nil, 'unknown parcel' end
        if seen[pl.id] then return false, nil, 'duplicate parcel' end
        seen[pl.id] = true

        local x, y = tonumber(pl.x), tonumber(pl.y)
        local rot = math.floor(tonumber(pl.rot) or 0) % 4
        if not x or not y then return false, nil, 'invalid layout' end
        x, y = math.floor(x), math.floor(y)

        local cells = Puzzle.RotateCells(parcel.cells, rot)
        for _, c in ipairs(cells) do
            local cx, cy = x + c[1], y + c[2]
            if cx < 0 or cy < 0 or cx >= grid.w or cy >= grid.h then
                return false, nil, 'outside the van'
            end
            local key = cy * grid.w + cx
            if occ[key] then return false, nil, 'overlap' end
            occ[key] = pl.id
        end
        resolved[pl.id] = { id = pl.id, x = x, y = y, rot = rot, cells = cells }
    end

    for _, p in ipairs(manifest.parcels) do
        if not seen[p.id] then return false, nil, 'missing parcel' end
    end

    local out = {}
    for _, p in ipairs(manifest.parcels) do out[#out + 1] = resolved[p.id] end
    return true, out, nil
end

--- Scores a valid layout 0..100. Deterministic.
function Puzzle.Score(manifest, grid, resolved)
    local byId = {}
    for _, p in ipairs(manifest.parcels) do byId[p.id] = p end

    -- Delivery order: earlier stops should sit closer to the DOORS (y = 0).
    local front = {}
    for _, r in ipairs(resolved) do
        local minY = math.huge
        for _, c in ipairs(r.cells) do minY = math.min(minY, c[2] + r.y) end
        front[r.id] = minY
    end
    local orderScore = 30
    for i = 1, #manifest.parcels - 1 do
        for j = i + 1, #manifest.parcels do
            local a, b = manifest.parcels[i], manifest.parcels[j]
            if front[a.id] > front[b.id] then orderScore = orderScore - 4 end
        end
    end
    orderScore = math.max(0, orderScore)

    -- Cell occupancy map for the fragile check.
    local occ = {}
    for _, r in ipairs(resolved) do
        for _, c in ipairs(r.cells) do
            occ[(c[2] + r.y) * grid.w + (c[1] + r.x)] = r.id
        end
    end

    -- Weight balance: left vs right half.
    local leftW, rightW = 0, 0
    for _, r in ipairs(resolved) do
        local w = byId[r.id].weight or #r.cells
        local perCell = w / #r.cells
        for _, c in ipairs(r.cells) do
            if (c[1] + r.x) < grid.w / 2 then leftW = leftW + perCell else rightW = rightW + perCell end
        end
    end
    local total = leftW + rightW
    local balance = total > 0 and math.abs(leftW - rightW) / total or 0
    local balanceScore = math.max(0, math.floor(20 - balance * 60))

    -- Fragile: nothing heavy may sit directly toward the cab (y + 1) of a fragile cell.
    local fragilePenalty = 0
    for _, r in ipairs(resolved) do
        if byId[r.id].fragile then
            for _, c in ipairs(r.cells) do
                local above = occ[(c[2] + r.y + 1) * grid.w + (c[1] + r.x)]
                if above and byId[above] and byId[above].heavy then
                    fragilePenalty = fragilePenalty + 3
                end
            end
        end
    end
    local fragileScore = math.max(0, 15 - fragilePenalty)

    local score = 40 + orderScore + balanceScore + fragileScore
    return math.max(0, math.min(100, score))
end

--- Order-independent fingerprint of a layout (used to spot an untouched auto-pack).
function Puzzle.Key(placements)
    local parts = {}
    for _, pl in ipairs(placements or {}) do
        if type(pl) == 'table' then
            parts[#parts + 1] = ('%s:%s:%s:%s'):format(pl.id, tonumber(pl.x) or 0, tonumber(pl.y) or 0, (tonumber(pl.rot) or 0) % 4)
        end
    end
    table.sort(parts)
    return table.concat(parts, '|')
end

--- Validate + score in one call. Returns ok, score, error.
function Puzzle.Check(manifest, grid, placements)
    local ok, resolved, err = Puzzle.Validate(manifest, grid, placements)
    if not ok then return false, nil, err end
    return true, Puzzle.Score(manifest, grid, resolved), nil
end

--- Backtracking packer. Returns placements in manifest order, or nil if it can't fit.
--- Gives up after MAX_STEPS tries so an impossible manifest can never stall the server thread.
local MAX_STEPS = 20000

function Puzzle.AutoPack(manifest, grid)
    local order, area = {}, 0
    for _, p in ipairs(manifest.parcels) do order[#order + 1] = p; area = area + #p.cells end
    if area > grid.w * grid.h then return nil end
    local steps = 0
    table.sort(order, function(a, b)
        if #a.cells ~= #b.cells then return #a.cells > #b.cells end
        return a.stop < b.stop
    end)

    local occ, placed = {}, {}
    local function fits(cells, x, y)
        for _, c in ipairs(cells) do
            local cx, cy = x + c[1], y + c[2]
            if cx < 0 or cy < 0 or cx >= grid.w or cy >= grid.h then return false end
            if occ[cy * grid.w + cx] then return false end
        end
        return true
    end
    local function setCells(cells, x, y, id)
        for _, c in ipairs(cells) do occ[(y + c[2]) * grid.w + (x + c[1])] = id end
    end
    local function solve(i)
        if i > #order then return true end
        steps = steps + 1
        if steps > MAX_STEPS then return false end
        local p = order[i]
        for rot = 0, 3 do
            local cells = Puzzle.RotateCells(p.cells, rot)
            for y = 0, grid.h - 1 do
                for x = 0, grid.w - 1 do
                    if fits(cells, x, y) then
                        setCells(cells, x, y, p.id)
                        placed[p.id] = { id = p.id, x = x, y = y, rot = rot }
                        if solve(i + 1) then return true end
                        setCells(cells, x, y, nil)
                        placed[p.id] = nil
                    end
                end
            end
        end
        return false
    end

    if not solve(1) then return nil end
    local out = {}
    for _, p in ipairs(manifest.parcels) do out[#out + 1] = placed[p.id] end
    return out
end
