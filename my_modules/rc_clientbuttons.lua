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
  end)
)
