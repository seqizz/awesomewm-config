local my_theme = require('my_modules/my_theme')
local create_toggle_widget = require('my_modules/toggle_widget')

local rotatewidget = create_toggle_widget({
  check_cmd = "systemctl --user show auto-rotate.service --property=ActiveState",
  enabled_pattern = "ActiveState=active",
  enable_cmd = "systemctl --user start auto-rotate.service",
  disable_cmd = "systemctl --user stop auto-rotate.service",
  icon = my_theme.rotate_icon,
  tooltip_on = "Screen rotation enabled",
  tooltip_off = "Screen rotation disabled",
  tooltip_error = "Error checking screen rotation",
})

return rotatewidget
