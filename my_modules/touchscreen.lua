local awful = require("awful")
local wibox = require("wibox")
local my_utils = require('my_modules/my_utils')
local my_theme = require('my_modules/my_theme')

local touchwidget= wibox.widget {
  widget = wibox.widget.textbox,
  align = "center",
  valign = "center",
  forced_width = 40,
  font = my_theme.font,
}

function touchwidget:set(state)
  if state == "on" then
    fg = "#268bd2"
    -- text = " On"
  else
    fg = "#cb4b16"
    -- text = "   "
  end
  markup_value = my_utils.create_markup{
    text="",
    fg=fg,
    size="x-large",
    rise="-3000",
    font="Ionicons"
  }

  -- self.markup = markup_value .. " " .. text
  self.markup = markup_value
end

function touchwidget:check()
  awful.spawn.with_line_callback(
    "xinput-toggle query 'Wacom HID 48EC Finger'",
    {
      stdout = function (line)
        local fg = "#6c71c4"

        if line == "on" then
          fg = "#268bd2"
          -- text = "On "
        elseif line == "off" then
          fg = "#cb4b16"
          -- text = "   "
        else
          text = "??"
          fg = "#FF0000"
        end
        markup_value = my_utils.create_markup{
          text="",
          fg=fg,
          size="x-large",
          rise="-3000",
          font="Ionicons"
        }

        self.markup = markup_value
        -- self.markup = markup_value .. " " .. text
      end
    }
  )
end

function touchwidget:toggle()
  awful.spawn.with_line_callback(
    "xinput-toggle query 'Wacom HID 48EC Finger'",
    {
      stdout = function (line)
        if line == "on" then
          touchwidget:set('off')
        elseif line == "off" then
          touchwidget:set('on')
        end
        awful.spawn("xinput-toggle 'Wacom HID 48EC Finger'")
      end
    }
  )
end

touchwidget:check()

return touchwidget
