local awful = require("awful")
local wibox = require("wibox")
local helpers = require("my_modules/geo_helpers")
local my_theme = require("my_modules/my_theme")

local soundbar = wibox.widget {
  widget = wibox.widget.textbox,
  align = "center",
  valign = "center",
  font = my_theme.font,
}

bar_contents = {}

function soundbar:check()
  helpers.async("pacmd list-sinks | grep muted | tail -1", function(out)
    status = out:gsub("%s+", "")
	if string.match(status, 'yes') then
      soundbar.text = "🔇"
      self.markup = self.activated
      self.forced_width = 50
    else
      self.markup = self.deactivated
      self.forced_width = 0
    end
    soundbar.text = table.concat(bar_contents, ' ')
  end, 0.3)
end

soundbar:check()

return soundbar
