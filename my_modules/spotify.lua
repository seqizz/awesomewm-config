local awful = require("awful")
local wibox = require("wibox")
local my_utils = require('my_modules/my_utils')
local my_theme = require('my_modules/my_theme')
local dpi = require('beautiful').xresources.apply_dpi

local spotify = wibox.widget {
  widget = wibox.widget.textbox,
  align = "center",
  valign = "center",
  font = my_theme.font,
}

function spotify:set(state)
    markup_value = my_utils.create_markup{
        text="",
        fg="#268bd2",
        size="large",
        rise="-3000",
        font="Font Awesome"
    }
    self.markup = markup_value .. " " .. awful.util.escape(state)
end

function spotify:check()
  awful.spawn.with_line_callback(
    "bash -c 'sleep 0.5 && playerctl -p spotify status'",
    {
      stderr = function (line)
        if line == "No players found" then
          self.markup = ''
          self.forced_width = dpi(0)
        end
      end,
      stdout = function (line)
        awful.spawn.easy_async(
            "bash -c \"playerctl -p spotify metadata | grep -w 'xesam:title' | sed 's/.*xesam:title\\s*//;s/$/ /'\"",
            function(stdout, stderr, reason, exit_code)
                spotify:set(stdout:sub(1,50))
        end)
        self.forced_width = nil
      end
    }
  )
end

spotify:check()

return spotify
