
-- gives player all usable non-debug items from mod (to avoid using SummonTutorialChest)
function SP_GiveVoreItems()
    local host = Osi.GetHostCharacter()
    Osi.TemplateAddTo('68dc579e-d3aa-4277-ab1f-5ccd6f78d113', host, 1)
    -- the bag's root template InventoryList does not reliably generate its treasure table,
    -- so fill the bag explicitly (issue: bag spawning empty)
    local bag = Osi.GetItemByTemplateInInventory('68dc579e-d3aa-4277-ab1f-5ccd6f78d113', host)
    if bag ~= nil then
        Osi.GenerateTreasure(bag, 'SP_VoreAssignmentItemsBag_Treasure', Osi.GetLevel(host) or 1, host)
    end
end
-- used to make getting values from the MCM less verbose
function SP_MCMGet(settingID)
    return Mods.BG3MCM.MCMAPI:GetSettingValue(settingID, ModuleUUID)
end

function SP_MCMSet(settingID, newVal)
    Mods.BG3MCM.MCMAPI:SetSettingValue(settingID, newVal, ModuleUUID)
end


