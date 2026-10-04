local statFiles = {
    -- 'Armor.txt',
    -- 'Items.txt',
    -- 'Potions.txt',
    -- 'Passive.txt',
    -- 'Passive_Feat.txt',
    -- 'Regurgitate_Vore_Core.txt',
    -- 'Spells_Projectile.txt',
    -- 'Spells_Spellbook.txt',
    -- 'Spells_Target.txt',
    -- 'Spells_Upcasting.txt',
    -- 'Spell_Vore_Core.txt',
    -- 'Passive_Status.txt',
    'Status_Debug.txt',
    -- 'Status_Spells_Spellbook.txt',
    -- 'Status_Vore_Core.txt',
    -- 'GreatHunger_Interrupt.txt',
    -- 'GreatHunger_Passive.txt',
    -- 'GreatHunger_Spell.txt',
    -- 'GreatHunger_Status.txt',
    -- 'StomachSentinel_Passive.txt',
    -- 'StomachSentinel_Status.txt',
    -- 'StomachSentinel_EveryonesStrength.txt',
    -- 'StomachSentinel_KnowledgeWithin.txt',
}

local modPath = "Public/DevouringAndDigesting/Stats/Generated/Data/"


local function spHandleBeforeDealDamage(e)
    if (e.Hit ~= nil and e.Hit.InflicterOwner ~= nil and e.Hit.Damage ~= nil and e.Hit.InflicterOwner.ServerCharacter ~= nil) then
        local inflicterEntityUuid = e.Hit.InflicterOwner.ServerCharacter.Template.Name .. "_" .. e.Hit.InflicterOwner.Uuid.EntityUuid
        if VoreData[inflicterEntityUuid] ~= nil then
            -- when prey inflicts damage
            if VoreData[inflicterEntityUuid].Pred ~= "" then
                if Osi.HasPassive(VoreData[inflicterEntityUuid].Pred, "SP_LeadBelly") == 1 then
                    -- Cache the original DamageType to use it when converting to Force if need
                    local originalDamageType = e.Hit.DamageType
                    
                    e.Hit.Damage.FinalDamagePerType[originalDamageType] = e.Hit.Damage.FinalDamagePerType[originalDamageType] // 2
                    e.Hit.Damage.FinalDamage = e.Hit.Damage.FinalDamage // 2
                    e.Hit.TotalDamageDone = e.Hit.TotalDamageDone // 2
        
                    for k, v in pairs(e.Hit.DamageList) do
                        e.Hit.DamageList[k].Amount = v.Amount // 2
                    end
                end
            -- elseif next(VoreData[inflicterEntityUuid].Prey) ~= nil then
            --     if Osi.HasActiveStatus(inflicterEntityUuid, "SP_LeechingAcidStatus") == 1 then
            --         _P("Pred " .. inflicterEntityUuid .. " dealt damage")
            --         _P("Has leeching insides")
            --         _D(e.Hit.field_158:GetAllComponents())
            --     end
            end
        end
    end
end

---Runs when reset command is sent to console.
-- local function SP_OnResetCompleted()

-- end

---Runs on session load
function SP_OnSessionLoaded()
    -- Mod variables are only available after SessionLoaded is triggered!
    local modVars = Ext.Vars.GetModVariables(ModuleUUID)
    if modVars.ModVoreData == nil then
        modVars.ModVoreData = {}
    end
    -- One-time migration from the deprecated PersistentVars mechanism (BG3SE may remove it at any time).
    -- PersistentVars is only populated in savegames created before this migration.
    if modVars.ModVoreDataMigrated ~= true and type(PersistentVars) == "table" and type(PersistentVars['VoreData']) == "table"
        and next(PersistentVars['VoreData']) ~= nil then
        local migrated = {}
        local migratedCount = 0
        for k, v in pairs(PersistentVars['VoreData']) do
            migrated[k] = v
            migratedCount = migratedCount + 1
        end
        -- direct write through the proxy marks the variable as dirty
        modVars.ModVoreData = migrated
        _P("Migrated " .. migratedCount .. " VoreData entries from PersistentVars to ModVariables.")
        Ext.Vars.SyncModVariables(ModuleUUID)
    end
    modVars.ModVoreDataMigrated = true
    VoreData = modVars.ModVoreData
    -- SP_ResetConfig()
    SP_ResetRaceWeightsConfig()
    --SP_LoadConfigFromFile()
    SP_LoadRaceWeightsConfigFromFile()
    SP_LoadRaceBellyConfigFromFile()
    SP_MigrateVoreData()

    -- one-time diagnostics: are the mod's key stats actually loaded?
    SP_DelayCallTicks(10, function ()
        _P("[SP] build: r15 (swallow family flattened no-using, statdump probe)")
        -- compare the resolved shape of the real Swallow container against the
        -- probe container that provably registers; a broken 'using' resolution
        -- would show up as missing/nil fields here
        for _, statName in ipairs({ "SP_Target_Swallow_O", "SP_Test_C_ContainerRoll" }) do
            local ok, stat = pcall(function () return Ext.Stats.Get(statName) end)
            if not ok or stat == nil then
                _P("[SP] statdump " .. statName .. ": <unavailable>")
            else
                local parts = {}
                for _, field in ipairs({ "SpellType", "SpellFlags", "UseCosts", "ContainerSpells", "SpellSuccess" }) do
                    local okf, v = pcall(function () return stat[field] end)
                    local repr = okf and tostring(v) or "<no prop>"
                    if type(v) == "string" and #v > 50 then repr = string.sub(v, 1, 50) .. "..." end
                    parts[#parts+1] = field .. "=" .. repr
                end
                local okc, conds = pcall(function () return stat.TargetConditions end)
                if okc and type(conds) == "string" then
                    parts[#parts+1] = "TargetConditionsLen=" .. tostring(#conds)
                end
                _P("[SP] statdump " .. statName .. ": " .. table.concat(parts, " | "))
            end
        end
        for _, statName in ipairs({ "SP_IsPred", "SP_CanOralVore", "SP_PotionOfOralVore",
            "SP_Stuffed", "SP_Target_Swallow_O", "SP_Target_Swallow_Lethal_O" }) do
            _P("[SP] stat " .. statName .. " loaded: " .. tostring(Ext.Stats.Get(statName) ~= nil))
        end
    end)

end

local voreDataSyncTicks = 0

function SP_Tick()
    SP_BellyQueueUpdate()
    -- Writing to subproperties of a mod variable table does not mark it as dirty for savegame
    -- persistence, so periodically re-assign the variable (see BG3SE docs on synchronization).
    voreDataSyncTicks = voreDataSyncTicks + 1
    if voreDataSyncTicks >= 300 then
        voreDataSyncTicks = 0
        Ext.Vars.GetModVariables(ModuleUUID).ModVoreData = VoreData
    end
end

Ext.Events.BeforeDealDamage:Subscribe(spHandleBeforeDealDamage)
Ext.Events.SessionLoaded:Subscribe(SP_OnSessionLoaded)
-- Ext.Events.ResetCompleted:Subscribe(SP_OnResetCompleted)
Ext.Events.Tick:Subscribe(SP_Tick)


