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
  background_enabled = my_theme.warning_bg,
  tooltip_on = "Caps Lock on",
  tooltip_off = "Caps Lock off",
  visible_when_disabled = false,
})

-- Keyboard-grabbing popups (rofi, greenclip, ...) hold an active grab, which
-- beats the passive root grabs below, so a Caps_Lock press inside them is
-- invisible to awesome. Re-check on focus changes to resync afterwards.
-- Covers managed grabbers, including on their death (unmanage refocuses).
client.connect_signal('focus', function() capslock:check() end)

-- Rofi is override-redirect unless started with -normal-window, so awesome
-- never manages it and no client signal fires around it. Launch such grabbers
-- through this helper instead of awful.spawn to get a re-check when they exit.
function capslock.spawn_and_check(cmd)
  awful.spawn.easy_async(cmd, function() capslock:check() end)
end

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
