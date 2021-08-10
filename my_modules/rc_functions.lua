local awful = require("awful")
local gears = require("gears")
local beautiful = require("beautiful")
local naughty = require("naughty")
local my_utils = require('my_modules/my_utils')

function mark_client()
  c = client.focus
  if c == nil or c.sticky then
    -- we don't care
    return
  end

  if c.opacity == 0.89 then
    -- marked one, unmark
    c.opacity = 1
    c.border_width = 0
  end
end

function unmark_client()
  c = client.focus
  if c == nil or c.sticky then
    -- we don't care
    return
  end

  if c.opacity ~= 0.89 then
    -- unmarked one, mark
    c.opacity = 0.89
    c.border_width = 15
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

function float_toggle(c)
  awful.client.floating.toggle()
  if c.floating then
    c.ontop = true
    c.sticky = true
    c.skip_taskbar = true
    c.width = 533
    c.height = 860
    c.y = 35
    awful.placement.top_right(client.focus, {honor_workarea=true})
  else
    c.ontop = false
    c.sticky = false
    c.skip_taskbar = false
  end
end

function switch_focus_without_mouse(c, dir)
  -- Get the mouse position
  mouselocation_x = mouse.coords().x
  mouselocation_y = mouse.coords().y
  awful.client.focus.global_bydirection(dir, c, true)
  -- Keep the mouse position
  mouse.coords {x = mouselocation_x, y = mouselocation_y}
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
    if c.border_color == '#26b7d4' and c.opacity == 0.7 then
      -- already minimized, unminimize
      c.width = 533
      c.height = 860
      c.border_color = beautiful.border_normal
      c.border_width = beautiful.border_width
      c.opacity = 1
      awful.placement.top_right(c)
      c.y = 30
    else
      -- minimize request
      c.fullscreen = false
      c.width = 50
      c.height = 50
      c.border_color = '#26b7d4'
      c.border_width = 10
      c.opacity = 0.7
      awful.placement.bottom_right(c)
    end
  end
end

function run_once(program, grep_for, on_tag)
	grep_for = grep_for or program
	awful.spawn.easy_async(
		"pgrep -f " .. grep_for,
		function(stdout, stderr, reason, exit_code)
			if exit_code ~= 0 then
				naughty.notify { text = "starting " .. program .. " once" }
				if on_tag ~= nil then
					awful.spawn(program, {tag = on_tag})
				else
					awful.spawn(program)
				end
			end
		end
	)
end

-- experimental fs-level locking for internal ops
function lock(action)
	if action == "is_locked" then
		if os.execute("ls /tmp/.awesome_lock >/dev/null 2>&1") then
			return true
		else
			return false
		end
	end

	if action == "lock" then
		if os.execute("mkdir /tmp/.awesome_lock >/dev/null 2>&1") then
			return true
		else
			return false
		end
	end

	if action == "unlock" then
		if os.execute("rmdir /tmp/.awesome_lock >/dev/null 2>&1") then
			return true
		else
			return false
		end
	end

end

function font_hacks()
  -- some magic for terminal font size
	if screen:count() > 1 then
    awful.spawn('sed -i --follow-symlinks "s/size: .*/size: 13.0/" /home/gurkan/.config/alacritty/alacritty.yml')
    awful.spawn('sed -i --follow-symlinks "s/    font_size = .*/    font_size = 14.0,/" /home/gurkan/.wezterm.lua')
  else
    awful.spawn('sed -i --follow-symlinks "s/size: .*/size: 10.0/" /home/gurkan/.config/alacritty/alacritty.yml')
    awful.spawn('sed -i --follow-symlinks "s/    font_size = .*/    font_size = 17.5,/" /home/gurkan/.wezterm.lua')
  end
end

function set_wallpaper(s)
  -- choose random wallpaper
  awful.spawn.easy_async(
    "find /home/gurkan/syncfolder/wallpaper -not -path 'phone*' -type f",
    function(stdout, stderr, reason, exit_code)
      if exit_code == 0 then
        local wallpapers = {}
        for wp in stdout:gmatch("[^\r\n]+") do
          table.insert(wallpapers, wp)
        end
        -- lua is the shittiest language ever
        -- you need to set seed again, or the "random" will always return same
        math.randomseed(my_utils.get_randomseed())
        gears.wallpaper.maximized(wallpapers[math.random(#wallpapers)], s)
      else
        naughty.notify({text = "Wallpaper assign error: " .. stderr})
      end
    end)
end

function save_current_tag()
    local f = assert(io.open("/home/gurkan/.awesome-last-ws", "w"))
    local t = client.focus and client.focus.first_tag or nil
    f:write(t.name, "\n")
    f:close()
end

function load_last_active_tag()
	local f = assert(io.open("/home/gurkan/.awesome-last-ws", "r"))
	tag_name = f:read("*line")
	f:close()
	local t = awful.tag.find_by_name(nil, tag_name)
    if t ~= nil then
        awful.tag.viewnone()
        awful.tag.viewtoggle(t)
    end
end
