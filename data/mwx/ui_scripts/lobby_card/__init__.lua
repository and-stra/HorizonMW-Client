-- MWX: the private-lobby player card (mplobbyplayerstats) draws its emblem/background from the party
-- member data, which the retail client fills from the online service. MWX has no online service, so
-- the values are empty and the images fall back to the white default material - the white block that
-- used to sit above the callsign. When there is no patch, hide those images so the card shows the
-- name/rank cleanly. The real fix (a patch/background per LAN player) is docs/todo-callsigns.md.
if not Engine.IsMultiplayer() then return end

local patch_ids = { patchEmblem = true, patchBG = true, patchShape = true, patch = true }

local function hide(element)
    if element == nil then return end
    -- alpha 0 keeps the layout (close() would reflow the card); both calls are optional
    pcall(function() element:SetAlpha(0) end)
end

local function has_patch(menu)
    local ok, patch = pcall(function() return Lobby.GetMemberPatch(0) end)
    if not ok then return true end -- unknown API: do not hide anything
    return patch ~= nil and patch ~= 0 and patch ~= ""
end

local function fix_card(element, depth)
    if element == nil or depth > 8 then return end

    if patch_ids[tostring(element.id)] then
        hide(element)
    end

    local count = element:getNumChildren()
    local child = element:getFirstChild()
    local index = 0
    while child ~= nil and index < count do
        fix_card(child, depth + 1)
        child = child:getNextSibling()
        index = index + 1
    end
end

local build = LUI.MenuBuilder.m_types_build["menu_xboxlive_privatelobby"]
if type(build) == "function" then
    LUI.MenuBuilder.m_types_build["menu_xboxlive_privatelobby"] = function(menu, event)
        local result = build(menu, event)

        -- the card is filled by a feeder after the build; check it on a slow timer
        result:registerEventHandler("mwx_lobby_card", function(element, _)
            if has_patch(element) then return end
            fix_card(element, 0)
        end)
        result:addElement(LUI.UITimer.new(500, "mwx_lobby_card", nil, true))

        return result
    end
end
