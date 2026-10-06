function L(key, ...)
    local str = (Locales[Config.Locale] or Locales.en)[key] or key
    if select('#', ...) > 0 then return str:format(...) end
    return str
end

--- Returns level, xp at start of that level, xp needed for next level (nil at max)
function GetLevelFromXp(xp)
    local level = 1
    for i, need in ipairs(Config.Levels) do
        if xp >= need then level = i end
    end
    return level, Config.Levels[level], Config.Levels[level + 1]
end
