-- Ported Advanced Warfare weapons: Create-a-Class glue (W1: the crossbow).
--
-- The crossbow is a secondary (Launchers tab, weapon_projectile). HMW's attachment menu filters the
-- attachkits table by weapon class token ("prj" for projectiles) and launcher rows do not list the
-- optics, so the two optics are appended for this weapon only. HMW has no attachments on its own
-- launchers (their weapon defs list none), so nothing else changes.
--
-- The list wrapper is a safety net for the item-lock filter: it makes sure the crossbow appears in
-- the Launchers list even if the weapon has no inventory/unlock item (AW assets have no HMW GUID).
--
-- Load order: this module runs after every HMW ui_scripts module (ui_scripting.cpp loads the zone
-- __init__.lua files first, then GAME\<data>\ui_scripts), so Cac.GetValidAttachKits /
-- Cac.GetAllDefinedAndValidWeapons from create_a_class\utils.lua already exist.

-- No Engine calls at load time: this chunk runs while the LUI/zones are still loading, and an
-- engine call in that window is the 0xC0000005 at 0x1400BCB13 crash pattern (see the note in
-- gamemodes/__init__.lua). In a VM without the class menus (Cac absent) there is nothing to wrap;
-- return without touching any engine binding.
if Cac == nil then
    return
end

local CROSSBOW = "iw5_exocrossbow"
local OPTICS = { "reflex", "acog" }

local function list_has(list, name)
    for i = 1, #list do
        if list[i][1] == name then
            return true
        end
    end
    return false
end

if type(Cac.GetValidAttachKits) == "function" then
    local base_get_valid_attach_kits = Cac.GetValidAttachKits
    Cac.GetValidAttachKits = function(controller, weaponName, storageCategory)
        local kits = base_get_valid_attach_kits(controller, weaponName, storageCategory)
        if weaponName == CROSSBOW then
            for i = 1, #OPTICS do
                if not list_has(kits, OPTICS[i]) then
                    kits[#kits + 1] = { OPTICS[i], 0 }
                end
            end
        end
        return kits
    end
end

if type(Cac.GetAllDefinedAndValidWeapons) == "function" then
    local base_get_weapons = Cac.GetAllDefinedAndValidWeapons
    Cac.GetAllDefinedAndValidWeapons = function(storageCategory, weaponCategory, classType, arg3, arg4, controller, weaponID)
        local weapons = base_get_weapons(storageCategory, weaponCategory, classType, arg3, arg4, controller, weaponID)
        if storageCategory == "Secondary" and weaponCategory == "weapon_projectile" and not weaponID then
            if not list_has(weapons, CROSSBOW) then
                weapons[#weapons + 1] = { CROSSBOW, 0 }
            end
        end
        return weapons
    end
end
