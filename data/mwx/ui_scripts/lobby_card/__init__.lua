-- MWX: the private-lobby player card draws its background/emblem from the party member data, which the
-- retail client fills from the online service. MWX has no online service, so the values are empty and
-- the images fall back to the white default material (the white block above the callsign and the small
-- white patch square). When there is no patch, hide those images so the card shows name/rank cleanly.
-- The real fix (a patch/background per LAN player) is docs/todo-callsigns.md.
if not Engine.IsMultiplayer() then return end

local function hide(element)
    if element == nil then return end
    -- alpha 0 keeps the layout (close() would reflow the card)
    local ok = pcall(function() element:setAlpha(0) end)
    if not ok then pcall(function() element:hide() end) end
end

-- R7: the local card comes from the MWX profile dvars (the retail party member data is empty on
-- LAN). The lobby wrappers below answer for member 0 (the local player) only; remote members still
-- use the engine's data. Host -> client is carried in the getInfo answer (next step: a per-player
-- wire format, see docs/todo-callsigns.md).
local function dvar_int(name)
    local ok, value = pcall(function() return Engine.GetDvarString(name) end)
    if not ok or value == nil then return nil end
    local number = tonumber(value)
    if number == nil then return nil end
    return number
end

local function local_card(name)
    local value = dvar_int("mwx_card_" .. name)
    if value ~= nil and value ~= 0 then return value end
    return nil
end

local function wrap_card(name, api)
    local original = Lobby[api]
    if type(original) ~= "function" then return end

    Lobby[api] = function(member, ...)
        if member == nil or member == 0 then
            local card = local_card(name)
            if card ~= nil then return card end
        end
        return original(member, ...)
    end
end

wrap_card("patch", "GetMemberPatch")
wrap_card("backing", "GetMemberPatchbacking")
wrap_card("background", "GetMemberBackground")

local function has_patch()
    local card = local_card("patch")
    if card ~= nil then return true end
    local ok, patch = pcall(function() return Lobby.GetMemberPatch(0) end)
    if not ok then return false end -- the call is not available here: treat it as "no patch"
    return patch ~= nil and patch ~= 0 and patch ~= ""
end

local function local_name()
    local ok, name = pcall(function() return Lobby.GetMemberName(0) end)
    if ok and type(name) == "string" and name ~= "" then return name end
    return Engine.GetDvarString("name")
end

local function find_text(element, text, depth)
    if element == nil or depth > 12 then return nil end

    local ok, value = pcall(function() return element:getText() end)
    if ok and value == text then return element end

    local ok_count, count = pcall(function() return element:getNumChildren() end)
    local ok_child, child = pcall(function() return element:getFirstChild() end)
    if not ok_count or not ok_child then return nil end

    local index = 0
    while child ~= nil and index < count do
        local found = find_text(child, text, depth + 1)
        if found ~= nil then return found end

        local current = child
        local ok_next, next_child = pcall(function() return current:getNextSibling() end)
        if not ok_next then return nil end
        child = next_child
        index = index + 1
    end

    return nil
end

local function clean_card(menu)
    if has_patch() then return end

    local name = local_name()
    if name == nil or name == "" then return end

    local name_element = find_text(menu, name, 0)
    if name_element == nil then return end

    local ok, card = pcall(function() return name_element:getParent() end)
    if not ok or card == nil then return end

    -- the card: backgroundContainer, the background image, the name, the patch image, another text
    local function walk(element, depth)
        if element == nil or depth > 2 then return end

        local ok_id, id = pcall(function() return element.id end)
        if ok_id and (tostring(id) == "background" or tostring(id) == "LUIImage") then
            hide(element)
        end

        local ok_count, count = pcall(function() return element:getNumChildren() end)
        local ok_child, child = pcall(function() return element:getFirstChild() end)
        if not ok_count or not ok_child then return end

        local index = 0
        while child ~= nil and index < count do
            walk(child, depth + 1)
            local current = child
            local ok_next, next_child = pcall(function() return current:getNextSibling() end)
            if not ok_next then return end
            child = next_child
            index = index + 1
        end
    end

    walk(card, 0)
end

local build = LUI.MenuBuilder.m_types_build["menu_xboxlive_privatelobby"]
if type(build) == "function" then
    LUI.MenuBuilder.m_types_build["menu_xboxlive_privatelobby"] = function(menu, event)
        local result = build(menu, event)

        -- the card is filled by a feeder after the build; check it on a slow timer
        result:registerEventHandler("mwx_lobby_card", function(element, _)
            clean_card(element)
        end)
        result:addElement(LUI.UITimer.new(500, "mwx_lobby_card", nil, true))

        return result
    end
end
