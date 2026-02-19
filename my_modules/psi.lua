local awful = require('awful')
local wibox = require('wibox')
local my_utils = require('my_modules/my_utils')
local my_theme = require('my_modules/my_theme')
local dpi = require('beautiful').xresources.apply_dpi
local gears = require('gears')

-- Helpful functions
dofile(gears.filesystem.get_configuration_dir() .. "my_modules/rc_functions.lua")

local psitext = wibox.widget({
  widget = wibox.widget.textbox,
  align = 'center',
  valign = 'center',
  font = my_theme.font,
})

local psiimage = wibox.widget({
  image = my_theme.gauge_icon,
  resize = true,
  widget = wibox.widget.imagebox,
})

local psiimage_lifted = wibox.container.margin(
  psiimage,
  nil,
  nil,
  nil,
  dpi(2) -- bottom margin to match visually
)

local psiwidget = wibox.widget({
  psiimage_lifted,
  psitext,
  layout = wibox.layout.fixed.horizontal,
})

psi_tooltip = get_tooltip(psiwidget)

function psiwidget:check()
  local color = my_theme.fg_normal
  awful.spawn.with_line_callback('psitool-script', {
    stdout = function(line)
      if tonumber(line) > 100000 then
        color = '#FF0000'
        psi_tooltip.text = 'System goes brrrrr'
      elseif tonumber(line) > 50000 then
        color = '#cb4b16'
        psi_tooltip.text = 'System is busy'
      elseif tonumber(line) > 20000 then
        color = my_theme.fg_normal_alt
        psi_tooltip.text = 'System is okay'
      elseif tonumber(line) > 5000 then
        color = my_theme.fg_normal
        psi_tooltip.text = 'System is idle'
      else
        psi_tooltip.text = 'Not doing any shit tbh'
      end
      psiimage:set_image(gears.color.recolor_image(my_theme.gauge_icon, color))
      psitext:set_markup_silently(line)
    end,
  })
end

psiwidget:buttons(awful.util.table.join(
  -- Update PSI widget with click, if we're not patient enough
  awful.button({}, 1, function() psiwidget:check() end)
))

psiwidget:check()

return psiwidget
--  vim: set ts=2 sw=2 tw=0 et :
