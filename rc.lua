pcall(require, "luarocks.loader")

local gears = require("gears")
local awful = require("awful")
require("my_modules/compositor")
require("awful.autofocus")
local wibox = require("wibox")
local menubar = require("menubar")
local beautiful = require("beautiful")
local my_theme = require('my_modules/my_theme')
local naughty = require("naughty")
local my_utils = require('my_modules/my_utils')
local lain = require("lain")
local capslock = require("my_modules/capslock")
local mpris = require("my_modules/mpris")
local mpris_lyrics = require("my_modules/mpris_lyrics")
local nextthing = require("my_modules/nextthing")
local psi_widget = require("my_modules/psi")
local rotate_widget = require("my_modules/rotatescreen")
local touch_widget = require("my_modules/touchscreen")
local autolock_widget = require("my_modules/autolock")
local dynamic_separator = require("my_modules/dynamic_separator")
-- local keyboard_widget = require("my_modules/keyboard")
local helpers = require("my_modules/geo_helpers")
local edid = require('my_modules/edid')
local dpi = require('beautiful').xresources.apply_dpi
hostname = io.popen("uname -n"):read()
-- wezterm mux socket path; needed when spawning wezterm CLI from outside a wezterm pane
wezterm_sock = os.getenv("WEZTERM_UNIX_SOCKET") or (os.getenv("HOME") .. "/.wezterm.sock")

-- Get config and cache paths dynamically
local config_path = gears.filesystem.get_configuration_dir()
local cache_path = gears.filesystem.get_cache_dir()

-- debug stuff if needed
-- global (not local) so required modules can honor it as a master debug switch
printmore = true

-- my theme
beautiful.init(config_path .. "my_modules/my_theme.lua")

-- WezTerm emits its toasts (e.g. the snippet-capture feedback) at critical
-- urgency, which naughty renders with its bright-red critical preset. Recolor
-- just wezterm's notifications to a calm gold-on-dark style with a real
-- timeout. Appended after naughty's default rules so it wins for these.
local ruled = require('ruled')
ruled.notification.connect_signal('request::rules', function()
  ruled.notification.append_rule {
    rule       = { app_name = 'wezterm' },
    properties = {
      bg      = '#282828',
      fg      = '#d79921',
      timeout = 4,
      urgency = 'normal',
    },
  }
end)

awful.input.rules = {
    {
        rule = { type = "touchpad" },
        properties = {
            natural_scrolling = 1,
        },
    },
    {
        rule = { type = "pointer" },
        properties = {
            natural_scrolling = 0,
        },
    },
}

-- print errors as naughty notifications
dofile(config_path .. "my_modules/rc_errorhandling.lua")

-- some fancy functions I'm using
dofile(config_path .. "my_modules/rc_functions.lua")

-- define tags at the beginning
dofile(config_path .. "my_modules/rc_tags.lua")

-- stuff related to volume/brightness OSD notifications
dofile(config_path .. "my_modules/rc_fn_actions.lua")

-- stuff including usernames etc
dofile(config_path .. "my_modules/rc_secret.lua")

-- @Reference: disable notification system
-- package.loaded["naughty.dbus"] = {}

clientkeys = gears.table.join(
-- Increase/decrease windows sizes on tiled layout: Win + asdf
awful.key({ win                }, "d",      function ()  awful.tag.incmwfact( 0.01)  end),
awful.key({ win                }, "a",      function ()  awful.tag.incmwfact(-0.01)  end),
awful.key({ win                }, "s",      function ()  awful.client.incwfact( 0.01)  end),
awful.key({ win                }, "w",      function ()  awful.client.incwfact(-0.01)  end),
-- Quit window: Win + q
awful.key({ win                }, "q",      function (c) c:kill() end),
-- Swap master windows: Win + enter
awful.key({ win                }, "Return", function (c) c:swap(awful.client.getmaster()) end),
-- Movement and focus:
-- Win                + Arrows -> Swap focus between windows
-- Win        + Shift + WASD   -> Move windows to that direction
-- Win + Ctrl         + Arrows -> Expand windows to that direction
-- Win + Ctrl + Shift + Arrows -> Shrink windows from that direction
awful.key({ ctrl, win          }, "Right",  function (c) move_or_expand(c, "expand", "right") end),
awful.key({ win,  "Shift"      }, "a",      function (c) move_or_expand(c, "move", "left") end),
awful.key({ ctrl, win, "Shift" }, "Left",   function (c) move_or_expand(c, "shrink", "left") end),
awful.key({ ctrl, win          }, "Left",   function (c) move_or_expand(c, "expand", "left") end),
awful.key({ ctrl, win, "Shift" }, "Right",  function (c) move_or_expand(c, "shrink", "right") end),
awful.key({ win, "Shift"       }, "d",      function (c) move_or_expand(c, "move", "right") end),
awful.key({ ctrl, win          }, "Down",   function (c) move_or_expand(c, "expand", "down") end),
awful.key({ ctrl, win, "Shift" }, "Up",     function (c) move_or_expand(c, "shrink", "up") end),
awful.key({ ctrl, win          }, "Up",     function (c) move_or_expand(c, "expand", "up") end),
awful.key({ win, "Shift"       }, "s",      function (c) move_or_expand(c, "move", "down") end),
awful.key({ win, "Shift"       }, "w",      function (c) move_or_expand(c, "move", "up") end),
awful.key({ ctrl, win, "Shift" }, "Down",   function (c) move_or_expand(c, "shrink", "down") end),
awful.key({ win                }, "Right",  function (c) switch_focus_without_mouse(c, "right", printmore) end),
awful.key({ win                }, "Left",   function (c) switch_focus_without_mouse(c, "left",  printmore) end),
awful.key({ win                }, "Down",   function (c)
  if c.sticky then
    -- sticky is on top; go back to previous client on the same screen
    local prev = awful.client.focus.history.get(c.screen, 1)
    if prev then client.focus = prev; prev:raise() end
  else
    focus_bydirection_or_wezterm(c, "down")
  end
end),
awful.key({ win                }, "Up",     function (c)
  -- only consider stickies on the same screen
  local has_screen_sticky = false
  for _, sc in ipairs(client.get()) do
    if sc.sticky and sc.screen == c.screen then
      has_screen_sticky = true; break
    end
  end
  if has_screen_sticky then
    awful.client.focus.history.previous()
  else
    focus_bydirection_or_wezterm(c, "up")
  end
end),
-- Minimize window: Win + z
awful.key({ win                }, "z",      function (c) c.minimized = true end),
-- Suspend the window's app with SIGSTOP: Ctrl + Alt + s
awful.key({ ctrl, alt          }, "s",      function (c) suspend_toggle(c) end),
-- Shrink window and make it sticky & on top (e.g. conference call): Ctrl + Alt + w
awful.key({ ctrl, alt          }, "w",      function (c) float_toggle(c) end),
awful.key({ ctrl, alt          }, "f",      function (c) c.fullscreen = not c.fullscreen end),
-- Sticky toggle for window: Ctrl + Alt + Shift + s
awful.key({ ctrl, alt, "Shift" }, "s",      function (c) sticky_toggle(c) end),
-- Hide stickies to the bottom-right corner (toggle) : Win + Esc
awful.key({ win                }, "Escape", function (c) hide_stickies() end),
awful.key({ win                }, "F7",     nil, function (c) resize_screen(c.screen, screens_table, false); update_dynamic_widgets() end),
awful.key({ win                }, "F8",     nil, function (c) resize_screen(c.screen, screens_table, true); update_dynamic_widgets() end)
)

function set_keys_after_screen_new(clientkeys, globalkeys, screens_table, printmore)
  if get_total_screen_count(screens_table) > 1 then
    -- Shortcut for moving window between screens
    clientkeys = gears.table.join(clientkeys,
    awful.key({ win, "Shift" }, "Left",   function (c) c:move_to_screen(c.screen.index-1) end),
    awful.key({ win, "Shift" }, "Right",  function (c) c:move_to_screen(c.screen.index+1) end)
    )
  end

  -- not sure why we're doing 10+ here 🤷
  globalkeys = gears.table.join(
  globalkeys,
  awful.key({win}, "#10", function() switch_to_tag("web", printmore) end),
  awful.key({win}, "#11", function() switch_to_tag("mail", printmore) end),
  awful.key({win}, "#12", function() switch_to_tag("term", printmore) end),
  awful.key({win}, "#13", function() switch_to_tag("chat", printmore) end),
  awful.key({win, "Shift"}, "#10", function() move_focused_client_to_tag("web") end),
  awful.key({win, "Shift"}, "#11", function() move_focused_client_to_tag("mail") end),
  awful.key({win, "Shift"}, "#12", function() move_focused_client_to_tag("term") end),
  awful.key({win, "Shift"}, "#13", function() move_focused_client_to_tag("chat") end)
  )

  return clientkeys, globalkeys

end

-- some aliases
terminal = 'wezterm start'
browser = 'firefox'
editor = os.getenv('EDITOR') or 'nvim'
editor_cmd = terminal .. ' -e ' .. editor
greenclip_cmd = 'rofi -dpi '
  .. dpi(80)
  .. ' -modi \'clipboard:greenclip print\' -show clipboard -run-command \'{cmd}\' '
rofi_cmd = 'rofi -dpi ' .. dpi(80) .. ' -show run'
rofi_emoji_cmd = 'rofi -dpi ' .. dpi(80) .. ' -show emoji -modi emoji'
rofi_calc_cmd = 'rofi -dpi ' .. dpi(80) .. ' -show calc -modi calc'
rofi_subsuper = 'rofi -dpi ' .. dpi(80) .. ' -show fb -modes \'fb:rofi-subsuper\''
proxified_chromium_cmd =
  'chromium-browser --password-store=basic --incognito --proxy-server="socks://127.0.0.1:8080" --host-resolver-rules="MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"'

win = 'Mod4'
alt = 'Mod1'
ctrl = 'Control'

-- dropdown terminal from lain
my_dropdown = lain.util.quake({
  app = terminal,
  argname = '--class %s',
  name = 'myshittydropdown',
  height = 0.5,
  followtag = true,
  visible = false,
})

-- Create a wibox for each screen and add it
local taglist_buttons = gears.table.join(
awful.button({ }, 1, function(t) t:view_only() end),
awful.button({ win }, 1, function(t)
  if client.focus then
    client.focus:move_to_tag(t)
  end
end),
awful.button({ }, 3, awful.tag.viewtoggle),
awful.button({ win }, 3, function(t)
  if client.focus then
    client.focus:toggle_tag(t)
  end
end),
awful.button({ }, 4, function(t) awful.tag.viewprev(t.screen) end),
awful.button({ }, 5, function(t) awful.tag.viewnext(t.screen) end)
)

local tasklist_buttons = gears.table.join(
awful.button({ }, 1, function (c)
  if c == client.focus then
    c.minimized = true
  else
    c:emit_signal(
    "request::activate",
    "tasklist",
    {raise = true}
    )
  end
end),
awful.button({ }, 2, function (c)
  c:kill()
end),
awful.button({ }, 4, function ()
  awful.client.focus.byidx(1)
end),
awful.button({ }, 5, function ()
  awful.client.focus.byidx(-1)
end)
)

separator = my_utils.create_separator()

separator_empty = my_utils.create_separator({
  width = 10,
  color = beautiful.bg_normal,
  shape = nil  -- no shape for empty separator
})

separator_reverse = my_utils.create_separator({
  span_ratio = 0.7,
  set_shape = function(cr, width, height)
    gears.shape.parallelogram(cr, width, height)
    -- gears.shape.powerline(cr, width, height, (height / 2) * (-1))
  end
})

separator_faint = my_utils.create_separator({
  color = beautiful.bg_focus .. "70"
})

mpris_separator = dynamic_separator.create({
  signal = "widget::mpris::visible",
  initial_visible = false
})

-- Dynamic widget placement for fake screens
-- Containers that can hold dynamic widgets, keyed by screen object
dynamic_widget_containers = {}

-- Build the dynamic widgets layout (touch, rotate, autolock, mpris)
function build_dynamic_widgets_layout()
  local layout = wibox.layout.fixed.horizontal()
  local sc = screens_table and get_total_screen_count(screens_table) or 1
  -- Guard every add: the X11-only widgets return `false` on somewm, and adding
  -- a non-widget raises "Type should be table, but is nil" deep inside wibox,
  -- which takes the whole config down (somewm then has no config at all).
  local function add(widget)
    if type(widget) == 'table' and widget.is_widget then
      layout:add(widget)
    end
  end
  add(separator_reverse)
  if sc == 1 and (hostname == 'bebop' or hostname == 'splinter') then
    add(touch_widget)
    if hostname == 'bebop' then
      add(rotate_widget)
    end
  end
  add(autolock_widget)
  add(mpris_separator)
  add(mpris)
  return layout
end

-- The dynamic widgets (touch, rotate, autolock, mpris) live on the roomiest
-- screen: the wider half of a split pair, the non-primary screen on a
-- multi-monitor setup, the only screen when there is just one.
local function hosts_dynamic_widgets(entry, screens_table)
  local sibling = split_sibling(entry, screens_table)
  if sibling then
    -- a tie goes to the fake (left) half, so the widgets do not jump around
    -- while the boundary is moved with win+F7/F8
    return entry.width > sibling.width
      or (entry.width == sibling.width and entry.is_fake)
  end
  if #screens_table == 1 then
    return entry.primary
  end
  return not entry.primary
end

function update_dynamic_widgets()
  if not screens_table then return end

  local target_screen = nil
  local largest_width = 0

  for _, props in ipairs(screens_table) do
    -- the screen can be gone already when an output change races the rebuild;
    -- reading geometry off an invalid screen raises an error
    if props['object'].valid
      and hosts_dynamic_widgets(props, screens_table)
      and props['width'] > largest_width then
      largest_width = props['width']
      target_screen = props['object']
    end
  end

  -- Move dynamic widgets to the target screen's container
  local dynamic_layout = build_dynamic_widgets_layout()
  for scr, container in pairs(dynamic_widget_containers) do
    if scr == target_screen then
      container.widget = dynamic_layout
      container.visible = true
    else
      container.widget = nil
      container.visible = false
    end
  end
end

-- battery widget: required here (not with the top requires) because it reads
-- beautiful.* at load time, which is only populated after beautiful.init() above
local battery_widget = require("my_modules/battery")

-- @Reference
-- When a new sound device is added/removed,
-- create a temporary popup to change default output device
-- function sound_device_change(signal)
  -- refresh_sound_popup()
  -- temp_sound_popup = sound_popup
  -- primary_screen = awful.screen.focused()
  -- if docked then
    -- -- Use secondary screen, on the right side
    -- for s in screen do
        -- if not my_utils.is_screen_primary(s) then
            -- primary_screen = s
        -- end
    -- end
  -- end
  -- temp_sound_popup.screen = primary_screen
  -- awful.placement.top_right(temp_sound_popup, {honor_workarea=true})
  -- temp_sound_popup.visible = true
  -- hide_popup = gears.timer {
    -- timeout   = 10,
    -- single_shot = true,
    -- callback  = function()
      -- temp_sound_popup.visible = false
      -- temp_sound_popup = nil
    -- end
  -- }
  -- hide_popup:start()
-- end
-- dbus.add_match("system","type='signal',interface='org.custom.gurkan'")
-- dbus.connect_signal("org.custom.gurkan", sound_device_change)

-- Create a textclock widget and attach the calendar
mytextclock = wibox.widget{
   widget = wibox.widget.textclock,
   format = " %d %b %H:%M (%a) ",
   refresh = 30
}
-- calendarwidget = lain.widget.cal({
--   followtag = true,
--   week_number = "left",
--   attach_to = { mytextclock },
--   notification_preset = {
--     font = beautiful.font_big,
--     fg = beautiful.fg_normal,
--     bg = beautiful.bg_focus
--   }
-- })

-- change tag names dynamically
refresh_tag_name = function()
  for s = 1, screen.count() do
    -- get a list of all tags
    local atags = screen[s].tags
    for i, t in ipairs(atags) do
      local clients_on_this_tag = 0
      for i, c in ipairs(t:clients()) do
        if not c.skip_taskbar then
          clients_on_this_tag = clients_on_this_tag + 1
        end
      end
      local original_name = my_utils.get_first_word(t.name)
      t.name = original_name .. ' ' .. string.rep('ॱ', clients_on_this_tag)
    end
  end
end

-- signal function to execute when a client disappears
client.connect_signal('unmanage', function(c, startup)
  -- dropdown killed: restore pre-dropdown focus instead of picking randomly
  if c.instance == my_dropdown.name then
    if my_dropdown.pre_focus and my_dropdown.pre_focus.valid then
      client.focus = my_dropdown.pre_focus
      my_dropdown.pre_focus:raise()
    end
    my_dropdown.pre_focus = nil
    refresh_tag_name()
    return
  end
  if c.type == 'normal' then
    focus_previous_client(c.screen.selected_tag.name, printmore)
  end
  refresh_tag_name()
end)

psi_timer = gears.timer({
  timeout = 15,
  autostart = true,
  callback = function() psi_widget:check() end,
})

-- spotify is now event-driven via `playerctl --follow` inside my_modules/spotify.lua;
-- no polling timer needed.

nextthing_timer = gears.timer({
  timeout = 30,
  autostart = true,
  call_now = true,
  callback = function() nextthing:check() end,
})

local function screen_organizer(s, screen_count, primary, is_extra)

  debug_print('Now organizing screen: ' .. s['name'], printmore)

  -- This can run several times for the same screen (screen list changes, fake
  -- screen creation, decoration requests), so drop the previous wibar first.
  -- Without this every run stacks another wibar on top of the screen.
  if s['object'].mywibox then
    s['object'].mywibox:remove()
    s['object'].mywibox = nil
  end
  dynamic_widget_containers[s['object']] = nil

  -- Create an imagebox widget which will contain an icon indicating which layout we're using.
  -- We need one layoutbox per screen.
  s['object'].mylayoutbox = awful.widget.layoutbox(s['object'])
  s['object'].mylayoutbox:buttons(
    gears.table.join(
      awful.button({}, 1, function() awful.layout.inc(1) end),
      awful.button({}, 3, function() awful.layout.inc(-1) end),
      awful.button({}, 4, function() awful.layout.inc(1) end),
      awful.button({}, 5, function() awful.layout.inc(-1) end)
    )
  )

  -- some convenience stuff
  if screen_count > 1 then
    taglist_width = dpi(250)
    wibar_height = dpi(25)
  else
    taglist_width = dpi(350)
    wibar_height = dpi(23)
  end
  if not wibar_height or wibar_height == 0 then wibar_height = 24 end

  if not is_extra then
    -- Create a taglist widget
    s['object'].mytaglist = awful.widget.taglist({
      screen = s['object'],
      filter = awful.widget.taglist.filter.all,
      style = {
        shape = gears.shape.powerline,
      },
      layout = {
        spacing = -15,
        spacing_widget = {
          color = beautiful.bg_normal,
          shape = gears.shape.powerline,
          widget = wibox.widget.separator,
        },
        layout = wibox.layout.flex.horizontal,
        forced_width = taglist_width,
        -- max_widget_width = taglist_width /50
      },
      widget_template = {
        {
          {
            {
              id = 'text_role',
              widget = wibox.widget.textbox,
            },
            layout = wibox.layout.flex.horizontal,
          },
          left = 24,
          right = 12,
          widget = wibox.container.margin,
        },
        id = 'background_role',
        widget = wibox.container.background,
      },
      buttons = taglist_buttons,
    })

    -- Create a tasklist widget
    s['object'].mytasklist = awful.widget.tasklist({
      screen = s['object'],
      filter = awful.widget.tasklist.filter.currenttags,
      style = {
        shape = gears.shape.powerline,
      },
      layout = {
        spacing = -15,
        spacing_widget = {
          color = beautiful.bg_normal,
          shape = gears.shape.powerline,
          widget = wibox.widget.separator,
        },
        layout = wibox.layout.flex.horizontal,
      },
      widget_template = {
        {
          {
            {
              id = 'text_role',
              widget = wibox.widget.textbox,
            },
            layout = wibox.layout.flex.horizontal,
          },
          left = 18,
          right = 18,
          widget = wibox.container.margin,
        },
        id = 'background_role',
        widget = wibox.container.background,
      },
      buttons = tasklist_buttons,
    })
  end

  -- Create the wibox
  s['object'].mywibox = awful.wibar({
    position = 'top',
    screen = s['object'],
    height = wibar_height,
  })

  systray_right_widgets = {
    layout = wibox.layout.fixed.horizontal,
  }

  table.insert(systray_right_widgets, separator_empty)
  table.insert(systray_right_widgets, capslock)

  -- On single screen, place dynamic widgets early (before battery/psi/systray)
  if not is_extra and screen_count == 1 then
    local dynamic_container = wibox.container.background()
    dynamic_widget_containers[s['object']] = dynamic_container
    table.insert(systray_right_widgets, dynamic_container)
  end

  if primary then
    -- table.insert(systray_right_widgets, keyboard_widget)
    table.insert(systray_right_widgets, separator_reverse)
    table.insert(systray_right_widgets, battery_widget)
    table.insert(systray_right_widgets, separator_reverse)
    table.insert(systray_right_widgets, psi_widget)
    table.insert(systray_right_widgets, separator_reverse)
    table.insert(systray_right_widgets, my_systray)
  end

  -- Create container for dynamic widgets (touch, rotate, autolock, spotify)
  -- These move to the larger screen when fake screens are present
  if primary then
    table.insert(systray_right_widgets, separator_reverse)
    table.insert(systray_right_widgets, mytextclock)
  else
    -- Not visible on single screen, by choice
    table.insert(systray_right_widgets, nextthing)
    table.insert(systray_right_widgets, mpris_lyrics)
    table.insert(systray_right_widgets, separator_empty)
  end
  -- Multi-screen: dynamic container goes after other widgets (as before)
  if not is_extra and screen_count > 1 then
    local dynamic_container = wibox.container.background()
    dynamic_widget_containers[s['object']] = dynamic_container
    table.insert(systray_right_widgets, dynamic_container)
  end
  table.insert(systray_right_widgets, s['object'].mylayoutbox)

  -- Add widgets to the wibox
  if is_extra then
    -- Doesn't get much stuff on this screen by default
    -- Only if we move some shit to it
    s['object'].mywibox:setup({
      layout = wibox.layout.align.horizontal,
      { -- Left widgets
        layout = wibox.layout.align.horizontal,
        separator,
      },
      systray_right_widgets,
    })
  else
    -- Normal setup, tag and taskslists
    s['object'].mywibox:setup({
      layout = wibox.layout.align.horizontal,
      { -- Left widgets
        layout = wibox.layout.align.horizontal,
        s['object'].mytaglist,
        separator,
      },
      { -- Middle widget
        layout = wibox.layout.fixed.horizontal,
        s['object'].mytasklist,
        separator_faint,
      },
      systray_right_widgets,
    })
  end
end

-- Order the 4 permanent tags get in a taglist, left to right.
local TAG_ORDER = { web = 1, mail = 2, term = 3, chat = 4 }

-- Tags of the primary screen when there is more than one screen. The others
-- (web, mail) go to the secondary screen, which on a split ultrawide is the
-- fake left half.
local PRIMARY_TAGS = { term = true, chat = true }

-- awful.tag's index is per screen, so the global 1..4 order cannot be assigned
-- directly: on a two-tag screen index 3 is out of range and silently ignored,
-- and setting the index of a tag that does not live on the screen awful thinks
-- it lives on raises "attempt to compare number with nil" inside awful.tag.
-- So order each screen's own tags by the global preference instead.
local function order_tags_of(s)
  local own = {}
  for _, t in ipairs(s.tags) do
    table.insert(own, t)
  end
  table.sort(own, function(a, b)
    return (TAG_ORDER[my_utils.get_first_word(a.name)] or 99)
         < (TAG_ORDER[my_utils.get_first_word(b.name)] or 99)
  end)
  for i, t in ipairs(own) do
    t.index = i
  end
end

function place_tags(properties, primary, screens_table)
  local single_screen = #screens_table == 1
  for _, tag in ipairs(root.tags()) do
    local first_word = my_utils.get_first_word(tag.name)
    -- with one screen everything lands there, otherwise term/chat go to the
    -- primary screen and web/mail to the secondary one
    if single_screen or (PRIMARY_TAGS[first_word] or false) == primary then
      table.insert(properties['tags'], tag)
      if tag.screen ~= properties['object'] then
        debug_print('Re-assigning ' .. first_word .. ' to ' .. properties['name'], printmore)
      end
      set_tag_screen(tag, properties['object'])
    end
  end

  order_tags_of(properties['object'])
end

-- Filled by the first screen rebuild, see schedule_screen_rebuild() below.
screens_table = {}

my_systray = wibox.container.margin(wibox.widget.systray(), 0, 0, 0, 0)

function process_screens(systray, screens_table, printmore)

  debug_print('Processing screens result: ' .. my_utils.dump(screens_table), printmore)

  -- forget containers of screens that no longer exist (removed monitor, fake_remove)
  for scr, _ in pairs(dynamic_widget_containers) do
    if not scr.valid then
      dynamic_widget_containers[scr] = nil
    end
  end

  local screen_count = #screens_table
  -- systray icons have to shrink on the smaller wibar of a multi-screen setup
  systray.top = screen_count > 1 and dpi(3) or 0
  my_systray.widget:set_base_size(screen_count > 1 and dpi(20) or dpi(24))

  -- Roles come from get_screens(); see assign_roles() there.
  for _, properties in ipairs(screens_table) do
    -- skip screens that died between building the table and now
    if properties['object'].valid then
      local role = properties['role']

      debug_print('Screen ' .. properties['name'] .. ' is ' .. tostring(role), printmore)
      if role == 'primary' then
        -- the primary screen carries the systray
        systray.widget:set_screen(properties['object'])
      end
      screen_organizer(properties, screen_count, role == 'primary', role == 'extra')
      if role ~= 'extra' then
        place_tags(properties, role == 'primary', screens_table)
      end
    else
      debug_print('Skipping gone screen: ' .. properties['name'], printmore)
    end
  end
  -- define rules since we have filled the screen table
  dofile(config_path .. "my_modules/rc_rules.lua")

  clientkeys, globalkeys = set_keys_after_screen_new(clientkeys, globalkeys, screens_table, printmore)
  dofile(config_path .. "my_modules/rc_clientbuttons.lua")
  root.keys = globalkeys
  set_rules(clientkeys)

  -- Set initial spotify placement based on screen sizes
  update_dynamic_widgets()
end

-- {{{ Mouse bindings
root.buttons(gears.table.join(
  awful.button({ }, 4, awful.tag.viewprev),
  awful.button({ }, 5, awful.tag.viewnext)
))
-- }}}

-- {{{ Key bindings
globalkeys = gears.table.join(
  -- Standard X11 keys, comes from Fn keys etc.
  awful.key({              }, "XF86MonBrightnessUp",   nil, function() fn_process_action('brightness', 'up') end),
  awful.key({              }, "XF86MonBrightnessDown", nil, function() fn_process_action('brightness', 'down') end),
  awful.key({              }, "XF86AudioRaiseVolume",  nil, function() fn_process_action('sink', 'up') end),
  awful.key({              }, "XF86AudioLowerVolume",  nil, function() fn_process_action('sink', 'down') end),
  awful.key({              }, "XF86AudioMute",         nil, function() fn_process_action('sink', 'toggle') end),
  awful.key({              }, "XF86AudioMicMute" ,     nil, function() fn_process_action('source', 'toggle') end),
  awful.key({              }, "XF86AudioPlay",         nil, function() fn_process_action('media', 'pausetoggle') end),
  awful.key({              }, "XF86AudioStop",         nil, function() fn_process_action('media', 'stop') end),
  awful.key({              }, "XF86AudioPrev",         nil, function()
                                                              fn_process_action('media', 'previous')
                                                              mpris:check()
                                                            end),
  awful.key({              }, "XF86AudioNext",         nil, function()
                                                              fn_process_action('media', 'next')
                                                              mpris:check()
                                                            end),
  -- Ctrl + sound knob switches between tmux panes and firefox tabs 🤯
  -- awful.key({ ctrl         }, "XF86AudioRaiseVolume",  nil, function()
  --                                                             root.fake_input('key_press', 'Ctrl_L')
  --                                                             root.fake_input('key_press', 'Tab')
  --                                                             root.fake_input('key_release', 'Tab')
  --                                                             root.fake_input('key_release', 'Ctrl_L')
  --                                                           end),
  -- awful.key({ ctrl         }, "XF86AudioLowerVolume",  nil, function()
  --                                                             root.fake_input('key_press', 'Shift_L')
  --                                                             root.fake_input('key_press', 'Ctrl_L')
  --                                                             root.fake_input('key_press', 'Tab')
  --                                                             root.fake_input('key_release', 'Tab')
  --                                                             root.fake_input('key_release', 'Ctrl_L')
  --                                                             root.fake_input('key_release', 'Shift_L')
  --                                                           end),
  -- Win + sound knob switches between all windows 🤯
  awful.key({ win          }, "XF86AudioRaiseVolume",  nil, function()
                                                              root.fake_input('key_press', 196)
                                                              root.fake_input('key_release', 196)
                                                            end),
  awful.key({ win          }, "XF86AudioLowerVolume",  nil, function()
                                                              root.fake_input('key_press', 'Shift_L')
                                                              root.fake_input('key_press', 196)
                                                              root.fake_input('key_release', 196)
                                                              root.fake_input('key_release', 'Shift_L')
                                                            end),
  -- Smart plug toggle
  -- awful.key({              }, "XF86HomePage",          nil, function() awful.spawn(bulb_toggle) end),
  -- For laptop, which doesn't have next/prev buttons
  awful.key({ ctrl         }, "XF86AudioRaiseVolume",  nil, function()
                                                              fn_process_action('media', 'next')
                                                              mpris:check()
                                                            end),
  awful.key({ ctrl         }, "XF86AudioLowerVolume",  nil, function()
                                                              fn_process_action('media', 'previous')
                                                              mpris:check()
                                                            end),
  awful.key({ win          }, "F9",                    nil, function() awful.spawn("rofi-pulse-select sink") end),
  -- Dropdown terminal: F12
  awful.key({              }, "F12",                   nil, function()
    -- record focused client before showing, so we can restore on unmanage
    if not my_dropdown.visible then
      my_dropdown.pre_focus = client.focus
    end
    my_dropdown:toggle()
  end),
  -- flameshot has no working Wayland capture path, but somewm can take the
  -- screenshot itself. No clipboard copy here: that would need wl-clipboard.
  awful.key({              }, "Print",                 nil, function() screenshot('interactive') end),
  awful.key({ "Shift"      }, "Print",                      function() screenshot('save') end),
  awful.key({ ctrl         }, "space",                      function() awful.spawn(rofi_cmd) end),
  awful.key({              }, "F9",                    nil, function() awful.spawn(rofi_emoji_cmd) end),
  awful.key({ ctrl         }, "F9",                    nil, function() awful.spawn(rofi_calc_cmd) end),
  awful.key({ "Shift"      }, "F9",                    nil, function() awful.spawn(rofi_subsuper) end),
  awful.key({ ctrl, alt    }, "c",                          function() awful.spawn(greenclip_cmd) end),
  awful.key({ win          }, "p",                          function() awful.spawn("rofi-rbw") end),
  awful.key({ ctrl, alt    }, "t",                          function() awful.spawn(terminal) end),
  awful.key({ win          }, "XF86WakeUp",            nil, function() awful.spawn("sudo systemctl suspend") end),
  awful.key({ alt, "Shift" }, "t",                          function() awful.spawn("wezterm --config-file /home/gurkan/.config/wezterm/old-nomux.lua start") end),
  awful.key({ win          }, "c",                          function() awful.spawn("chromium-browser --password-store=basic") end),
  awful.key({ ctrl, alt    }, "p",                          function() notifytest() end),
  awful.key({ win          }, "f",                          function() awful.spawn(browser) end),
  awful.key({ win          }, "l",                          function() awful.spawn("sudo slock") end),
  -- awful.key({ win, "Shift" }, "l",                          function() awful.spawn("xdotool search --name \" Slack\" windowactivate &&  sleep 1 && xdotool key ctrl+k && sleep 0.8 && xdotool key g u r k a n Return && sleep 0.8 && xdotool key slash a w a y Return && sleep 0.8 && xdotool key slash s t a t u s space semicolon a y o o semicolon space l u n c h Return") end),
  -- If something goes wrong with loose setup
  awful.key({ win          }, "r",                          function() awful.spawn("loose rotate --interactive") end),
  -- Cycle between available layouts
  awful.key({ win          }, "space",                      function() awful.layout.inc(1) end),
  awful.key({ win          }, "x",                          function() awful.spawn("pcmanfm-qt") end),
  awful.key({ win,         }, "Tab",                        function() awful.tag.viewnext(get_screen_of_focused()) end),
  -- There is no "win-capslock", we meant win-tab probably
  awful.key({ win,         }, "Caps_Lock",                  function() awful.tag.viewnext(get_screen_of_focused()) end),
  awful.key({ win, "Shift" }, "Tab",                        function() awful.tag.viewprev(get_screen_of_focused()) end),
  awful.key({ win, "Shift" }, "c",                          function() awful.spawn(proxified_chromium_cmd) end),
  -- awful.key({ win, ctrl    }, "q",                          awesome.quit),
  awful.key({ win, ctrl    }, "r",                          function()
                                                                save_current_tags(screens_table)
                                                                awesome.restart()
                                                            end),
  awful.key({ win, "Shift" }, "z",                          unminimize_client)
)
if ( hostname == "splinter" ) then
  gears.table.merge(globalkeys, gears.table.join(
    awful.key({ win          }, "v",                          function() awful.spawn("vpn-toggle 'Innogames Wireguard (Primary)'") end),
    awful.key({ win, "Shift" }, "v",                          function() awful.spawn("vpn-toggle 'Innogames Wireguard (Secondary)'") end)
  ))
  -- Shortcut cemetery
  -- awful.key({ win          }, "u",                          function() awful.spawn("/home/gurkan/clicky") end),
  -- awful.key({ ctrl, alt    }, "p",                          function() reset_pulse() end),
  -- awful.key({ win          }, "k",                          function() keyboard_widget:toggle() end),
  -- awful.key({ win          }, "e",                          function() keyboard_widget:toggle() end),
elseif ( hostname == "bebop" ) then
  gears.table.merge(globalkeys, gears.table.join(
    awful.key({ win          }, "v",                          function() awful.spawn("vpn-toggle 'Truenas connection for bebop'") end)
  ))
end

-- needed for capslock helper
gears.table.merge(globalkeys, capslock.possible_combinations)

-- Put a new client at the end of the tiling order instead of making it the
-- master. somewm has no awful.client.setslave, so swap it past every other
-- tiled client on its tag, which ends up in the same place.
local function set_slave(c)
  for _, other in ipairs(awful.client.tiled(c.screen)) do
    if other ~= c then
      c:swap(other)
    end
  end
end

-- Signal function to execute when a new client appears.
client.connect_signal("request::manage", function (c)
  refresh_tag_name()
  if not awesome.startup and not c.floating then
    set_slave(c)
  end

  if awesome.startup
    and not c.size_hints.user_position
    and not c.size_hints.program_position then
    -- Prevent clients from being unreachable after screen count changes.
    awful.placement.no_offscreen(c)
  end
end)

-- Telegram Media viewer keeps requesting fullscreen — block it
client.connect_signal("property::fullscreen", function(c)
  if c.class == "TelegramDesktop" and c.name == "Media viewer" and c.fullscreen then
    c.fullscreen = false
    return
  end
  -- Remove cut corners in fullscreen, restore when leaving
  if c.fullscreen then
    c.shape = gears.shape.rectangle
  else
    local s = dpi(12)
    c.shape = function(cr, w, h)
      cr:move_to(s, 0)
      cr:line_to(w - s, 0)
      cr:line_to(w, s)
      cr:line_to(w, h)
      cr:line_to(0, h)
      cr:line_to(0, s)
      cr:close_path()
    end
  end
end)

client.connect_signal('property::minimized', function(c)
  -- If a sticky window is minimized, ensure it's visible on taskbar
  if c.sticky then
    c.skip_taskbar = false
  end
  if c.type == 'normal' then
    focus_previous_client(c.screen.selected_tag.name, printmore)
  end
end)

client.connect_signal('focus', function(c)
  -- If a sticky window is unminimized, remove from taskbar
  if c.sticky and not c.minimized then
    c.skip_taskbar = true
  end
  -- border setup
  c.border_color = beautiful.border_focus
  -- transparency
  -- if c.opacity == 0.95 then
    -- c.opacity = 1
  -- end
end)

-- Screen handling
--
-- Every output change produces a burst of signals: `list`, one
-- `request::desktop_decoration` per screen (including the ones the split
-- creates), plus the somewm-specific `output` class signals. They all funnel
-- into a single debounced rebuild; running one rebuild per signal stacks
-- duplicate wibars and re-shuffles the tags several times per change.
local REBUILD_DELAY = 0.5

screen_rebuild_timer = nil  -- global: a local upvalue timer can be collected
local screen_rebuild_running = false
local initial_tags_loaded = false

-- Geometry of all screens as of the last completed rebuild, so a rebuild that
-- would change nothing can be skipped.
local last_rebuilt_signature = nil

function screen_signature()
  local parts = {}
  for _, s in ipairs(all_screens()) do
    local geo = s.geometry
    -- A fake half has no output of its own, and get_output_name() would fall
    -- back to its index, which shifts around when screens are added or removed.
    -- Identify it by the output it was split off instead, so the signature also
    -- changes when a fake screen is orphaned.
    local id = s.split_parent_output and ('fake@' .. s.split_parent_output)
               or get_output_name(s)
    table.insert(parts, string.format('%s:%dx%d+%d+%d',
      id, geo.width, geo.height, geo.x, geo.y))
  end
  table.sort(parts)
  return table.concat(parts, ' ')
end

function schedule_screen_rebuild(reason)
  debug_print('Screen rebuild requested (' .. tostring(reason) .. ')', printmore)

  -- fake_add()/fake_resize() emit screen signals synchronously from inside the
  -- rebuild, ignore those instead of recursing
  if screen_rebuild_running or screen_split_in_progress() then
    debug_print('Screen rebuild already running, ignoring', printmore)
    return
  end

  if not screen_rebuild_timer then
    screen_rebuild_timer = gears.timer({
      timeout     = REBUILD_DELAY,
      single_shot = true,
      callback    = do_screen_rebuild,
    })
  end
  -- restart on every request, so a burst collapses into one run
  screen_rebuild_timer:again()
end

function do_screen_rebuild()
  if screen_rebuild_running then
    debug_print('Screen rebuild re-entered, ignoring', printmore)
    return
  end

  local signature = screen_signature()
  if signature == last_rebuilt_signature then
    debug_print('Screen rebuild skipped, outputs unchanged: ' .. signature, printmore)
    return
  end
  debug_print('Screen rebuild starting', printmore)

  screen_rebuild_running = true
  -- Everything in here runs under pcall: get_screens() adds and removes fake
  -- screens and awful's handlers for that can throw (e.g. awful.tag's
  -- relocation when a screen disappears). An error escaping here used to leave
  -- screen_rebuild_running set, and every later rebuild request was then
  -- silently dropped for the rest of the session: no wibars, no tags, stale
  -- layout, and tags left pointing at destroyed screens.
  local ok, err = pcall(function()
    local screens = get_screens()
    if screens then screens_table = screens end

    process_screens(my_systray, screens_table, printmore)

    -- Tag restore needs the tags already placed on their screens, so it runs
    -- after the first rebuild, not at the end of rc.lua. Only once: later
    -- rebuilds would throw away whatever tags are currently in view.
    if not initial_tags_loaded and #screens_table > 0 then
      initial_tags_loaded = true
      load_last_active_tags(screens_table, printmore)
    end
  end)
  screen_rebuild_running = false

  if not ok then
    debug_print('Screen rebuild FAILED: ' .. tostring(err), true)
    -- do not record the signature, so the next request retries instead of
    -- deciding there is nothing to do
    return
  end

  -- signature of what we actually ended up with (the split changed it)
  last_rebuilt_signature = screen_signature()
  debug_print('Screen rebuild done, outputs: ' .. last_rebuilt_signature, printmore)
end

screen.connect_signal('list', function()
  schedule_screen_rebuild('list signal')
end)

screen.connect_signal('request::desktop_decoration', function(s)
  schedule_screen_rebuild('desktop decoration for ' .. tostring(s))
end)

-- Output changes are also announced on the output class, which is somewm
-- specific. Cheap to listen to and independent of the screen class signals.
if output and output.connect_signal then
  for _, signal_name in ipairs({ 'added', 'removed' }) do
    output.connect_signal(signal_name, function(o)
      schedule_screen_rebuild('output ' .. signal_name .. ' ' .. tostring(o))
    end)
  end
end

-- Safety net for output changes that produce no signal we listen to (mode
-- changes, DPMS wake). Cheap: it only compares geometry strings.
screen_watch_timer = gears.timer({
  timeout = 5,
  autostart = true,
  callback = function()
    if screen_rebuild_running or screen_split_in_progress() then return end
    if screen_signature() == last_rebuilt_signature then return end
    schedule_screen_rebuild('screen watcher')
  end,
})

-- First rebuild. Synchronous, so the session has wibars and tags before the
-- startup applications show up.
-- screen.count(), not #screen: somewm's screen module has no __len metamethod,
-- so the length operator always reports 0 and this would never run.
if screen.count() > 0 then
  debug_print('Initial screen setup for ' .. screen.count() .. ' screens', printmore)
  do_screen_rebuild()
end

-- Recover a tag whose screen is being removed.
--
-- This has to succeed no matter what: a tag left on a destroyed screen makes
-- every later client rule fail with "invalid object" (ruled.client assigns
-- c.screen = tag.screen), and the tag is unreachable until the next restart.
-- So it is deliberately dumb, guarded, and does not depend on anything else in
-- the config being in a sane state at that moment.
tag.connect_signal('request::screen', function(t)
  local target = nil
  for _, s in ipairs(all_screens()) do
    -- not the screen going away, and not a fake half of it either
    if s.valid and s ~= t.screen then
      target = s
      break
    end
  end
  if not target then
    debug_print('request::screen: no screen left to recover ' .. tostring(t.name), true)
    return
  end

  debug_print('request::screen: recovering ' .. tostring(t.name) .. ' onto ' ..
    get_output_name(target), true)
  set_tag_screen(t, target)

  -- the dropdown terminal follows, it is bound to a screen too
  if my_dropdown then
    my_dropdown.screen = target
    my_dropdown.visible = false
  end
end)

-- A removed screen also invalidates the wibar and the widget container we keep
-- per screen, and it needs a rebuild to reassign roles and tags. The `list`
-- signal covers the rebuild, this only drops the stale references early so
-- nothing reads them in between.
screen.connect_signal('removed', function(s)
  dynamic_widget_containers[s] = nil
  schedule_screen_rebuild('screen removed')
end)

-- A mode change (loose/wlr-randr) does not add or remove a screen, so `list`
-- never fires, but it does invalidate a split: somewm drops the fake_resize
-- override and gives the real screen its full geometry back, leaving the fake
-- half overlapping it (objects/screen.c:721). Rebuild so the pair is repaired.
screen.connect_signal('property::geometry', function(s)
  if screen_split_in_progress() then return end
  schedule_screen_rebuild('geometry change on ' .. tostring(get_output_name(s)))
end)

-- I only need 2 of these though 😬 max, tile or bust.
tag.connect_signal('request::default_layouts', function()
  -- awful.layout.append_default_layouts({
  --   awful.layout.suit.tile,
  --   awful.layout.suit.max,
  -- }) # Changed on awesome-git
  awful.layout.layouts = {
    awful.layout.suit.tile,
    awful.layout.suit.max,
  }
end)

client.connect_signal('mouse::enter', function(c)
  if c.ontop and c.sticky and c.skip_taskbar and c.marked then
    c.opacity = 0.9
    -- Run away from mouse, to the other side of the screen
    if c.x > (c.screen.geometry.x + c.screen.geometry.width - 600) then
      c:relative_move(-(c.screen.geometry.width - c.width), 0, 0, 0)
    else
      c:relative_move((c.screen.geometry.width - c.width), 0, 0, 0)
    end
  end
end)

-- @Reference: Reflect click to the client below
-- Still can't "undo" click on the original client, but fun to play
-- client.connect_signal("button::press", function (c)
-- if c.ontop and c.sticky and c.skip_taskbar and c.marked then
-- next_client = awful.client.next (1, c, true)
-- helpers.async("xdotool click --window " .. next_client.window .. " 1", function(out)
-- end)
-- end
-- end)

-- Add a titlebar if titlebars_enabled is set to true in the rules.
client.connect_signal('request::titlebars', function(c)
  -- buttons for the titlebar
  local buttons = gears.table.join(
    awful.button({}, 1, function()
      c:emit_signal('request::activate', 'titlebar', { raise = true })
      awful.mouse.client.move(c)
    end),
    awful.button({}, 3, function()
      c:emit_signal('request::activate', 'titlebar', { raise = true })
      awful.mouse.client.resize(c)
    end)
  )

  awful.titlebar(c):setup({
    { -- Left
      awful.titlebar.widget.iconwidget(c),
      buttons = buttons,
      layout = wibox.layout.fixed.horizontal,
    },
    { -- Middle
      { -- Title
        align = 'center',
        widget = awful.titlebar.widget.titlewidget(c),
      },
      buttons = buttons,
      layout = wibox.layout.flex.horizontal,
    },
    { -- Right
      awful.titlebar.widget.floatingbutton(c),
      awful.titlebar.widget.maximizedbutton(c),
      awful.titlebar.widget.stickybutton(c),
      awful.titlebar.widget.ontopbutton(c),
      awful.titlebar.widget.closebutton(c),
      layout = wibox.layout.fixed.horizontal(),
    },
    layout = wibox.layout.align.horizontal,
  })
end)

awesome.connect_signal('save-tags', function()
  -- We are about to exit / restart awesome, save our last used tag
  save_current_tags(screens_table)
end)

tag.connect_signal('property::layout', function(t)
  -- make the focused window master on layout change
  local c = client.focus
  if c and awful.layout.get(t.screen).name == 'max' then
    awful.client.setmaster(c)
    c:raise()
  end
end)

client.connect_signal('property::size', function(c)
  -- workaround for exiting fullscreen on floating windows
  -- some params do not stay as they should, so we enforce them
  if c.floating and c.skip_taskbar and not c.fullscreen then
    c.sticky = true
    c.ontop = true
  end
end)

client.connect_signal('unfocus', function(c)
  -- border setup
  c.border_color = beautiful.border_normal

  -- transparency
  -- if c.opacity == 1 and not c.fullscreen then
    -- c.opacity = 0.95
  -- end

  -- auto-hide dropdown
  if c.instance == my_dropdown.name then
    my_dropdown.visible = false
    my_dropdown:display()
  end
end)

-- HACK START --
-- Git version workaround, shit is not complete (e.g. slack does not switch to)
-- alerting chat etc. but at least hovers the app itself
-- https://github.com/awesomeWM/awesome/issues/3182 waiting for proper fix
-- naughty.connect_signal('destroyed', function(n, reason)
--   local client_to_jump = nil
--   if reason == require('naughty.constants').notification_closed_reason.dismissed_by_user then
--     if n.clients then
--       -- notification thingy (maybe) gave us some client names, use them
--       for _, notification_client in ipairs(n.clients) do
--         if not notification_client then
--           -- Means this is nothingburger
--           goto noclient
--         end
--         client_to_jump = notification_client
--         debug_print('Jumping to notification-client: ' .. client_to_jump.name, printmore)
--         break
--         ::noclient::
--       end
--     else
--       -- no notification client is here
--       -- we will just assume when we clicked the pop-up, we have created
--       -- an urgent client. So we will be optimistic, will just jump to it
--       client_to_jump = get_latest_urgent_client()
--       debug_print('Jumping to latest urgent one: ' .. client_to_jump.name, printmore)
--     end
--   end
--   if client_to_jump then
--     local x, y, prev_scr = save_mouse_location()
--     client_to_jump:jump_to()
--     restore_mouse_location(x, y, prev_scr, printmore, true)
--   end
-- end)

client.connect_signal('property::urgent', function(c)
    if c.urgent then
        c.urgent_since = os.time()
    end
end)
-- HACK END --

-- Show OSD notification of current status on volume:change signal
awesome.connect_signal('volume::change', function()
  -- check if it's muted first
  awful.spawn.easy_async('pamixer --get-mute', function(stdout, stderr, reason, exit_code)
    -- f*king whitespaces
    stdout = stdout:gsub('%s+', '')
    if stdout == 'true' then
      -- muted, only show state
      triggerwibox('mute')
      return
    else
      helpers.async('pamixer --get-volume', function(out)
        vb_slider.widget.value = tonumber(out)
        triggerwibox('volume')
      end)
    end
  end)
end)

-- Show OSD notification of current brightness on brightness:change signal
awesome.connect_signal('brightness:change', function()
  awful.spawn.easy_async('brightnessctl -q get', function(current)
    awful.spawn.easy_async('brightnessctl -q max', function(max)
      vb_slider.widget.value = 100 * tonumber(current) / tonumber(max)
      triggerwibox('brightness')
    end)
  end)
end)

-- When switching to a tag with urgent clients, raise them.
awful.tag.attached_connect_signal(s, 'property::selected', function()
  local urgent_clients = function(c) return c.urgent end
  for c in awful.client.iterate(urgent_clients) do
    if c.first_tag == mouse.screen.selected_tag then
      client.focus = c
      c:raise()
    end
  end
end)

awesome.connect_signal('startup', function(s, state)
  run_once('sleep 3 && firefox', 'firefox')
  -- only makes sense on this laptop
  -- if ( hostname == 'splinter' ) then
    -- run_once('sleep 5 && slack -s', 'slack')
  -- end
  -- on-screen keyboard
  if ( hostname == 'bebop' ) then
    run_once('onboard')
  end
  run_once('sleep 8 && thunderbird', 'rbird')
  run_once('sleep 3 && XDG_CURRENT_DESKTOP=gnome Telegram', 'Telegram')
  run_once('pasystray')
  run_once("wezterm-mux-server --daemonize", "wezterm-mux-server")
  run_once("wezterm connect default --class mainqterm", "mainqterm", "term")
  -- run_once('picom')

  -- standard alt+tab
  -- run_once(
  --   'alttab -w 1 -t 400x300 -frame "'
  --     .. string.upper(beautiful.fg_normal)
  --     .. '" -i 100x100 -font xft:firacode-20',
  --     '400x300'
  -- )
  -- -- Alt+Tab for switching all windows
  -- run_once(
  --   'alttab -w 1 -t 250x100 -frame "'
  --     .. string.upper(beautiful.fg_normal)
  --     .. '" -d 1 -kk 0x1008ff49 -mk Super_L -i 50x50 -font xft:firacode-10 -vertical -p none',
  --   '0x1008ff49'
  -- )
end)

debug_print("Last state of the screens table is: \n" .. my_utils.dump(screens_table), printmore)
-- load_last_active_tags() runs from schedule_screen_rebuild() instead: the
-- screens are processed from a timer now, so at this point no tag has been
-- placed on a screen yet and the restore would have nothing to work with.
-- vim: set ts=2 sw=2 tw=0 :
