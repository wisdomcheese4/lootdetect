--[[
LootDetect - standalone in-game loot popup addon

Watches chat for item drops (several different message formats FFXI
uses), resolves the item name/id, and shows a small fading toast panel
on screen for it. Multiple simultaneous drops stack vertically. This
is a single, self-contained addon - no dependency on MogWatch or any
other addon.

TESTING:
    //lootdetect test          -- shows one fake popup
    //lootdetect test 3        -- shows 3 fake popups stacked

MOVING THE LIST:
    //lootdetect move          -- show a draggable yellow handle; drag
                                   it with the mouse, then run this
                                   again to lock the position in
                                   (auto-saved)
    //lootdetect mousedebug    -- if dragging doesn't respond right,
                                   turn this on and share the console
                                   output

BACKGROUND STYLE:
    //lootdetect style             -- list available styles
    //lootdetect style gold        -- switch style (saved)
    Options: steel, gold, shadow, royal, emerald

DISPLAY DURATION:
    //lootdetect duration          -- show current duration
    //lootdetect duration 5        -- keep popups on screen for 5
                                       seconds (saved per character)

DEBUGGING DROP DETECTION:
    //lootdetect debugall      -- print mode number + raw text of
                                   every chat line, to find a drop
                                   format that isn't being detected

INSTALL:
    addons/lootdetect/lootdetect.lua
    addons/lootdetect/assets/white_pixel.png
    addons/lootdetect/icons/<item_id>.png   (optional, for icons)
    //lua load lootdetect
]]

_addon.name = 'LootDetect'
_addon.author = 'Brian (w/ Claude)'
_addon.version = '1.0.0'
_addon.commands = {'lootdetect'}

local config = require('config')
local res = require('resources')

-- ============================================================
-- CONFIG - tweak these if you want, nothing else needs editing
-- ============================================================
local ROW_HEIGHT = 56       -- vertical spacing between stacked popups
local ICON_SIZE = 32        -- displayed icon size in pixels
local FADE_IN = 0.25        -- seconds
local HOLD = 3.0            -- seconds fully visible - overridden per-character below
local FADE_OUT = 0.6        -- seconds
local FONT_SIZE = 15
local PADDING = 8           -- space between panel edge and icon/text
local BORDER_PX = 2         -- panel border thickness
local INSET_PX = 1          -- thickness of the beveled inset highlight line
local TOP_STRIP_PX = 6       -- height of the title-bar-style top accent strip
local ICON_PAD = 3          -- padding between the icon and its backdrop slot
local FILL_ALPHA_MAX = 210  -- panel fill never goes fully opaque

-- A few named look-and-feel presets. Switch with //lootdetect style <name>.
local STYLES = {
    steel   = { border = { 130, 150, 190 }, fill = { 10, 12, 28 },  accent = { 180, 205, 235 } },
    gold    = { border = { 180, 140, 60 },  fill = { 25, 18, 8 },   accent = { 235, 195, 95 } },
    shadow  = { border = { 75, 75, 80 },    fill = { 5, 5, 8 },     accent = { 120, 120, 125 } },
    royal   = { border = { 150, 110, 200 }, fill = { 20, 10, 32 },  accent = { 195, 150, 235 } },
    emerald = { border = { 80, 170, 120 },  fill = { 8, 20, 14 },   accent = { 115, 225, 155 } },
}

local ICON_DIR = windower.addon_path .. 'icons\\'
local BG_TEXTURE = windower.addon_path .. 'assets\\white_pixel.png'

-- Anchor position and chosen style are persisted across sessions via
-- the config library.
local default_settings = {
    anchor_x = 100,
    anchor_y = 200,
    style = 'steel',
    duration_by_character = {},  -- { ["CharName"] = seconds, ... }
}
local settings = config.load(default_settings)

local function current_style()
    return STYLES[settings.style] or STYLES.steel
end

local function save_settings()
    local ok1, err1 = pcall(function() settings:save() end)
    if ok1 then
        return
    end
    local ok2, err2 = pcall(function() config.save(settings) end)
    if ok2 then
        return
    end
    windower.add_to_chat(167, 'LootDetect: position save failed.')
    windower.add_to_chat(167, '  settings:save() error: ' .. tostring(err1))
    windower.add_to_chat(167, '  config.save() error: ' .. tostring(err2))
end

-- ============================================================
-- Popup display: internal state
-- ============================================================
local active = {}   -- ordered list of active popups (oldest first)
local next_uid = 1

local function file_exists(path)
    local f = io.open(path, 'rb')
    if f then f:close() return true end
    return false
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- Create the prims for one popup entry. Layering (back to front):
-- border panel -> fill panel -> icon -> text
local function create_popup(item_id, item_name)
    local uid = next_uid
    next_uid = next_uid + 1

    local border_name = 'lootdetect_border_' .. uid
    local inset_name = 'lootdetect_inset_' .. uid
    local fill_name = 'lootdetect_fill_' .. uid
    local accent_name = 'lootdetect_accent_' .. uid
    local icon_bg_name = 'lootdetect_iconbg_' .. uid
    local icon_name = 'lootdetect_icon_' .. uid
    local text_name = 'lootdetect_text_' .. uid

    local icon_path = ICON_DIR .. tostring(item_id) .. '.png'
    local has_icon = file_exists(icon_path)

    windower.text.create(text_name)
    windower.text.set_text(text_name, item_name)
    windower.text.set_font_size(text_name, FONT_SIZE)
    windower.text.set_bg_visibility(text_name, false)
    windower.text.set_color(text_name, 0, 255, 255, 255)
    windower.text.set_stroke_color(text_name, 0, 0, 0, 0)
    windower.text.set_stroke_width(text_name, 2)
    windower.text.set_visibility(text_name, true)

    windower.prim.create(border_name)
    windower.prim.set_texture(border_name, BG_TEXTURE)
    windower.prim.set_visibility(border_name, true)

    windower.prim.create(inset_name)
    windower.prim.set_texture(inset_name, BG_TEXTURE)
    windower.prim.set_visibility(inset_name, true)

    windower.prim.create(fill_name)
    windower.prim.set_texture(fill_name, BG_TEXTURE)
    windower.prim.set_visibility(fill_name, true)

    windower.prim.create(accent_name)
    windower.prim.set_texture(accent_name, BG_TEXTURE)
    windower.prim.set_visibility(accent_name, true)

    if has_icon then
        windower.prim.create(icon_bg_name)
        windower.prim.set_texture(icon_bg_name, BG_TEXTURE)
        windower.prim.set_visibility(icon_bg_name, true)

        windower.prim.create(icon_name)
        windower.prim.set_texture(icon_name, icon_path)
        windower.prim.set_size(icon_name, ICON_SIZE, ICON_SIZE)
        windower.prim.set_fit_to_texture(icon_name, false)
        windower.prim.set_color(icon_name, 0, 255, 255, 255)
        windower.prim.set_visibility(icon_name, true)
    end

    return {
        uid = uid,
        border_name = border_name,
        inset_name = inset_name,
        fill_name = fill_name,
        accent_name = accent_name,
        icon_bg_name = icon_bg_name,
        icon_name = icon_name,
        text_name = text_name,
        has_icon = has_icon,
        text_w = 100,
        text_h = FONT_SIZE,
        start_time = os.clock(),
        destroyed = false,
    }
end

local function destroy_popup(p)
    if p.destroyed then return end
    p.destroyed = true
    windower.prim.delete(p.border_name)
    windower.prim.delete(p.inset_name)
    windower.prim.delete(p.fill_name)
    windower.prim.delete(p.accent_name)
    if p.has_icon then
        windower.prim.delete(p.icon_bg_name)
        windower.prim.delete(p.icon_name)
    end
    windower.text.delete(p.text_name)
end

-- Public entry point: call this when an item drops
local function show_item_popup(item_id, item_name)
    local p = create_popup(item_id, item_name or ('Item ' .. tostring(item_id)))
    table.insert(active, p)
end

-- ============================================================
-- Animation / layout loop
-- ============================================================
windower.register_event('prerender', function()
    if #active == 0 then return end

    local now = os.clock()
    local total_life = FADE_IN + HOLD + FADE_OUT

    for i = #active, 1, -1 do
        local p = active[i]
        local elapsed = now - p.start_time

        if elapsed >= total_life then
            destroy_popup(p)
            table.remove(active, i)
        else
            local alpha
            if elapsed < FADE_IN then
                alpha = 255 * (elapsed / FADE_IN)
            elseif elapsed < FADE_IN + HOLD then
                alpha = 255
            else
                local fade_elapsed = elapsed - FADE_IN - HOLD
                alpha = 255 * (1 - (fade_elapsed / FADE_OUT))
            end
            alpha = clamp(alpha, 0, 255)
            local style = current_style()
            local fill_alpha = math.floor(alpha * (FILL_ALPHA_MAX / 255))
            local border_alpha = math.floor(alpha)
            local content_alpha = math.floor(alpha)

            local measured_w, measured_h = windower.text.get_extents(p.text_name)
            if measured_w and measured_w > 0 then p.text_w = measured_w end
            if measured_h and measured_h > 0 then p.text_h = measured_h end

            local icon_block_w = p.has_icon and (ICON_SIZE + ICON_PAD * 2 + PADDING) or 0
            local box_w = PADDING + icon_block_w + p.text_w + PADDING
            local box_h = math.max(ICON_SIZE + ICON_PAD * 2, p.text_h) + PADDING * 2 + TOP_STRIP_PX

            local slot = i - 1
            local box_x = settings.anchor_x
            local box_y = settings.anchor_y + slot * ROW_HEIGHT

            -- Border: full outer rectangle
            windower.prim.set_position(p.border_name, box_x, box_y)
            windower.prim.set_size(p.border_name, box_w, box_h)
            windower.prim.set_color(p.border_name, border_alpha, style.border[1], style.border[2], style.border[3])

            -- Inset highlight: a thin lighter line just inside the border,
            -- for a subtle beveled/embossed edge
            windower.prim.set_position(p.inset_name, box_x + BORDER_PX, box_y + BORDER_PX)
            windower.prim.set_size(p.inset_name, box_w - BORDER_PX * 2, INSET_PX)
            windower.prim.set_color(p.inset_name, math.floor(border_alpha * 0.6), style.accent[1], style.accent[2], style.accent[3])

            -- Fill: main panel background, inset from the border
            windower.prim.set_position(p.fill_name, box_x + BORDER_PX, box_y + BORDER_PX + INSET_PX)
            windower.prim.set_size(p.fill_name, box_w - BORDER_PX * 2, box_h - BORDER_PX * 2 - INSET_PX)
            windower.prim.set_color(p.fill_name, fill_alpha, style.fill[1], style.fill[2], style.fill[3])

            -- Accent: a title-bar-style strip across the top, replacing
            -- the earlier left-edge bar for a more "dialog box" feel
            windower.prim.set_position(p.accent_name, box_x, box_y)
            windower.prim.set_size(p.accent_name, box_w, TOP_STRIP_PX)
            windower.prim.set_color(p.accent_name, border_alpha, style.accent[1], style.accent[2], style.accent[3])

            local content_x = box_x + PADDING
            local content_y = box_y + TOP_STRIP_PX + (box_h - TOP_STRIP_PX - ICON_SIZE - ICON_PAD * 2) / 2

            if p.has_icon then
                -- Icon backdrop: a small outlined slot behind the icon,
                -- tinted toward the accent color so it reads as its own
                -- distinct area rather than floating on the plain fill
                windower.prim.set_position(p.icon_bg_name, content_x, content_y)
                windower.prim.set_size(p.icon_bg_name, ICON_SIZE + ICON_PAD * 2, ICON_SIZE + ICON_PAD * 2)
                windower.prim.set_color(p.icon_bg_name, math.floor(fill_alpha * 0.7), style.accent[1], style.accent[2], style.accent[3])

                windower.prim.set_position(p.icon_name, content_x + ICON_PAD, content_y + ICON_PAD)
                windower.prim.set_color(p.icon_name, content_alpha, 255, 255, 255)
                content_x = content_x + ICON_SIZE + ICON_PAD * 2 + PADDING
            end

            local dark_stroke = style.fill[1] < 40 and 0 or math.floor(style.fill[1] * 0.3)
            windower.text.set_stroke_color(p.text_name, content_alpha, dark_stroke, dark_stroke, dark_stroke)
            windower.text.set_location(p.text_name, content_x, box_y + TOP_STRIP_PX + (box_h - TOP_STRIP_PX - FONT_SIZE) / 2 - 2)
            windower.text.set_color(p.text_name, content_alpha, 255, 255, 255)
        end
    end
end)

-- ============================================================
-- Move mode: drag the popup anchor with the mouse
-- ============================================================
local move_mode = false
local dragging = false
local drag_offset_x, drag_offset_y = 0, 0
local HANDLE_W, HANDLE_H = 260, 56
local handle = nil

local function handle_box()
    return settings.anchor_x, settings.anchor_y, HANDLE_W, HANDLE_H
end

local function create_handle()
    if handle then return end
    local border_name, fill_name, text_name = 'lootdetect_handle_border', 'lootdetect_handle_fill', 'lootdetect_handle_text'

    windower.prim.create(border_name)
    windower.prim.set_texture(border_name, BG_TEXTURE)
    windower.prim.set_visibility(border_name, true)

    windower.prim.create(fill_name)
    windower.prim.set_texture(fill_name, BG_TEXTURE)
    windower.prim.set_visibility(fill_name, true)

    windower.text.create(text_name)
    windower.text.set_text(text_name, 'Drag me, then //lootdetect move to lock in')
    windower.text.set_font_size(text_name, 12)
    windower.text.set_bg_visibility(text_name, false)
    windower.text.set_color(text_name, 255, 255, 255, 255)
    windower.text.set_stroke_color(text_name, 255, 0, 0, 0)
    windower.text.set_stroke_width(text_name, 2)
    windower.text.set_visibility(text_name, true)

    handle = { border_name = border_name, fill_name = fill_name, text_name = text_name }
end

local function destroy_handle()
    if not handle then return end
    windower.prim.delete(handle.border_name)
    windower.prim.delete(handle.fill_name)
    windower.text.delete(handle.text_name)
    handle = nil
end

local function draw_handle()
    if not handle then return end
    local x, y, w, h = handle_box()
    windower.prim.set_position(handle.border_name, x, y)
    windower.prim.set_size(handle.border_name, w, h)
    windower.prim.set_color(handle.border_name, 255, 255, 220, 80)

    windower.prim.set_position(handle.fill_name, x + BORDER_PX, y + BORDER_PX)
    windower.prim.set_size(handle.fill_name, w - BORDER_PX * 2, h - BORDER_PX * 2)
    windower.prim.set_color(handle.fill_name, 200, current_style().fill[1], current_style().fill[2], current_style().fill[3])

    windower.text.set_location(handle.text_name, x + PADDING, y + PADDING)
end

windower.register_event('prerender', function()
    if move_mode then
        draw_handle()
    end
end)

local seen_mouse_types = {}
local mouse_debug = false

windower.register_event('mouse', function(type, x, y, delta, blocked)
    if not move_mode then return blocked end

    if mouse_debug and not seen_mouse_types[type] then
        seen_mouse_types[type] = true
        windower.add_to_chat(207, ('LootDetect MOUSE DEBUG: type=%s x=%s y=%s'):format(tostring(type), tostring(x), tostring(y)))
    end

    if type == 1 then
        local hx, hy, hw, hh = handle_box()
        if x >= hx and x <= hx + hw and y >= hy and y <= hy + hh then
            dragging = true
            drag_offset_x = x - hx
            drag_offset_y = y - hy
            return true
        end
    elseif type == 2 then
        if dragging then
            dragging = false
            return true
        end
    elseif type == 0 then
        if dragging then
            settings.anchor_x = x - drag_offset_x
            settings.anchor_y = y - drag_offset_y
            save_settings()
            return true
        end
    end

    return blocked
end)

-- ============================================================
-- Drop detection
-- ============================================================
local player_name = nil

local function get_player_name()
    local player = windower.ffxi.get_player()
    if player then
        player_name = player.name
        local saved_duration = settings.duration_by_character and settings.duration_by_character[player_name]
        if saved_duration then
            HOLD = saved_duration
        end
    end
end

get_player_name()

windower.register_event('login', function()
    windower.send_command('@wait 1; lua i lootdetect get_player_name')
end)

_G.get_player_name = get_player_name

local function normalize_item_name(item_name)
    -- Capitalize the first letter of each space-separated word, leave
    -- the rest of the word exactly as-is - force-lowercasing the rest
    -- mangles roman numerals and acronyms (e.g. "II" -> "Ii").
    return item_name:gsub("(%a)([%w_']*)", function(first, rest)
        return first:upper() .. rest
    end)
end

local item_id_by_name = {}
local name_cache_built = false

local function build_name_cache()
    if name_cache_built then return end
    for id, item in pairs(res.items) do
        if item.name then
            item_id_by_name[item.name] = id
            item_id_by_name[normalize_item_name(item.name)] = id
        end
        if item.name_log then
            item_id_by_name[item.name_log] = id
            item_id_by_name[normalize_item_name(item.name_log)] = id
        end
    end
    name_cache_built = true
end

local function trigger_popup(item_name)
    build_name_cache()
    local item_id = item_id_by_name[item_name] or 0
    local popup_name = item_name
    if item_id ~= 0 and res.items[item_id] then
        popup_name = res.items[item_id].name_log or res.items[item_id].name or item_name
    end
    show_item_popup(item_id, popup_name)
end

local function strip_format(text)
    text = text:gsub(string.char(0xEF)..string.char(0x27), '')
    text = text:gsub(string.char(0xEF)..string.char(0x28), '')
    text = text:gsub(string.char(0x1F)..'[%z\1-\255]', '')
    text = text:gsub(string.char(0x1E)..'[%z\1-\255]', '')
    text = text:gsub(string.char(0x7F)..'[%z\1-\255]', '')
    text = text:gsub('%c', '')
    return text
end

local function parse_obtains_message(clean_message)
    local player, item_match = clean_message:match("^(%w+) obtains? an? (.+)%.$")
    if not player then
        player, item_match = clean_message:match("^(%w+) obtains? (.+)%.$")
    end
    if not player then
        player, item_match = clean_message:match("^(%w+) obtains? an? (.+)$")
    end
    if not player then
        player, item_match = clean_message:match("^(%w+) obtains? (.+)$")
    end
    return player, item_match
end

local debug_all = false

local function check_for_drops(message, mode)
    if message:find("^LootDetect:") or message:find("^DEBUG ALL:") then
        return
    end

    if not player_name then
        get_player_name()
    end

    if debug_all then
        windower.add_to_chat(207, string.format('DEBUG ALL: Mode=%d, Message=%s', mode, message))
    end

    local clean_message = strip_format(message)

    -- Mode 121: a personal-drop message channel that happens to use
    -- the same "<Player> obtains <item>" phrasing as enemy loot.
    if mode == 121 then
        local player, item_match = parse_obtains_message(clean_message)
        if player and item_match and (not player_name or player == player_name) then
            item_match = item_match:gsub("^[Tt]he [Tt]emporary [Ii]tem:%s*", "")
            item_match = item_match:gsub("[%.!%?]+$", ""):gsub("^%s+", ""):gsub("%s+$", "")
            trigger_popup(normalize_item_name(item_match))
            return
        end
    end

    -- Mode 127: enemy loot
    if mode == 127 then
        local player, item_match = parse_obtains_message(clean_message)
        if player and item_match and (not player_name or player == player_name) then
            item_match = item_match:gsub("[%.!%?]+$", ""):gsub("^%s+", ""):gsub("%s+$", "")
            trigger_popup(normalize_item_name(item_match))
            return
        end
    end

    -- "You obtain (x) <item>." - personal drops
    local obtain_count, obtain_item = clean_message:match("^You obtain (%d+) (.+)%.$")
    if obtain_count and obtain_item then
        obtain_item = obtain_item:gsub("[%.!%?]+$", ""):gsub("^%s+", ""):gsub("%s+$", "")
        trigger_popup(normalize_item_name(obtain_item))
        return
    end

    -- "Obtained: <item>" - chests/NPCs
    local obtained_item = clean_message:match("^Obtained:%s*(.+)$")
        or clean_message:match("^You obtained:%s*(.+)$")
        or clean_message:match("^Obtained%s+(.+)$")
    if obtained_item then
        obtained_item = obtained_item:gsub("%.+$", ""):gsub("!+$", "")
            :gsub("^%s+", ""):gsub("%s+$", "")
        if obtained_item ~= '' then
            trigger_popup(normalize_item_name(obtained_item))
        end
        return
    end
end

windower.register_event('incoming text', function(original, modified, original_mode, modified_mode)
    check_for_drops(original, original_mode)
end)

-- ============================================================
-- Commands
-- ============================================================
windower.register_event('addon command', function(...)
    local args = {...}
    if args[1] == 'test' then
        local count = tonumber(args[2]) or 1
        for i = 1, count do
            coroutine.schedule(function()
                show_item_popup(4102 + i, 'Test Item ' .. i)
            end, (i - 1) * 0.3)
        end
    elseif args[1] == 'show' then
        local item_id = tonumber(args[2])
        if item_id then
            local name_parts = {}
            for i = 3, #args do
                table.insert(name_parts, args[i])
            end
            local item_name = table.concat(name_parts, ' ')
            show_item_popup(item_id, item_name)
        end
    elseif args[1] == 'move' then
        move_mode = not move_mode
        if move_mode then
            create_handle()
            windower.add_to_chat(207, 'LootDetect: move mode ON. Left-click and drag the yellow box, then run //lootdetect move again to lock it in.')
        else
            destroy_handle()
            save_settings()
            windower.add_to_chat(207, ('LootDetect: move mode OFF. Position saved at %d, %d.'):format(settings.anchor_x, settings.anchor_y))
        end
    elseif args[1] == 'style' then
        local name = args[2] and args[2]:lower()
        if name and STYLES[name] then
            settings.style = name
            save_settings()
            windower.add_to_chat(207, 'LootDetect: style set to "' .. name .. '" (saved).')
        else
            local names = {}
            for k in pairs(STYLES) do table.insert(names, k) end
            table.sort(names)
            windower.add_to_chat(207, 'LootDetect: current style is "' .. settings.style .. '". Options: ' .. table.concat(names, ', '))
        end
    elseif args[1] == 'duration' then
        local seconds = tonumber(args[2])
        if seconds and seconds > 0 then
            HOLD = seconds
            if not settings.duration_by_character then
                settings.duration_by_character = {}
            end
            if player_name then
                settings.duration_by_character[player_name] = seconds
                save_settings()
                windower.add_to_chat(207, ('LootDetect: display duration set to %.1fs for %s (saved).'):format(seconds, player_name))
            else
                windower.add_to_chat(207, ('LootDetect: display duration set to %.1fs for this session (not saved yet - player name not known).'):format(seconds))
            end
        else
            local current = player_name and settings.duration_by_character and settings.duration_by_character[player_name]
            windower.add_to_chat(207, ('LootDetect: current display duration is %.1fs%s. Use //lootdetect duration <seconds> to change it.')
                :format(HOLD, current and ' (saved for this character)' or ' (default)'))
        end
    elseif args[1] == 'mousedebug' then
        mouse_debug = not mouse_debug
        seen_mouse_types = {}
        windower.add_to_chat(207, 'LootDetect: mouse debug ' .. (mouse_debug and 'ON' or 'OFF'))
    elseif args[1] == 'debugall' then
        debug_all = not debug_all
        windower.add_to_chat(207, 'LootDetect: debug ALL mode ' .. (debug_all and 'ON - showing all messages' or 'OFF'))
    end
end)

-- Clean up any leftover prims if the addon is unloaded mid-animation
windower.register_event('unload', function()
    for _, p in ipairs(active) do
        destroy_popup(p)
    end
    active = {}
end)
