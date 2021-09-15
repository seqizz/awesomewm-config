local awful = require("awful")
local gears = require("gears")
local beautiful = require("beautiful")
local naughty = require("naughty")
local my_utils = require('my_modules/my_utils')

function debug_print(text)
  print('<<<<<<< ' .. text)
end

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
    if c.marked then
      -- already transparent
      c.marked = false
      c.border_color = beautiful.border_normal
      c.border_width = beautiful.border_width
      c.opacity = 1
    else
      c.marked = true
      c.border_color = '#26b7d4'
      c.border_width = 10
    end
    -- if c.border_color == '#26b7d4' and c.opacity == 0.7 then
      -- -- already minimized, unminimize
      -- c.width = 533
      -- c.height = 860
      -- c.border_color = beautiful.border_normal
      -- c.border_width = beautiful.border_width
      -- c.opacity = 1
      -- awful.placement.top_right(c)
      -- c.y = 30
    -- else
      -- -- minimize request
      -- c.fullscreen = false
      -- c.width = 50
      -- c.height = 50
      -- c.border_color = '#26b7d4'
      -- c.border_width = 10
      -- c.opacity = 0.7
      -- awful.placement.bottom_right(c)
    -- end
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
    active_tags = {}
    for s in screen do
        os.remove("/home/gurkan/.awesome-last-ws")
        for _, tagobj in pairs(s.selected_tags) do
            table.insert(active_tags, tagobj)
        end
    end
    local f = assert(io.open("/home/gurkan/.awesome-last-ws", "a+"))
    for _, tagobj in pairs(active_tags) do
        f:write(tagobj.name, "\n")
    end
    f:close()
end

function load_last_active_tag()
    tag_list = my_utils.read_lines_from("/home/gurkan/.awesome-last-ws")
    if next(tag_list) ~= nil then
        local previous_tags = {}
        for _, tag_name in pairs(tag_list) do
            local t = awful.tag.find_by_name(nil, tag_name)
            table.insert(previous_tags, t)
        end
        awful.tag.viewnone()
        awful.tag.viewmore(previous_tags)
    end
end

local function parse_transformations(text, assume_normal)
  local rot = { normal = (assume_normal or false), left = false, right = false, inverted = false}
  local refl = { x = false, y = false, normal = (assume_normal or false) }
  for word in text:gmatch("(%w+)") do
    for k, _v in pairs(rot) do
      if k == word then rot[k] = true end
    end
    for k, _v in pairs(refl) do
      if k == word:lower() then refl[k] = true end
    end
  end
  return { rotations = rot, reflections = refl }
end

function xrandr_info(fp)
  local info = { screens = {}, outputs = {} }
  local current_output
  local last_property
  local pats = { 
    ['^Screen (%d+): minimum (%d+) x (%d+), current (%d+) x (%d+), maximum (%d+) x (%d+)$'] = function(matches)
      -- X screens. Usually just one, when used with Xinerama
      info.screens[tonumber(matches[1])] = { 
        minimum = { tonumber(matches[2]), tonumber(matches[3]) },
        resolution = { tonumber(matches[4]), tonumber(matches[5]) },
        maximum = { tonumber(matches[6]), tonumber(matches[7]) } 
      }
    end,
    ['^([-%a%d]+) connected ([%S]-)%s*(%d+)x(%d+)+(%d+)+(%d+)%s*(.-)%(([%a%s]+)%) (%d+)mm x (%d+)mm$'] = function(matches)
      -- Match connected and active outputs
      current_output = {
        name = matches[1],

        resolution = { tonumber(matches[3]), tonumber(matches[4]) },
        offset = { tonumber(matches[5]), tonumber(matches[6]) },
        transformations = parse_transformations(matches[7]),
        available_transformations = parse_transformations(matches[8], false),
        physical_size = { tonumber(matches[9]), tonumber(matches[10]) },
        connected = true,
        on = true,
        primary = (matches[2] == 'primary'),
        modes = {},
        properties = {},
        edid = ''
      }
      info.outputs[matches[1]] = current_output
    end,
    ['^([-%a%d]+) connected %(([%a%s]+)%)$'] = function(matches)
      -- DVI-1 connected (normal left inverted right x axis y axis)
      -- Match outputs that are connected but disabled
      current_output = {
        name = matches[1],
        available_transformations = parse_transformations(matches[2], false),
        transformations = parse_transformations(''),
        modes = {},
        connected = true,
        on = false,
        properties = {},
        edid = ''
      }
      info.outputs[matches[1]] = current_output
    end,
    ['^([-%a%d]+) disconnected .*%(([%a%s]+)%)$'] = function(matches)
      -- Match disconnected outputs
      current_output = {
        available_transformations = parse_transformations(matches[2], false),
        connected = false, on = false,
        properties = {},
        edid = ''
      }
      info.outputs[matches[1]] = current_output
    end,
    ['^%s%s%s(%d+)x(%d+)%s+(.+)$'] = function(matches)
      -- Match modelines. Only care about resolution and refresh.
      local w = tonumber(matches[1])
      local h = tonumber(matches[2])
      for refresh, symbols in matches[3]:gmatch('([%d.]+)(..)') do
        local mode = { w, h, math.floor(tonumber(refresh)) }
        local modes = current_output.modes
        modes[#modes + 1] = mode
        if symbols:find('%*') then
          current_output.current_mode = mode
        end
        if symbols:find('%+') then
          current_output.default_mode = mode
        end
      end
    end,
    ['^\t(.+):%s+(.+)%s+$'] = function(matches)
      -- Match properties, which are rather freeform
      last_property = matches[1]
      local properties = current_output.properties
      properties[last_property] = { value = matches[2] }
    end,
    ['^\t\tsupported:%s+(.+)$'] = function(matches)
      -- Match supported property values, freeform but comma separated
      if last_property ~= nil then 
        local prop = current_output.properties[last_property]
        local supported = { }
        for word in matches[1]:gmatch('([^,]+),?%s?') do
          supported[#supported + 1] = word
        end
        prop.supported = supported
      end
    end,
    ['^\t\t(' .. string.rep('[0-9a-f]', 32) .. ')$'] = function(matches)
      -- Match EDID block
      current_output.edid = current_output.edid .. matches[1]
    end,
    ['^\t\trange:%s+%((%d+), (%d+)%)$'] = function(matches)
      -- Match ranged property values, e.g. brightness
      if last_property ~= nil then
        local prop = current_output.properties[last_property]
        local range = { tonumber(matches[1]), tonumber(matches[2]) }
        prop.range = range
      end
    end
  }

  fp = fp or io.popen('xrandr --query --prop', 'r')
  for line in fp:lines() do
    for pat, func in pairs(pats) do
      local res 
      res = {line:find(pat)}
      if #res > 0 then
        table.remove(res, 1)
        table.remove(res, 1)
        func(res)
        break
      end
    end
  end
  return info
end
