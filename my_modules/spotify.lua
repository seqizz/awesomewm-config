local awful = require('awful')
local wibox = require('wibox')
local my_utils = require('my_modules/my_utils')
local my_theme = require('my_modules/my_theme')
local dpi = require('beautiful').xresources.apply_dpi
local gears = require('gears')

local spotifytext = wibox.widget({
  widget = wibox.widget.textbox,
  align = 'center',
  valign = 'center',
  font = my_theme.font,
})

local spotifyimage = wibox.widget({
  resize = true,
  widget = wibox.widget.imagebox,
})

local spotifyimage_lifted = wibox.container.margin(
  spotifyimage,
  nil,
  nil,
  nil,
  dpi(2) -- bottom margin to match visually
)

local spotifywidget = wibox.widget({
  spotifyimage_lifted,
  spotifytext,
  layout = wibox.layout.fixed.horizontal,
})

-- set text of spotify widget
function spotifywidget:set(state, is_playing)
  if is_playing then
    spotifyimage:set_image(gears.color.recolor_image(my_theme.music_icon, my_theme.fg_normal))
  else
    spotifyimage:set_image(gears.color.recolor_image(my_theme.music_icon_paused, my_theme.fg_normal))
  end

  spotifytext:set_markup_silently(' ' .. awful.util.escape(state))
end

_raise_tag_of_client = function(c)
  local tags = root.tags()
  for _, t in ipairs(tags) do
    if my_utils.table_contains(t:clients(), c, false) then
      t:view_only()
    end
  end
end

-- Hide / show spotify
function spotifywidget:raise_toggle()
  local cls = client.get()
  for _, c in ipairs(cls) do
    if c.class == 'Spotify' then
      if c.skip_taskbar then
        _raise_tag_of_client(c)
        c.skip_taskbar = false
        c.minimized = false
        c:raise()
        client.focus = c
      else
        c.skip_taskbar = true
        c.minimized = true
      end
    end
  end
  spotifywidget:check()
end

function spotifywidget:check()
  awful.spawn.with_line_callback('bash -c \'sleep 1 && playerctl -p spotify status\'', {
    stderr = function(line)
      if line == 'No players found' then
        self.forced_width = dpi(0)
      end
    end,
    stdout = function(line)
      is_playing = true
      if line == 'Paused' then
        is_playing = false
      end
      awful.spawn.easy_async(
        'bash -c "playerctl -p spotify metadata | grep -w \'xesam:title\' | sed \'s/.*xesam:title\\s*//;s/$/ /\'"',
        function(stdout, stderr, reason, exit_code) spotifywidget:set(stdout:sub(1, 40), is_playing) end
      )
      self.forced_width = nil
    end,
  })
end

spotifywidget:check()

return spotifywidget
