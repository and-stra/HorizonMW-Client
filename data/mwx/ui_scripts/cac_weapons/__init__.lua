-- The CAC builds Cac.Weapons from mp/customweapons.csv in its own __init__.lua, and reads the row
-- count once at UI load - before the weapon zones have finished loading. The rows that
-- stock_weapons.cpp appends for the CoD4/MWR weapons (and the MWR DLC melee) are therefore left
-- out of the class menu. Add any missing row when the class menu opens (idempotent, cheap).
local function sync_cac_weapons()
    if Cac == nil or Cac.Weapons == nil or Engine == nil then
        return
    end

    local csv = "mp/customweapons.csv"
    local ok, rows = pcall(function() return Engine.TableGetRowCount(csv) end)
    if not ok or rows == nil then
        return
    end

    local function add(list, weap)
        if type(list) ~= "table" then
            return
        end
        for _, item in ipairs(list) do
            if type(item) == "table" and item[1] == weap then
                return
            end
        end
        table.insert(list, { weap, 0 })
    end

    for i = 0, rows - 1 do
        local weap = Engine.TableLookupByRow(csv, i, 0)
        local class = Engine.TableLookupByRow(csv, i, 1)
        local weapon_type = Engine.TableLookupByRow(csv, i, 2)
        if weap and weap ~= "" and class and class ~= "" and weapon_type and weapon_type ~= "" then
            local group = Cac.Weapons[weapon_type]
            if group then
                add(group[class], weap)
                if group.Keys then
                    for k, v in pairs(group.Keys) do
                        if v == class then
                            add(group[k], weap)
                        end
                    end
                end
            end
        end
    end
end

if LUI ~= nil and LUI.onmenuopen ~= nil then
    LUI.onmenuopen("CacMenu", function() sync_cac_weapons() end)
    LUI.onmenuopen("CacLoadoutEditorMenu", function() sync_cac_weapons() end)
end
