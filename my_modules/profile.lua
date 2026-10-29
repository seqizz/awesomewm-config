-- Tints the UI by NixOS profile (/etc/nixos-profile: "work" or "private").
--
-- The profile is a runtime specialisation switch (work-on / work-off), not a
-- reboot, so the tint has to be re-applicable without restarting awesome.
-- work-profile.nix calls profile.refresh() over awesome-client as part of its
-- post-switch resettle; the timer below is only a fallback for a switch done
-- behind our back (manual switch-to-configuration, boot entry, failed poke).
local awful = require('awful')
local beautiful = require('beautiful')
local gears = require('gears')
local naughty = require('naughty')
local my_theme = require('my_modules/my_theme')

local PROFILE_FILE = '/etc/nixos-profile'

-- Hosts without the work/private specialisation have no PROFILE_FILE at all,
-- which must look exactly like an untinted theme rather than an error state.
local DEFAULT_PROFILE = 'private'

-- accent: focused client border, the loud signal.
-- taglist_bg: selected tag background.
-- bar_bg: wibar background.
--
-- private is the baseline: it reproduces the plain theme values exactly, so
-- the untinted look is what you get on the private profile. my_theme is read
-- instead of beautiful because this module is required before beautiful.init.
local PROFILES = {
  work = {
    accent = '#689d6a', -- gruvbox aqua
    taglist_bg = '#689d6a',
    bar_bg = '#1f2b22', -- desaturated aqua, keeps widget colors readable
  },
  private = {
    accent = my_theme.border_focus,
    taglist_bg = my_theme.bg_focus,
    bar_bg = my_theme.bg_normal,
  },
}

local profile = {
  name = nil,
}

-- A missing or unparsable file is not an error worth signalling in the UI: any
-- host that does not switch profiles simply stays on the baseline look.
local function read_profile()
  local f = io.open(PROFILE_FILE, 'r')
  if not f then return DEFAULT_PROFILE end
  local line = f:read('*l') or ''
  f:close()
  local name = line:match('^%s*(%S+)')
  if not name or not PROFILES[name] then return DEFAULT_PROFILE end
  return name
end

-- Repaint everything that cached a theme color at construction time. Widgets
-- built from beautiful.* read it once, so changing the theme table alone is
-- not enough after startup.
local function repaint(colors)
  for s in screen do
    if s.mywibox then
      s.mywibox.bg = colors.bar_bg
    end
    -- awful.widget.taglist keeps a private updater; name differs across
    -- awesome versions and is absent on some, hence the guarded calls.
    local tl = s.mytaglist
    if tl then
      local update = tl._do_taglist_update_now or tl._do_taglist_update
      if update then pcall(update) end
    end
  end

  for _, c in ipairs(client.get()) do
    c.border_color = (c == client.focus) and colors.accent or beautiful.border_normal
  end
end

function profile.apply()
  local colors = PROFILES[profile.name] or PROFILES[DEFAULT_PROFILE]

  beautiful.border_focus = colors.accent
  beautiful.taglist_bg_focus = colors.taglist_bg
  beautiful.profile_accent = colors.accent -- for other widgets that want it

  repaint(colors)
end

-- Re-read the file and re-tint. Silent when nothing changed, so the fallback
-- timer never spams notifications.
function profile.refresh(opts)
  opts = opts or {}
  local previous = profile.name
  profile.name = read_profile()

  if previous == profile.name and not opts.force then return profile.name end

  profile.apply()

  if previous ~= nil then
    naughty.notify({
      title = 'NixOS profile',
      text = ('%s → %s'):format(previous, profile.name),
      fg = PROFILES[profile.name].accent,
      timeout = 5,
    })
  end

  return profile.name
end

gears.timer({
  timeout = 300,
  autostart = true,
  callback = function() profile.refresh() end,
})

-- Global alias so `awesome-client 'nixos_profile.refresh()'` stays short and
-- does not depend on require() path setup inside the client's chunk.
nixos_profile = profile

return profile
