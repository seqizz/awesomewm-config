pcall(require, "luarocks.loader")

local gears = require("gears")
local awful = require("awful")
require("awful.autofocus")
local wibox = require("wibox")
local menubar = require("menubar")
local beautiful = require("beautiful")
local naughty = require("naughty")
local my_utils = require('my_modules/my_utils')
local lain = require("lain")
local capslock = require("my_modules/capslock")
local spotify = require("my_modules/spotify")
local psi_widget = require("my_modules/psi")
local rotate_widget = require("my_modules/rotatescreen")
local touch_widget = require("my_modules/touchscreen")
local keyboard_widget = require("my_modules/keyboard")
local helpers = require("my_modules/geo_helpers")
local edid = require('my_modules/edid')
local dpi = require('beautiful').xresources.apply_dpi
hostname = io.popen("uname -n"):read()

-- debug stuff
-- local inspect = require 'inspect'
local printmore = false

-- my theme
beautiful.init("/home/gurkan/.config/awesome/my_modules/my_theme.lua")

-- print errors as naughty notifications
dofile ("/home/gurkan/.config/awesome/my_modules/rc_errorhandling.lua")

-- some fancy functions I'm using
dofile ("/home/gurkan/.config/awesome/my_modules/rc_functions.lua")

-- define tags at the beginning
dofile ("/home/gurkan/.config/awesome/my_modules/rc_tags.lua")

-- stuff related to volume/brightness OSD notifications
dofile ("/home/gurkan/.config/awesome/my_modules/rc_sliderstuff.lua")

-- stuff including usernames etc
dofile ("/home/gurkan/.config/awesome/my_modules/rc_secret.lua")

docked = false
xrandr_table = get_xrandr_outputs()
-- TODO: Fix for all environments
if screen:count() == 2 and not my_utils.table_contains(xrandr_table, "eDP-1", false) then
  docked = true
end

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
  -- Win        + Shift + Arrows -> Move windows to that direction
  -- Win + Ctrl         + Arrows -> Expand windows to that direction
  -- Win + Ctrl + Shift + Arrows -> Shrink windows from that direction
  awful.key({ ctrl, win          }, "Right",  function (c) move_or_expand(c, "expand", "right") end),
  awful.key({ win, "Shift"       }, "Left",   function (c) move_or_expand(c, "move", "left") end),
  awful.key({ ctrl, win, "Shift" }, "Left",   function (c) move_or_expand(c, "shrink", "left") end),
  awful.key({ ctrl, win          }, "Left",   function (c) move_or_expand(c, "expand", "left") end),
  awful.key({ ctrl, win, "Shift" }, "Right",  function (c) move_or_expand(c, "shrink", "right") end),
  awful.key({ win, "Shift"       }, "Right",  function (c) move_or_expand(c, "move", "right") end),
  awful.key({ ctrl, win          }, "Down",   function (c) move_or_expand(c, "expand", "down") end),
  awful.key({ ctrl, win, "Shift" }, "Up",     function (c) move_or_expand(c, "shrink", "up") end),
  awful.key({ ctrl, win          }, "Up",     function (c) move_or_expand(c, "expand", "up") end),
  awful.key({ win, "Shift"       }, "Down",   function (c) move_or_expand(c, "move", "down") end),
  awful.key({ win, "Shift"       }, "Up",     function (c) move_or_expand(c, "move", "up") end),
  awful.key({ ctrl, win, "Shift" }, "Down",   function (c) move_or_expand(c, "shrink", "down") end),
  awful.key({ win                }, "Right",  function (c) switch_focus_without_mouse(c, "right") end),
  awful.key({ win                }, "Left",   function (c) switch_focus_without_mouse(c, "left") end),
  awful.key({ win                }, "Down",   function (c)
                                                          if c.sticky then
                                                            -- in case it's on top
                                                            awful.client.focus.history.previous()
                                                          else
                                                            awful.client.focus.bydirection("down")
                                                          end
                                              end),
  awful.key({ win                }, "Up",     function (c)
                                                          local cls = client.get()
                                                          local stickies = {}
                                                          -- Get all the stickies
                                                          for _, c in ipairs(cls) do
                                                            if c.sticky then
                                                              table.insert(stickies, c)
                                                            end
                                                          end
                                                          if my_utils.table_length(stickies) == 0 then
                                                            awful.client.focus.bydirection("up")
                                                          else
                                                            awful.client.focus.history.previous()
                                                          end
                                              end),
  -- Minimize window: Win + z
  awful.key({ win                }, "z",      function (c) c.minimized = true end),
  -- Suspend the window's app with SIGSTOP: Ctrl + Alt + s
  awful.key({ ctrl, alt          }, "s",      function (c) suspend_toggle(c) end),
  -- Shrink window and make it sticky & on top (e.g. conference call): Ctrl + Alt + w
  awful.key({ ctrl, alt          }, "w",      function (c) float_toggle(c) end),
  -- Sticky toggle for window: Ctrl + Alt + Shift + s
  awful.key({ ctrl, alt, "Shift" }, "s",      function (c) sticky_toggle(c) end),
  -- Hide stickies to the bottom-right corner (toggle) : Win + Esc
  awful.key({ win                }, "Escape", function (c) hide_stickies() end)
)

function set_keys_after_screen_new(clientkeys, globalkeys)
  if screen:count() > 1 then
    -- Shortcut for moving window between screens
    clientkeys = gears.table.join(clientkeys,
      awful.key({ win, "Shift" }, "Left",   function (c) c:move_to_screen(c.screen.index-1) end),
      awful.key({ win, "Shift" }, "Right",  function (c) c:move_to_screen(c.screen.index+1) end)
  )
  end

  -- for global_tag_number = 1, 9 do
    -- globalkeys = gears.table.join(globalkeys,
                                  -- awful.key({win}, "#" .. global_tag_number + 9,
                                            -- function()
      -- local local_tag_number = global_tag_number
      -- -- only makes sense if I have more than 1 screens
      -- if screen:count() > 1 then
        -- if my_utils.is_screen_primary_new(awful.screen.focused()) then
          -- -- i am on primary
          -- if global_tag_number
            -- > my_utils.table_length(awful.screen.focused().tags) then
            -- -- need to go to second screen, if exists
            -- next_screen = awful.screen.focused():get_next_in_direction("right")
            -- if next_screen then
              -- -- subtract the tag count before focusing it
              -- local_tag_number = global_tag_number - my_utils.table_length(awful.screen.focused().tags)
              -- awful.screen.focus_relative(1)
            -- end
          -- end
        -- else
          -- -- i am on secondary
          -- prev_screen = awful.screen.focused():get_next_in_direction("left")
          -- if prev_screen then
            -- if global_tag_number <= my_utils.table_length(prev_screen.tags) then
              -- -- need to go to previous screen
              -- awful.screen.focus_bydirection("left")
            -- else
              -- -- just subtract the tag count
              -- local_tag_number = global_tag_number - my_utils.table_length(prev_screen.tags)
            -- end
          -- end
        -- end
      -- end
      -- -- default stuff below
      -- local screen = awful.screen.focused()
      -- local tag = screen.tags[local_tag_number]
      -- if tag then
        -- tag:view_only()
      -- end
    -- end),
    -- -- Move client to tag.
    -- awful.key({win, "Shift"}, "#" .. global_tag_number + 9, function()
      -- if client.focus then
        -- local_tag_number = global_tag_number
        -- screen_to_move = awful.screen.focused()
        -- -- only makes sense if I have more than 1 screens
        -- if screen:count() > 1 then
          -- if my_utils.is_screen_primary(awful.screen.focused()) then
            -- -- i am on primary
            -- if global_tag_number
              -- > my_utils.table_length(awful.screen.focused().tags) then
              -- -- need to move to second screen, if exists
              -- next_screen =
                -- awful.screen.focused():get_next_in_direction("right")
              -- if next_screen then
                -- screen_to_move = next_screen
                -- -- subtract the tag count
                -- local_tag_number = global_tag_number
                                     -- - my_utils.table_length(
                                       -- awful.screen.focused().tags)
              -- end
            -- end
          -- else
            -- -- i am on secondary
            -- prev_screen = awful.screen.focused():get_next_in_direction("left")
            -- if prev_screen then
              -- if global_tag_number <= my_utils.table_length(prev_screen.tags) then
                -- -- need to go to previous screen
                -- screen_to_move = prev_screen
              -- else
                -- -- just subtract the tag count
                -- local_tag_number = global_tag_number
                                     -- - my_utils.table_length(prev_screen.tags)
              -- end
            -- end
          -- end
        -- end
        -- -- default stuff below
        -- local tag = screen_to_move.tags[local_tag_number]
        -- if tag then
          -- client.focus:move_to_tag(tag)
        -- end
      -- end
    -- end))
  -- end

  return clientkeys, globalkeys

end
function set_keys_after_screen(clientkeys, globalkeys)
  if screen:count() > 1 then
    clientkeys = gears.table.join(clientkeys,
      awful.key({ win, "Shift" }, "Left",   function (c) c:move_to_screen(c.screen.index-1) end),
      awful.key({ win, "Shift" }, "Right",  function (c) c:move_to_screen(c.screen.index+1) end)
  )
  end

  for global_tag_number = 1, 9 do
    globalkeys = gears.table.join(globalkeys,
                                  awful.key({win}, "#" .. global_tag_number + 9,
                                            function()
      local local_tag_number = global_tag_number
      -- only makes sense if I have more than 1 screens
      if screen:count() > 1 then
        if my_utils.is_screen_primary(awful.screen.focused()) then
          -- i am on primary
          if global_tag_number
            > my_utils.table_length(awful.screen.focused().tags) then
            -- need to go to second screen, if exists
            next_screen = awful.screen.focused():get_next_in_direction("right")
            if next_screen then
              -- subtract the tag count before focusing it
              local_tag_number = global_tag_number - my_utils.table_length(awful.screen.focused().tags)
              awful.screen.focus_relative(1)
            end
          end
        else
          -- i am on secondary
          prev_screen = awful.screen.focused():get_next_in_direction("left")
          if prev_screen then
            if global_tag_number <= my_utils.table_length(prev_screen.tags) then
              -- need to go to previous screen
              awful.screen.focus_bydirection("left")
            else
              -- just subtract the tag count
              local_tag_number = global_tag_number - my_utils.table_length(prev_screen.tags)
            end
          end
        end
      end
      -- default stuff below
      local screen = awful.screen.focused()
      local tag = screen.tags[local_tag_number]
      if tag then
        tag:view_only()
      end
    end), -- Move client to tag.
    awful.key({win, "Shift"}, "#" .. global_tag_number + 9, function()
      if client.focus then
        local_tag_number = global_tag_number
        screen_to_move = awful.screen.focused()
        -- only makes sense if I have more than 1 screens
        if screen:count() > 1 then
          if my_utils.is_screen_primary(awful.screen.focused()) then
            -- i am on primary
            if global_tag_number
              > my_utils.table_length(awful.screen.focused().tags) then
              -- need to move to second screen, if exists
              next_screen =
                awful.screen.focused():get_next_in_direction("right")
              if next_screen then
                screen_to_move = next_screen
                -- subtract the tag count
                local_tag_number = global_tag_number
                                     - my_utils.table_length(
                                       awful.screen.focused().tags)
              end
            end
          else
            -- i am on secondary
            prev_screen = awful.screen.focused():get_next_in_direction("left")
            if prev_screen then
              if global_tag_number <= my_utils.table_length(prev_screen.tags) then
                -- need to go to previous screen
                screen_to_move = prev_screen
              else
                -- just subtract the tag count
                local_tag_number = global_tag_number
                                     - my_utils.table_length(prev_screen.tags)
              end
            end
          end
        end
        -- default stuff below
        local tag = screen_to_move.tags[local_tag_number]
        if tag then
          client.focus:move_to_tag(tag)
        end
      end
    end))
  end

  return clientkeys, globalkeys

end

-- some aliases
terminal = "wezterm start"
browser = "firefox"
editor = os.getenv("EDITOR") or "nvim"
editor_cmd = terminal .. " -e " .. editor
greenclip_cmd = "rofi -dpi " .. dpi(80) .. " -modi 'clipboard:greenclip print' -show clipboard -run-command '{cmd}' "
rofi_cmd = "rofi -dpi " .. dpi(80) .. " -show run"
rofi_emoji_cmd = "rofi -dpi " .. dpi(80) .. " -show emoji -modi emoji"
proxified_chromium_cmd = 'chromium-browser --incognito --proxy-server="socks://127.0.0.1:8080" --host-resolver-rules="MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"'
gather_town_cmd = 'chromium-browser --app="https://gather.town/app/7Rxu9DG6dVHm2qDR/sysadmin-tiny" --noerrdialogs --disable-translate --no-first-run --fast --fast-start --disable-infobars --class="gathertown"  --user-data-dir=/devel/.tmp_gather_profile'

win = "Mod4"
alt = "Mod1"
ctrl = "Control"

-- default layout table, keeping for reference, I only need 2 of these
layouts = {
  -- awful.layout.suit.floating,
  awful.layout.suit.tile,
  -- awful.layout.suit.tile.left,
  -- awful.layout.suit.tile.bottom,
  -- awful.layout.suit.tile.top,
  -- awful.layout.suit.fair,
  -- awful.layout.suit.fair.horizontal,
  -- awful.layout.suit.spiral,
  -- awful.layout.suit.spiral.dwindle,
  awful.layout.suit.max
  -- awful.layout.suit.max.fullscreen,
  -- awful.layout.suit.magnifier,
  -- awful.layout.suit.corner.nw,
  -- awful.layout.suit.corner.ne,
  -- awful.layout.suit.corner.sw,
  -- awful.layout.suit.corner.se,
}
awful.layout.layouts = layouts

-- dropdown terminal from lain
my_dropdown = lain.util.quake({
  app = terminal,
  argname = '--class %s',
  name = 'myshittydropdown',
  height = 0.5,
  followtag = true,
  visible = false
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

separator = wibox.widget {
  widget       = wibox.widget.separator,
  orientation  = "horizontal",
  forced_width = 30,
  color        = beautiful.separator,
  shape        = gears.shape.powerline
}

separator_empty = wibox.widget {
  widget       = wibox.widget.separator,
  orientation  = "horizontal",
  forced_width = 10,
  color        = beautiful.bg_normal,
}

separator_reverse = wibox.widget {
  widget       = wibox.widget.separator,
  orientation  = "horizontal",
  forced_width = 30,
  span_ratio   = 0.7,
  color        = beautiful.separator,
  set_shape    = function(cr, width, height)
    gears.shape.powerline(cr, width, height, (height / 2) * (-1))
  end
}

-- widgets I need
my_systray = wibox.widget.systray()

adapter_name = "BAT0"
if my_utils.file_exists('/sys/class/power_supply/BAT1/status') then
  adapter_name = "BAT1"
end
local battery_widget = lain.widget.bat({
    battery = adapter_name,
    full_notify = "off",
    settings = function()
      if bat_now.status == "Charging" then
        battery_widget_color = "#268bd2"
      elseif bat_now.status == "Full" then
        battery_widget_color = beautiful.bg_focus
      else
        battery_widget_color = "#cb4b16"
      end

      markup_value = my_utils.create_markup{
        text=" ",
        fg=battery_widget_color,
        size="x-large",
        rise="-3000",
        font="Ionicons"
      }
      local perc = bat_now.perc ~= "N/A" and markup_value .. bat_now.perc .. "%" or bat_now.perc

      widget:set_markup(lain.util.markup.fontfg(beautiful.font, beautiful.fg_normal, perc .. " "))
    end
})
battery_widget.widget:buttons(awful.util.table.join(
  -- Update battery widget with click, if we're not patient enough
  awful.button({}, 1, function()
    battery_widget:update()
  end)
))

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
calendarwidget = lain.widget.cal({
  followtag = true,
  week_number = "left",
  attach_to = { mytextclock },
  notification_preset = {
    font = beautiful.font_big,
    fg = beautiful.fg_normal,
    bg = beautiful.bg_focus
  }
})

if hostname == "innodellix" then
  rotate_widget:buttons(awful.util.table.join(
    awful.button({}, 1, function() -- left click
        rotate_widget:toggle()
    end)
  ))
  touch_widget:buttons(awful.util.table.join(
    awful.button({}, 1, function() -- left click
        touch_widget:toggle()
    end)
  ))
end
capslock:buttons(awful.util.table.join(
  awful.button({}, 1, function() -- left click
      capslock:toggle()
  end)
))
keyboard_widget:buttons(awful.util.table.join(
  awful.button({}, 1, function() -- left click
      keyboard_widget:toggle()
  end)
))
spotify:buttons(awful.util.table.join(
  awful.button({}, 1, function() -- left click
    handle_media("play-pause")
    spotify:check()
  end),
  awful.button({}, 3, function() -- right click
    spotify:raise()
  end),
  awful.button({}, 4, function() -- scroll up
    handle_media("previous")
    spotify:check()
  end),
  awful.button({}, 5, function() -- scroll down
    handle_media("next")
    spotify:check()
  end)
))

psi_timer = gears.timer {
  timeout = 15,
  autostart = true,
  callback = function()
    psi_widget:check()
  end
}

spotify_timer = gears.timer {
  timeout = 15,
  autostart = true,
  call_now = true,
  callback = function()
    spotify:check()
  end
}

local function screen_organizer(s, primary, is_extra)
  -- Wallpaper -- one for each screen
  set_wallpaper(s)

  -- Create an imagebox widget which will contain an icon indicating which layout we're using.
  -- We need one layoutbox per screen.
  s.mylayoutbox = awful.widget.layoutbox(s)
  s.mylayoutbox:buttons(gears.table.join(
    awful.button({ }, 1, function () awful.layout.inc( 1) end),
    awful.button({ }, 3, function () awful.layout.inc(-1) end),
    awful.button({ }, 4, function () awful.layout.inc( 1) end),
    awful.button({ }, 5, function () awful.layout.inc(-1) end)
  ))

  if not is_extra then
    -- Create a taglist widget
    if screen:count() > 1 then
      taglist_width = dpi(250)
    else
      taglist_width = dpi(300)
    end
    s.mytaglist = awful.widget.taglist {
      screen  = s,
      filter  = awful.widget.taglist.filter.all,
      style   = {
          shape = gears.shape.powerline
      },
      layout   = {
          spacing = -15,
          spacing_widget = {
              color  = beautiful.bg_normal,
              shape  = gears.shape.powerline,
              widget = wibox.widget.separator,
          },
          layout  = wibox.layout.flex.horizontal,
          forced_width = taglist_width
          -- max_widget_width = taglist_width /50
      },
      widget_template = {
          {
              {
                  {
                      id     = 'text_role',
                      widget = wibox.widget.textbox,
                  },
                  layout = wibox.layout.flex.horizontal,
              },
              left  = 24,
              right = 12,
              widget = wibox.container.margin
          },
          id     = 'background_role',
          widget = wibox.container.background,
      },
      buttons = taglist_buttons
    }

    -- Create a tasklist widget
    s.mytasklist = awful.widget.tasklist {
      screen  = s,
      filter  = awful.widget.tasklist.filter.currenttags,
      style   = {
          shape = gears.shape.powerline
      },
      layout   = {
          spacing = -15,
          spacing_widget = {
              color  = beautiful.bg_normal,
              shape  = gears.shape.powerline,
              widget = wibox.widget.separator,
          },
          layout  = wibox.layout.flex.horizontal
      },
      widget_template = {
          {
              {
                  {
                      id     = 'text_role',
                      widget = wibox.widget.textbox,
                  },
                  layout = wibox.layout.flex.horizontal,
              },
              left  = 18,
              right = 18,
              widget = wibox.container.margin
          },
          id     = 'background_role',
          widget = wibox.container.background,
      },
      buttons = tasklist_buttons
    }
  end

  -- Create the wibox
  if screen:count() == 1 then
    wibar_height = dpi(23)
  else
    wibar_height = dpi(25)
  end
  s.mywibox = awful.wibar({
    position = "top",
    screen = s,
    height = wibar_height
  })

  systray_right_widgets = {
    layout = wibox.layout.fixed.horizontal
  }

  table.insert(systray_right_widgets, separator_empty)
  if primary then
    if screen:count() == 1 and hostname == "innodellix" then
      table.insert(systray_right_widgets, touch_widget)
      table.insert(systray_right_widgets, rotate_widget)
    end
    table.insert(systray_right_widgets, separator_reverse)
    table.insert(systray_right_widgets, keyboard_widget)
    table.insert(systray_right_widgets, separator_reverse)
    table.insert(systray_right_widgets, battery_widget)
    table.insert(systray_right_widgets, separator_reverse)
    table.insert(systray_right_widgets, psi_widget)
    table.insert(systray_right_widgets, separator_reverse)
    table.insert(systray_right_widgets, spotify)
    table.insert(systray_right_widgets, my_systray)
  end
  table.insert(systray_right_widgets, capslock)
  table.insert(systray_right_widgets, mytextclock)
  table.insert(systray_right_widgets, s.mylayoutbox)

  -- Add widgets to the wibox
  if is_extra then
    -- Doesn't get much stuff on this screen
    s.mywibox:setup {
      layout = wibox.layout.align.horizontal,
      { -- Left widgets
        layout = wibox.layout.align.horizontal,
        separator,
      },
      systray_right_widgets
    }
  else
    -- Normal setup, tag and taskslists
    s.mywibox:setup {
      layout = wibox.layout.align.horizontal,
      { -- Left widgets
        layout = wibox.layout.align.horizontal,
        s.mytaglist,
        separator,
      },
      s.mytasklist, -- Middle widget
      systray_right_widgets
    }
  end
end

function place_tags(screen_obj, primary)
  if screen:count() == 1 then
    -- Only 1 screen here, no need for drama
    for _, tag in pairs(root.tags()) do
      if tag.screen ~= screen_obj then
        tag.screen = screen_obj
      end
    end
  else
    for _, tag in pairs(root.tags()) do
      if primary == false and ( tag.name == "web" or tag.name == "mail") then
        if tag.screen ~= screen_obj then
          debug_print("Re-assigning " .. tag.name, printmore)
          tag.screen = screen_obj
        end
      elseif primary == true and ( tag.name == "term" or tag.name == "chat") then
        if tag.screen ~= screen_obj then
          debug_print("Re-assigning " .. tag.name, printmore)
          tag.screen = screen_obj
        end
      end
    end
  end

  -- ordering shit
  for _, tag in pairs(root.tags()) do
    if tag.name == "term" then
      tag.index = 3
    elseif tag.name == "mail" then
      tag.index = 2
    elseif tag.name == "web" then
        tag.index = 1
    else -- chat
      tag.index = 4
    end
  end
end

function process_screens(systray)

  systray = systray or nil

  xrandr_table = get_xrandr_outputs()

  debug_print("Xrandr result: " .. my_utils.dump(xrandr_table), printmore)

  for number, name in pairs(xrandr_table) do
    if number == "primary" then
      -- that is the helper value, ignore
      goto skip
    end

    screen_obj = my_utils.find_screen_by_name(name)
    debug_print("Got screen object: " .. my_utils.dump(screen_obj), printmore)

    -- In case we have more than 2 screens, we will register first
    -- non-primary screen as 2nd, others won't get tags.
    second_screen_already_processed = false
    if xrandr_table["primary"] == name then
      -- this is the "primary" screen so it should have the systray
      systray:set_screen(screen_obj)
      screen_organizer(screen_obj, true)
      debug_print("Checking tags for: " .. name .. " (primary) ", printmore)
      place_tags(screen_obj, true)
    else
      screen_organizer(screen_obj, false, second_screen_already_processed)
      if second_screen_already_processed then
        debug_print("Extra screen found: " .. my_utils.dump(screen_obj), printmore)
      else
        debug_print("Checking tags for: " .. name .. " (not primary) ", printmore)
        place_tags(screen_obj, false)
        second_screen_already_processed = true
      end
    end
    ::skip::
  end
  -- define rules since we have filled the screen table
  dofile ("/home/gurkan/.config/awesome/my_modules/rc_rules.lua")

  clientkeys, globalkeys = set_keys_after_screen(clientkeys, globalkeys)
  -- clientkeys, globalkeys = set_keys_after_screen_new(clientkeys, globalkeys)
  dofile ("/home/gurkan/.config/awesome/my_modules/rc_clientbuttons.lua")
  root.keys(globalkeys)
  set_rules(clientkeys)
  -- font_hacks()
end

-- {{{ Mouse bindings
root.buttons(gears.table.join(
  awful.button({ }, 4, awful.tag.viewprev),
  awful.button({ }, 5, awful.tag.viewnext)
      ))
-- }}}

-- {{{ Key bindings
globalkeys = gears.table.join(
  -- needed for capslock helper
  capslock.key,
  capslock.keyWithAlt,
  capslock.keyWithWin,
  capslock.keyWithCtrl,
  -- Standard X11 keys, comes from Fn keys etc.
  awful.key({              }, "XF86MonBrightnessUp",   nil, function() set_brightness('5%+') end),
  awful.key({              }, "XF86MonBrightnessDown", nil, function() set_brightness('5%-') end),
  awful.key({              }, "XF86AudioRaiseVolume",  nil, function() set_volume('i') end),
  awful.key({              }, "XF86AudioLowerVolume",  nil, function() set_volume('d') end),
  awful.key({              }, "XF86AudioMute",         nil, audio_mute),
  awful.key({              }, "XF86AudioMicMute" ,     nil, mic_mute),
  awful.key({              }, "XF86AudioPlay",         nil, function () handle_media("play-pause") end),
  awful.key({              }, "XF86AudioStop",         nil, function () handle_media("stop") end),
  awful.key({              }, "XF86AudioPrev",         nil, function ()
                                                              handle_media("previous")
                                                              spotify:check()
                                                            end),
  awful.key({              }, "XF86AudioNext",         nil, function ()
                                                              handle_media("next")
                                                              spotify:check()
                                                            end),
  -- Smart plug toggle
  awful.key({              }, "XF86HomePage",          nil, function () awful.spawn(bulb_toggle) end),
  -- For laptop, which doesn't have next/prev buttons
  awful.key({ ctrl         }, "XF86AudioRaiseVolume",  nil, function ()
                                                              handle_media("next")
                                                              spotify:check()
                                                            end),
  awful.key({ ctrl         }, "XF86AudioLowerVolume",  nil, function ()
                                                              handle_media("previous")
                                                              spotify:check()
                                                            end),
  -- Dropdown terminal: F12
  awful.key({              }, "F12",                   nil, function () my_dropdown:toggle() end),
  awful.key({              }, "Print",                 nil, function () awful.spawn("flameshot gui") end),
  awful.key({ "Shift"      }, "Print",                      function () awful.spawn("flameshot full -c") end),
  awful.key({ ctrl         }, "space",                      function () awful.spawn(rofi_cmd) end),
  awful.key({              }, "F9",                    nil, function () awful.spawn(rofi_emoji_cmd) end),
  awful.key({ ctrl, alt    }, "c",                          function () awful.spawn(greenclip_cmd) end),
  awful.key({ win          }, "p",                          function () awful.spawn("rofi-pass") end),
  awful.key({ ctrl, alt    }, "t",                          function () awful.spawn(terminal) end),
  awful.key({ win          }, "c",                          function () awful.spawn("chromium-browser") end),
  -- awful.key({ ctrl, alt    }, "p",                          function () reset_pulse() end),
  awful.key({ ctrl, alt    }, "p",                          function () notifytest() end),
  awful.key({ win          }, "f",                          function () awful.spawn(browser) end),
  awful.key({ win          }, "l",                          function () awful.spawn("sudo slock") end),
  awful.key({ win          }, "k",                          function () keyboard_widget:toggle() end),
  awful.key({ win          }, "e",                          function () keyboard_widget:toggle() end),
  -- If something goes wrong with grobi
  awful.key({ win          }, "m",                          function () awful.spawn("grobi apply mobile") end),
  -- Cycle between available layouts
  awful.key({ win          }, "space",                      function () awful.layout.inc(1) end),
  awful.key({ win          }, "x",                          function () awful.spawn("pcmanfm-qt") end),
  awful.key({ win,         }, "Tab",                        function () awful.tag.viewnext(get_screen_of_focused()) end),
  awful.key({ win, "Shift" }, "Tab",                        function () awful.tag.viewprev(get_screen_of_focused()) end),
  awful.key({ win, "Shift" }, "c",                          function () awful.spawn(proxified_chromium_cmd) end),
  awful.key({ win, ctrl    }, "q",                          awesome.quit),
  awful.key({ win, ctrl    }, "r",                          awesome.restart),
  awful.key({ win, "Shift" }, "z",                          unminimize_client)
)
if hostname == "innixos" or hostname == "innodellix" then
  gears.table.merge(globalkeys, gears.table.join(
    awful.key({ win          }, "v",                          function () awful.spawn("innovpn-toggle aw") end),
    awful.key({ win, "Shift" }, "v",                          function () awful.spawn("innovpn-toggle af") end),
    awful.key({ win          }, "g",                          function () awful.spawn(gather_town_cmd) end)
  ))
end

-- Signal function to execute when a new client appears.
client.connect_signal("manage", function (c)
  -- Set the windows at the slave,
  -- i.e. put it at the end of others instead of setting it master.
  if not awesome.startup then awful.client.setslave(c) end

  if awesome.startup
    and not c.size_hints.user_position
    and not c.size_hints.program_position then
    -- Prevent clients from being unreachable after screen count changes.
    awful.placement.no_offscreen(c)
  end
end)

client.connect_signal("property::minimized", function(c)
  -- If a sticky window is minimized, ensure it's visible on taskbar
  if c.sticky then
    c.skip_taskbar = false
  end
end)
client.connect_signal("focus", function(c)
  -- If a sticky window is unminimized, remove from taskbar
  if c.sticky and not c.minimized then
    c.skip_taskbar = true
  end
end)

-- Screen handling
screen.connect_signal("list", function()
  naughty.notify({text = "Reorganizing tags"})
  process_screens(my_systray)
end)

process_screens(my_systray)

tag.connect_signal("request::screen", function(t)
  -- recover tags on a removed screen
  naughty.notify({text = "Recovering tag: " .. t.name})
  for s in screen do t.screen = s return end
end)

client.connect_signal("mouse::enter", function (c)
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

awesome.connect_signal("exit", function (c)
  -- We are about to exit / restart awesome, save our last used tag
  save_current_tag()
end)

-- Add a titlebar if titlebars_enabled is set to true in the rules.
client.connect_signal("request::titlebars", function(c)
  -- buttons for the titlebar
  local buttons = gears.table.join(
    awful.button({ }, 1, function()
      c:emit_signal("request::activate", "titlebar", {raise = true})
      awful.mouse.client.move(c)
    end),
    awful.button({ }, 3, function()
    c:emit_signal("request::activate", "titlebar", {raise = true})
    awful.mouse.client.resize(c)
  end)
  )

  awful.titlebar(c) : setup {
    { -- Left
      awful.titlebar.widget.iconwidget(c),
      buttons = buttons,
      layout  = wibox.layout.fixed.horizontal
    },
    { -- Middle
      { -- Title
        align  = "center",
        widget = awful.titlebar.widget.titlewidget(c)
      },
      buttons = buttons,
      layout  = wibox.layout.flex.horizontal
    },
    { -- Right
      awful.titlebar.widget.floatingbutton (c),
      awful.titlebar.widget.maximizedbutton(c),
      awful.titlebar.widget.stickybutton   (c),
      awful.titlebar.widget.ontopbutton  (c),
      awful.titlebar.widget.closebutton  (c),
      layout = wibox.layout.fixed.horizontal()
    },
    layout = wibox.layout.align.horizontal
  }
end)

tag.connect_signal("property::layout", function(t)
  -- make the focused window master on layout change
  local c = client.focus
  if c and awful.layout.get(t.screen).name == "max" then
    awful.client.setmaster(c)
    c:raise()
  end
end)

client.connect_signal("property::size", function(c)
  -- workaround for exiting fullscreen on floating windows
  -- some params do not stay as they should, so we enforce them
  if c.floating and c.skip_taskbar and not c.fullscreen then
    c.sticky=true
    c.ontop=true
  end
end)

client.connect_signal("focus", function(c)
  -- border setup
  c.border_color = beautiful.border_focus
end)

client.connect_signal("unfocus", function(c)
  -- border setup
  c.border_color = beautiful.border_normal

  -- auto-hide dropdown
  if c.instance == my_dropdown.name then
    my_dropdown.visible = not my_dropdown.visible
    my_dropdown:display()
  end
end)

-- Show OSD notification of current status on volume:change signal
awesome.connect_signal("volume::change", function()
  -- check if it's muted first
  awful.spawn.easy_async(
    "pamixer --get-mute",
    function(stdout, stderr, reason, exit_code)
    if exit_code == 0 then
      return
    else
      helpers.async("pamixer --get-volume", function(out)
        vb_slider.widget.value = tonumber(out)
        triggerwibox('volume')
      end)
    end
  end)
end)

-- Show OSD notification of current brightness on brightness:change signal
awesome.connect_signal("brightness:change", function()
  awful.spawn.easy_async("brightnessctl -q get", function(current)
    awful.spawn.easy_async("brightnessctl -q max", function(max)
      vb_slider.widget.value = 100 * tonumber(current) / tonumber(max)
      triggerwibox('brightness')
    end)
  end)
end)

-- When switching to a tag with urgent clients, raise them.
awful.tag.attached_connect_signal(s, "property::selected", function ()
  local urgent_clients = function (c)
    return awful.rules.match(c, { urgent = true })
  end
  for c in awful.client.iterate(urgent_clients) do
    if c.first_tag == mouse.screen.selected_tag then
      client.focus = c
      c:raise()
    end
  end
end)

awesome.connect_signal("startup", function(s, state)
  run_once("sleep 3 && firefox", "firefox")
  -- only makes sense on this laptop
  if hostname == "innixos" or hostname == "innodellix" then
    run_once("slack -s")
    run_once("thunderbird")
  end
  run_once("telegram-desktop")
  run_once("pasystray")
  run_once("wezterm start --class mainqterm", "mainqterm", "term")
  run_once("picom --experimental-backends")
  run_once("alttab -w 1 -t 400x300 -frame cyan -i 100x100 -font xft:firacode-20")
end)

load_last_active_tag()
-- vim: set ts=2 sw=2 sts=2 tw=0 noet :
