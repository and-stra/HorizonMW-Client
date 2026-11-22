-- MWX: "AW (2014)" tab in the Private Match map selection, for Advanced Warfare maps ported to H1 with x64-zt
-- (docs/aw-map-porting.md). HMW's map selection (hmw_files.ff: ui_scripts/mp/map_selection) resolves map data
-- only for its own tabs (h1 / iw4 / iw5) through local functions, so the AW maps are appended to the shared
-- iw5 data table (package.loaded["data.iw5_maps"]) and the AW tab reports itself as "iw5". The MW3 tab's
-- feeder hides them again.
if not Engine.InFrontend() or not Engine.IsMultiplayer() then return end
if not LUI.MapSetup or not LUI.IW5Maps or not package or not package.loaded then return end

local iw5_maps = package.loaded["data.iw5_maps"]
if type(iw5_maps) ~= "table" then return end

-- only maps that are actually ported (GAME\hmw-usermaps\<loadName>\)
local aw_maps = {
    {
        loadName = "mp_greenband",
        name = "Greenband",
        description = "An Atlas hydroponics research facility in the Pacific Northwest.",
        image = "loadscreen_mp_greenband",
        game = "Advanced Warfare"
    }
}

local aw_first = #iw5_maps + 1
for _, map in ipairs(aw_maps) do
    table.insert(iw5_maps, map)
end
local aw_last = #iw5_maps

-- MW3 tab: hide the appended AW entries while it builds its buttons
local iw5_feeder = LUI.IW5Maps.MapFeeder
LUI.IW5Maps.MapFeeder = function(...)
    local removed = {}
    for i = aw_last, aw_first, -1 do
        table.insert(removed, 1, table.remove(iw5_maps, i))
    end
    local ok, err = pcall(iw5_feeder, ...)
    for _, map in ipairs(removed) do
        table.insert(iw5_maps, map)
    end
    if not ok then error(err) end
end

LUI.AWMaps = InheritFrom(LUI.UIElement)
LUI.AWMaps.Buttons = {}

LUI.AWMaps.MapFeeder = function(menu, list)
    LUI.AWMaps.Buttons = {}
    for idx = aw_first, aw_last do
        local mapData = iw5_maps[idx]
        local selectMapEvent = MBh.EmitEventToRoot({ name = "select_map_new", idx = idx, game = "iw5" })
        local updateMapEvent = MBh.EmitEventToRoot({ name = "update_map_new", idx = idx, game = "iw5" })
        local isSelectedMap = mapData.loadName == Engine.GetDvarString("ui_mapname")

        local buttonData = {
            button_text = Engine.Localize(mapData.name),
            variant = GenericButtonSettings.Variants.FlatButton,
            content_margin = 0,
            content_width = 60,
            button_over_func = updateMapEvent
        }
        if isSelectedMap then
            buttonData.text_default_color = Colors.mw1_green
        end

        local mapButton = list:AddButton(Engine.Localize(mapData.name), selectMapEvent, nil, nil, nil, buttonData)
        mapButton.listDefaultFocus = isSelectedMap
        mapButton:registerEventHandler("element_refresh", function(element, event)
            element:setText(Engine.Localize(mapData.name))
        end)
        LUI.AWMaps.Buttons[#LUI.AWMaps.Buttons + 1] = mapButton
    end
end

LUI.AWMaps.GetTabLabel = function()
    return "AW (2014)"
end

LUI.AWMaps.GetTabReferrer = function()
    return "iw5" -- see the header: the data lives in the iw5 table
end

LUI.AWMaps.new = function(menu, controller)
    local state = CoD.CreateState(0, 80, 100, 200, CoD.AnchorTypes.TopLeft)
    state.alpha = 0
    local root = LUI.UIElement.new(state)
    root.id = "AWMapsRoot"
    root:setClass(LUI.AWMaps)
    root:registerAnimationState("disabled", { alpha = 0 })
    root:registerAnimationState("enabled", { alpha = 1 })
    root:animateToState("enabled", 1000)
    return root
end

LUI.MenuBuilder.registerType("aw_tab", LUI.AWMaps.new)

-- HMW's AddTabs with a fourth tab (its tab count is a local, so the whole function is replaced)
LUI.MapSetup.AddTabs = function(menu)
    local tabManager = LUI.MenuBuilder.BuildRegisteredType("MFTabManager", {
        defState = CoD.CreateState(nil, nil, nil, nil, CoD.AnchorTypes.TopLeftRight),
        numOfTabs = 4
    })
    tabManager:keepRightBumperAlignedToHeader(false)
    tabManager.tabSelected = 1

    local tabs = {}
    for _, name in ipairs({ "h1_tab", "iw4_tab", "iw5_tab", "aw_tab" }) do
        local tab = LUI.MenuBuilder.BuildRegisteredType(name, { controller = menu.controller })
        tabs[#tabs + 1] = tab
        menu:addElement(tab)
    end

    tabs[1]:MapFeeder(menu)

    for count = 1, #tabs do
        local counter = count
        tabManager:addTab(menu.controller, tabs[counter]:GetTabLabel(), function()
            menu:ChangeTab(tabs[counter], tabManager)
        end)
    end

    tabManager:refreshTab(menu.controller)
    menu:addElement(tabManager)
end
