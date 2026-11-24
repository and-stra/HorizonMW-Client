-- MWX main menu tweaks (M3).
-- Loaded after HMW's ui_scripts; only changes the frontend menu.
--
--  * "Play Online" is labelled "Play".
--  * Play works offline: the stock handler calls Engine.UserCanAccessMPLiveMenu, which errors
--    without Xbox Live; it now opens the private match lobby directly (like the old autoplay
--    hack did, but without pressing the button for the user).

if not Engine.InFrontend() or not Engine.IsMultiplayer() then return end

local function find_by_id(element, id)
    if element == nil then return nil end
    if tostring(element.id) == id then return element end

    local count = element:getNumChildren()
    local child = element:getFirstChild()
    local index = 0

    while child ~= nil and index < count do
        local found = find_by_id(child, id)
        if found ~= nil then return found end
        child = child:getNextSibling()
        index = index + 1
    end

    return nil
end

-- the button label is a UIText child (id "text_label") of the button element. It only exists
-- after the builder finished (the stock label is applied later), so the rename runs from a LUI
-- timer in the game's own event loop.
local function rename_play_button(menu)
    local button = find_by_id(menu, "mp_main_menu_play_online")
    if button == nil then return end

    local child = button:getFirstChild()
    while child ~= nil do
        if tostring(child.id) == "button" then
            local inner = child:getFirstChild()
            while inner ~= nil do
                if tostring(inner.id) == "text_label" then
                    -- the stock labels are all caps ("OPTIONS", "MODS", ...); keep it consistent
                    inner:setText("PLAY")
                end
                inner = inner:getNextSibling()
            end
        end
        child = child:getNextSibling()
    end
end

local build_main_menu = LUI.MenuBuilder.m_types_build["mp_main_menu"]
if type(build_main_menu) == "function" then
    LUI.MenuBuilder.m_types_build["mp_main_menu"] = function(menu, event)
        local result = build_main_menu(menu, event)

        result:registerEventHandler("mwx_rename_play", function(element, _)
            rename_play_button(element)
        end)
        result:addElement(LUI.UITimer.new(100, "mwx_rename_play", nil, true))

        return result
    end
end

-- offline "Play": the stock OnPlayButton is a global the menu handler looks up at call time
if type(OnPlayButton) == "function" then
    OnPlayButton = function(element, event)
        LUI.FlowManager.RequestAddMenu(nil, "menu_xboxlive_privatelobby")
    end
end
