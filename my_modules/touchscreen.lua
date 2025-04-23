local awful = require('awful')
local gears = require('gears')
local wibox = require('wibox')
local my_utils = require('my_modules/my_utils')
local my_theme = require('my_modules/my_theme')

-- Helpful functions
dofile ("/home/gurkan/.config/awesome/my_modules/rc_functions.lua")

local touchwidget = wibox.widget({
  widget = wibox.widget.textbox,
  align = 'center',
  valign = 'center',
  forced_width = 40,
  font = my_theme.font,
})

function touchwidget:set(state)
  if state == 'on' then
    fg = '#268bd2'
  else
    fg = '#cb4b16'
  end
  markup_value = my_utils.create_markup({
    text = '',
    fg = fg,
    size = 'x-large',
    rise = '-3000',
    font = 'Ionicons',
  })

  -- self.markup = markup_value .. " " .. text
  self.markup = markup_value
end

local touch_tooltip = get_tooltip(touchwidget)

hostname = io.popen('uname -n'):read()
if hostname == 'bebop' then
  fingerdevice = 'Wacom HID 48EC Finger'
elseif hostname == 'splinter' then
  fingerdevice = 'ELAN900C:00 04F3:41EE'
end

function touchwidget:check()
  awful.spawn.with_line_callback('xinput-toggle query \'' .. fingerdevice .. '\'', {
    stdout = function(line)
      local fg = '#6c71c4'

      if line == 'on' then
        fg = '#268bd2'
        touch_tooltip.text = 'Touchy touchy ;)'
      elseif line == 'off' then
        fg = '#cb4b16'
        touch_tooltip.text = 'No touchy :('
      else
        fg = '#FF0000'
        touch_tooltip.text = 'Not sure if touchy or not?!?'
      end
      markup_value = my_utils.create_markup({
        text = '',
        fg = fg,
        size = 'x-large',
        rise = '-3000',
        font = 'Ionicons',
      })

      self.markup = markup_value
    end,
  })
end

function touchwidget:toggle()
  awful.spawn.with_line_callback('xinput-toggle query \'' .. fingerdevice .. '\'', {
    stdout = function(line)
      if line == 'on' then
        touchwidget:set('off')
        touch_tooltip.text = 'No touchy :('
      elseif line == 'off' then
        touchwidget:set('on')
        touch_tooltip.text = 'Touchy touchy ;)'
      end
      awful.spawn('xinput-toggle \'' .. fingerdevice .. '\'')
    end,
  })
end

touchwidget:check()

touchwidget:buttons(awful.util.table.join(awful.button({}, 1, function() -- left click
  touchwidget:toggle()
end)))

return touchwidget
