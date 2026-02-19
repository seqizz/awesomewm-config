local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local beautiful = require("beautiful")
local naughty = require("naughty")
local my_utils = require('my_modules/my_utils')
local my_theme = require('my_modules/my_theme')
local xresources = require("beautiful.xresources")
local dpi = xresources.apply_dpi

tagsave_folder = gears.filesystem.get_cache_dir() .. "tagsaves"

function debug_print(text, needed)
  if needed == nil then
      needed = true
  end
  if needed then
    print('<<<<<<< ' .. tostring(text))
  end
end

function suspend_toggle(c)
  awful.spawn.easy_async("ps -q " .. c.pid .. " -o state --no-headers",
                         function(stdout, stderr, reason, exit_code)
    if stdout == "T\n" then
      -- suspended, let's wake up
      c.border_color = beautiful.border_normal
      c.border_width = beautiful.border_width
      c.opacity = 1
      naughty.notify {
        text = "waking up client: " .. c.class .. " (" .. c.pid .. ")"
      }
      awful.spawn("kill -18 " .. c.pid)
    else
      -- working, let's suspend
      c.border_color = '#ff0000'
      c.border_width = 10
      c.opacity = 0.8
      naughty.notify {
        text = "suspending client: " .. c.class .. " (" .. c.pid .. ")"
      }
      awful.spawn("kill -19 " .. c.pid)
    end
  end)
end

-- Used from xidlehook to notify we're about to lock the screen
function flash_toggle(c)
  old_opacity = c.opacity
  c.opacity = 0.2
  awful.spawn.easy_async("sleep 0.03", function()
    c.opacity = 0.3
  end)
  awful.spawn.easy_async("sleep 0.05", function()
    c.opacity = 0.4
  end)
  awful.spawn.easy_async("sleep 0.09", function()
    c.opacity = 0.5
  end)
  awful.spawn.easy_async("sleep 0.13", function()
    c.opacity = 0.6
  end)
  awful.spawn.easy_async("sleep 0.16", function()
    c.opacity = 0.7
  end)
  awful.spawn.easy_async("sleep 0.20", function()
    c.opacity = 0.8
  end)
  awful.spawn.easy_async("sleep 0.25", function()
    c.opacity = old_opacity
  end)
end

function sticky_toggle(c)
  if c.sticky then
    c.ontop = false
    c.sticky = false
  else
    c.ontop = true
    c.sticky = true
  end
  naughty.notify {
    text = "Sticky set to " .. tostring(c.sticky)
  }
end

function shit(c)
  nextcl = awful.client.next (1, c, true)
  print(nextcl.name)
end

function float_toggle(c)
  awful.client.floating.toggle()
  if c.floating then
    c.ontop = true
    c.sticky = true
    c.skip_taskbar = true
    c.width = dpi(500)
    c.height = dpi(700)
    c.y = 35
    awful.placement.top_right(client.focus, {honor_workarea=true})
  else
    c.ontop = false
    c.sticky = false
    c.skip_taskbar = false
  end
end

function move_or_expand(c, action, direction)
  -- Check if client is floating
  if c.floating then
    if action == "expand" then
      if direction == "right" then
        c:relative_move(0, 0, dpi(40), 0)
      elseif direction == "left" then
        c:relative_move(dpi(-20), 0, dpi(20), 0)
      elseif direction == "up" then
        c:relative_move(0, dpi(-20), 0, dpi(20))
      elseif direction == "down" then
        c:relative_move(0, 0, 0, dpi(40))
      end
    elseif action == "shrink" then
      if direction == "right" then
        c:relative_move(dpi(20), 0, dpi(-20), 0)
      elseif direction == "left" then
        c:relative_move(0, 0, dpi(-40), 0)
      elseif direction == "up" then
        c:relative_move(0, 0, 0, dpi(-40))
      elseif direction == "down" then
        c:relative_move(0, dpi(20), 0, dpi(-20))
      end
    elseif action == "move" then
      if direction == "right" then
        c:relative_move(dpi(40), 0, 0, 0)
      elseif direction == "left" then
        c:relative_move(dpi(-40), 0, 0, 0)
      elseif direction == "up" then
        c:relative_move(0, dpi(-40), 0, 0)
      elseif direction == "down" then
        c:relative_move(0, dpi(40), 0, 0)
      end
    end
  else
    -- Not a floating one, sooo.. let's start moving tiling factors.
    -- XXX: Consider action here, we might want to swap windows instead of moving them
    if direction == "right" then
      awful.tag.incmwfact(0.02)
    elseif direction == "left" then
      awful.tag.incmwfact(-0.02)
    elseif direction == "up" then
      if c.y > 100 then
        -- A guess at this point, this client is on bottom
        awful.client.incwfact(0.05)
      else
        awful.client.incwfact(-0.05)
      end
    elseif direction == "down" then
      if c.y > 100 then
        -- A guess at this point, this client is on bottom
        awful.client.incwfact(-0.05)
      else
        awful.client.incwfact(0.05)
      end
    end
  end
end

function save_mouse_location(printmore)
  printmore = printmore or false
  debug_print('save_mouse_location, x: ' .. mouse.coords().x .. ', y: ' .. mouse.coords().y, printmore)
  return mouse.coords().x, mouse.coords().y, awful.screen.focused()
end

function restore_mouse_location(x, y, screen, printmore, refocus)
  refocus = refocus or false
  printmore = printmore or false
  debug_print('restore_mouse_location: Restoring mouse location to ' .. x .. ', ' .. y, printmore)
  mouse.coords {x = x, y = y}
  if refocus then
    awful.screen.focus(screen)
  end
end

function switch_focus_without_mouse(c, dir, printmore)
  x, y, prev_scr = save_mouse_location(printmore)
  awful.client.focus.global_bydirection(dir, c, true)
  restore_mouse_location(x, y, prev_scr, printmore)
end

function switch_to_tag(tag_name, printmore)
  debug_print('switch_to_tag: Switching to tag ' .. tag_name, printmore)
  t = find_tag_by_first_word(tag_name, printmore)
  awful.tag.viewmore({t}, t.screen)
  awful.screen.focus(t.screen)
  -- Shoo any lingering Thunderbird tooltip windows (they bypass WM) buggy as fuck
  awful.spawn.easy_async('bash /home/gurkan/.path/hide-tb-tooltips', function() end)
end

function find_tag_by_first_word(first_word, printmore)
  local all_tags = root.tags()
  for _, t in ipairs(all_tags) do
    if first_word == my_utils.get_first_word(t.name) then
      debug_print("find_tag_by_first_word: Found tag " .. t.name, printmore)
      return t
    end
  end
end

function focus_previous_client(tag_name, printmore)
    local tag_of_gone = find_tag_by_first_word(my_utils.get_first_word(tag_name), printmore)
    if not tag_of_gone then
        debug_print("focus_previous_client: Could not find tag for " .. tag_name, printmore)
        return
    end

    debug_print("focus_previous_client: Looking for clients in tag: " .. tag_of_gone.name, printmore)

    -- FIRST: Check actual clients currently on this tag (including new ones not in history yet)
    local clients_on_tag = tag_of_gone:clients()
    if #clients_on_tag > 0 then
        -- We have clients on this tag, try to find one in focus history first
        local max_history_depth = 10
        local client_to_focus = nil

        for idx = 0, max_history_depth - 1 do
            local history_client = awful.client.focus.history.get(nil, idx)
            if not history_client then break end

            -- Check if this history client is in our current tag's client list
            for _, tag_client in ipairs(clients_on_tag) do
                if history_client == tag_client then
                    client_to_focus = history_client
                    debug_print("focus_previous_client: Found client " .. client_to_focus.name .. " in both history and tag", printmore)
                    break
                end
            end
            if client_to_focus then break end
        end

        -- If no client found in history, just pick the first client on the tag
        if not client_to_focus then
            client_to_focus = clients_on_tag[1]
            debug_print("focus_previous_client: No client in history, focusing first client on tag: " .. client_to_focus.name, printmore)
        end

        client.focus = client_to_focus
        client_to_focus:raise()
    else
        -- No clients on this tag, fall back to most recent on same screen only
        debug_print("focus_previous_client: No clients on tag " .. tag_of_gone.name .. ", looking for clients on same screen", printmore)
        local current_screen = tag_of_gone.screen
        local max_history_depth = 10

        for idx = 0, max_history_depth - 1 do
            local history_client = awful.client.focus.history.get(nil, idx)
            if not history_client then break end

            -- Only focus clients on the same screen to avoid jumping to different tags
            if history_client.screen == current_screen then
                client.focus = history_client
                debug_print("focus_previous_client: Focusing screen-local client " .. history_client.name, printmore)
                history_client:raise()
                return
            end
        end
        debug_print("focus_previous_client: No suitable client found, leaving focus empty", printmore)
    end
end

-- @Reference:
-- function focus_previous_client(tag_name)
--   -- local prev_idx = 0
--   local prev = awful.client.focus.history.get(nil, 0)
--   if prev then
--     -- if prev.first_tag.name == tag_name then
--       client.focus = prev
--       prev:raise()
--     -- end
--   end
-- end

function find_screen_of_tag(screens_table, tag_obj, printmore)
  for name, properties in pairs(screens_table) do
    for _, t in ipairs(properties.tags) do
      if t == tag_obj then
        debug_print("find_screen_of_tag: Found " .. name .. " for tag " .. tag_obj.name, printmore)
        return properties["object"]
      else
        debug_print("find_screen_of_tag: " .. tag_obj.name .. " not in screen " .. name, printmore)
      end
    end
  end
end

function move_focused_client_to_tag(tag_name)
  -- tag_obj = awful.tag.find_by_name(nil, tag_name)
  tag_obj = find_tag_by_first_word(tag_name)
  if client.focus then
    my_client_obj = client.focus
    debug_print('Moving focused window (' .. my_client_obj.name .. ') to tag ' .. tag_name, printmore)
    my_client_obj:move_to_tag(tag_obj)
    switch_to_tag(tag_name, printmore)
    client.focus = my_client_obj
  end
end

function hide_stickies()
  local cls = client.get()
  local stickies = {}
  -- Get all the stickies
  for _, c in ipairs(cls) do
    if c.sticky then
      table.insert(stickies, c)
    end
  end
  if my_utils.table_length(stickies) == 0 then
    -- no sticky found
    naughty.notify {text = "Can't find a damn sticky window", timeout = 1}
    return
  end
  for idx, c in ipairs(stickies) do
    if c.marked then
      -- already transparent
      c.marked = false
      if c.class == "gathertown" then
        c.width = dpi(1800)
        c.height = dpi(250)
      else
        c.width = dpi(500)
        c.height = dpi(700)
      end
      c.border_color = beautiful.border_normal
      c.border_width = beautiful.border_width
      c.opacity = 1
      awful.placement.top_right(c)
      c.y = dpi(30)
    else
      c.marked = true
      c.opacity = 0.9
      c.height = 200
      c.width = 300
      c.border_color = '#26b7d4'
      c.border_width = 10
      awful.placement.top_right(c)
      c.y = dpi(30)
    end
  end
end

function run_once(program, grep_for, on_tag)
  grep_for = grep_for or program:gmatch("%w+")() -- get first word
  awful.spawn.easy_async(
    "pgrep -f " .. grep_for,
    function(stdout, stderr, reason, exit_code)
      if exit_code ~= 0 then
        naughty.notify { text = "starting " .. program .. " once" }
        if on_tag ~= nil then
          awful.spawn.with_shell(program, {tag = on_tag})
        else
          awful.spawn.with_shell(program)
        end
      end
    end
  )
end

-- @Reference experimental fs-level locking for internal ops
-- function lock(action)
-- 	if action == "is_locked" then
-- 		if os.execute("ls /tmp/.awesome_lock >/dev/null 2>&1") then
-- 			return true
-- 		else
-- 			return false
-- 		end
-- 	end
--
-- 	if action == "lock" then
-- 		if os.execute("mkdir /tmp/.awesome_lock >/dev/null 2>&1") then
-- 			return true
-- 		else
-- 			return false
-- 		end
-- 	end
--
-- 	if action == "unlock" then
-- 		if os.execute("rmdir /tmp/.awesome_lock >/dev/null 2>&1") then
-- 			return true
-- 		else
-- 			return false
-- 		end
-- 	end
--
-- end

function get_child_of(s, screens_table)
  -- Lua doesn't have "continue" statement, so using goto 🤷
  for name, properties in pairs(screens_table) do
    if properties["object"] == s then
      goto skipthis
    end
    if properties["parent"] == nil then
      goto skipthis
    end
    if properties["parent"]["object"] == s then
      return properties["object"]
    end
    ::skipthis::
  end
  return nil
end

local lock_file = "/tmp/awesome_wallpaper.lock"
function resize_screen(s, screens_table, shrink)
  if shrink then
      diff = -dpi(50)
  else
      diff = dpi(50)
  end

  for name, properties in pairs(screens_table) do
    if properties["object"] == s then
        -- I found my screen
      if properties["is_fake"] then
        -- this is a fake screen which has a sibling (parent)
        -- whatever you do here, do the reverse to the parent
        -- first, we will reverse the action on the shrink variable
        -- because we want to have a consistent shortcut, independent of our current screen
        -- e.g. same key will always cause growth on the same screen, shrink on the other
        diff = -diff
        local geo = s.geometry
        local parent_geo = properties["parent"]["object"].geometry
        s:fake_resize(geo.x, geo.y, geo.width + diff, geo.height)
        properties["parent"]["object"]:fake_resize(parent_geo.x + diff, parent_geo.y, parent_geo.width - diff, parent_geo.height)
      else
        local geo = s.geometry
        child = get_child_of(s, screens_table)
        if child == nil then
            -- this screen has no fake screen under it, noop
            goto nochange
        end
        -- this is a screen which has a fake screen sibling
        -- whatever you do here, do the reverse to the sibling
        local fake_geo = child.geometry
        s:fake_resize(geo.x - diff, geo.y, geo.width + diff, geo.height)
        child:fake_resize(fake_geo.x,fake_geo.y, fake_geo.width - diff, fake_geo.height)
        ::nochange::
      end
    end
  end
end

local function set_wallpaper(s)
  gears.wallpaper.maximized(gears.filesystem.get_random_file_from_dir(
    "/home/gurkan/syncfolder/wallpaper",
    {".jpg", ".png", ".svg"},
    true
  ), s, false)
end

local function is_fresh(filepath, max_age_seconds)
    local f = io.popen("stat -c %Y " .. filepath)
    if not f then return false end
    local mod_time = tonumber(f:read("*all"))
    f:close()
    if not mod_time then return false end
    return (os.time() - mod_time) < max_age_seconds
end


screen.connect_signal("request::wallpaper", function(_)
  if wallpaper_timer then return end  -- Already scheduled
  wallpaper_timer = gears.timer.start_new(0.1, function()
    -- Lock logic as above
    if gears.filesystem.file_readable(lock_file) and is_fresh(lock_file, 10) then
      wallpaper_timer = nil
      return false
    end
    awful.spawn.with_shell("touch " .. lock_file)
    gears.timer.start_new(3, function()
      for scr in screen do
        set_wallpaper(scr)
      end
      awful.spawn.with_shell("rm -f " .. lock_file)
      wallpaper_timer = nil
      return false
    end)
    return false
  end)
end)

local function createFolder(folder)
  local p = io.popen('mkdir -p ' .. folder)
  p:close()
end

local function get_tag_with_focused_window()
    for s in screen do
        for _, t in ipairs(s.tags) do
            if t.selected then
                for _, c in ipairs(t:clients()) do
                    if client.focus == c then
                        return t
                    end
                end
            end
        end
    end
    return nil
end

function save_current_tags(screens_table)
  focused_tag = get_tag_with_focused_window()

  -- Ensure that the folder exists
  createFolder(tagsave_folder)
  for name, feat in pairs(screens_table) do
    active_tags = {}
    local filename = tagsave_folder .. "/tagsave-" .. name
    os.remove(filename)
    for _, tagobj in pairs(feat["object"].selected_tags) do
        if my_utils.table_contains(feat["tags"], tagobj) then
            if tagobj == focused_tag then
              -- this is the focused tag so it has to get marked
              table.insert(active_tags, my_utils.get_first_word(tagobj.name) .. ":")
            else
              table.insert(active_tags, my_utils.get_first_word(tagobj.name))
            end
        end
    end
    local f = assert(io.open(filename, "w"))
    for _, tagname in pairs(active_tags) do
        f:write(tagname, "\n")
    end
    f:close()
  end
end


function get_latest_urgent_client()
    local latest_urgent_client = nil
    local latest_urgent_time = 0

    for _, c in ipairs(client.get()) do
        if c.urgent == true and c.urgent_since and c.urgent_since > latest_urgent_time then
            latest_urgent_client = c
            latest_urgent_time = c.urgent_since
        end
    end

    return latest_urgent_client
end

function load_last_active_tags(screens_table, printmore)
  focused_tag = nil
  for name, feat in pairs(screens_table) do
    local filename = tagsave_folder .. "/tagsave-" .. name
    tag_list = my_utils.read_lines_from(filename)
    if next(tag_list) ~= nil then
      local previous_tags = {}
      for _, tag_name in pairs(tag_list) do
        if tag_name:sub(-1) == ":" then
          tag_name = tag_name:sub(1, -2)
          focused_tag = find_tag_by_first_word(tag_name, printmore)
        end
        local t = find_tag_by_first_word(tag_name, printmore)
        table.insert(previous_tags, t)
      end
      local _, firsttag = next(previous_tags)
      local screen_name = find_screen_of_tag(screens_table, firsttag, printmore)
      awful.tag.viewnone(screen_name)
      awful.tag.viewmore(previous_tags, screen_name)
    end
  end
  if focused_tag then
    debug_print("load_last_active_tags: Last focused tag is " .. focused_tag.name .. " .. loading last", printmore)
    -- Switch to the screen of the focused tag by emptying its screen and toggling it
    awful.tag.viewnone(find_screen_of_tag(screens_table, focused_tag, printmore))
    awful.tag.viewtoggle(focused_tag)
  end
end

function string:firstword()
    -- matches the first word and returns it, or it returns nil
    return self:match("^([%w\\-]+)");
end

function string:resolutions()
    -- returns resolutions (x and y) from xrandr output line
    return self:match("(%d+)x(%d+)")
end

function find_screen_by_name(name)
  for s in screen do
    for screen_name, _ in pairs(s.outputs) do
      if screen_name == name then
        return s
      end
    end
  end
end

function get_screen_of_focused()
  -- check if any client is focused
  local c = client.focus
  if c then
    -- found focus, return its screen
    return c.screen
  end
end

function unminimize_client()
  local c = awful.client.restore()
  -- Focus restored client
  if c then
    c:emit_signal(
    "request::activate", "key.unminimize", {raise = true}
    )
  end
end


function get_screens()
  local output_tbl = {}
  local xrandr = io.popen("xrandr -q --current | grep -E ' connected (primary )?[0-9]'")

  if xrandr then
    for line in xrandr:lines() do
      -- if no physical screen is found, skip this line
      screen_obj = my_utils.find_screen_by_name(line:firstword())
      if screen_obj == nil then
          goto skipanother
      end
      width, height = line:resolutions()
      name = line:firstword() .. "_" .. width .. "x" .. height
      output_tbl[name] = {}
      primary = false
      if string.match(line, " primary ") then
          primary = true
      end
      output_tbl[name]["name"] = name
      output_tbl[name]["primary"] = primary
      output_tbl[name]["width"] = width
      output_tbl[name]["height"] = height
      output_tbl[name]["object"] = screen_obj
      output_tbl[name]["parent"] = nil
      output_tbl[name]["tags"] = {}
      ::skipanother::
    end
    xrandr:close()
  end

    -- now check if there is any fake screens needed to be added
    -- if the screen is too wide (or pixel count is too high, e.g. 4K), we will create a fake screen and add it to the table
    for name, properties in pairs(output_tbl) do
        if properties["is_fake"] then
            goto skip
        end
        local geo = properties["object"].geometry
        if (( geo.width / geo.height) > 2) or geo.width > 3000 then
            fake_width = math.ceil(geo.width/2)
            new_width = math.ceil(geo.width/2)
            new_width2 = geo.width - new_width
            if not (( geo.width / geo.height) > 2) then
                -- this is not a wide screen, let's give more to the left side a bit more (web/mail)
                fake_width = math.ceil(geo.width*0.55)
            end
            properties["object"]:fake_resize(geo.x + fake_width, geo.y, (geo.width - fake_width), geo.height)
            fake_obj = screen.fake_add(geo.x, geo.y, fake_width, geo.height)
            fake_screen_name = name .. "_sub_" .. tostring(fake_width) .. "x" .. tostring(geo.height)
            output_tbl[fake_screen_name] = {}
            output_tbl[fake_screen_name]["is_fake"] = true
            output_tbl[fake_screen_name]["name"] = fake_screen_name
            output_tbl[fake_screen_name]["parent"] = output_tbl[name]
            output_tbl[fake_screen_name]["object"] = fake_obj
            output_tbl[fake_screen_name]["primary"] = false
            output_tbl[fake_screen_name]["tags"] = {}
        end
        ::skip::
    end
	return output_tbl
end

function get_tooltip(object_to_attach)
  local tt = awful.tooltip({
    align = 'bottom_right',
    bg = my_theme.tooltip_bg,
    fg = my_theme.tooltip_fg,
    font = my_theme.font,
    margin_topbottom = dpi(5),
    objects = { object_to_attach },
    text = '',
    visible = false,
  })
  tt:set_shape(function(cr, width, height)
    gears.shape.partially_rounded_rect(cr, width, height, false, true, true, true, 30)
  end)
  return tt
end

function detect_external_monitor()
  for name, _ in pairs(awful.screen.focused().outputs) do
    if name ~= 'eDP-1' then
      return true
    end
  end
  return false
end

function get_total_screen_count(screens_table)
  if screens_table then
    -- Count all screens in the screens_table (including fake ones)
    local count = 0
    for _, _ in pairs(screens_table) do
      count = count + 1
    end
    return count
  else
    -- Fallback to built-in count if no screens_table provided
    return screen:count()
  end
end
--  vim: set ts=2 sw=2 tw=0 et :
