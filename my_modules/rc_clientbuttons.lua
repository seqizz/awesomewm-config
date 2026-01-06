local awful = require('awful')

clientbuttons = awful.util.table.join(
  awful.button({}, 1, function(c) c:emit_signal('request::activate', 'mouse_click', { raise = true }) end),
  awful.button({}, 2, function(c) c:emit_signal('request::activate', 'mouse_click', { raise = true }) end),
  awful.button({ win }, 1, function(c)
    c:emit_signal('request::activate', 'mouse_click', { raise = true })
    if c.maximized then
      c.maximized = false
    end
    awful.mouse.client.move(c)
  end),
  awful.button({ win }, 3, function(c)
    c:emit_signal('request::activate', 'mouse_click', { raise = true })
    awful.mouse.client.resize(c)
  end),
  -- Opacity stuff
  awful.button({ win }, 4, function(c)
    -- Disgusting "workaround" for issue: https://github.com/awesomeWM/awesome/issues/1447
    -- Basically I'm moving the mouse to the top right corner of the window
    -- since it's the least possible place to have a scrollable element
    c:emit_signal('request::activate', 'mouse_click', { raise = true })
    local geo = c:geometry()
    mouse.coords({
      x = geo.x + geo.width - 1,
      y = geo.y + 1,
    })
    mousegrabber.run(function(_mouse)
      c.opacity = c.opacity + 0.1
      return false
    end, 'mouse')
  end, nil), -- nil is for "release" feedback, which is also broken
  awful.button({ win }, 5, function(c)
    -- Same as above but for scroll down event
    c:emit_signal('request::activate', 'mouse_click', { raise = true })
    local geo = c:geometry()
    mouse.coords({
      x = geo.x + geo.width - 1,
      y = geo.y + 1,
    })
    mousegrabber.run(function(_mouse)
      c.opacity = c.opacity - 0.1
      return false
    end, 'mouse')
  end, nil), -- nil is for "release" feedback, which is also broken
  -- modkey + Alt + Left Click drag to resize (laptop touchpad 😅)
  awful.button({ win, alt }, 1, function(c)
    c:emit_signal('request::activate', 'mouse_click', { raise = true })
    awful.mouse.client.resize(c)
  end),
  -- modkey + Alt + Right Click drag to resize fake screen boundary
  awful.button({ win, alt }, 3, function(c)
    c:emit_signal('request::activate', 'mouse_click', { raise = true })
    local s = mouse.screen
    local start_x = mouse.coords().x

    -- Find screen info in screens_table
    local fake_screen = nil
    local parent_screen = nil
    for name, properties in pairs(screens_table) do
      if properties["object"] == s then
        if properties["is_fake"] then
          fake_screen = s
          parent_screen = properties["parent"]["object"]
        else
          -- Check if this screen has a fake child
          for n2, p2 in pairs(screens_table) do
            if p2["is_fake"] and p2["parent"]["object"] == s then
              fake_screen = p2["object"]
              parent_screen = s
              break
            end
          end
        end
        break
      end
    end

    if not fake_screen or not parent_screen then
      return -- No fake screen pair found
    end

    local fake_start_geo = fake_screen.geometry
    local parent_start_geo = parent_screen.geometry

    mousegrabber.run(function(_mouse)
      if _mouse.buttons[3] then
        local diff = _mouse.x - start_x
        -- Fake screen is on the left, parent on the right
        -- Moving mouse right = grow fake, shrink parent
        local new_fake_width = fake_start_geo.width + diff
        local new_parent_width = parent_start_geo.width - diff

        -- Minimum width sanity check
        if new_fake_width > 200 and new_parent_width > 200 then
          fake_screen:fake_resize(fake_start_geo.x, fake_start_geo.y, new_fake_width, fake_start_geo.height)
          parent_screen:fake_resize(parent_start_geo.x + diff, parent_start_geo.y, new_parent_width, parent_start_geo.height)
        end
        return true
      end
      return false
    end, 'sb_h_double_arrow')
  end)
)
