local my_theme = require('my_modules/my_theme')
local create_toggle_widget = require('my_modules/toggle_widget')

local autolock_widget = create_toggle_widget({
  check_cmd = "systemctl --user show xidlehook.service --property=ActiveState",
  enabled_pattern = "ActiveState=active",
  enable_cmd = "systemctl --user start xidlehook.service",
  disable_cmd = "systemctl --user stop xidlehook.service",
  icon = my_theme.lock_icon,
  tooltip_on = "Auto-lock enabled",
  tooltip_off = "Auto-lock disabled",
  tooltip_error = "Error checking auto-lock service",
})

return autolock_widget
