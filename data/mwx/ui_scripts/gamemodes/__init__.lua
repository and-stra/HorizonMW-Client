if not Engine.InFrontend() or not Engine.IsMultiplayer() then
    if type(mwx_trace) == "function" then mwx_trace("gamemodes: not frontend") end
    return
end
if not Cac or not Cac.GameModes or not Cac.GameModes.Data then
    if type(mwx_trace) == "function" then mwx_trace("gamemodes: no cac") end
    return
end

Cac.GameModes.Group.Party = "Party"

-- M2: this chunk runs on every LUI (re)start (hks_start), while the LUI bindings can still be
-- incomplete. Calling Engine.* here killed the client (0xC0000005 at 0x1400BCB13; the step trace
-- stopped between "mod list" and "survival", i.e. at Engine.GetDvarString("mwx_show_survival")).
-- Load only pure Lua; every engine call happens when a menu first reads the Party table.
local base_party = { "infect", "gun", "slasher", "rpg", "oic", "aon", "cranked", "sharpshooter", "reinforce", "srescue", "mugger", "arena", "ph", "mprops" }
local party = {
    Image = "h1_ui_icon_playlist_weekend"
}

local function build_list()
    local list = {}
    for i, ref in ipairs(base_party) do
        list[i] = ref
    end

    -- gametypes of the loaded mod (mod.json "gametypes", registered in C++ by mods.cpp)
    if game and game.getmodgametypes then
        for ref in string.gmatch(game:getmodgametypes(), "%S+") do
            table.insert(list, ref)
        end
    end

    -- R6: the survival prototype is hidden unless mwx_show_survival is 1
    local ok, show = pcall(function() return Engine.GetDvarString("mwx_show_survival") end)
    if ok and show == "1" then
        table.insert(list, "survival")
    end

    return list
end

-- M4b: MatchRules.SetData("gametype", ref) only accepts the gametypes of the base fastfile table;
-- for the party refs it returns false and leaves ui_gametype at "war", so the private match started
-- as Team Deathmatch. Remember the pick (read by the C++ side when xpartygo starts) and keep the
-- lobby label on ui_gametype. Installed lazily with the first menu read, never at load.
local hooks_done = false
local function install_hooks()
    if hooks_done then
        return
    end
    hooks_done = true

    if not mwx_gametype_capture then
        mwx_gametype_capture = true

        local set_data = MatchRules.SetData

        -- only a pick made in the mode menu counts: the engine re-applies the current match-rules
        -- gametype when the lobby/setup is built, and that must not replace the user's choice
        local function picking_mode()
            local ok, name = pcall(function() return LUI.FlowManager.GetTopOpenAndVisibleMenuName() end)
            return ok and tostring(name) == "settings_recipe_choosetype"
        end

        MatchRules.SetData = function(field, value)
            if tostring(field) == "gametype" and picking_mode() then
                local wanted = tostring(value)
                if wanted ~= "" and wanted ~= "nil" then
                    pcall(function() Engine.SetDvarString("mwx_selected_gametype", wanted) end)
                end
            end

            local ok, result = pcall(set_data, field, value)
            return ok and result or false
        end
    end

    -- the party state still says "war" for a party ref; the lobby panel reads ui_gametype
    if Lobby ~= nil and type(Lobby.GameTypeNameAbbreviated) == "function" and not mwx_lobby_name_hook then
        mwx_lobby_name_hook = true
        local original_name = Lobby.GameTypeNameAbbreviated
        Lobby.GameTypeNameAbbreviated = function(...)
            local ui = Engine.GetDvarString("ui_gametype")
            local private = Engine.GetDvarBool("xblive_privatematch")
            if private and ui ~= nil and ui ~= "" then
                local name = Engine.TableLookup(GameTypesTable.File, GameTypesTable.Cols.Ref, ui,
                    GameTypesTable.Cols.Name)
                if name ~= nil and name ~= "" then
                    return Engine.Localize(name)
                end
            end
            return original_name(...)
        end
    end

    if type(mwx_trace) == "function" then mwx_trace("gamemodes: hooks") end
end

setmetatable(party, {
    __index = function(table, key)
        install_hooks()

        if key == "Label" then
            local ok, value = pcall(function() return Engine.Localize("@MWX_PARTY_CAPS") end)
            value = ok and value or "@MWX_PARTY_CAPS"
            rawset(table, key, value)
            return value
        end

        if key == "List" then
            local list = build_list()
            rawset(table, key, list)
            return list
        end
    end
})

Cac.GameModes.Data.Party = party

-- Standard list: HMW's own script (liam_tests) sets it with "gtnw", which has no script in any zone.
-- dz = HMW's Drop Zone (dz.gsc in hmw_files.ff).
if Cac.GameModes.Data.Standard then
    Cac.GameModes.Data.Standard.List = { "dm", "war", "sd", "dom", "conf", "sab", "koth", "hp", "dz" }
end

if type(mwx_trace) == "function" then mwx_trace("gamemodes: done") end
