-- MWX: "AW (2014)" tab in the Private Match map selection, for Advanced Warfare maps ported to H1 with x64-zt
-- (docs/aw-map-porting.md). HMW's map selection (hmw_files.ff: ui_scripts/mp/map_selection) resolves map data
-- only for its own tabs (h1 / iw4 / iw5) through local functions, so the AW maps are appended to the shared
-- iw5 data table (package.loaded["data.iw5_maps"]) and the AW tab reports itself as "iw5". The MW3 tab's
-- feeder hides them again.
if not Engine.InFrontend() or not Engine.IsMultiplayer() then return end
if not LUI.MapSetup or not LUI.IW5Maps or not package or not package.loaded then return end

local iw5_maps = package.loaded["data.iw5_maps"]
if type(iw5_maps) ~= "table" then return end

-- Advanced Warfare maps (community H1 ports in GAME\hmw-usermaps\<loadName>\); only installed ones are listed
local aw_all = {
    { loadName = "mp_refraction", name = "Ascend", description = "Advanced Warfare", image = "loadscreen_mp_refraction", game = "Advanced Warfare" },
    { loadName = "mp_dam", name = "Atlas Gorge", description = "Advanced Warfare", image = "loadscreen_mp_dam", game = "Advanced Warfare" },
    { loadName = "mp_lab2", name = "Bio Lab", description = "Advanced Warfare", image = "loadscreen_mp_lab2", game = "Advanced Warfare" },
    { loadName = "mp_spark", name = "Chop Shop", description = "Advanced Warfare", image = "loadscreen_mp_spark", game = "Advanced Warfare" },
    { loadName = "mp_climate_3", name = "Climate", description = "Advanced Warfare", image = "loadscreen_mp_climate_3", game = "Advanced Warfare" },
    { loadName = "mp_comeback", name = "Comeback", description = "Advanced Warfare", image = "loadscreen_mp_comeback", game = "Advanced Warfare" },
    { loadName = "mp_sector17", name = "Compound", description = "Advanced Warfare", image = "loadscreen_mp_sector17", game = "Advanced Warfare" },
    { loadName = "mp_lost", name = "Core", description = "Advanced Warfare", image = "loadscreen_mp_lost", game = "Advanced Warfare" },
    { loadName = "mp_laser2", name = "Defender", description = "Advanced Warfare", image = "loadscreen_mp_laser2", game = "Advanced Warfare" },
    { loadName = "mp_detroit", name = "Detroit", description = "Advanced Warfare", image = "loadscreen_mp_detroit", game = "Advanced Warfare" },
    { loadName = "mp_torqued", name = "Drift", description = "Advanced Warfare", image = "loadscreen_mp_torqued", game = "Advanced Warfare" },
    { loadName = "mp_fracture", name = "Fracture", description = "Advanced Warfare", image = "loadscreen_mp_fracture", game = "Advanced Warfare" },
    { loadName = "mp_greenband", name = "Greenband", description = "Advanced Warfare", image = "loadscreen_mp_greenband", game = "Advanced Warfare" },
    { loadName = "mp_levity", name = "Horizon", description = "Advanced Warfare", image = "loadscreen_mp_levity", game = "Advanced Warfare" },
    { loadName = "mp_instinct", name = "Instinct", description = "Advanced Warfare", image = "loadscreen_mp_instinct", game = "Advanced Warfare" },
    { loadName = "mp_kremlin", name = "Kremlin", description = "Advanced Warfare", image = "loadscreen_mp_kremlin", game = "Advanced Warfare" },
    { loadName = "mp_lair", name = "Overload", description = "Advanced Warfare", image = "loadscreen_mp_lair", game = "Advanced Warfare" },
    { loadName = "mp_bigben2", name = "Parliament", description = "Advanced Warfare", image = "loadscreen_mp_bigben2", game = "Advanced Warfare" },
    { loadName = "mp_perplex_1", name = "Perplex", description = "Advanced Warfare", image = "loadscreen_mp_perplex_1", game = "Advanced Warfare" },
    { loadName = "mp_liberty", name = "Quarantine", description = "Advanced Warfare", image = "loadscreen_mp_liberty", game = "Advanced Warfare" },
    { loadName = "mp_recovery", name = "Recovery", description = "Advanced Warfare", image = "loadscreen_mp_recovery", game = "Advanced Warfare" },
    { loadName = "mp_venus", name = "Retreat", description = "Advanced Warfare", image = "loadscreen_mp_venus", game = "Advanced Warfare" },
    { loadName = "mp_prison", name = "Riot", description = "Advanced Warfare", image = "loadscreen_mp_prison", game = "Advanced Warfare" },
    { loadName = "mp_clowntown3", name = "Sideshow", description = "Advanced Warfare", image = "loadscreen_mp_clowntown3", game = "Advanced Warfare" },
    { loadName = "mp_blackbox", name = "Site 244", description = "Advanced Warfare", image = "loadscreen_mp_blackbox", game = "Advanced Warfare" },
    { loadName = "mp_highrise2", name = "Skyrise", description = "Advanced Warfare", image = "loadscreen_mp_highrise2", game = "Advanced Warfare" },
    { loadName = "mp_solar", name = "Solar", description = "Advanced Warfare", image = "loadscreen_mp_solar", game = "Advanced Warfare" },
    { loadName = "mp_seoul2", name = "Swarm", description = "Advanced Warfare", image = "loadscreen_mp_seoul2", game = "Advanced Warfare" },
    { loadName = "mp_terrace", name = "Terrace", description = "Advanced Warfare", image = "loadscreen_mp_terrace", game = "Advanced Warfare" },
    { loadName = "mp_urban", name = "Urban", description = "Advanced Warfare", image = "loadscreen_mp_urban", game = "Advanced Warfare" },
}

local aw_maps = {}
for _, map in ipairs(aw_all) do
    if Engine.ControllerHasMap(0, map.loadName) then
        table.insert(aw_maps, map)
    end
end
if #aw_maps == 0 then return end

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
