--- purely visual updating
---@param pred CHARACTER
---@param weight integer How many weight placeholders in inventory.
function SP_UpdateBelly(pred, weight)

    if weight == 0 then
        local predData = Ext.Entity.Get(pred)
        if predData.CharacterCreationAppearance ~= nil then
            for k, v in pairs(predData.CharacterCreationAppearance.Visuals) do
                if AllBellies[v] == true then
                    Osi.RemoveCustomVisualOvirride(pred, v)
                end
            end
        end
        return
    end
    local predRace = Osi.GetRace(pred, 1)
    -- These races use the same or similar model.

    if CustomRaceAliases[predRace] ~= nil then
        predRace = CustomRaceAliases[predRace]
    end
    if RaceAliases[predRace] ~= nil then
        predRace = RaceAliases[predRace]
    end

    local sex = Osi.GetBodyType(pred, 1)
    local raceSettings = nil
    local bodyShape = "Default"
    -- try the custom race config first, then the built-in table; a candidate is only
    -- valid if the referenced belly set actually exists (user configs can point at
    -- sets that don't exist, e.g. Dragonborn4), otherwise the next candidate is used
    local candidates = {}
    if CustomRacesBellies[predRace] ~= nil then
        table.insert(candidates, CustomRacesBellies[predRace])
    end
    if BellyTable[predRace] ~= nil then
        table.insert(candidates, BellyTable[predRace])
    end
    for _, candidate in ipairs(candidates) do
        -- configs with Sexes == false keep their entries under the "Sex" key
        local sexEntry = candidate.Sexes == false and candidate.Sex or candidate[sex]
        if sexEntry ~= nil then
            local shape = "Default"
            if sexEntry.BodyShapes then
                local tags = Ext.Entity.Get(pred).Tag.Tags
                for _, v in pairs(tags) do
                    if v == "d3116e58-c55a-4853-a700-bee996207397" then
                        shape = "Strong"
                    end
                end
            end
            if sexEntry[shape] ~= nil and BellySets[sexEntry[shape]] ~= nil then
                raceSettings = candidate
                bodyShape = shape
                break
            end
        end
    end
    if raceSettings == nil then
        _P("Race " .. predRace .. " does not support bellies (no valid belly set for sex " .. sex .. ")")
        return
    end
    -- fixes most npcs not having a field that stores visual overrides
    local predData = Ext.Entity.Get(pred)
    if predData.CharacterCreationAppearance == nil then
        predData:CreateComponent("CharacterCreationAppearance")
    end

    
    -- base volume ~ base weight
    -- offset is to account for some empty space inside the pred, which allows the pred to swallow light items without belly sticking out
    local baseVolume = 150
    local baseWeight = 80
    local offset = 10
    local sizeMulti = predData.GameObjectVisual.Scale ^ 3
    local volume = (weight * baseVolume / baseWeight - offset) * (SP_MCMGet("BellyScale") / 100) / sizeMulti

    local bellySize = 0
    local bellyShape = ""
    for k, v in pairs(BellySets[raceSettings[sex][bodyShape]]) do
        if volume > k and k > bellySize then
            bellySize = k
            bellyShape = v
        end
    end
    

    -- Clears overrides. Changed this so it will remove all belly-related visual overrides, meaning it should not break on polymorph
    for k, v in pairs(predData.CharacterCreationAppearance.Visuals) do
        if AllBellies[v] == true and bellyShape ~= v then
            Osi.RemoveCustomVisualOvirride(pred, v)
        elseif bellyShape == v then
            bellyShape = ""
        end
    end
    -- Delay is necessary, otherwise will not work.
    if bellyShape ~= "" then
        SP_DelayCallTicks(2, function ()
            _P("Updating belly visual; Race: " .. predRace .. " Sex: " .. sex .. " Belly: " .. bellyShape)
            Osi.AddCustomVisualOverride(pred, bellyShape)
            -- probe: confirm the override actually stuck (distinguishes code-path
            -- failure from a visual that applies but silently fails to render)
            SP_DelayCallTicks(2, function ()
                local visuals = {}
                local app = Ext.Entity.Get(pred).CharacterCreationAppearance
                if app ~= nil then
                    for _, v in pairs(app.Visuals) do
                        table.insert(visuals, tostring(v))
                    end
                end
                _P("Visuals after override: " .. table.concat(visuals, ", "))
            end)
            -- belly spawn diagnostics (TEMPORARY): the same visual resource via
            -- alternative CC slots, a NeedsSkeletonRemap bank variant, and a
            -- vanilla beard control. One swallow after a fresh load reports
            -- which chain actually spawns; observe the character right after.
            if SP_BellyProbesDone == nil then SP_BellyProbesDone = {} end
            if not SP_BellyProbesDone[pred] then
                SP_BellyProbesDone[pred] = true
                local probes = {
                    { "7f5ecdda-2aa5-40e8-8dac-1f6f2a4c16cc", "DragonbornTop" },
                    { "ea9861eb-ac79-4c7a-b0fb-df74b8df3283", "DragonbornJaw" },
                    { "700f2c4d-aa36-4f0a-9afc-f05939841739", "DragonbornChin" },
                    { "3aad9f7f-557e-4ea0-88ed-41fcd38f3c8a", "Hair" },
                    { "ef7ec058-5dcc-4857-b9dc-8f15ba5ced15", "Beard+Remap" },
                }
                for i, pr in ipairs(probes) do
                    AllBellies[pr[1]] = true
                    SP_DelayCallTicks(8 + i * 3, function ()
                        _P("[SP] belly probe " .. pr[2] .. " applied: " .. pr[1])
                        Osi.AddCustomVisualOverride(pred, pr[1])
                    end)
                end
                AllBellies["06d99409-955b-474b-91ed-6fb8a69e3d3d"] = true
                SP_DelayCallTicks(30, function ()
                    _P("[SP] belly probe VanillaBeard applied")
                    Osi.AddCustomVisualOverride(pred, "06d99409-955b-474b-91ed-6fb8a69e3d3d")
                end)
            end
        end)
    end
end

---Checks if eating an item would exceed pred's carry limit.
---@param pred CHARACTER
---@param item GUIDSTRING
function SP_CanFitItem(pred, item)
    local predData = Ext.Entity.Get(pred)
    local predRoom = predData.EncumbranceStats["HeavilyEncumberedWeight"] - predData.InventoryWeight.Weight
    -- Cavernous passive does not reduce the weight of items because of how it works
    local itemData = Ext.Entity.Get(item).Data.Weight
    if predRoom > itemData then
        return true
    else
        _P("Can't fit " .. item " inside " .. pred)
        return false
    end
end

---Checks if any of the pred's prey are still alive
---@param pred CHARACTER the pred to querey
---@param onlyLethal? boolean if true, only check prey being digested
---@return boolean
function SP_HasLivingPrey(pred, onlyLethal)
    for prey, _ in pairs(VoreData[pred].Prey) do
        if VoreData[prey].Digestion ~= DType.Dead and (VoreData[prey].Digestion == DType.Lethal or not onlyLethal) then
            return true
        end
    end
    return false
end


---Checks if eating a character would exceed pred's carry limit.
---@param pred CHARACTER
---@param prey CHARACTER
---@param digestionType integer
---@return boolean
function SP_CanFitPrey(pred, prey, digestionType)
    local predData = Ext.Entity.Get(pred)
    local predRoom = (predData.EncumbranceStats["HeavilyEncumberedWeight"] - predData.InventoryWeight.Weight) // GramsPerKilo

    local preyWeight = SP_CalculateWeightReduction(pred, prey, digestionType)

    if preyWeight > predRoom then
        _P("Can't fit " .. SP_GetDisplayNameFromGUID(prey) .. " inside of " .. SP_GetDisplayNameFromGUID(pred) ..
            "'s stomach!")
        return false
    else
        return true
    end
end

---returns what swallowed status should be appled to a prey on swallow
---@param pred CHARACTER
---@param prey CHARACTER
---@return string
function SP_GetPartialSwallowStatus(pred, prey)
    if Osi.HasPassive(pred, "SP_MuscleControl") == 1 and Osi.IsEnemy(pred, prey) == 0 then
        return "SP_PartiallySwallowedGentle"
    else
        return "SP_PartiallySwallowed"
    end
end



---returns what swallowed status should be appled to a prey
---@param pred CHARACTER
---@param prey CHARACTER
---@param digestionType integer
---@param locus string
---@return string
function SP_GetSwallowedVoreStatus(pred, prey, digestionType, locus)
    local correctlocus = locus == 'O' or SP_MCMGet("StatusBonusLocus") ~= 'Stomach'
    -- for k, v in pairs(SP_MCMGet("StatusBonusLocus")) do
    --     if string.sub(v, 1, 1) == locus then
    --         correctlocus = true
    --     end
    -- end

    --- !!! when adding status here's don't forget to add it to condition.khn !!!
    if correctlocus then
        if digestionType == DType.Endo then
            if Osi.HasPassive(prey, "SP_Gastronaut") == 1 or Osi.HasPassive(pred, "SP_MuscleControl") == 1 or Osi.HasPassive(pred, "SP_SC_StomachShelter") == 1 then
                return "SP_SwallowedXray"
            elseif Osi.HasPassive(prey, "SP_BellyDiver") == 1 then
                return "SP_SwallowedDiver"
            else
                return "SP_SwallowedGentle"
            end
        elseif Osi.HasPassive(prey, "SP_BellyDiver") == 1 then
            return "SP_SwallowedDiver"
        else
            return "SP_Swallowed"
        end
    else
        return "SP_Swallowed"
    end
end

---@param pred CHARACTER
---@param prey CHARACTER
---@return string, string
function SP_GetSwallowSkill(pred, prey)
    local predStat = 'Athletics'
    local preyStat = 'Athletics'
    if Osi.HasSkill(pred, "Acrobatics") > Osi.HasSkill(pred, "Athletics") then
        predStat = "Acrobatics"
    end
    if Osi.HasSkill(prey, "Acrobatics") > Osi.HasSkill(prey, "Athletics") then
        preyStat = "Acrobatics"
    end
    if Osi.HasPassive(pred, "SP_SC_GreatHunger") == 1 and Osi.HasSkill(pred, "Intimidation") > Osi.HasSkill(pred, predStat) then
        predStat = "Intimidation"
    end
    return predStat, preyStat
end

---Teleports a prey to a pred. If prey is "ALL", teleports all prey to their respective preds.
---@param prey CHARACTER | string
function SP_TeleportToPred(prey)
    if prey == "ALL" then
        for k, v in pairs(VoreData) do
            
            -- _P(v.Pred)
            if v.Pred ~= "" then
                local predX, predY, predZ = Osi.GetPosition(v.Pred)
                Osi.TeleportToPosition(k, predX, predY, predZ, "", 0, 0, 0, 0, 1)
            end
        end
    -- .Pred is always a string
    elseif VoreData[prey] ~= nil and VoreData[prey].Pred ~= "" then
        local predX, predY, predZ = Osi.GetPosition(VoreData[prey].Pred)
        Osi.TeleportToPosition(prey, predX, predY, predZ, "", 0, 0, 0, 0, 1)
    end

end

---@param pred CHARACTER
---@param forRegurgitate? boolean set this to true if this function is used to get loci for regurgitation spells
function SP_GetPredLoci(pred, forRegurgitate)

    if forRegurgitate then
        return 'OAUC'
    end
    local loci = ''
    local skipA = false
    if SP_HasPassiveSafe(pred, "SP_CanOralVore") then
        if forRegurgitate then
            loci = loci .. 'OA'
            skipA = true
        else
            loci = loci .. 'O'
        end
    end
    if not skipA and SP_HasPassiveSafe(pred, "SP_CanAnalVore") then
        loci = loci .. 'A'
    end
    if SP_HasPassiveSafe(pred, "SP_CanUnbirth") then
        loci = loci .. 'U'
    end
    if SP_HasPassiveSafe(pred, "SP_CanCockVore") then
        loci = loci .. 'C'
    end
    _P("Pred Loci are: " .. loci)
    return loci
end

---Keeps the active Swallow container spells in the pred's spellbook in sync with
---their locus passives. The passive UnlockSpell boost has proven unreliable for
---these Target container spells (zone spells from the same mechanism enter the
---spellbook, the Swallow containers never do), so the prey-side pattern that
---demonstrably works - Osi.AddSpell/Osi.RemoveSpell - is used here as well.
---@param pred GUIDSTRING
function SP_SyncSwallowSpells(pred)
    local loci = SP_GetPredLoci(pred)
    local containers = {
        O = "SP_Target_Swallow_O",
        A = "SP_Target_Swallow_A",
        U = "SP_Target_Swallow_U",
        C = "SP_Target_Swallow_C",
    }
    for locus, spell in pairs(containers) do
        if string.find(loci, locus, 1, true) then
            Osi.AddSpell(pred, spell, 0, 0)
        else
            Osi.RemoveSpell(pred, spell, 1)
        end
    end
end

---plays a random gurgle
---@param pred GUIDSTRING
---@param preyLethal integer
---@param preyDigestion integer how many prey are dead and being digested
function SP_PlayGurgle(pred, preyLethal, preyDigestion)
    local basePercentage = SP_MCMGet("GurgleProbability")

    -- base percentage is increased based on the number of preys of certain types
    basePercentage = basePercentage * (1 + preyLethal + preyDigestion * 0.5)

    if basePercentage > 100 then
        basePercentage = 100
    elseif basePercentage == 0 or #GurgleSounds == 0 then
        return
    end
    -- convert the percentage
    basePercentage = 100 * #GurgleSounds // basePercentage
    local randomResult = Osi.Random(basePercentage) + 1
    if randomResult <= #GurgleSounds then
        Osi.PlaySound(pred, GurgleSounds[randomResult])
    end
end

---@param level integer
---@param num integer
---@return integer
function SP_LevelMapValue(level, num)
    local rollcount = 1
    if level >= 17 then
        rollcount = 4
    elseif level >= 10 then
        rollcount = 3
    elseif level >= 5 then
        rollcount = 2
    end
    local result = 0
    for i = 1, rollcount do
        result = result + Osi.Random(num) + 1
    end
    return result
end

---@param prey CHARACTER
function SP_Resurrect(prey)
    Osi.Resurrect(prey)
    Osi.RemoveStatus(prey, "SP_ReformationStatus")
    -- statuses from 5e spells
    Osi.RemoveStatus(prey, "DEAD_TECHNICAL")
    Osi.RemoveStatus(prey, "DEAD_ONE_MINUTE")
end
