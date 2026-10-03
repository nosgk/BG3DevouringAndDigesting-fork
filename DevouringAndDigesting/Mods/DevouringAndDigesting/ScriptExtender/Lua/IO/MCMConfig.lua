
-- gives player all usable non-debug items from mod (to avoid using SummonTutorialChest)
local SP_VoreBagTemplate = '68dc579e-d3aa-4277-ab1f-5ccd6f78d113'
local SP_VoreBagContents = {
    '1219e0c2-e893-4de0-8a92-6212d1348223', -- Potion of Oral Vore
    '04987160-cb88-4d3e-b219-1843e5253d51', -- Potion of Anal Vore
    '92067c3c-547e-4451-9377-632391702de9', -- Potion of Unbirth
    '04cbdeb4-a98e-44cd-b032-972df0ba3ca1', -- Potion of Cock Vore
    '319379c2-3627-4c26-b14d-3ce8abb676c3', -- Potion of Inedibility
    '02ee5321-7bcd-4712-ba06-89eb1850c2e4', -- Potion of Prey
    'b8d700d0-681f-4c38-b444-fe69b361d9b3', -- Potion of Assign
    '37eee091-99b3-4756-8d96-16f09dbecec9', -- Potion of Rest
}

function SP_GiveVoreItems()
    local host = Osi.GetHostCharacter()
    Osi.TemplateAddTo(SP_VoreBagTemplate, host, 1)
    -- TemplateAddTo is asynchronous: the bag only exists after a few ticks. The bag's
    -- root-template InventoryList does not generate its treasure table either, so the
    -- potions are added into the bag directly (issue: bag spawning empty).
    SP_DelayCallTicks(4, function()
        local bag = Osi.GetItemByTemplateInInventory(SP_VoreBagTemplate, host)
        if bag == nil then
            _F("Vore bag could not be found after being added to the host")
            return
        end
        for _, potionTemplate in ipairs(SP_VoreBagContents) do
            Osi.TemplateAddTo(potionTemplate, bag, 1)
        end
    end)
end
-- used to make getting values from the MCM less verbose
function SP_MCMGet(settingID)
    return Mods.BG3MCM.MCMAPI:GetSettingValue(settingID, ModuleUUID)
end

function SP_MCMSet(settingID, newVal)
    Mods.BG3MCM.MCMAPI:SetSettingValue(settingID, newVal, ModuleUUID)
end


