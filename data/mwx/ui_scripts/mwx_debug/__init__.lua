-- MWX test interface: LUI helpers (see docs/mcp.md).
-- Loaded with the other MWX ui_scripts; nothing runs until the debug RPC calls it.
--
-- H1's LUI elements are userdata with a dynamic __index: only a few fields (id) and the methods
-- of the class are readable. Children: getNumChildren() / getFirstChild() / getNextSibling();
-- text: getText() (UIText only); layout: getRect(); visibility: isClosed().
-- The menu stack is LUI.FlowManager + LUI.MenuBuilder.m_types_build (all registered menu names).

mwx_debug = mwx_debug or {}

mwx_debug.max_depth = 6
mwx_debug.max_nodes = 400

local function encode_string(value)
    local escapes = {
        ['\\'] = '\\\\',
        ['"'] = '\\"',
        ['\n'] = '\\n',
        ['\r'] = '\\r',
        ['\t'] = '\\t',
        ['\b'] = '\\b',
        ['\f'] = '\\f'
    }
    -- control characters must be escaped, nlohmann::json rejects them raw
    return '"' .. string.gsub(value, '[%z\1-\31\\"]', function(character)
        return escapes[character] or string.format('\\u%04x', string.byte(character))
    end) .. '"'
end

local function encode(value, depth, seen)
    local value_type = type(value)

    if value == nil then
        return 'null'
    end
    if value_type == 'boolean' then
        return value and 'true' or 'false'
    end
    if value_type == 'number' then
        if value ~= value or value == math.huge or value == -math.huge then
            return 'null'
        end
        if value == math.floor(value) then
            return string.format('%d', value)
        end
        return string.format('%.4f', value)
    end
    if value_type == 'string' then
        return encode_string(value)
    end
    if value_type ~= 'table' then
        return encode_string(tostring(value))
    end
    if depth <= 0 or seen[value] then
        return 'null'
    end

    seen[value] = true

    local count = 0
    for key, entry in pairs(value) do
        count = count + 1
    end

    local is_array = count > 0
    for i = 1, count do
        if value[i] == nil then
            is_array = false
            break
        end
    end

    local result
    if is_array or count == 0 then
        local parts = {}
        for i = 1, count do
            parts[i] = encode(value[i], depth - 1, seen)
        end
        result = '[' .. table.concat(parts, ',') .. ']'
    else
        local parts = {}
        for key, entry in pairs(value) do
            parts[#parts + 1] = encode_string(tostring(key)) .. ':' .. encode(entry, depth - 1, seen)
        end
        result = '{' .. table.concat(parts, ',') .. '}'
    end

    seen[value] = nil
    return result
end

function mwx_debug.to_json(value)
    return encode(value, 6, {})
end

function mwx_debug.keys(value)
    local result = {}
    for key, entry in pairs(value) do
        result[#result + 1] = tostring(key) .. ' = ' .. tostring(entry)
    end
    table.sort(result)
    return table.concat(result, '\n')
end

local function safe(fn, default)
    local ok, value = pcall(fn)
    if ok then
        return value
    end
    return default
end

local function upper(value)
    return string.upper(tostring(value or ''))
end

local function get_root()
    return safe(function() return Engine.GetLuiRoot() end, nil)
end

local function describe(element, focus_id)
    local id = safe(function() return element.id end, nil)
    local text = safe(function() return element:getText() end, nil)

    local node = {
        id = tostring(id),
        full_id = tostring(safe(function() return element:getFullID() end, '')),
        visible = not safe(function() return element:isClosed() end, false)
    }

    if type(text) == 'string' and text ~= '' then
        node.text = text
    end

    if focus_id ~= nil and id ~= nil and tostring(id) == tostring(focus_id) then
        node.focused = true
    end

    local rect = safe(function() return element:getRect() end, nil)
    if type(rect) == 'table' then
        node.rect = rect
    end

    return node
end

-- walks the tree below `element`; `visit(element, node, depth)` is called for every child
local function walk(element, visit, depth, budget, seen)
    if depth > mwx_debug.max_depth or budget.count >= mwx_debug.max_nodes then
        return
    end

    local count = safe(function() return element:getNumChildren() end, 0)
    if type(count) ~= 'number' or count <= 0 then
        return
    end

    local child = safe(function() return element:getFirstChild() end, nil)
    local index = 0

    while child ~= nil and index < count and budget.count < mwx_debug.max_nodes do
        if seen[child] then
            break
        end
        seen[child] = true

        if visit(child, depth) ~= false then
            walk(child, visit, depth + 1, budget, seen)
        end

        child = safe(function() return child:getNextSibling() end, nil)
        index = index + 1
    end
end

local function open_menu_names()
    local root = get_root()
    local names = {}

    if root == nil then
        return names
    end

    local types = LUI.MenuBuilder and LUI.MenuBuilder.m_types_build or {}
    for name, _ in pairs(types) do
        local open = safe(function() return LUI.FlowManager.IsMenuOpenAndVisible(root, name) end, false)
        if open then
            names[#names + 1] = tostring(name)
        end
    end

    table.sort(names)
    return names
end

function mwx_debug.snapshot()
    local root = get_root()
    if root == nil then
        return mwx_debug.to_json({ error = 'no LUI root (frontend not loaded)' })
    end

    local focus_id = safe(function() return LUI.UIRoot.GetFirstButtonActionInFocusId(root) end, nil)
    local budget = { count = 0 }
    local seen = {}
    local result = {
        menu = tostring(safe(function() return LUI.FlowManager.GetTopOpenAndVisibleMenuName() end, '')),
        open_menus = open_menu_names(),
        elements = {}
    }

    local function visit(element, depth)
        budget.count = budget.count + 1
        local node = describe(element, focus_id)
        node.depth = depth
        result.elements[#result.elements + 1] = node
        return true
    end

    walk(root, visit, 0, budget, seen)
    result.count = budget.count

    return mwx_debug.to_json(result)
end

-- finds a visible element by id (exact, then substring) or by its text
local function find_element(id, text, index)
    local root = get_root()
    if root == nil then
        return nil
    end

    local wanted_id = id ~= nil and string.lower(tostring(id)) or nil
    local wanted_text = text ~= nil and string.lower(tostring(text)) or nil
    local wanted_index = index ~= nil and tonumber(index) or 1

    local matches = {}
    local exact = {}

    local function consider(element)
        local element_id = safe(function() return element.id end, nil)
        local element_text = safe(function() return element:getText() end, nil)

        if wanted_id ~= nil and element_id ~= nil then
            local current = string.lower(tostring(element_id))
            if current == wanted_id then
                exact[#exact + 1] = element
                return
            end
            if string.find(current, wanted_id, 1, true) ~= nil then
                matches[#matches + 1] = element
                return
            end
        end

        if wanted_text ~= nil and type(element_text) == 'string' then
            local current = string.lower(element_text)
            if current == wanted_text then
                exact[#exact + 1] = element
                return
            end
            if string.find(current, wanted_text, 1, true) ~= nil then
                matches[#matches + 1] = element
            end
        end
    end

    consider(root)
    walk(root, function(element) consider(element) return true end, 0, { count = 0 }, {})

    local list = #exact > 0 and exact or matches
    return list[wanted_index], #list
end

local function element_info(element)
    return {
        id = tostring(safe(function() return element.id end, '')),
        full_id = tostring(safe(function() return element:getFullID() end, '')),
        text = safe(function() return element:getText() end, nil)
    }
end

local pending_actions = {}

-- Runs `action` from the game's own LUI event loop. Calling Engine.ExecNow (which the menu
-- button handlers do) directly from a loadstring chunk fails, so the click has to happen in a
-- timer event like the game's own button presses do.
local function queue_action(root, action)
    local name = 'mwx_debug_action_' .. tostring(#pending_actions + 1)

    local function run()
        local result = { }
        local ok, error = pcall(action)
        result.ok = ok
        if not ok then
            result.error = tostring(error)
        end
        pending_actions[#pending_actions + 1] = result
    end

    local registered = safe(function()
        root:registerEventHandler(name, function(_, _) run() end)
        return true
    end, false)

    if not registered then
        return false
    end

    local added = safe(function()
        root:addElement(LUI.UITimer.new(50, name, nil, true))
        return true
    end, false)

    return added
end

local function get_action_root(element)
    return safe(function() return element:getRootParent() end, nil) or get_root()
end

function mwx_debug.click(element_id, text, index)
    local element, count = find_element(element_id, text, index)
    if element == nil then
        return mwx_debug.to_json({ ok = false, error = 'no matching element', count = count or 0 })
    end

    local info = element_info(element)
    info.matches = count or 1

    local root = get_action_root(element)
    if root == nil then
        info.ok = false
        info.error = 'no LUI root'
        return mwx_debug.to_json(info)
    end

    local queued = queue_action(root, function()
        -- stock menu handlers read event.controller (older LUI API), newer ones
        -- controllerIndex; send both so Play Online / game setup work from the debug UI
        element:processEvent({ name = 'button_action', controller = 0, controllerIndex = 0 })
    end)

    info.ok = queued
    info.queued = queued
    if not queued then
        info.error = 'could not schedule the click'
    end

    return mwx_debug.to_json(info)
end

function mwx_debug.actions()
    return mwx_debug.to_json(pending_actions)
end

function mwx_debug.back()
    local name = safe(function() return LUI.FlowManager.GetTopOpenAndVisibleMenuName() end, nil)
    if name == nil or name == '' then
        return mwx_debug.to_json({ ok = false, error = 'no open menu' })
    end

    local root = get_root()
    if root == nil then
        return mwx_debug.to_json({ ok = false, error = 'no LUI root' })
    end

    local queued = queue_action(root, function()
        LUI.FlowManager.RequestLeaveMenuByName(name)
    end)

    return mwx_debug.to_json({ ok = queued, queued = queued, left = tostring(name) })
end

function mwx_debug.open(name)
    if name == nil or name == '' then
        return mwx_debug.to_json({ ok = false, error = 'name is required' })
    end

    local root = get_root()
    if root == nil then
        return mwx_debug.to_json({ ok = false, error = 'no LUI root' })
    end

    local queued = queue_action(root, function()
        LUI.FlowManager.RequestAddMenu(nil, tostring(name))
    end)

    return mwx_debug.to_json({ ok = queued, queued = queued, opened = tostring(name) })
end

function mwx_debug.menu_open(name)
    local root = get_root()
    if root == nil or name == nil then
        return false
    end

    return safe(function()
        return LUI.FlowManager.IsMenuOpenAndVisible(root, tostring(name)) and true or false
    end, false)
end
