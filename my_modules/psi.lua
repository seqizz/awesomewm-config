local awful = require("awful")
local wibox = require("wibox")
local my_utils = require('my_modules/my_utils')
local my_theme = require('my_modules/my_theme')
local dpi = require('beautiful').xresources.apply_dpi
local gears = require("gears")

local psitext = wibox.widget {
  widget = wibox.widget.textbox,
  align = "center",
  valign = "center",
  font = my_theme.font,
  forced_width = dpi(80)
}

local psiimage = wibox.widget {
  image = my_theme.gauge_icon,
  resize = true,
  widget = wibox.widget.imagebox,
}

local psiimage_lifted = wibox.container.margin(
  psiimage,
  nil, nil, nil, dpi(2) -- bottom margin to match visually
)

local psiwidget = wibox.widget {
  psiimage_lifted,
  psitext,
  layout  = wibox.layout.fixed.horizontal
}

function psiwidget:check()
  local color = my_theme.fg_normal
  awful.spawn.with_line_callback(
  "psitool-script",
  {
    stdout = function (line)
      if tonumber(line) > 100000 then
        color = "#FF0000"
      elseif tonumber(line) > 50000 then
        color = "#cb4b16"
      elseif tonumber(line) > 20000 then
        color = my_theme.fg_normal_alt
      elseif tonumber(line) > 5000 then
        color = my_theme.fg_normal
      end
      psiimage:set_image(gears.color.recolor_image(my_theme.gauge_icon, color))
      psitext:set_markup_silently(line)
      self.forced_width = math.max(dpi(10 * #line), dpi(65))
      psitext.forced_width = math.min(dpi(10 * #line), dpi(70))
    end
  }
  )
end

psiwidget:check()

psiwidget:buttons(awful.util.table.join(
  -- Update PSI widget with click, if we're not patient enough
  awful.button({}, 1, function()
    psiwidget:check()
  end)
))

return psiwidget
--  vim: set ts=2 sw=2 tw=0 et :
