if not Engine.InFrontend() or not Engine.IsMultiplayer() then return end
Cac.GameModes.Group.Party = "Party"
Cac.GameModes.Data.Party = {
    Label = Engine.Localize("@MWX_PARTY_CAPS"),
    Image = "h1_ui_icon_playlist_standard",
    List = { "ph", "mprops", "slasher", "snipers", "rpg" }
}

local party_base = { ph = "war", mprops = "war", slasher = "war", snipers = "war", rpg = "war" }

-- selecting a mode in game setup goes through MatchRules.SetData("gametype", ref)
local set_data = MatchRules.SetData
MatchRules.SetData = function(key, value, ...)
    if key == "gametype" then
        local base = party_base[value]
        if base then
            Engine.SetDvarString("mwx_party_mode", value)
            return set_data(key, base, ...)
        end
        Engine.SetDvarString("mwx_party_mode", "")
    end
    return set_data(key, value, ...)
end

-- show the party mode wherever the UI reads ui_gametype (lobby label/icon, list highlight, loadscreen)
local get_dvar_string = Engine.GetDvarString
Engine.GetDvarString = function(name, ...)
    local value = get_dvar_string(name, ...)
    if name == "ui_gametype" then
        local mode = get_dvar_string("mwx_party_mode")
        if mode ~= "" and party_base[mode] == value then
            return mode
        end
    end
    return value
end
