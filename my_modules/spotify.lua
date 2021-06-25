local awful = require("awful")
local wibox = require("wibox")

local spotify = wibox.widget {
  widget = wibox.widget.textbox,
  align = "center",
  valign = "center",
  font = "Fira Code Italic 10",
}

function magiclines(s)
  if s:sub(-1)~="\n" then s=s.."\n" end
  return s:gmatch("(.-)\n")
end

function spotify:check()
  local title = ''
  local artist = ''
  awful.spawn.with_line_callback(
    "bash -c 'sleep 1 && playerctl metadata'",
    {
      stdout = function (outline)
        for line in magiclines(outline) do
          if line:match("No players found") then
            self.markup = ""
            self.forced_width = 0
            return spotify
          elseif line:match("spotify xesam:title") then
            title = line:gsub("spotify xesam:title %s+(.+).*", "%1")
          elseif line:match("spotify xesam:artist") then
            artist = line:gsub("spotify xesam:artist %s+(.+).*", "%1")
          end
        end
        if artist ~= '' and title ~= '' then
          self.markup = "<span foreground='#eee8d5'>▷ " .. artist .. ":" .. title .. "</span>"
          self.forced_width = 300
        end
      end
    }
  )
end

spotify:check()

return spotify
