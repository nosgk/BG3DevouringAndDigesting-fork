---Fetches display name of a thing given its GUIDSTRING.
---@param target GUIDSTRING
---@return string
function SP_GetDisplayNameFromGUID(target)
    return Osi.ResolveTranslatedString(Osi.GetDisplayName(target))
end

---Returns a character's name given it's GUID
---@param guid GUIDSTRING
---@return CHARACTER
function SP_CharacterFromGUID(guid)
    local name = Ext.Entity.Get(guid).ServerCharacter.Template.Name
    return name .. "_" .. guid
end

-- !!!!! Custom difficulty classes do not work for some reason. It just sets the difficulty class to 0.
---@param character CHARACTER guid of character
---@param stat number stat to get save DC of 1 == Str, 2 == Dex, 3 == Con, 4 == Wis, 5 == Int, 6 == Cha, 0 = Highest
---@return DIFFICULTYCLASS guid that corresponds to that DC
function SP_GetSaveDC(character, stat)
    local entity = Ext.Entity.Get(character)
    local total_boosts = 0
    if entity.BoostsContainer.Boosts.SpellSaveDC ~= nil then
        for _, boost in pairs(entity.BoostsContainer.Boosts.SpellSaveDC) do
            total_boosts = total_boosts + boost.SpellSaveDCBoost.DC
        end
    end
    local highest = 0
    if stat == 0 then
        for i = 1, 6 do
            if entity.Stats.AbilityModifiers[i] > highest then
                highest = entity.Stats.AbilityModifiers[i]
            end
        end
    end
    local DC = 8 + total_boosts + entity.Stats.ProficiencyBonus + (highest or entity.Stats.AbilityModifiers[stat])
    
    return DCTable[DC]
end

---@param character CHARACTER the character to query
---@return number size of the character
function SP_GetCharacterSize(character)
    local charData = Ext.Entity.Get(character)
    return charData.ObjectSize.Size
end

---Checks if a character has a status caused by another character
---@param character CHARACTER
---@param status string
---@param cause CHARACTER
---@return boolean
function SP_HasStatusWithCause(character, status, cause)
    local causeGUID = string.sub(cause, -36)
    local charStatusData = Ext.Entity.Get(character).ServerCharacter.StatusManager.Statuses
    for _, i in ipairs(charStatusData) do
        if i.CauseGUID == causeGUID and i.StatusId == status then
            _P("Found status " .. status .. " in " .. character)
            return true
        end
    end
    return false
end

---Delays a function call by given milliseconds.
---Preferable not to use, as time is not properly synced between server and client.
---@param ms integer
---@param func function
function SP_DelayCall(ms, func)
    local startTime = Ext.Utils.MonotonicTime()
    local handlerId
    handlerId = Ext.Events.Tick:Subscribe(function ()
        if (Ext.Utils.MonotonicTime() - startTime >= ms) then
            Ext.Events.Tick:Unsubscribe(handlerId)
            func()
        end
    end)
end

---Delays a function call for a given number of ticks.
---Server runs at a target of 30hz, so each tick is ~33ms and 30 ticks is ~1 second. This IS synced between server and client.
---@param ticks integer
---@param fn function
function SP_DelayCallTicks(ticks, fn)
    local ticksPassed = 0
    local eventID
    eventID = Ext.Events.Tick:Subscribe(function ()
        ticksPassed = ticksPassed + 1
        if ticksPassed >= ticks then
            fn()
            Ext.Events.Tick:Unsubscribe(eventID)
        end
    end)
end

---Checks a passive against the entity's PassiveContainer directly, because
---Osi.HasPassive can report stale/negative results on some game/SE versions.
---@param character CHARACTER
---@param passiveName string
---@return boolean
function SP_HasPassiveSafe(character, passiveName)
    if Osi.HasPassive(character, passiveName) == 1 then
        return true
    end
    local ok, present = pcall(function ()
        local passives = Ext.Entity.Get(character).PassiveContainer.Passives
        for _, p in ipairs(passives) do
            if p == passiveName or p.Name == passiveName then
                return true
            end
        end
        return false
    end)
    if ok then
        return present == true
    end
    return false
end

---Adds a passive with several fallbacks: Osi.AddPassive may silently do nothing
---when the passive stats are missing or when the entity can't be resolved from
---the Osiris Name_UUID string on some game/SE versions.
---@param character CHARACTER
---@param passiveName string
---@return boolean whether the passive is present on the character afterwards
function SP_AddPassiveSafe(character, passiveName)
    if SP_HasPassiveSafe(character, passiveName) then
        return true
    end
    -- diagnose: is the passive defined in the loaded stats?
    -- (Ext.Stats.Get takes a single stat-name string; there is no (type, name) overload)
    local stat
    local okStat, statErr = pcall(function () stat = Ext.Stats.Get(passiveName) end)
    if not okStat then
        _F("[SP] Ext.Stats.Get errored for " .. passiveName .. ": " .. tostring(statErr))
    elseif stat == nil then
        _F("[SP] Passive not found in loaded stats (stats file failed to load?): " .. passiveName)
    end
    -- attempt 1: Osiris call (must run even if the stats diagnosis above failed)
    local ok, err = pcall(function () Osi.AddPassive(character, passiveName) end)
    if not ok then
        _F("[SP] Osi.AddPassive errored for " .. passiveName .. ": " .. tostring(err))
    end
    if SP_HasPassiveSafe(character, passiveName) then
        return true
    end
    -- fallback 1: resolve the entity via the bare UUID part of the Osiris name
    local bareUuid = string.sub(character, -36)
    pcall(function () Osi.AddPassive(bareUuid, passiveName) end)
    if SP_HasPassiveSafe(character, passiveName) then
        _P("[SP] " .. passiveName .. " added via bare UUID")
        return true
    end
    -- fallback 2: write into the entity's PassiveContainer directly
    local ok3, err3 = pcall(function ()
        local entity = Ext.Entity.Get(bareUuid)
        local passives = entity.PassiveContainer.Passives
        passives[#passives + 1] = stat
        entity.PassiveContainer.Passives = passives
        entity:Replicate("PassiveContainer")
    end)
    if not ok3 then
        _F("[SP] PassiveContainer fallback failed for " .. passiveName .. ": " .. tostring(err3))
    end
    local present = SP_HasPassiveSafe(character, passiveName)
    _P("[SP] AddPassiveSafe(" .. passiveName .. ") -> " .. tostring(present))
    return present
end

---Removes a passive with the same fallbacks as SP_AddPassiveSafe.
---@param character CHARACTER
---@param passiveName string
function SP_RemovePassiveSafe(character, passiveName)
    local ok, err = pcall(function () Osi.RemovePassive(character, passiveName) end)
    if not ok then
        _F("[SP] Osi.RemovePassive errored for " .. passiveName .. ": " .. tostring(err))
    end
    if not SP_HasPassiveSafe(character, passiveName) then
        return
    end
    local bareUuid = string.sub(character, -36)
    pcall(function () Osi.RemovePassive(bareUuid, passiveName) end)
    if not SP_HasPassiveSafe(character, passiveName) then
        return
    end
    pcall(function ()
        local entity = Ext.Entity.Get(bareUuid)
        local passives = entity.PassiveContainer.Passives
        for i, p in ipairs(passives) do
            if p == passiveName or p.Name == passiveName then
                table.remove(passives, i)
                break
            end
        end
        entity.PassiveContainer.Passives = passives
        entity:Replicate("PassiveContainer")
    end)
end
