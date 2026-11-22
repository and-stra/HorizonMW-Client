-- MWX: MODS button in the main menu and the mods menu (folders in GAME\mods\, see mods.cpp).
-- Loading or unloading a mod relaunches the game.
if not Engine.InFrontend() or not Engine.IsMultiplayer() then return end

local function list_mods()
    local result = {}
    local data = game:listmods()
    for record in string.gmatch(data, "([^\31]+)") do
        local path, name, desc = string.match(record, "^([^\t]*)\t([^\t]*)\t(.*)$")
        if path and path ~= "" then
            table.insert(result, { path = path, name = name ~= "" and name or path, desc = desc or "" })
        end
    end
    return result
end

local function add_divider(menu, text)
    local element = LUI.UIElement.new({
        leftAnchor = true, rightAnchor = true, left = 0, right = 0,
        topAnchor = true, bottomAnchor = false, top = 0, bottom = 33.33
    })
    element.scrollingToNext = true
    element:addElement(LUI.MenuBuilder.BuildRegisteredType("h1_option_menu_titlebar", {
        title_bar_text = Engine.ToUpperCase(text)
    }))
    menu.list:addElement(element)
end

LUI.MenuBuilder.registerType("mwx_mods_menu", function(root)
    local menu = LUI.MenuTemplate.new(root, {
        menu_title = "@MWX_MENU_MODS",
        exclusiveController = 0,
        menu_width = 400,
        menu_top_indent = LUI.MenuTemplate.spMenuOffset,
        showTopRightSmallBar = true,
        uppercase_title = true
    })

    local loaded = game:getloadedmod()
    local mods = list_mods()

    if loaded ~= "" then
        local loaded_name = loaded
        for _, mod in ipairs(mods) do
            if mod.path == loaded then loaded_name = mod.name end
        end
        add_divider(menu, Engine.Localize("@MWX_MODS_LOADED") .. ": " .. loaded_name)
        menu:AddButton("@MWX_MODS_UNLOAD", function()
            Engine.Exec("unloadmod")
        end, nil, true, nil, { desc_text = Engine.Localize("@MWX_MODS_UNLOAD_DESC") })
    end

    add_divider(menu, Engine.Localize("@MWX_MODS_AVAILABLE"))

    local count = 0
    for _, mod in ipairs(mods) do
        if mod.path ~= loaded then
            count = count + 1
            game:addlocalizedstring("MWX_MOD_NAME_" .. count, mod.name)
            game:addlocalizedstring("MWX_MOD_DESC_" .. count, mod.desc)
            local path = mod.path
            menu:AddButton("@MWX_MOD_NAME_" .. count, function()
                Engine.Exec("loadmod \"" .. path .. "\"")
            end, nil, true, nil, { desc_text = Engine.Localize("@MWX_MOD_DESC_" .. count) })
        end
    end

    if count == 0 and loaded == "" then
        add_divider(menu, Engine.Localize("@MWX_MODS_NONE"))
    end

    menu:AddBackButton(function(m)
        Engine.PlaySound(CoD.SFX.MenuBack)
        LUI.FlowManager.RequestLeaveMenu(m)
    end)

    LUI.Options.InitScrollingList(menu.list, nil)
    menu:CreateBottomDivider()
    menu.optionTextInfo = LUI.Options.AddOptionTextInfo(menu)

    return menu
end)

-- HMW has no LUI.addmenubutton (calling it threw at frontend load and crashed the
-- client in the engine's error path); wrap the registered mp_main_menu builder instead.
local build_main_menu = LUI.MenuBuilder.m_types_build["mp_main_menu"]
if type(build_main_menu) == "function" then
    LUI.MenuBuilder.m_types_build["mp_main_menu"] = function(menu, event)
        local result = build_main_menu(menu, event)
        result:AddButton("@MWX_MENU_MODS", function()
            LUI.FlowManager.RequestAddMenu(nil, "mwx_mods_menu")
        end)
        return result
    end
end
