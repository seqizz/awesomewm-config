local gears = require('gears')
local awful = require('awful')

clientbuttons = gears.table.join(
  awful.button({}, 1, function(c) c:emit_signal('request::activate', 'mouse_click', { raise = true }) end),
  awful.button({}, 2, function(c) c:emit_signal('request::activate', 'mouse_click', { raise = true }) end),
  awful.button({ win }, 1, function(c)
    c:emit_signal('request::activate', 'mouse_click', { raise = true })
    awful.mouse.client.move(c)
  end),
  awful.button({ win }, 3, function(c)
    c:emit_signal('request::activate', 'mouse_click', { raise = true })
    awful.mouse.client.resize(c)
  end),
  -- Opacity stuff
  awful.button({ win }, 4, function(c)
    c:emit_signal('request::activate', 'mouse_click', { raise = true })
    mousegrabber.run(function(_mouse)
      c.opacity = c.opacity + 0.1
      return false
    end, 'mouse')
  end, nil),
  awful.button({ win }, 5, function(c)
    c:emit_signal('request::activate', 'mouse_click', { raise = true })
    mousegrabber.run(function(_mouse)
      c.opacity = c.opacity - 0.1
      return false
    end, 'mouse')
  end, nil),
  -- modkey + Alt + Left Click drag to resize (laptop touchpad 😅)
  awful.button({ win, alt }, 1, function(c)
    c:emit_signal('request::activate', 'mouse_click', { raise = true })
    awful.mouse.client.resize(c)
  end)
)
