local wibox = require('wibox')
local beautiful = require('beautiful')
local gears = require('gears')
local dpi = require('beautiful').xresources.apply_dpi

local M = {}

function M.create(opts)
  opts = opts or {}

  local width = opts.width or 30

  local sep = wibox.widget {
    widget       = wibox.widget.separator,
    orientation  = opts.orientation or "horizontal",
    forced_width = width,
    span_ratio   = opts.span_ratio or 0.7,
    color        = opts.color or beautiful.separator,
    set_shape    = function(cr, w, h)
      gears.shape.parallelogram(cr, w, h)
    end
  }

  function sep:show()
    self.forced_width = width
  end

  function sep:hide()
    self.forced_width = dpi(0)
  end

  -- Bind to a signal if provided
  if opts.signal then
    awesome.connect_signal(opts.signal, function(visible)
      if visible then
        sep:show()
      else
        sep:hide()
      end
    end)
    -- Start hidden if initial_visible is false
    if opts.initial_visible == false then
      sep:hide()
    end
  end

  return sep
end

return M
