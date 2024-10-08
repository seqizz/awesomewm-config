local awful = require('awful')
local gears = require('gears')
local wibox = require('wibox')
local my_utils = require('my_modules/my_utils')
local my_theme = require('my_modules/my_theme')
local dpi = require('beautiful').xresources.apply_dpi

local rotateimage = wibox.widget({
  image = my_theme.rotate_icon,
  resize = true,
  widget = wibox.widget.imagebox,
})

local rotatewidget = wibox.container.margin(
  rotateimage,
  dpi(1),
  nil,
  nil,
  dpi(2) -- bottom margin to match visually
)

local tt = awful.tooltip({
  objects = { rotatewidget },
  text = '',
  visible = false,
  bg = my_theme.tooltip_bg,
})
tt:set_shape(function(cr, width, height)
    gears.shape.infobubble(cr, width, height, corner_radius, 5, 3)
end)

function rotatewidget:set(state)
  if state == 'start' then
    fg = '#268bd2'
    tt.text = 'Screen rotation enabled'
  else
    fg = '#cb4b16'
    tt.text = 'Screen rotation disabled'
  end
  tt.visible = true
  rotateimage.image = gears.color.recolor_image(my_theme.rotate_icon, fg)
end

function rotatewidget:check()
  awful.spawn.with_line_callback('systemctl --user show auto-rotate.service --property=ActiveState', {
    stdout = function(line)
      local fg = '#6c71c4'

      if line == 'ActiveState=active' then
        fg = '#268bd2'
        tt.text = 'Screen rotation enabled'
      elseif line == 'ActiveState=inactive' then
        fg = '#cb4b16'
        tt.text = 'Screen rotation disabled'
      else
        fg = '#FF0000'
        tt.text = 'Error checking screen rotation'
      end
      rotateimage.image = gears.color.recolor_image(my_theme.rotate_icon, fg)
    end,
  })
end

function rotatewidget:toggle()
  awful.spawn.with_line_callback('systemctl --user show auto-rotate.service --property=ActiveState', {
    stdout = function(line)
      if line == 'ActiveState=active' then
        awful.spawn('systemctl --user stop auto-rotate.service')
        rotatewidget:set('stop')
      elseif line == 'ActiveState=inactive' then
        awful.spawn('systemctl --user start auto-rotate.service')
        rotatewidget:set('start')
      end
    end,
  })
end

rotatewidget:check()

return rotatewidget
