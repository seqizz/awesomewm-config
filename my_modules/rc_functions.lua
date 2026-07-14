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
      naughty.notification {
        text = "waking up client: " .. c.class .. " (" .. c.pid .. ")"
      }
      awful.spawn("kill -18 " .. c.pid)
    else
      -- working, let's suspend
      c.border_color = '#ff0000'
      c.border_width = 10
      c.opacity = 0.8
      naughty.notification {
        text = "suspending client: " .. c.class .. " (" .. c.pid .. ")"
      }
      awful.spawn("kill -19 " .. c.pid)
    end
  end)
end

-- Used from xidlehook to notify we're about to lock the screen
function flash_toggle(c)
  local old_opacity = c.opacity
  -- Each step: {delay_from_previous_step_in_seconds, target_opacity}
  local steps = {
    { 0.03, 0.3 },
    { 0.02, 0.4 },
    { 0.04, 0.5 },
    { 0.04, 0.6 },
    { 0.03, 0.7 },
    { 0.04, 0.8 },
    { 0.05, old_opacity },
  }
  c.opacity = 0.2
  local function run_step(i)
    if i > #steps then return end
    gears.timer.start_new(steps[i][1], function()
      if c.valid then c.opacity = steps[i][2] end
      run_step(i + 1)
      return false
    end)
  end
  run_step(1)
end

function sticky_toggle(c)
  if c.sticky then
    c.ontop = false
    c.sticky = false
  else
    c.ontop = true
    c.sticky = true
  end
  naughty.notification {
    text = "Sticky set to " .. tostring(c.sticky)
  }
end

function float_toggle(c)
  c.floating = not c.floating
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

-- Navigate wezterm panes via the wezterm CLI when there is no adjacent
-- awesome client to focus. Only acts on mainqterm windows.
-- dir must be capitalised: Up, Down, Left, Right.
function wezterm_navigate(c, dir)
  if not c or not c.valid or c.class ~= "mainqterm" then return end
  local sock = "WEZTERM_UNIX_SOCKET=" .. wezterm_sock .. " "
  awful.spawn.easy_async_with_shell(
    sock .. "wezterm cli list-clients --format json | jq -r 'first(.[]).focused_pane_id'",
    function(pane_id)
      pane_id = pane_id:gsub("%s+", "")
      if pane_id == "" or pane_id == "null" then return end
      awful.spawn.with_shell(sock .. "wezterm cli activate-pane-direction --pane-id " .. pane_id .. " " .. dir)
    end
  )
end

-- Single-screen directional focus with wezterm pane fallback (used for Up/Down).
function focus_bydirection_or_wezterm(c, dir)
  local prev_c = client.focus
  awful.client.focus.bydirection(dir)
  if client.focus == prev_c then
    wezterm_navigate(c, dir:sub(1,1):upper() .. dir:sub(2))
  end
end

function switch_focus_without_mouse(c, dir, printmore)
  local x, y, prev_scr = save_mouse_location(printmore)
  local prev_screen = c.screen

  -- Snapshot each other screen's currently focused client before global_bydirection mutates history
  local screen_focused = {}
  for _, s in ipairs(all_screens()) do
    if s ~= prev_screen then
      screen_focused[s] = awful.client.focus.history.get(s, 0)
    end
  end

  awful.client.focus.global_bydirection(dir, c, true)
  local new_c = client.focus

  -- Skip sticky windows on the same screen for left/right navigation;
  -- they are only reachable via up/down. Hop over them in the same direction.
  local visited = { [c] = true }
  while new_c and new_c ~= c and new_c.sticky and new_c.screen == prev_screen do
    if visited[new_c] then
      client.focus = c
      new_c = c
      break
    end
    visited[new_c] = true
    awful.client.focus.global_bydirection(dir, new_c, true)
    new_c = client.focus
  end

  -- Corrections when landing on a different screen:
  -- 1. In max layout, global_bydirection may focus a hidden client; use the
  --    client that was actually displayed on the target screen instead.
  -- 2. Prefer a non-sticky client unless sticky is the only option.
  if new_c and new_c.screen ~= prev_screen then
    local target_tag = new_c.screen.selected_tag
    if target_tag and target_tag.layout.name == "max" then
      local prev_focused = screen_focused[new_c.screen]
      if prev_focused and prev_focused ~= new_c then
        debug_print('switch_focus_without_mouse: max layout correction, focusing: ' .. prev_focused.name, printmore)
        client.focus = prev_focused
        new_c = client.focus
      end
    end
    -- After max-layout correction, if we still ended up on a sticky,
    -- walk the focus history of the target screen to find a non-sticky.
    if new_c.sticky then
      for i = 0, 100 do
        local candidate = awful.client.focus.history.get(new_c.screen, i)
        if not candidate then break end
        if not candidate.sticky then
          client.focus = candidate
          new_c = candidate
          break
        end
      end
    end
  end

  restore_mouse_location(x, y, prev_scr, printmore)
  local changed = client.focus ~= c
  if not changed then
    -- no adjacent client found; pass the direction to wezterm if applicable
    wezterm_navigate(c, dir:sub(1,1):upper() .. dir:sub(2))
  end
  return changed
end

function switch_to_tag(tag_name, printmore)
  debug_print('switch_to_tag: Switching to tag ' .. tag_name, printmore)
  local t = find_tag_by_first_word(tag_name, printmore)
  if not t then return end
  awful.tag.viewmore({t}, t.screen)
  awful.screen.focus(t.screen)
  -- Shoo any lingering Thunderbird tooltip windows (they bypass WM) buggy as fuck
  awful.spawn.easy_async('bash /home/gurkan/.path/hide-tb-tooltips', function() end)
end

-- Move a tag to a screen.
--
-- somewm implements `screen` as a native property of the tag class (see
-- luaA_tag_set_screen in objects/tag.c), so a plain `t.screen = s` only updates
-- the C side and never reaches awful.tag.object.set_screen. awful keeps its own
-- copy of a tag's screen in the tag's private properties and uses it for tag
-- indexes and client relocation, so the two views drift apart: awful.tag then
-- looks the tag up on its old screen, does not find it, and dies with
-- "attempt to compare number with nil" the next time a tag index is set.
-- Drive both sides here, and nowhere else.
function set_tag_screen(t, s)
  if awful.tag.getproperty(t, 'screen') ~= s then
    awful.tag.object.set_screen(t, s)
  end
  if t.screen ~= s then
    t.screen = s
  end
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
  for _, properties in ipairs(screens_table) do
    for _, t in ipairs(properties.tags) do
      if t == tag_obj then
        debug_print("find_screen_of_tag: Found " .. properties['name'] .. " for tag " .. tag_obj.name, printmore)
        return properties["object"]
      end
    end
  end
end

function move_focused_client_to_tag(tag_name)
  -- tag_obj = awful.tag.find_by_name(nil, tag_name)
  local tag_obj = find_tag_by_first_word(tag_name)
  if client.focus then
    local my_client_obj = client.focus
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
    naughty.notification {text = "Can't find a damn sticky window", timeout = 1}
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
        naughty.notification { text = "starting " .. program .. " once" }
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

-- Move the boundary between the two halves of a split screen.
-- Independent of which half is focused: growing always means growing the left
-- (fake) half, so the same key always has the same visible effect.
function resize_screen(s, screens_table, shrink)
  local entry = find_screen_entry(s, screens_table)
  if not entry then return end

  local fake, real
  if entry.is_fake then
    fake, real = entry, entry.parent
  else
    fake, real = split_child_of(entry, screens_table), entry
  end
  if not (fake and real) then
    -- not a split pair, nothing to move
    return
  end

  local diff = shrink and -dpi(50) or dpi(50)
  local fgeo, rgeo = fake.object.geometry, real.object.geometry
  -- the fake half sits left of the real one, so the boundary is fake.x + width
  fake.object:fake_resize(fgeo.x, fgeo.y, fgeo.width + diff, fgeo.height)
  real.object:fake_resize(rgeo.x + diff, rgeo.y, rgeo.width - diff, rgeo.height)
end

local lock_file = "/tmp/awesome_wallpaper.lock"

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
      for _, scr in ipairs(all_screens()) do
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
    for _, s in ipairs(all_screens()) do
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
  local focused_tag = get_tag_with_focused_window()

  -- Ensure that the folder exists
  createFolder(tagsave_folder)
  for _, feat in ipairs(screens_table) do
    local active_tags = {}
    local filename = tagsave_folder .. "/tagsave-" .. feat["name"]
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
  local focused_tag = nil
  for _, feat in ipairs(screens_table) do
    local filename = tagsave_folder .. "/tagsave-" .. feat["name"]
    local tag_list = my_utils.read_lines_from(filename)
    if next(tag_list) ~= nil then
      local previous_tags = {}
      for _, tag_name in pairs(tag_list) do
        if tag_name:sub(-1) == ":" then
          tag_name = tag_name:sub(1, -2)
          focused_tag = find_tag_by_first_word(tag_name, printmore)
        end
        local t = find_tag_by_first_word(tag_name, printmore)
        -- a saved tag can be missing (renamed tag, stale tagsave file)
        if t then table.insert(previous_tags, t) end
      end
      -- restore on the screen the tag actually lives on now, which is not
      -- necessarily the screen the tagsave file was written for
      local target = find_screen_of_tag(screens_table, previous_tags[1], printmore)
      if target then
        awful.tag.viewnone(target)
        awful.tag.viewmore(previous_tags, target)
      end
    end
  end
  if focused_tag then
    debug_print("load_last_active_tags: Last focused tag is " .. focused_tag.name .. " .. loading last", printmore)
    -- Switch to the screen of the focused tag by emptying its screen and toggling it
    local focused_screen = find_screen_of_tag(screens_table, focused_tag, printmore)
    if focused_screen then
      awful.tag.viewnone(focused_screen)
      awful.tag.viewtoggle(focused_tag)
    end
  end
end

-- Screenshot through somewm's own capture support (somewm-client screenshot).
-- mode is "interactive" (drag a region) or "save" (whole desktop).
function screenshot(mode)
  local dir = os.getenv("HOME") .. "/Pictures/screenshots"
  local path = dir .. "/" .. os.date("%Y%m%d-%H%M%S") .. ".png"
  awful.spawn.easy_async_with_shell(
    "mkdir -p " .. dir .. " && somewm-client screenshot " .. mode .. " " .. path,
    function(_, stderr, _, exit_code)
      if exit_code == 0 then
        naughty.notification { text = "Screenshot: " .. path }
      else
        naughty.notification { text = "Screenshot failed: " .. tostring(stderr), timeout = 5 }
      end
    end
  )
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


-- ============================================================================
-- Screen detection and wide-screen splitting
-- ============================================================================
-- somewm is a Wayland compositor, so the `screen` objects are the only source
-- of truth here (no xrandr to parse, and io.popen("xrandr") would just block).
--
-- A wide monitor is split into two logical screens so an ultrawide behaves like
-- two side-by-side monitors: the right half stays the monitor-backed screen
-- (shrunk with :fake_resize()), the left half is a screen.fake_add() one.
-- Splitting needs the fake-screen patches in /devel/somewm (screen/monitor
-- lookups by geometry); without them clients and wibars fall back to the
-- physical monitor's screen.
--
-- get_screens() returns screens_table: an array ordered left to right, where
-- every entry is
--   name    stable key, also the suffix of the tagsave file
--   object  the screen object
--   is_fake true for the fake_add() half of a split
--   parent  the entry of the real screen a fake half was carved out of
--   primary the entry that carries systray/clock/battery
--   width, height, tags
--
-- Recovery/debug switches, read from the environment so they can be set on the
-- somewm command line without editing the config:
--   AWESOME_NO_FAKE_SCREEN=1        -> never split, start with the plain outputs
--   AWESOME_FAKE_SCREEN_MIN_WIDTH=N -> pixel width that triggers a split
--                                      (default 3000; lower it to exercise the
--                                      split in a small nested compositor)
--   AWESOME_FAKE_SCREEN_OUTPUTS=pat -> Lua pattern the output name must match
--                                      (default "^DP", so the DP-* monitors get
--                                      split but the internal eDP-1 panel does not)
--   AWESOME_PRIMARY_OUTPUT=name     -> output that owns systray/clock/battery,
--                                      instead of whatever somewm calls primary

-- All screens, as a plain array.
--
-- Never use `for s in screen do` in this config. somewm's iterator is stateless
-- and computes the next screen as screen_refs[prev.index] (objects/screen.c,
-- luaA_screen_call). A hotplugged monitor gets its `index` from counting
-- monitors only (monitor.c:723), fake screens excluded, while it is appended to
-- the end of the refs array. Plug a monitor back in while a fake screen exists
-- and two screens end up with the same index, at which point the iterator keeps
-- returning the same screen and `for s in screen do` never terminates: the
-- compositor spins in Lua, input and the VT switch keys die with it, and the
-- only way out is a hard reboot.
--
-- Indexing by position cannot loop, so everything here goes through this.
function all_screens()
  local list = {}
  for i = 1, screen.count() do
    local s = screen[i]
    if s and s.valid then
      table.insert(list, s)
    end
  end
  return list
end

-- fake_add()/fake_resize() emit `list` and `request::desktop_decoration`
-- synchronously, and those handlers ask for another rebuild. The flag lets
-- rc.lua ignore the signals our own splitting causes.
local splitting_screens = false

function screen_split_in_progress()
  return splitting_screens
end

-- Output name of a screen, used to build the screens_table keys.
-- somewm answers `outputs` from C with a numerically indexed table
-- ({ [1] = { name = "DP-1", ... } }) instead of awful's name-keyed table, so
-- plain next(s.outputs) returns the index 1 and all screens end up with the
-- same key. Handle both shapes, fall back to the screen index to stay unique.
function get_output_name(s)
  for key, value in pairs(s.outputs or {}) do
    if type(value) == "table" and value.name then
      return value.name
    end
    if type(key) == "string" then
      return key
    end
  end
  if s.output and s.output.name then
    return s.output.name
  end
  return "screen" .. tostring(s.index)
end

-- Stable name of a real screen, cached on the screen object itself.
-- The name embeds the resolution and splitting shrinks the screen, so
-- recomputing it after a split would rename the screen (and with it its tagsave
-- file). Caching on the object is also the right lifetime: an output change
-- destroys the object, and the fresh one is measured at its full mode again.
local function real_screen_name(s)
  if not s.stable_name then
    local geo = s.geometry
    s.stable_name = get_output_name(s) .. "_" .. geo.width .. "x" .. geo.height
  end
  return s.stable_name
end

-- Name of a fake half: the parent's stable name plus its own size. The parent
-- name is remembered on the fake screen at creation time, because by the time
-- anything asks, the parent has already been shrunk to its own half.
local function fake_screen_name(s)
  local geo = s.geometry
  return (s.split_parent_name or s.split_parent_output) .. "_sub_" .. geo.width .. "x" .. geo.height
end

local function screen_name(s)
  if s.split_parent_output then
    return fake_screen_name(s)
  end
  return real_screen_name(s)
end

-- Live real screen serving an output name. Fake screens are excluded, and the
-- output name (not the object) is the identity that survives an output change:
-- unplugging a monitor destroys and recreates the screen objects of the outputs
-- that stay, which is what used to declare healthy split pairs orphaned.
local function screen_by_output(name)
  for _, s in ipairs(all_screens()) do
    if s.valid and not s.split_parent_output and get_output_name(s) == name then
      return s
    end
  end
end

-- The fake half carved out of a real screen, if there is one.
local function fake_child_of(s)
  local out = get_output_name(s)
  for _, other in ipairs(all_screens()) do
    if other.valid and other.split_parent_output == out then
      return other
    end
  end
end

-- A split pair is intact while the two halves are still adjacent and cover the
-- same vertical band. This replaces snapshotting the geometry the split
-- produced: a manual boundary move (win+F7/F8) keeps the pair adjacent and is
-- left alone, while a mode change or a monitor moved in the output layout
-- breaks adjacency and gets the pair rebuilt.
local function pair_is_intact(fake, real)
  local f, r = fake.geometry, real.geometry
  return f.y == r.y and f.height == r.height and f.x + f.width == r.x
end

-- Drop the fake half and, where it applies, hand its area back to the real
-- screen. This is only done while the two boxes still form one rectangle, i.e.
-- while the real screen is the shrunken half of a live pair: then fake_remove()
-- alone would leave it shrunk and leak half the monitor.
--
-- When they no longer line up, the real screen's geometry is authoritative and
-- must be left alone. somewm resets it from the monitor on a mode change
-- (objects/screen.c:721), and the fake half can then sit entirely outside it
-- (e.g. the left half stays at the old x while the monitor moves to 0 because
-- another output was unplugged). Merging the two boxes in that state produces a
-- screen wider than the monitor, which the next split then halves into two
-- oversized screens.
local function unsplit(fake, real)
  local f = fake.geometry
  if real and real.valid and pair_is_intact(fake, real) then
    local r = real.geometry
    local x1 = math.min(f.x, r.x)
    local y1 = math.min(f.y, r.y)
    local x2 = math.max(f.x + f.width, r.x + r.width)
    local y2 = math.max(f.y + f.height, r.y + r.height)
    real:fake_resize(x1, y1, x2 - x1, y2 - y1)
  end
  if fake.valid then
    -- awful's own screen-removal handler tries to relocate the tags of a
    -- disappearing screen and dies with "attempt to index local 'target_scr'"
    -- when it cannot pick a target, and that error aborts the whole rebuild.
    local fallback = real
    if not (fallback and fallback.valid) then
      for _, other in ipairs(all_screens()) do
        if other.valid and other ~= fake then
          fallback = other
          break
        end
      end
    end
    if fallback then
      for _, t in ipairs(fake.tags or {}) do
        set_tag_screen(t, fallback)
      end
    end
    fake:fake_remove()
  end
end

-- Width the left (fake) half gets.
local function split_width(geo)
  if (geo.width / geo.height) > 2 then
    -- ultrawide: halve it
    return math.ceil(geo.width / 2)
  end
  -- not that wide (e.g. 4K): give the left side (web/mail) a bit more
  return math.ceil(geo.width * 0.55)
end

-- Drop fake screens whose real screen is gone (monitor unplugged or switched
-- off, e.g. by the wlr-randr line in the startup script). They would otherwise
-- survive as ghost screens with a wibar and tags on an area nothing renders.
local function drop_orphan_fake_screens()
  local orphans = {}
  for _, s in ipairs(all_screens()) do
    if s.split_parent_output and not screen_by_output(s.split_parent_output) then
      table.insert(orphans, s)
    end
  end
  for _, s in ipairs(orphans) do
    debug_print('Dropping orphaned fake screen of ' .. tostring(s.split_parent_output), true)
    unsplit(s, nil)
  end
end

-- Split every eligible output into a real + fake screen pair, and repair pairs
-- whose geometry no longer lines up.
local function split_wide_screens()
  if os.getenv("AWESOME_NO_FAKE_SCREEN") == "1" then return end

  local min_width = tonumber(os.getenv("AWESOME_FAKE_SCREEN_MIN_WIDTH")) or 3000
  local output_pattern = os.getenv("AWESOME_FAKE_SCREEN_OUTPUTS") or "^DP"

  -- snapshot first: the loop adds and removes screens, and the native iterator
  -- walks the live list
  local reals = {}
  for _, s in ipairs(all_screens()) do
    if s.valid and not s.split_parent_output and get_output_name(s):match(output_pattern) then
      table.insert(reals, s)
    end
  end

  splitting_screens = true
  for _, s in ipairs(reals) do
    local child = fake_child_of(s)
    if child and not pair_is_intact(child, s) then
      debug_print('Re-splitting ' .. get_output_name(s) .. ', geometry changed under the fake screen', true)
      unsplit(child, s)
      child = nil
    end
    if not child and s.valid then
      local geo = s.geometry
      if (geo.width / geo.height) > 2 or geo.width > min_width then
        local fake_width = split_width(geo)
        s:fake_resize(geo.x + fake_width, geo.y, geo.width - fake_width, geo.height)
        local fake = screen.fake_add(geo.x, geo.y, fake_width, geo.height)
        fake.split_parent_output = get_output_name(s)
        fake.split_parent_name = real_screen_name(s)
        debug_print('Split ' .. fake.split_parent_output .. ' into ' ..
          fake_width .. ' + ' .. (geo.width - fake_width), true)
      end
    end
  end
  splitting_screens = false
end

-- Entry that owns the systray, clock, battery and PSI widgets.
local function elect_primary(entries)
  local wanted = os.getenv("AWESOME_PRIMARY_OUTPUT")
  if wanted then
    for _, e in ipairs(entries) do
      if not e.is_fake and get_output_name(e.object) == wanted then return e end
    end
  end

  -- The real half of a split monitor wins over everything else. Only two
  -- screens carry tags (see assign_roles), and if a third screen took one of
  -- those roles, one half of the split monitor would end up with no tags at
  -- all: exactly what happens with the laptop panel on next to the ultrawide,
  -- where screen.primary is the panel.
  for _, e in ipairs(entries) do
    if not e.is_fake and split_child_of(e, entries) then return e end
  end

  -- screen.primary is only a hint: when the primary output disappears somewm
  -- falls back to "the first screen in the list", which can be a fake half, and
  -- a fake half must never be the primary (no systray on half a monitor).
  local primary = screen.primary
  for _, e in ipairs(entries) do
    if e.object == primary then
      if e.is_fake then return e.parent end
      return e
    end
  end

  -- primary unknown or not in the table: widest real screen wins
  local best
  for _, e in ipairs(entries) do
    if not e.is_fake and (not best or e.width > best.width) then best = e end
  end
  return best or entries[1]
end

-- Give every entry a role:
--   primary   systray, clock, battery, PSI + the term/chat tags
--   secondary the web/mail tags
--   extra     a bare wibar, no taglist, no tags
-- Only two screens carry tags, as on X11. When a monitor is split, its two
-- halves take both roles, so an ultrawide never ends up half-tagged.
local function assign_roles(entries)
  local primary = elect_primary(entries)
  if not primary then return end
  primary.role = 'primary'
  primary.primary = true

  local secondary = split_sibling(primary, entries)
  if not secondary then
    for _, e in ipairs(entries) do
      if e ~= primary then
        secondary = e
        break
      end
    end
  end
  if secondary then secondary.role = 'secondary' end

  for _, e in ipairs(entries) do
    if not e.role then e.role = 'extra' end
  end
end

function get_screens()
  -- Measure the real screens before anything shrinks them: their stable name
  -- embeds the resolution and is the key of the tagsave files.
  for _, s in ipairs(all_screens()) do
    if s.valid and not s.split_parent_output then
      real_screen_name(s)
    end
  end

  drop_orphan_fake_screens()
  split_wide_screens()

  local entries = {}
  local by_object = {}
  for _, s in ipairs(all_screens()) do
    if s.valid then
      local geo = s.geometry
      local entry = {
        name    = screen_name(s),
        object  = s,
        is_fake = s.split_parent_output ~= nil,
        primary = false,
        parent  = nil,
        width   = geo.width,
        height  = geo.height,
        tags    = {},
      }
      table.insert(entries, entry)
      by_object[s] = entry
    end
  end

  -- left to right, so "the second screen" is the same screen on every rebuild
  table.sort(entries, function(a, b)
    local ga, gb = a.object.geometry, b.object.geometry
    if ga.x ~= gb.x then return ga.x < gb.x end
    return ga.y < gb.y
  end)

  -- link the fake halves to their parent entry now that all entries exist
  for _, e in ipairs(entries) do
    if e.is_fake then
      e.parent = by_object[screen_by_output(e.object.split_parent_output)]
      if not e.parent then
        -- parent alive but not in the table: treat it as a normal screen,
        -- everything downstream expects a fake screen to have a parent
        e.is_fake = false
      end
    end
  end

  assign_roles(entries)

  return entries
end

-- screens_table entry of a screen object.
function find_screen_entry(s, screens_table)
  for _, e in ipairs(screens_table or {}) do
    if e.object == s then return e end
  end
end

-- The fake half belonging to a real screen's entry.
function split_child_of(entry, screens_table)
  for _, e in ipairs(screens_table or {}) do
    if e.is_fake and e.parent == entry then return e end
  end
end

-- The other half of a split pair, whichever half is asked about.
function split_sibling(entry, screens_table)
  if entry.is_fake then return entry.parent end
  return split_child_of(entry, screens_table)
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
  local s = awful.screen.focused()
  -- a fake screen has no output of its own, so ask the monitor it lives on
  if s.split_parent_output then
    return s.split_parent_output ~= 'eDP-1'
  end
  return get_output_name(s) ~= 'eDP-1'
end

-- Number of logical screens, fake halves included.
function get_total_screen_count(screens_table)
  if screens_table then
    return #screens_table
  end
  return screen.count()
end
--  vim: set ts=2 sw=2 tw=0 et :
