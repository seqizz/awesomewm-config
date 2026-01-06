local my_theme = require('my_modules/my_theme')
local create_toggle_widget = require('my_modules/toggle_widget')
local awful = require('awful')
local gears = require('gears')

local capslock = create_toggle_widget({
  check_cmd = "bash -c 'sleep 0.15 && xset q | grep Caps'",
  enabled_pattern = "Caps Lock:   on",
  disabled_pattern = "Caps Lock:   off",
  toggle_cmd = "xdotool key Caps_Lock",
  icon = my_theme.capslock_icon,
  color_enabled = '#ffffff',
  background_enabled = '#dc322f',
  tooltip_on = "Caps Lock on",
  tooltip_off = "Caps Lock off",
  visible_when_disabled = false,
})

-- keybindings (these need to be global for rc.lua to merge them)
win = 'Mod4'
alt = 'Mod1'
ctrl = 'Control'

-- Catch as many keypresses as possible, which could be accidental
capslock.possible_combinations = gears.table.join(
  awful.key({}, 'Caps_Lock', function() capslock:check() end),
  awful.key({ alt }, 'Caps_Lock', function() capslock:check() end),
  awful.key({ ctrl }, 'Caps_Lock', function() capslock:check() end),
  awful.key({ win }, 'Caps_Lock', function() capslock:check() end),
  awful.key({ win, alt }, 'Caps_Lock', function() capslock:check() end),
  awful.key({ win, ctrl }, 'Caps_Lock', function() capslock:check() end),
  awful.key({ 'Shift' }, 'Caps_Lock', function() capslock:check() end)
)

return capslock
