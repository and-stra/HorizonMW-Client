-- MWX: party mode name on the loading screen.
-- HMW's loading screen is its own "connect" menu (hmw_files.ff ui_scripts/mp/loadscreen): it reads ui_gametype once,
-- when the menu is built, in the in-game UI state (so this script must not be gated by Engine.InFrontend()).
-- On the host, the match starts with the base gametype (war), so the menu showed "TEAM DEATHMATCH" until the
-- party ref came back at the end of the load. Joining clients get the party ref from the server and need nothing.
if not Engine.IsMultiplayer() then return end

local party_refs = { ph = true, mprops = true, slasher = true, snipers = true, rpg = true }
local party_base = "war"

local function loading_gametype()
    local gametype = Engine.GetDvarString("ui_gametype")
    local party = Engine.GetDvarString("mwx_party_mode")
    -- only our own listen server: a client joining someone else keeps the server's gametype
    if party ~= "" and party_refs[party] and Engine.GetDvarBool("sv_running") and
        (gametype == party_base or gametype == party) then
        return party
    end
    return gametype
end

local connect_build = LUI.MenuBuilder.m_types_build["connect"]
if connect_build then
    LUI.MenuBuilder.m_types_build["connect"] = function(...)
        local menu = connect_build(...)
        local gametype = loading_gametype()
        local display = menu and menu.getFirstDescendentById and menu:getFirstDescendentById("gametypeDisplay")
        if display and gametype ~= "" then
            display:setText(Engine.Localize("@" .. Engine.ToUpperCase(gametype)))
        end
        if Engine.GetDvarBool("mwx_debug_gamemodes") then
            print("[gamemodes] loading screen gametype=" .. gametype .. " (ui_gametype=" ..
                Engine.GetDvarString("ui_gametype") .. ", party=" .. Engine.GetDvarString("mwx_party_mode") ..
                ", element=" .. tostring(display ~= nil) .. ")")
        end
        return menu
    end
end
