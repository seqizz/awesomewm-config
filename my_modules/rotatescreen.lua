local awful = require("awful")
local wibox = require("wibox")
local my_utils = require('my_modules/my_utils')
local my_theme = require('my_modules/my_theme')

local rotatewidget = wibox.widget {
  widget = wibox.widget.textbox,
  align = "center",
  valign = "center",
  forced_width = 40,
  font = my_theme.font,
}

function rotatewidget:set(state)
  if state == "start" then
    fg = "#268bd2"
    -- text = "On "
  else
    fg = "#cb4b16"
    -- text = "   "
  end
  markup_value = my_utils.create_markup{
    text="",
    fg=fg,
    size="x-large",
    rise="-3000",
    font="Ionicons"
  }

  -- self.markup = markup_value .. " " .. text
  self.markup = markup_value
end

function rotatewidget:check()
  awful.spawn.with_line_callback(
    "systemctl --user show auto-rotate.service --property=ActiveState",
    {
      stdout = function (line)
        local fg = "#6c71c4"

        -- if string.find(line, "ActiveState=active") then
        if line == "ActiveState=active" then
          fg = "#268bd2"
          -- text = "On "
        elseif line == "ActiveState=inactive" then
        -- elseif string.find(line, "ActiveState=inactive") then
          fg = "#cb4b16"
          -- text = "   "
        else
          text = "??"
          fg = "#FF0000"
        end
        markup_value = my_utils.create_markup{
          text="",
          fg=fg,
          size="x-large",
          rise="-3000",
          font="Ionicons"
        }

        -- self.markup = markup_value .. " " .. text
        self.markup = markup_value
      end
    }
  )
end

function rotatewidget:toggle()
  awful.spawn.with_line_callback(
    "systemctl --user show auto-rotate.service --property=ActiveState",
    {
      stdout = function (line)
        if line == "ActiveState=active" then
          awful.spawn("systemctl --user stop auto-rotate.service")
          rotatewidget:set('stop')
        elseif line == "ActiveState=inactive" then
          awful.spawn("systemctl --user start auto-rotate.service")
          rotatewidget:set('start')
        end
      end
    }
  )
end

rotatewidget:check()

return rotatewidget
