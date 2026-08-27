local my_theme = require('my_modules/my_theme')
local create_toggle_widget = require('my_modules/toggle_widget')

-- Marker file makes a manual disable stateful: the unit carries
-- ConditionPathExists=!<marker>, so home-manager switches (sd-switch) cannot
-- resurrect xidlehook while it exists. Plain `systemctl stop` is not enough.
local marker = "$HOME/.local/state/xidlehook.disabled"

local autolock_widget = create_toggle_widget({
  check_cmd = "bash -c 'if [ -e " .. marker .. " ]; then echo AUTOLOCK=disabled; "
    .. "elif systemctl --user is-active --quiet xidlehook.service; then echo AUTOLOCK=enabled; "
    .. "else echo AUTOLOCK=disabled; fi'",
  enabled_pattern = "AUTOLOCK=enabled",
  disabled_pattern = "AUTOLOCK=disabled",
  enable_cmd = "bash -c 'rm -f " .. marker .. "; systemctl --user start xidlehook.service'",
  disable_cmd = "bash -c 'mkdir -p \"$(dirname " .. marker .. ")\"; touch " .. marker .. "; "
    .. "systemctl --user stop xidlehook.service'",
  -- enabled (auto-lock active) = secure/locked, disabled = insecure/unlocked
  icon_enabled = my_theme.secure_icon,
  icon_disabled = my_theme.insecure_icon,
  tooltip_on = "Auto-lock enabled",
  tooltip_off = "Auto-lock disabled",
  tooltip_error = "Error checking auto-lock service",
})

return autolock_widget
