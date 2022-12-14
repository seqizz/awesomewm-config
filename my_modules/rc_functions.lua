local awful = require("awful")
local gears = require("gears")
local beautiful = require("beautiful")
local naughty = require("naughty")
local my_utils = require('my_modules/my_utils')
local xresources = require("beautiful.xresources")
local dpi = xresources.apply_dpi

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

function switch_focus_without_mouse(c, dir)
  -- Get the mouse position
  mouselocation_x = mouse.coords().x
  mouselocation_y = mouse.coords().y
  awful.client.focus.global_bydirection(dir, c, true)
  -- Keep the mouse position
  mouse.coords {x = mouselocation_x, y = mouselocation_y}
end

function switch_to_tag(tag_name, printmore)
	debug_print('Switching to tag ' .. tag_name, printmore)
	tag_obj = awful.tag.find_by_name(nil, tag_name)
	tags_screen_obj = tag_obj.screen
	awful.tag.viewnone(tags_screen_obj)
	awful.tag.viewtoggle(tag_obj)
end

function switch_to_tag_new(tag_name, printmore)
	debug_print('Switching to tag ' .. tag_name, printmore)
    t = find_tag_by_first_word(tag_name)
    tags_screen_obj = t.screen
    awful.tag.viewnone(tags_screen_obj)
    awful.tag.viewtoggle(t)
end

function find_tag_by_first_word(first_word, printmore)
    local all_tags = root.tags()
    for _, t in ipairs(all_tags) do
        if first_word == my_utils.get_first_word(t.name) then
            return t
        end
    end
end

function move_focused_client_to_tag(tag_name)
	tag_obj = awful.tag.find_by_name(nil, tag_name)
	if client.focus then
		my_client_obj = client.focus
		debug_print('Moving focused window (' .. my_client_obj.name .. ') to tag ' .. tag_name, printmore)
		my_client_obj:move_to_tag(tag_obj)
		switch_to_tag(tag_name)
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
        f:write(my_utils.get_first_word(tagobj.name), "\n")
    end
    f:close()
end

function load_last_active_tag()
    tag_list = my_utils.read_lines_from("/home/gurkan/.awesome-last-ws")
    if next(tag_list) ~= nil then
        local previous_tags = {}
        for _, tag_name in pairs(tag_list) do
            -- local t = awful.tag.find_by_name(nil, tag_name)
            local t = find_tag_by_first_word(tag_name)
            table.insert(previous_tags, t)
        end
        awful.tag.viewnone()
        awful.tag.viewmore(previous_tags)
    end
end

function string:firstword()
    -- matches the first word and returns it, or it returns nil
    return self:match("^([%w\\-]+)");
end

function string:resolutions()
    -- returns resolutions (x and y) from xrandr output line
    local needed_word = self:match("[^%s]+ [^%s]+ [^%s]+ ([^%s]+)")
    return needed_word:match("(%d+)x(%d+)")
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

function get_screens()
	local output_tbl = {}
	local xrandr = io.popen("xrandr -q --current | grep -E ' connected (primary )?[0-9]'")

	if xrandr then
        for line in xrandr:lines() do
            name = line:firstword()
            screen_obj = my_utils.find_screen_by_name(name)
            if screen_obj == nil then
                goto skipanother
            end
            width, height = line:resolutions()
            output_tbl[name] = {}
            primary = false
            if string.match(line, " primary ") then
                primary = true
            end
            output_tbl[name]["name"] = name -- oh well..
            output_tbl[name]["primary"] = primary
            output_tbl[name]["width"] = width
            output_tbl[name]["height"] = height
            output_tbl[name]["object"] = screen_obj
            ::skipanother::
        end
        xrandr:close()
	end

    -- now check if there is any fake screens needed to be added
    -- if the screen is too wide, we will create a fake screen and add it to the table
    for name, properties in pairs(output_tbl) do
        if properties["object"] == nil then
            goto skip
        end
        local geo = properties["object"].geometry
        if ( geo.width / geo.height) > 2 then
            local new_width = math.ceil(geo.width/2)
            local new_width2 = geo.width - new_width
            properties["object"]:fake_resize(geo.x + new_width, geo.y, new_width, geo.height)
            fake_obj = screen.fake_add(geo.x, geo.y, new_width2, geo.height)
            fake_screen_name = name .. "_sub_" .. my_utils.random_string(2)
            output_tbl[fake_screen_name] = {}
            output_tbl[fake_screen_name]["is_fake"] = true
            output_tbl[fake_screen_name]["name"] = fake_screen_name
            output_tbl[fake_screen_name]["parent"] = output_tbl[name]
            output_tbl[fake_screen_name]["object"] = fake_obj
            output_tbl[fake_screen_name]["primary"] = false
        end
        ::skip::
    end

	return output_tbl
end

