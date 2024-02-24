local awful = require('awful')
local wibox = require('wibox')
local my_utils = require('my_modules/my_utils')
local my_theme = require('my_modules/my_theme')
local dpi = require('beautiful').xresources.apply_dpi
local gears = require('gears')

local spacer_string = wibox.widget({
  widget = wibox.widget.textbox,
  align = 'center',
  valign = 'center',
  font = my_theme.font,
})
spacer_string:set_markup_silently(' ')

local nextthingtext = wibox.widget({
  widget = wibox.widget.textbox,
  align = 'center',
  valign = 'center',
  font = my_theme.font,
})

local left_image_base = wibox.widget({
  resize = true,
  widget = wibox.widget.imagebox,
})
local right_image_base = wibox.widget({
  resize = true,
  widget = wibox.widget.imagebox,
})
left_image_base:set_image(gears.color.recolor_image(my_theme.thing_icon_left , my_theme.fg_normal))
right_image_base:set_image(gears.color.recolor_image(my_theme.thing_icon_right , my_theme.fg_normal))

-- bottom margin to match visually
local left_image = wibox.container.margin(
  left_image_base,
  nil,
  nil,
  nil,
  dpi(2)
)
local right_image = wibox.container.margin(
  right_image_base,
  nil,
  nil,
  nil,
  dpi(2)
)

local nextthingwidget = wibox.widget({
  left_image,
  spacer_string,
  nextthingtext,
  spacer_string,
  right_image,
  layout = wibox.layout.fixed.horizontal,
})

-- set text of nextthing widget
function nextthingwidget:set(thing, exists)
  if exists then
    left_image_base:set_image(gears.color.recolor_image(my_theme.thing_icon_left , my_theme.fg_normal))
    right_image_base:set_image(gears.color.recolor_image(my_theme.thing_icon_right , my_theme.fg_normal))
  else
    left_image_base:set_image(nil)
    right_image_base:set_image(nil)
  end

  nextthingtext:set_markup_silently(awful.util.escape(thing))
end

function nextthingwidget:check()
  awful.spawn.easy_async(
    'bash -c "head -1 ~/.nextthing"',
    function(stdout, stderr, reason, exit_code)
      exists = true
      if stdout == '' then
        self.forced_width = dpi(0)
        exists = false
      end
      nextthingwidget:set(stdout:sub(1, 40), exists)
      self.forced_width = nil
    end
  )
end

nextthingwidget:check()

return nextthingwidget
