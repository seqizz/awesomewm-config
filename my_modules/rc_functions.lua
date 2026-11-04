local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local beautiful = require("beautiful")
local naughty = require("naughty")
local my_utils = require('my_modules/my_utils')
local my_theme = require('my_modules/my_theme')
local geo_helpers = require('my_modules/geo_helpers')
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

-- Geometry of the whole physical panel `s` sits on: a fake screen only covers
-- half of a split ultrawide, so the union of the pair is taken. Screens that
-- are not part of a split answer with their own geometry.
function monitor_geometry(s)
  local left, right = get_fake_pair(s, screens_table)
  if not left then return s.geometry end

  local lg, rg = left.geometry, right.geometry

  local x1 = math.min(lg.x, rg.x)
  local y1 = math.min(lg.y, rg.y)
  local x2 = math.max(lg.x + lg.width, rg.x + rg.width)
  local y2 = math.max(lg.y + lg.height, rg.y + rg.height)

  return { x = x1, y = y1, width = x2 - x1, height = y2 - y1 }
end

-- Screen owning the right edge of the physical panel `s` sits on. For a split
-- ultrawide that is the real parent screen, since get_screens always resizes it
-- onto the right half; anything not part of a pair answers with itself.
--
-- Corner-anchored popups (the OSD, notifications) use this so they land on the
-- edge of the monitor instead of on the seam in the middle of it. screens_table
-- can lag a layout change (loose rebuilds it debounced) and hold a screen X has
-- already dropped, so a stale entry must not take the caller down with it.
function panel_right_screen(s)
  s = s or awful.screen.focused()

  if type(screens_table) ~= 'table' then return s end

  local ok, _, right = pcall(get_fake_pair, s, screens_table)
  if not ok or not right then return s end

  return right
end

-- Clients that are currently in alternative fullscreen, mapped to the state
-- needed to put them back. Weak keys so a closed client does not keep its entry
-- (and the client object) alive forever.
local real_fullscreen_state = setmetatable({}, { __mode = 'k' })

-- Guards the re-assert handlers below against reacting to their own geometry
-- change, which would recurse forever.
local real_fullscreen_applying = false

-- Push a client back onto its target geometry. Games are the reason this is
-- needed: toolkits like SDL/Wine re-assert their own size (and often ask for
-- EWMH fullscreen, which awesome would clamp back to a single screen) a moment
-- after the window is mapped or after an in-game resolution change.
local function enforce_real_fullscreen(c)
  if real_fullscreen_applying then return end

  local st = real_fullscreen_state[c]
  if not st or not c.valid then return end

  real_fullscreen_applying = true

  c.fullscreen = false
  c.maximized = false
  c.maximized_horizontal = false
  c.maximized_vertical = false

  local g, t = c:geometry(), st.target
  if g.x ~= t.x or g.y ~= t.y or g.width ~= t.width or g.height ~= t.height then
    c:geometry(t)
  end

  real_fullscreen_applying = false
end

-- One set of handlers for all clients; the state table decides whether a given
-- client is currently being held in place.
client.connect_signal('property::geometry',  enforce_real_fullscreen)
client.connect_signal('property::fullscreen', enforce_real_fullscreen)
client.connect_signal('property::maximized',  enforce_real_fullscreen)
client.connect_signal('request::geometry', function(c) enforce_real_fullscreen(c) end)

-- Alternative fullscreen: cover the entire physical monitor instead of the
-- screen object the client happens to live on. Needed because native fullscreen
-- is clamped to that screen, which on a split ultrawide is only half the panel.
function real_fullscreen_toggle(c)
  if not c or not c.valid then return end

  local old = real_fullscreen_state[c]
  if old then
    real_fullscreen_state[c] = nil

    c.fullscreen = old.fullscreen
    c.floating = old.floating
    c.ontop = old.ontop
    c.above = old.above
    c.border_width = old.border_width
    c.size_hints_honor = old.size_hints_honor
    -- Fall back to the default chamfer: a client that never had an explicit
    -- shape would otherwise come back square.
    c.shape = old.shape or geo_helpers.chamfer(dpi(12))

    -- Spanning past the screen boundary makes awesome re-home the client (and
    -- with it, re-tag it) by the top-left corner, so both have to be put back
    -- explicitly before the geometry lands.
    local tags = {}
    for _, t in ipairs(old.tags) do
      if t.activated then table.insert(tags, t) end
    end
    if #tags > 0 then c:tags(tags) end

    c:geometry(old.geometry)
    return
  end

  real_fullscreen_state[c] = {
    geometry = c:geometry(),
    fullscreen = c.fullscreen,
    floating = c.floating,
    ontop = c.ontop,
    above = c.above,
    border_width = c.border_width,
    size_hints_honor = c.size_hints_honor,
    shape = c.shape,
    tags = c:tags(),
    target = monitor_geometry(c.screen),
  }

  -- Must stay false: a fullscreen client gets re-clamped to its own screen on
  -- every geometry request, which would undo the span immediately.
  c.fullscreen = false
  c.floating = true
  c.ontop = true
  c.above = true
  c.border_width = 0
  -- Games and other clients with aspect/resize-increment hints would otherwise
  -- be snapped to a smaller size than the panel.
  c.size_hints_honor = false
  -- The default rule chamfers the top-left corner; nothing should be cut out of
  -- a window that is meant to cover the whole panel.
  c.shape = gears.shape.rectangle

  enforce_real_fullscreen(c)

  -- Clients that switch video mode settle late and with several resizes in a
  -- row; the signal handlers catch most of it, this covers whatever lands
  -- while awesome is not looking.
  local ticks = 0
  gears.timer.start_new(0.5, function()
    ticks = ticks + 1
    if not real_fullscreen_state[c] or not c.valid then return false end
    enforce_real_fullscreen(c)
    return ticks < 8
  end)
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
  for s in screen do
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
-- Resolve the fake screen pair that `s` belongs to.
-- Returns left, right (left is always the fake screen, right always the real
-- parent, matching how get_screens builds them), or nil when `s` is not part of
-- a split. Shared by the F7/F8 nudge, the Win+Alt-right-drag boundary handle
-- and the split presets, which all used to re-derive this independently.
function get_fake_pair(s, screens_table)
  for _, properties in pairs(screens_table) do
    if properties["object"] == s then
      if properties["is_fake"] then
        return s, properties["parent"]["object"]
      end
      local child = get_child_of(s, screens_table)
      if child == nil then return nil end
      return child, s
    end
  end
  return nil
end

-- Never let either half shrink past this: below it the wibar stops being
-- usable and the tags on that screen become effectively unreachable.
MIN_SPLIT_WIDTH = 300

-- Move the boundary of a fake screen pair by a fixed step.
-- The step always applies to the left (fake) screen regardless of which half is
-- focused, so the same key grows the same side no matter where you are. The old
-- implementation achieved that by flipping the sign per branch; expressed
-- directly here, with the original key directions preserved:
-- F7 (shrink=false) narrows the left screen, F8 (shrink=true) widens it.
function resize_screen(s, screens_table, shrink)
  local left, right = get_fake_pair(s, screens_table)
  if not left then return end

  local diff = shrink and dpi(50) or -dpi(50)
  set_split_boundary(left, right, left.geometry.width + diff)
end

-- Tiled clients reflow by themselves on a screen geometry change, floating ones
-- do not: they keep their absolute coords and end up straddling the seam or
-- outside their screen entirely. Barely visible with the 50px nudge, very
-- visible after a preset jump moves the boundary by a thousand pixels.
function reflow_floating_clients(left, right)
  for _, scr in ipairs({ left, right }) do
    for _, c in ipairs(scr.clients) do
      if c.floating and not c.fullscreen then
        awful.placement.no_offscreen(c, { honor_workarea = true, screen = scr })
      end
    end
  end
end

-- Apply an absolute boundary: give the left screen `left_width` px and hand the
-- rest of the pair's combined width to the right screen. Widths come from live
-- geometry, so this composes with whatever the nudge keys already did.
--
-- Callers driving a continuous drag pass defer_reflow=true and call
-- reflow_floating_clients() once on release; reflowing on every mousegrabber
-- tick makes floating windows jitter under the cursor.
function set_split_boundary(left, right, left_width, defer_reflow)
  local left_geo = left.geometry
  local right_geo = right.geometry
  local total = left_geo.width + right_geo.width

  local min = dpi(MIN_SPLIT_WIDTH)
  left_width = math.floor(math.max(min, math.min(total - min, left_width)))
  local right_width = total - left_width

  left:fake_resize(left_geo.x, left_geo.y, left_width, left_geo.height)
  right:fake_resize(left_geo.x + left_width, right_geo.y, right_width, right_geo.height)

  if not defer_reflow then
    reflow_floating_clients(left, right)
  end

  return left_width, right_width
end

-- Share of the pair width given to the left screen, in ascending order.
-- 0.55 is the get_screens default for a non-ultrawide 4K output.
SPLIT_PRESETS = { 0.34, 0.5, 0.55, 0.66 }

-- Step to the next preset wider than the current left share, wrapping around.
-- Picking "next larger" instead of an index means a boundary left in some
-- arbitrary spot by F7/F8 or the mouse drag still lands on a sane preset.
function cycle_screen_split(s, screens_table)
  local left, right = get_fake_pair(s, screens_table)
  if not left then
    -- No fake screen here: get_screens only splits outputs wider than 3000px or
    -- with an aspect ratio above 2, so on a laptop panel there is no boundary to
    -- move. Say so, otherwise the key looks broken.
    naughty.notification {
      app_name = 'screen_split',
      text = 'No fake screen split on this output',
      timeout = 2,
    }
    return
  end

  local total = left.geometry.width + right.geometry.width
  local current = left.geometry.width / total

  local target = SPLIT_PRESETS[1]
  for _, ratio in ipairs(SPLIT_PRESETS) do
    -- Tolerance: fake_resize works in whole pixels, so a ratio never round-trips
    -- exactly and an equality test would stick on the current preset.
    if ratio > current + 0.01 then
      target = ratio
      break
    end
  end

  local left_width, right_width = set_split_boundary(left, right, total * target)
  naughty.notification {
    app_name = 'screen_split',
    text = string.format('split %d/%d  (%dpx / %dpx)',
                         math.floor(left_width / total * 100 + 0.5),
                         math.floor(right_width / total * 100 + 0.5),
                         left_width, right_width),
    timeout = 2,
  }
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

-- The focus marker in the tagsave files only answers "which tag", so a selected
-- but empty tag is still a valid answer. get_tag_with_focused_window() can only
-- see tags that hold the focused client, hence the fall back to whatever tag the
-- focused screen is showing.
local function get_focused_tag()
  local t = get_tag_with_focused_window()
  if t then return t end

  local s = awful.screen.focused()
  return s and s.selected_tag or nil
end

-- One `key=value` line per entry. Used for the auxiliary state files
-- (layouts/splits/clients) whose keys are tag or screen names, unlike the
-- per-screen tag files which are a plain ordered list.
local function read_kv_file(filename)
  local entries = {}
  for _, line in ipairs(my_utils.read_lines_from(filename)) do
    local key, value = line:match("^([^=]+)=(.*)$")
    if key then entries[key] = value end
  end
  return entries
end

-- Merge into what is already on disk rather than replacing it. These files are
-- written by whichever screen layout happens to be active, and a layout only
-- knows about its own screens: saving from the laptop panel alone would drop the
-- wide monitor's split ratio, so switching back would come up at the default.
local function update_kv_file(filename, entries)
  local merged = read_kv_file(filename)
  for key, value in pairs(entries) do
    merged[key] = tostring(value)
  end

  local f = io.open(filename, "w")
  if not f then
    debug_print("update_kv_file: could not open " .. filename)
    return
  end
  for key, value in pairs(merged) do
    f:write(key, "=", value, "\n")
  end
  f:close()
end

-- Layouts belong to the four global tags, not to a screen, so they live in a
-- single file instead of being duplicated into every per-screen tagsave.
local function save_tag_layouts()
  local layouts = {}
  for _, t in ipairs(root.tags()) do
    if t.layout and t.layout.name then
      layouts[my_utils.get_first_word(t.name)] = t.layout.name
    end
  end
  update_kv_file(tagsave_folder .. "/tagsave-layouts", layouts)
end

local function load_tag_layouts(printmore)
  local layouts = read_kv_file(tagsave_folder .. "/tagsave-layouts")
  for _, t in ipairs(root.tags()) do
    local wanted = layouts[my_utils.get_first_word(t.name)]
    if wanted then
      -- Only accept a layout the tag actually offers; rc_tags.lua restricts each
      -- tag to max/tile and a stale file must not smuggle in a third one.
      for _, candidate in ipairs(t.layouts or {}) do
        if candidate.name == wanted then
          t.layout = candidate
          debug_print("load_tag_layouts: " .. t.name .. " -> " .. wanted, printmore)
          break
        end
      end
    end
  end
end

-- Store the share of the pair width held by the left (fake) half, keyed by the
-- parent screen. A ratio rather than a pixel width so it still means the same
-- thing if the output comes back at a different mode.
local function save_screen_splits(screens_table)
  local splits = {}
  for name, feat in pairs(screens_table) do
    if feat["is_fake"] and feat["parent"] then
      local left = feat["object"].geometry
      local right = feat["parent"]["object"].geometry
      local total = left.width + right.width
      if total > 0 then
        splits[feat["parent"]["name"]] = string.format("%.4f", left.width / total)
      end
    end
  end
  update_kv_file(tagsave_folder .. "/tagsave-splits", splits)
end

function load_screen_splits(screens_table, printmore)
  local splits = read_kv_file(tagsave_folder .. "/tagsave-splits")
  for name, feat in pairs(screens_table) do
    if feat["is_fake"] and feat["parent"] then
      local ratio = tonumber(splits[feat["parent"]["name"]])
      if ratio and ratio > 0 and ratio < 1 then
        local left = feat["object"]
        local right = feat["parent"]["object"]
        local total = left.geometry.width + right.geometry.width
        debug_print("load_screen_splits: " .. name .. " -> " .. ratio, printmore)
        set_split_boundary(left, right, total * ratio)
      end
    end
  end
end

-- Remember which window had the focus on each tag by X window id. The id stays
-- valid across an awesome restart because the X server keeps running; after a
-- full X restart nothing matches and the entry is simply ignored.
local function save_focused_clients()
  local clients = {}
  for _, t in ipairs(root.tags()) do
    -- Walk the global focus history and take the most recent client that is on
    -- this tag. Same depth as focus_previous_client() uses.
    for idx = 0, 9 do
      local c = awful.client.focus.history.get(nil, idx)
      if not c then break end
      if c.window and my_utils.table_contains(c:tags(), t) then
        clients[my_utils.get_first_word(t.name)] = c.window
        break
      end
    end
  end
  update_kv_file(tagsave_folder .. "/tagsave-clients", clients)
end

local function restore_focused_client(t, printmore)
  local clients = read_kv_file(tagsave_folder .. "/tagsave-clients")
  local wanted = tonumber(clients[my_utils.get_first_word(t.name)])
  if not wanted then return false end

  for _, c in ipairs(t:clients()) do
    if c.window == wanted then
      debug_print("restore_focused_client: " .. t.name .. " -> " .. tostring(c.name), printmore)
      client.focus = c
      c:raise()
      return true
    end
  end
  return false
end

function save_current_tags(screens_table)
  local focused_tag = get_focused_tag()

  gears.filesystem.make_directories(tagsave_folder)
  for name, feat in pairs(screens_table) do
    local active_tags = {}
    local filename = tagsave_folder .. "/tagsave-" .. name
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
    -- io.open can fail on a full or read-only cache dir; an error thrown here
    -- would abort the caller before it gets to restart awesome.
    local f = io.open(filename, "w")
    if f then
      for _, tagname in pairs(active_tags) do
          f:write(tagname, "\n")
      end
      f:close()
    else
      debug_print("save_current_tags: could not write " .. filename)
    end
  end

  -- screens_table can hold a screen object that X has already taken away (loose
  -- changes the layout between the save-tags hook and the debounced rebuild), and
  -- reading geometry off an invalid screen raises. This runs on the exit path, so
  -- an error here would stop awesome from restarting at all.
  for _, save in ipairs({ save_tag_layouts, save_screen_splits, save_focused_clients }) do
    local ok, err = pcall(save, screens_table)
    if not ok then
      debug_print("save_current_tags: auxiliary save failed: " .. tostring(err))
    end
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
  load_tag_layouts(printmore)

  local focused_tag = nil
  for name, feat in pairs(screens_table) do
    local filename = tagsave_folder .. "/tagsave-" .. name
    local tag_list = my_utils.read_lines_from(filename)
    if next(tag_list) ~= nil then
      local previous_tags = {}
      for _, tag_name in pairs(tag_list) do
        local is_focused = tag_name:sub(-1) == ":"
        if is_focused then
          tag_name = tag_name:sub(1, -2)
        end
        local t = find_tag_by_first_word(tag_name, printmore)
        -- A saved name can point at a tag that place_tags() has since handed to
        -- a different screen (undocked session restored while docked). Driving
        -- the view from a foreign screen's file scrambles both screens, and the
        -- loop order is undefined, so it scrambles them differently every boot.
        if t and my_utils.table_contains(feat["tags"], t) then
          table.insert(previous_tags, t)
          if is_focused then
            focused_tag = t
          end
        else
          debug_print("load_last_active_tags: skipping " .. tag_name .. ", not on " .. name, printmore)
        end
      end
      if next(previous_tags) ~= nil then
        awful.tag.viewnone(feat["object"])
        awful.tag.viewmore(previous_tags, feat["object"])
      end
    end
  end

  -- A screen showing no tag at all is a dead end: no clients, and the only way
  -- out is the taglist or a tag keybinding. It happens whenever nothing above
  -- selected anything for that screen, either because there is no save file for
  -- this screen layout yet or because the file only lists tags that place_tags()
  -- has since handed to another screen. rc_tags.lua marks only 'web' selected,
  -- so the screen holding term/chat is the usual victim.
  for name, feat in pairs(screens_table) do
    if next(feat["tags"]) ~= nil and not feat["object"].selected_tag then
      debug_print("load_last_active_tags: " .. name .. " has no tag selected, falling back to "
                  .. feat["tags"][1].name, printmore)
      feat["tags"][1]:view_only()
    end
  end

  if focused_tag then
    debug_print("load_last_active_tags: Last focused tag is " .. focused_tag.name .. " .. loading last", printmore)
    -- The tag is already selected by the viewmore above; all that is left is to
    -- put the input focus on its screen. Re-selecting it here would drop any
    -- other tag selected on the same screen.
    awful.screen.focus(focused_tag.screen)
    if not restore_focused_client(focused_tag, printmore) then
      focus_previous_client(focused_tag.name, printmore)
    end
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
  if awesome.release == "somewm" then
    local output_tbl = {}
    for s in screen do
      local name = s.outputs and next(s.outputs) or "screen"
      local geo = s.geometry
      local key = name .. "_" .. geo.width .. "x" .. geo.height
      output_tbl[key] = {
        name    = key,
        primary = (s == screen.primary),
        width   = geo.width,
        height  = geo.height,
        object  = s,
        parent  = nil,
        tags    = {},
      }
    end
    return output_tbl
  end

  local output_tbl = {}
  local xrandr = io.popen("xrandr -q --current | grep -E ' connected (primary )?[0-9]'")

  if xrandr then
    for line in xrandr:lines() do
      -- if no physical screen is found, skip this line
      local screen_obj = my_utils.find_screen_by_name(line:firstword())
      if screen_obj == nil then
          goto skipanother
      end
      local width, height = line:resolutions()
      local name = line:firstword() .. "_" .. width .. "x" .. height
      output_tbl[name] = {}
      local primary = false
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
            local fake_width = math.ceil(geo.width/2)
            local new_width = math.ceil(geo.width/2)
            local new_width2 = geo.width - new_width
            if not (( geo.width / geo.height) > 2) then
                -- this is not a wide screen, let's give more to the left side a bit more (web/mail)
                fake_width = math.ceil(geo.width*0.55)
            end
            properties["object"]:fake_resize(geo.x + fake_width, geo.y, (geo.width - fake_width), geo.height)
            local fake_obj = screen.fake_add(geo.x, geo.y, fake_width, geo.height)
            local fake_screen_name = name .. "_sub_" .. tostring(fake_width) .. "x" .. tostring(geo.height)
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
