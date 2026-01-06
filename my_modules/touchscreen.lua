local my_theme = require('my_modules/my_theme')
local create_toggle_widget = require('my_modules/toggle_widget')

hostname = io.popen('uname -n'):read()
if hostname == 'bebop' then
  fingerdevice = 'Wacom HID 48EC Finger'
elseif hostname == 'splinter' then
  fingerdevice = 'ELAN900C:00 04F3:41EE'
end

local touchwidget = create_toggle_widget({
  check_cmd = "xinput-toggle query '" .. fingerdevice .. "'",
  enabled_pattern = "on",
  toggle_cmd = "xinput-toggle '" .. fingerdevice .. "'",
  icon = my_theme.touch_icon,
  tooltip_on = "Touchy touchy ;)",
  tooltip_off = "No touchy :(",
  tooltip_error = "Not sure if touchy or not?!?",
})

return touchwidget
