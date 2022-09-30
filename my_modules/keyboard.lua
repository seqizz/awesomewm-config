local awful = require("awful")
local wibox = require("wibox")
local my_utils = require('my_modules/my_utils')
local my_theme = require('my_modules/my_theme')
local dpi = require('beautiful').xresources.apply_dpi

local keyboardwidget = wibox.widget {
  widget = wibox.widget.textbox,
  align = "center",
  valign = "center",
  forced_width = dpi(60),
  font = my_theme.font,
}

function keyboardwidget:set(state)
  if state == "tr" then
    fg = my_theme.fg_normal
    text = "TR"
  else
    fg = my_theme.fg_normal_alt
    text = "WM"
  end
  markup_value = my_utils.create_markup{
    text="⌨︁",
    fg=fg,
    size="large",
    rise="-3000",
    font="Font Awesome"
  }

  self.markup = markup_value .. " " .. text
end

function keyboardwidget:check()
  awful.spawn.with_line_callback(
    "workman-toggle query",
    {
      stdout = function (line)
        local fg = my_theme.fg_normal

        if line == "tr" then
          fg = my_theme.fg_normal
          text = "TR"
        elseif line == "workman-p-tr" then
          fg = my_theme.fg_normal_alt
          text = "WM"
        else
          text = "??"
          fg = "#FF0000"
        end
        markup_value = my_utils.create_markup{
          text="⌨︁",
          fg=fg,
          size="large",
          rise="-3000",
          font="Font Awesome"
        }

        self.markup = markup_value .. " " .. text
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
