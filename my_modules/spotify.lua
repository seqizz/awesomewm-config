local awful = require("awful")
local wibox = require("wibox")
local my_utils = require('my_modules/my_utils')
local my_theme = require('my_modules/my_theme')
local dpi = require('beautiful').xresources.apply_dpi

local spotify = wibox.widget {
  widget = wibox.widget.textbox,
  align = "center",
  valign = "center",
  font = my_theme.font,
}

-- set text of spotify widget
function spotify:set(state, is_playing)
    if is_playing then
      logo = ""
    else
      logo = ""
    end

    markup_value = my_utils.create_markup{
        text=logo,
        fg="#268bd2",
        size="large",
        rise="-2500",
        font="Font Awesome"
    }
    self.markup = markup_value .. " " .. awful.util.escape(state)
end

-- Raise spotify and make its tag visible
function spotify:raise()
  local cls = client.get()
  for _, c in ipairs(cls) do
    if c.name == "Spotify" then
        c:raise()
        local tags = root.tags()
        for _, t in ipairs(tags) do
            if my_utils.table_contains(t:clients(), c, false) then
                t:view_only()
            end
        end
    end
  end
end

function spotify:check()
  awful.spawn.with_line_callback(
    "bash -c 'sleep 1 && playerctl -p spotify status'",
    {
      stderr = function (line)
        if line == "No players found" then
          self.markup = ''
          self.forced_width = dpi(0)
        end
      end,
      stdout = function (line)
        is_playing = true
        if line == "Paused" then
          is_playing = false
        end
        awful.spawn.easy_async(
          "bash -c \"playerctl -p spotify metadata | grep -w 'xesam:title' | sed 's/.*xesam:title\\s*//;s/$/ /'\"",
          function(stdout, stderr, reason, exit_code)
            spotify:set(stdout:sub(1,40), is_playing)
        end)
        self.forced_width = nil
      end
    }
  )
end

spotify:check()

return spotify
