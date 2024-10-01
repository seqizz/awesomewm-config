local awful = require('awful')
local wibox = require('wibox')
local my_utils = require('my_modules/my_utils')
local my_theme = require('my_modules/my_theme')

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

local tt = awful.tooltip({
  objects = { touchwidget },
  text = '',
  visible = false,
})

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
        tt.text = 'Touchy touchy ;)'
      elseif line == 'off' then
        fg = '#cb4b16'
        tt.text = 'No touchy :('
      else
        fg = '#FF0000'
        tt.text = 'Not sure if touchy or not?!?'
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
        tt.text = 'No touchy :('
      elseif line == 'off' then
        touchwidget:set('on')
        tt.text = 'Touchy touchy ;)'
      end
      awful.spawn('xinput-toggle \'' .. fingerdevice .. '\'')
    end,
  })
end

touchwidget:check()

return touchwidget
