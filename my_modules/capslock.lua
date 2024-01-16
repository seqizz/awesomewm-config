local awful = require('awful')
local gears = require("gears")
local wibox = require('wibox')
local my_theme = require('my_modules/my_theme')
local dpi = require('beautiful').xresources.apply_dpi

local capslock = wibox.widget({
  widget = wibox.widget.textbox,
  align = 'center',
  valign = 'center',
  font = my_theme.font_small,
})

capslock.activated = '<span background=\'#dc322f\' foreground=\'white\'> CAPS </span>'
capslock.deactivated = ''

local tooltip = awful.tooltip({})

tooltip:add_to_object(capslock)

function capslock:check()
  awful.spawn.with_line_callback('bash -c \'sleep 0.2 && xset q\'', {
    stdout = function(line)
      if line:match('Caps Lock') then
        local status = line:gsub('.*(Caps Lock:%s+)(%a+).*', '%2')
        tooltip.text = 'Caps Lock ' .. status
        if status == 'on' then
          self.markup = self.activated
          self.forced_width = dpi(50)
        else
          self.markup = self.deactivated
          self.forced_width = 0
        end
      end
    end,
  })
end

function capslock:toggle() awful.spawn('xdotool key Caps_Lock') end

-- keybindings
win = 'Mod4'
alt = 'Mod1'
ctrl = 'Control'

-- Catch as many keypresses as possible, which could be accidental
capslock.possible_combinations = gears.table.join(
  awful.key({}, 'Caps_Lock', function() capslock:check() end),
  awful.key({ alt }, 'Caps_Lock', function() capslock:check() end),
  awful.key({ ctrl }, 'Caps_Lock', function() capslock:check() end),
  awful.key({ win }, 'Caps_Lock', function() capslock:check() end),
  awful.key({ win, alt }, 'Caps_Lock', function() capslock:check() end),
  awful.key({ win, ctrl }, 'Caps_Lock', function() capslock:check() end),
  awful.key({ 'Shift' }, 'Caps_Lock', function() capslock:check() end)
)

capslock:check()

return capslock
