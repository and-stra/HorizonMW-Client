-- MWX: the online MOTD/marketing feed is disabled (src/client/component/motd.cpp), but HMW's
-- ui_scripts/mp/motd/motd.lua still tries to force-open the MOTD popup when the virtual lobby
-- opens and errors on the empty marketing data ("attempt to index a * value" in
-- MarketingComms.CanReadReserveData). Keep the popup closed.
if LUI ~= nil and LUI.MOTD ~= nil then
    LUI.MOTD.TryForceOpenMOTD = function()
        return false
    end
end

-- the MOTD button in the lobby help bar would open the same empty popup; leave it inert
if LUI ~= nil and LUI.onmenuopen ~= nil then
    LUI.onmenuopen("menu_xboxlive", function(menu)
        if LUI.MOTD ~= nil then
            LUI.MOTD.TryForceOpenMOTD = function()
                return false
            end
        end
    end)
end
