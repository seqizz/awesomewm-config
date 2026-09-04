-- battery.lua - battery status widget (icon + percentage) backed by lain.
-- Recolors the feather-style battery SVGs via stylesheet (stroke mode) instead
-- of gears.color.recolor_image(), which rasterizes then scales and looks bad.

local awful = require('awful')
local wibox = require('wibox')
local gears = require('gears')
local beautiful = require('beautiful')
local my_utils = require('my_modules/my_utils')

-- get_tooltip lives in rc_functions.lua (global); pull it in like psi.lua does
dofile(gears.filesystem.get_configuration_dir() .. 'my_modules/rc_functions.lua')

local lain = require('lain')

-- prefer BAT1 when present, else BAT0
local adapter_name = 'BAT0'
if my_utils.file_exists('/sys/class/power_supply/BAT1/status') then
  adapter_name = 'BAT1'
end

-- battery icons are outline (stroke-based) feather glyphs, hence mode = 'stroke'
local battery_image_widget = my_utils.svg_icon({
  image = beautiful.battery_icon_empty,
  color = beautiful.fg_normal,
  mode = 'stroke',
})

local bat_tooltip = get_tooltip(battery_image_widget)

-- red bg used for the low-battery warning, matching capslock's warning color
-- rather than a naughty popup (which lain's default low-battery notify fires)
local LOW_BATTERY_BG = beautiful.warning_bg
local LOW_BATTERY_THRESHOLD = 20

-- lain.widget.bat's timer fires `settings()` once synchronously before the
-- factory call even returns, so the container must already exist (even
-- childless) by then, or the first low-battery bg write hits a nil upvalue
local battery_container = wibox.container.background()

local battery_widget_text = lain.widget.bat({
  battery = adapter_name,
  notify = 'off',
  settings = function()
    local low_battery = false

    if bat_now.status == 'Charging' then
      battery_widget_color = beautiful.fg_normal_alt
      battery_image = beautiful.battery_icon_charging
    elseif bat_now.status == 'Full' then
      perc = ''
      battery_widget_color = beautiful.fg_normal
      battery_image = beautiful.battery_icon_full
    else
      battery_widget_color = beautiful.fg_normal_alt
      if bat_now.perc > 80 then
        battery_image = beautiful.battery_icon_full
      elseif bat_now.perc > 40 then
        battery_image = beautiful.battery_icon_medium
      elseif bat_now.perc > LOW_BATTERY_THRESHOLD then
        battery_image = beautiful.battery_icon_low
      else
        battery_image = beautiful.battery_icon_empty
        low_battery = true
      end
    end

    if bat_now.perc > 90 then
      perc = ''
    elseif bat_now.perc == 'N/A' then
      perc = ''
    else
      perc = bat_now.perc .. '%'
    end

    bat_tooltip.text = bat_now.status .. ' (' .. bat_now.perc .. '%)'
    battery_container.bg = low_battery and LOW_BATTERY_BG or nil
    -- mirror low state to separators so their side-fill can bridge into the
    -- red block (separators are created later in rc.lua and connect on build)
    awesome.emit_signal('widget::battery::low', low_battery)
    widget:set_markup(lain.util.markup.fontfg(
      beautiful.font,
      low_battery and beautiful.fg_focus or beautiful.fg_normal,
      perc
    ))
    -- swap icon and recolor via stylesheet (stroke mode) rather than rasterizing
    battery_image_widget:set_image(battery_image)
    battery_image_widget:set_stylesheet(my_utils.svg_stylesheet(
      low_battery and beautiful.fg_focus or battery_widget_color, 'stroke'
    ))
  end,
})

battery_container:set_widget(wibox.widget({
  battery_image_widget,
  battery_widget_text,
  layout = wibox.layout.fixed.horizontal,
}))

local battery_widget = battery_container

battery_widget:buttons(gears.table.join(
  -- Update battery widget with click, if we're not patient enough
  awful.button({}, 1, function() battery_widget_text:update() end)
))

return battery_widget
--  vim: set ts=2 sw=2 tw=0 et :
