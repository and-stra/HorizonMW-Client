if not Engine.InFrontend() or not Engine.IsMultiplayer() then return end
Cac.GameModes.Group.Party = "Party"
Cac.GameModes.Data.Party = {
    Label = Engine.Localize("@MWX_PARTY_CAPS"),
    Image = "h1_ui_icon_playlist_weekend",
    -- ph/mprops hidden until the prop lists exist (props got the default weapon and kept the player model);
    -- snipers dropped: use preset classes in the game setup instead
    List = { "infect", "gun", "slasher", "rpg", "oic", "aon", "cranked" }
}

-- gametypes of the loaded mod (mod.json "gametypes", registered in C++ by mods.cpp / gamemodes.cpp)
if game and game.getmodgametypes then
    for ref in string.gmatch(game:getmodgametypes(), "%S+") do
        table.insert(Cac.GameModes.Data.Party.List, ref)
    end
end

-- Standard list: HMW's own script (liam_tests) sets it with "gtnw", which has no script in any zone.
-- dz = HMW's Drop Zone (dz.gsc in hmw_files.ff).
if Cac.GameModes.Data.Standard then
    Cac.GameModes.Data.Standard.List = { "dm", "war", "sd", "dom", "conf", "sab", "koth", "hp", "dz" }
end

local party_base = { ph = "war", mprops = "war", slasher = "war", snipers = "war", rpg = "war" }

-- name keys of the virtual modes (must match the C++ mode table in gamemodes.cpp)
local party_name = {
    ph = "MWX_GAMETYPE_PH",
    mprops = "MWX_GAMETYPE_MPROPS",
    slasher = "MWX_GAMETYPE_SLASHER",
    snipers = "MWX_GAMETYPE_SNIPERS",
    rpg = "MWX_GAMETYPE_RPG"
}

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

local get_data = MatchRules.GetData
MatchRules.GetData = function(key, ...)
    local value = get_data(key, ...)
    if key == "gametype" and select("#", ...) == 0 then
        local mode = Engine.GetDvarString("mwx_party_mode")
        if mode ~= "" and party_base[mode] == value then
            return mode
        end
    end
    return value
end

-- the private lobby label and the setup menu mode button read Lobby.GameTypeNameAbbreviated()
local game_type_name_abbreviated = Lobby.GameTypeNameAbbreviated
Lobby.GameTypeNameAbbreviated = function(...)
    local name = party_name[Engine.GetDvarString("mwx_party_mode")]
    if name then
        -- same case as the stock modes (the _CAPS name made party modes look different from Infected)
        return Engine.Localize("@" .. name)
    end
    return game_type_name_abbreviated(...)
end

-- Loading screen title (mplobbywidgets.lua lobby_game_type_title): it sets its text once on
-- lobby_transition_to_game from the gametypes table row of ui_gametype. While the host's own server
-- loads, the engine still runs the base gametype, so the title read "Team Deathmatch". With a party
-- mode selected, the party name is used instead (the engine and g_gametype stay untouched).
local function party_display_name()
    local name = party_name[Engine.GetDvarString("mwx_party_mode")]
    if name then
        return Engine.Localize("@" .. name)
    end
    return nil
end

local function wrap_title(registry)
    if type(registry) ~= "table" then return false end
    local title_build = registry["lobby_game_type_title"]
    if type(title_build) ~= "function" then return false end
    registry["lobby_game_type_title"] = function(...)
        local def = title_build(...)
        if type(def) == "table" and def.handlers and def.handlers.lobby_transition_to_game then
            local transition = def.handlers.lobby_transition_to_game
            def.handlers.lobby_transition_to_game = function(element, event)
                transition(element, event)
                local name = party_display_name()
                if Engine.GetDvarBool("mwx_debug_gamemodes") then
                    print("[gamemodes] loading title, ui_gametype=" .. Engine.GetDvarString("ui_gametype") ..
                        " party=" .. tostring(name))
                end
                if name and not Engine.IsAliensMode() then
                    element:setText(name)
                end
            end
        end
        return def
    end
    return true
end

-- the registry name of registerDef isn't known from the dumps: wrap it in every MenuBuilder table holding it
local wrapped = false
for key, registry in pairs(LUI.MenuBuilder) do
    if wrap_title(registry) then
        wrapped = true
        if Engine.GetDvarBool("mwx_debug_gamemodes") then
            print("[gamemodes] loading title wrapped in LUI.MenuBuilder." .. tostring(key))
        end
    end
end
if Engine.GetDvarBool("mwx_debug_gamemodes") then
    print("[gamemodes] loading title wrapper installed: " .. tostring(wrapped))
end
