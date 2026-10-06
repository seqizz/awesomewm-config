local beautiful = require("beautiful")
local awful = require("awful")
local wibox = require("wibox")
local gears = require("gears")
local spawn = require("awful.spawn")

local helpers = {}

-- Create rounded rectangle shape
helpers.rrect = function(radius)
  return function(cr, width, height)
    gears.shape.rounded_rect(cr, width, height, radius)
  end
end

-- Create rectangle shape
helpers.rect = function()
  return function(cr, width, height)
    gears.shape.rectangle(cr, width, height)
  end
end

-- Rectangle with the top-left corner cut off by `size` px. This is the window
-- shape every client gets from the default rule; kept here so the places that
-- have to re-apply it after temporarily squaring a client off stay in sync.
helpers.chamfer = function(size)
  return function(cr, width, height)
    cr:move_to(size, 0)
    cr:line_to(width - size, 0)
    cr:line_to(width, size)
    cr:line_to(width, height)
    cr:line_to(0, height)
    cr:line_to(0, size)
    cr:close_path()
  end
end

function helpers.create_titlebar(c, titlebar_buttons, titlebar_position, titlebar_size)
  awful.titlebar(c, {font = beautiful.titlebar_font, position = titlebar_position, size = titlebar_size}) : setup {
    {
      buttons = titlebar_buttons,
      layout  = wibox.layout.fixed.horizontal
    },
    {
      buttons = titlebar_buttons,
      layout  = wibox.layout.fixed.horizontal
    },
    {
      buttons = titlebar_buttons,
      layout = wibox.layout.fixed.horizontal
    },
    layout = wibox.layout.align.horizontal
  }
end

function helpers.colorize_text(txt, fg)
  local txt = txt or tostring(nil)
  return '<span foreground="'..fg..'">'..txt..'</span>'
end

function helpers.async(cmd, callback, sleeptime)
    sleeptime = sleeptime or 0
    return spawn.easy_async("bash -c 'sleep " .. sleeptime .. " && " .. cmd .. "'",
    function (stdout, stderr, reason, exit_code)
        callback(stdout, exit_code)
    end)
end

return helpers
