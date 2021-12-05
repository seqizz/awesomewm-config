local awful = require("awful")
local wibox = require("wibox")
local my_utils = require('my_modules/my_utils')
local my_theme = require('my_modules/my_theme')
local dpi = require('beautiful').xresources.apply_dpi

local mypsi = wibox.widget {
  widget = wibox.widget.textbox,
  align = "center",
  valign = "center",
  forced_width = dpi(80),
  font = my_theme.font,
}

function mypsi:check()
  awful.spawn.with_line_callback(
    "psitool-script",
    {
      stdout = function (line)
        local fg = "#6c71c4"

        if tonumber(line) > 100000 then
          fg = "#FF0000"
        elseif tonumber(line) > 50000 then
          fg = "#cb4b16"
        elseif tonumber(line) > 20000 then
          fg = "#b58900"
        elseif tonumber(line) > 5000 then
          fg = "#268bd2"
        end
        markup_value = my_utils.create_markup{
          text="",
          fg=fg,
          size="x-large",
          rise="-3000",
          font="Ionicons"
        }

        self.markup = markup_value .. " " .. line
      end
    }
  )
end

mypsi:check()

return mypsi
