if not Engine.InFrontend() or not Engine.IsMultiplayer() then return end
Cac.GameModes.Group.Party = "Party"
Cac.GameModes.Data.Party = {
    Label = Engine.Localize("@MWX_PARTY_CAPS"),
    Image = "h1_ui_icon_playlist_weekend",
    -- ph/mprops hidden until the prop lists exist (props got the default weapon and kept the player model);
    -- snipers dropped: use preset classes in the game setup instead
    List = { "infect", "gun", "slasher", "rpg", "oic", "aon", "cranked", "sharpshooter", "reinforce", "srescue", "mugger", "arena", "ph", "mprops" }
}

-- gametypes of the loaded mod (mod.json "gametypes", registered in C++ by mods.cpp / gamemodes.cpp)
if game and game.getmodgametypes then
    for ref in string.gmatch(game:getmodgametypes(), "%S+") do
        table.insert(Cac.GameModes.Data.Party.List, ref)
    end
end

-- R6: the survival prototype is a hidden mode until mwx_show_survival is set
if Engine.GetDvarString("mwx_show_survival") == "1" then
    table.insert(Cac.GameModes.Data.Party.List, "survival")
end

-- Standard list: HMW's own script (liam_tests) sets it with "gtnw", which has no script in any zone.
-- dz = HMW's Drop Zone (dz.gsc in hmw_files.ff).
if Cac.GameModes.Data.Standard then
    Cac.GameModes.Data.Standard.List = { "dm", "war", "sd", "dom", "conf", "sab", "koth", "hp", "dz" }
end

-- M4: the party refs are real gametypes (script alias + gametypesTable row), so the stock menus do the
-- whole selection (MatchRules, lobby label, loadscreen) with no wrappers.
