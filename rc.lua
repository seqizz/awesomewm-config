pcall(require, "luarocks.loader")

local gears = require("gears")
local awful = require("awful")
require("awful.autofocus")
local wibox = require("wibox")
local menubar = require("menubar")
local beautiful = require("beautiful")
local naughty = require("naughty")
-- local cst = require("naughty.constants")
local my_utils = require('my_modules/my_utils')
local lain = require("lain")
local capslock = require("my_modules/capslock")
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

-- my theme
beautiful.init("/home/gurkan/.config/awesome/my_modules/my_theme.lua")
local volume_widget = require("my_modules/sound-widget")

-- print errors as naughty notifications
dofile ("/home/gurkan/.config/awesome/my_modules/rc_errorhandling.lua")

-- some fancy functions I'm using
dofile ("/home/gurkan/.config/awesome/my_modules/rc_functions.lua")

-- define tags at the beginning
dofile ("/home/gurkan/.config/awesome/my_modules/rc_tags.lua")

-- stuff related to volume/brightness OSD notifications
dofile ("/home/gurkan/.config/awesome/my_modules/rc_sliderstuff.lua")

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
  awful.key({ ctrl, win          }, "Right",  function (c) c:relative_move(0, 0, dpi(40), 0) end),
  awful.key({ win, "Shift"       }, "Left",   function (c) c:relative_move(dpi(-40), 0, 0, 0) end),
  awful.key({ ctrl, win, "Shift" }, "Left",   function (c) c:relative_move(0, 0, dpi(-40), 0) end),
  awful.key({ ctrl, win          }, "Left",   function (c) c:relative_move(dpi(-20), 0, dpi(20), 0) end),
  awful.key({ ctrl, win, "Shift" }, "Right",  function (c) c:relative_move(dpi(20), 0, dpi(-20), 0) end),
  awful.key({ win, "Shift"       }, "Right",  function (c) c:relative_move(dpi(40), 0, 0, 0) end),
  awful.key({ ctrl, win          }, "Down",   function (c) c:relative_move(0, 0, 0, dpi(40)) end),
  awful.key({ ctrl, win, "Shift" }, "Up",     function (c) c:relative_move(0, 0, 0, dpi(-40)) end),
  awful.key({ ctrl, win          }, "Up",     function (c) c:relative_move(0, dpi(-20), 0, dpi(20)) end),
  awful.key({ win, "Shift"       }, "Down",   function (c) c:relative_move(0, dpi(40), 0, 0) end),
  awful.key({ win, "Shift"       }, "Up",     function (c) c:relative_move(0, dpi(-40), 0, 0) end),
  awful.key({ ctrl, win, "Shift" }, "Down",   function (c) c:relative_move(0, dpi(20), 0, dpi(-20)) end),
  awful.key({ win                }, "Right",  function (c) switch_focus_without_mouse(c, "right") end),
  awful.key({ win                }, "Left",   function (c) switch_focus_without_mouse(c, "left") end),
  awful.key({ win                }, "Down",   function (c) awful.client.focus.bydirection("down") end),
  awful.key({ win                }, "Up",     function (c) awful.client.focus.bydirection("up") end),
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
greenclip_cmd = "rofi -modi 'clipboard:greenclip print' -show clipboard -run-command '{cmd}' "
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

-- TODO: Declare whole table modularly

screen_table = {}
xrandr_table = {}

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

-- Create a textclock widget and attach the calendar
mytextclock = wibox.widget.textclock()
cw = lain.widget.cal({
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
end

docked = false
if screen:count() > 1 then
  docked = true
end

local function check_available_screens()
  if ( docked and screen:count() == 1 ) or ( not docked and screen:count() == 2 ) then
    print(">>>>>> Detected docking change, restarting awesomewm")
    -- awesome.restart()
    register_all_screens()
  end
end

restart_timer = gears.timer {
  timeout = 2,
  autostart = true,
  callback = function()
    check_available_screens()
  end
}

psi_timer = gears.timer {
  timeout = 15,
  autostart = true,
  callback = function()
    psi_widget:check()
  end
}

local function screen_organizer(s, primary)
  -- Wallpaper -- one for each screen
  set_wallpaper(s)

  -- grab needed tags
  if primary then
    tag_web.screen = s
    screen_table[s]["tags"]["web"] = tag_web
  end
  if (
      primary and my_utils.table_length(screen_table) == 1
    ) or (
      not primary and my_utils.table_length(screen_table) > 1 ) then
    tag_term.screen = s
    if not primary then
      tag_term.selected = true
    end
    screen_table[s]["tags"]["term"] = tag_term
  end
  if primary and ( hostname == "innixos" or hostname == "innodellix" ) then
    tag_mail.screen = s
    screen_table[s]["tags"]["mail"] = tag_mail
  end
  if (
      primary and my_utils.table_length(screen_table) == 1
    ) or (
      not primary and my_utils.table_length(screen_table) > 1 ) then
    tag_chat.screen = s
    screen_table[s]["tags"]["chat"] = tag_chat
  end

  -- Create an imagebox widget which will contain an icon indicating which layout we're using.
  -- We need one layoutbox per screen.
  s.mylayoutbox = awful.widget.layoutbox(s)
  s.mylayoutbox:buttons(gears.table.join(
    awful.button({ }, 1, function () awful.layout.inc( 1) end),
    awful.button({ }, 3, function () awful.layout.inc(-1) end),
    awful.button({ }, 4, function () awful.layout.inc( 1) end),
    awful.button({ }, 5, function () awful.layout.inc(-1) end)
  ))

  -- Create a taglist widget
  if screen:count() > 1 then
    taglist_width = dpi(220)
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

  -- Create the wibox
  s.mywibox = awful.wibar({
    position = "top",
    screen = s,
    height = 30
  })

  systray_right_widgets = {
    layout = wibox.layout.fixed.horizontal
  }

  table.insert(systray_right_widgets, separator_empty)
  if primary and my_utils.table_length(screen_table) == 1 and hostname == "innodellix" then
    table.insert(systray_right_widgets, touch_widget)
    table.insert(systray_right_widgets, rotate_widget)
    table.insert(systray_right_widgets, separator_reverse)
  end
  if (
      primary and my_utils.table_length(screen_table) == 1
    ) or (
      not primary and my_utils.table_length(screen_table) > 1 ) then
    table.insert(systray_right_widgets, keyboard_widget)
    table.insert(systray_right_widgets, separator_reverse)
    table.insert(systray_right_widgets, battery_widget)
    table.insert(systray_right_widgets, separator_reverse)
    table.insert(systray_right_widgets, psi_widget)
    table.insert(systray_right_widgets, separator_reverse)
    table.insert(systray_right_widgets, volume_widget)
    table.insert(systray_right_widgets, separator_reverse)
    table.insert(systray_right_widgets, my_systray)
  end
  table.insert(systray_right_widgets, capslock)
  table.insert(systray_right_widgets, mytextclock)
  table.insert(systray_right_widgets, s.mylayoutbox)

  -- Add widgets to the wibox
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

known_primary_screens = {
  "eDP1", -- laptop monitor
  "eDP-1", -- laptop monitor
  "DP3-2", -- main external monitor on dock
  "DP-3-2", -- main external monitor on dock
}

function register_all_screens(systray)

	for name, output in pairs(xrandr_info().outputs) do
		if output.connected and output.on then
			local text
			local monitor_id
      if output.edid ~= "" then
        parsed = edid.parse_edid(output.edid)
        local monitor_name = edid.monitor_name(output.edid)
        serial_number = edid.parse_edid(output.edid).serial_number
        man_code = edid.parse_edid(output.edid).manufacturer_code
        if monitor_name then
          text = name .. "\n" .. edid.monitor_name(output.edid)
        else
          text = name
        end
      else
        text = name
			end
			monitor_unique_id = text .. "_" .. man_code .. "_" .. serial_number
			print(monitor_unique_id .. " <<<<<<<<<<__---^^^^")
			xrandr_table[monitor_unique_id] = {}
		end
	end

  local changes_detected = false
  for s in screen do
    for screen_name, _ in pairs(s.outputs) do
      print('<<<<<<<<< Doing ' .. screen_name )
      screen_table[s] = {}

      naughty.notify({text = "Screen: " .. screen_name, screen = s})
      -- These are the cool guys
      -- One is laptop monitor, other is main monitor
      if my_utils.table_contains(known_primary_screens, screen_name) then
        screen_table[s]["role"] = "primary"
      else
        -- I am secondary
        screen_table[s]["role"] = "secondary"
				systray:set_screen(s)
				print('<<<<<<<<< set systray screen as ' .. screen_name )
      end
      screen_table[s]["name"] = screen_name
      screen_table[s]["tags"] = {}
    end
  end

  -- define rules since we have filled the screen table
  dofile ("/home/gurkan/.config/awesome/my_modules/rc_rules.lua")

  -- configure each screen and grab required tags etc.
  for screen, _ in pairs(screen_table) do
    screen_organizer(
      screen,
      screen_table[screen]["role"] == "primary"
    )
  end

  clientkeys, globalkeys = set_keys_after_screen(clientkeys, globalkeys)
  dofile ("/home/gurkan/.config/awesome/my_modules/rc_clientbuttons.lua")
  root.keys(globalkeys)
  set_rules(clientkeys)
  font_hacks()

  print(my_utils.dump(screen_table))
end
-- }}}

-- {{{ Mouse bindings
root.buttons(gears.table.join(
  -- awful.button({ }, 3, function () awful.spawn("rofi -show run") end),
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
  awful.key({              }, "XF86AudioPrev",         nil, function () handle_media("previous") end),
  awful.key({              }, "XF86AudioNext",         nil, function () handle_media("next") end),
  -- For laptop, which doesn't have next/prev buttons
  awful.key({ ctrl         }, "XF86AudioRaiseVolume",  nil, function () handle_media("next") end),
  awful.key({ ctrl         }, "XF86AudioLowerVolume",  nil, function () handle_media("previous") end),
  -- Dropdown terminal: F12
  awful.key({              }, "F12",                   nil, function () my_dropdown:toggle() end),
  awful.key({              }, "Print",                 nil, function () awful.spawn("flameshot gui") end),
  awful.key({ "Shift"      }, "Print",                      function () awful.spawn("flameshot full -c") end),
  awful.key({ ctrl         }, "space",                      function () awful.spawn("rofi -show run") end),
  awful.key({ ctrl, alt    }, "c",                          function () awful.spawn(greenclip_cmd) end),
  awful.key({ win          }, "p",                          function () awful.spawn("rofi-pass") end),
  awful.key({ ctrl, alt    }, "t",                          function () awful.spawn(terminal) end),
  awful.key({ win          }, "c",                          function () awful.spawn("chromium-browser") end),
  awful.key({ ctrl, alt    }, "p",                          function () reset_pulse() end),
  awful.key({ win          }, "f",                          function () awful.spawn(browser) end),
  awful.key({ win          }, "l",                          function () awful.spawn("sudo slock") end),
  awful.key({ win          }, "k",                          function () keyboard_widget:toggle() end),
  awful.key({ win          }, "e",                          function () keyboard_widget:toggle() end),
  -- If something goes wrong with grobi
  awful.key({ win          }, "m",                          function () awful.spawn("grobi apply mobile") end),
  awful.key({ win, "Shift" }, "m",                          function () awful.spawn("grobi apply inno-dell-dock") end),
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
    awful.key({ win          }, "v",                          function () awful.spawn("innovpn-toggle") end),
    awful.key({ win          }, "g",                          function () awful.spawn(gather_town_cmd) end)
  ))
end

-- run once on startup
register_all_screens(my_systray)

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

client.connect_signal("mouse::enter", function (c)
  if c.ontop and c.sticky and c.skip_taskbar and c.marked then
		c.opacity = 0.9
		-- Run away from mouse
		if c.x > 500 then
			awful.placement.top_left(c, {honor_workarea=true})
		else
			awful.placement.top_right(c, {honor_workarea=true})
		end
	end
end)

-- @Reference: Reflect click to the client below
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
  -- update systray
  volume_widget.update()
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
  run_once("firefox", "firefox", "web")
  -- only makes sense while working
  if hostname == "innixos" or hostname == "innodellix" then
    run_once("slack", "slack", "chat")
    run_once("thunderbird", "thunderbird", "mail")
  end
  run_once("telegram-desktop", "telegram", "chat")
  run_once("wezterm start --class mainqterm", "mainqterm", "term")
  run_once("picom --experimental-backends", "picom")
  run_once("alttab -w 1 -t 400x300 -frame cyan -i 100x100 -font xft:firacode-20", "alttab")
end)

load_last_active_tag()
-- vim: set ts=2 sw=2 sts=2 tw=0 noet :
