-- ── Editable server hooks ────────────────────────────────────────────────

Editable = {}

function Editable.Notify(src, msg, type)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Job Center', description = msg, type = type or 'inform' })
end

--- Called after a player is paid. Hook in society cuts, taxes, battle pass XP, etc.
function Editable.OnPaid(src, jobId, amount, xp) end

--- Called when a player reaches a new level in a job.
function Editable.OnLevelUp(src, jobId, level) end
