local awful = require("awful")
local wibox = require("wibox")
local my_utils = require('my_modules/my_utils')
local my_theme = require('my_modules/my_theme')

local keyboardwidget = wibox.widget {
  widget = wibox.widget.textbox,
  align = "center",
  valign = "center",
  forced_width = 40,
  font = my_theme.font,
}

function keyboardwidget:set(state)
  if state == "tr" then
    fg = "#268bd2"
    text = "TR"
  else
    fg = "#cb4b16"
    text = "WM"
  end
  markup_value = my_utils.create_markup{
    -- text="",
    text=text,
    fg=fg
    -- size="large"
    -- rise="-3000",
    -- font="Ionicons"
  }

  -- self.markup = markup_value .. " " .. text
  self.markup = markup_value
end

function keyboardwidget:check()
  awful.spawn.with_line_callback(
    "workman-toggle query",
    {
      stdout = function (line)
        local fg = "#6c71c4"

        if line == "tr" then
          fg = "#268bd2"
          text = "TR"
        elseif line == "workman-p-tr" then
          fg = "#cb4b16"
          text = "WM"
        else
          text = "??"
          fg = "#FF0000"
        end
        markup_value = my_utils.create_markup{
          -- text="",
          text=text,
          fg=fg
          -- size="large"
          -- rise="-3000",
          -- font="Ionicons"
        }

        self.markup = markup_value
        -- self.markup = markup_value .. " " .. text
      end
    }
  )
end

function keyboardwidget:toggle()
  awful.spawn.with_line_callback(
    "workman-toggle query",
    {
      stdout = function (line)
        if line == "tr" then
          keyboardwidget:set('wm')
        elseif line == "workman-p-tr" then
          keyboardwidget:set('tr')
        end
        awful.spawn("workman-toggle")
      end
    }
  )
end

keyboardwidget:check()

return keyboardwidget
