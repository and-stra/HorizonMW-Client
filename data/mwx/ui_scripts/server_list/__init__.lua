if not LUI.mp_menus then
    return
end

-- HMW's own ui_scripts/mp/server_list/__init__.lua already required "serverlist"
-- (the imgui browser of the closed-source exe), so drop it from the module cache:
-- require then loads this folder's serverlist.lua and replaces menu_systemlink_join.
package.loaded["serverlist"] = nil
require("serverlist")
