local awful = require("awful")
local beautiful = require("beautiful")

-- ── Input (somewm-only) ──
if awesome.release == "somewm" then
  awful.input.tap_to_click = 1
  awful.input.natural_scrolling = 1
  awful.input.disable_while_typing = 1
end

-- ── Shadow globals ──
beautiful.shadow_enabled = true
beautiful.shadow_radius   = 17
beautiful.shadow_offset_x = -5
beautiful.shadow_offset_y = -5
beautiful.shadow_opacity  = 0.5
