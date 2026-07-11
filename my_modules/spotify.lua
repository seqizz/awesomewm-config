local awful = require('awful')
local wibox = require('wibox')
local my_utils = require('my_modules/my_utils')
local my_theme = require('my_modules/my_theme')
local dpi = require('beautiful').xresources.apply_dpi
local gears = require('gears')

local spotifytext = wibox.widget({
  layout = wibox.container.scroll.horizontal,
  max_size = dpi(150),
  step_function = wibox.container.scroll.step_functions.linear_increase,
  speed = 25,
  extra_space = dpi(10),
  {
    widget = wibox.widget.textbox,
    align = 'center',
    valign = 'center',
    font = my_theme.font,
  },
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

  spotifytext.widget:set_markup_silently(' ' .. awful.util.escape(state))
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

-- Event-driven: one long-running `playerctl --follow` pushes a line on every
-- track/status change instead of polling+forking every 15s. The follower is the
-- single source of truth for widget state.
local follow_pid = nil
-- ASCII Unit Separator (0x1f): never appears in a track title, so it is a safe
-- field delimiter between status and title in the playerctl format template.
local SEP = '\31'

local debug = false       -- flip to true to trace the playerctl follow stream
-- debug print: fires on the module-local flag OR the global printmore master switch
local function dbg(msg)
  if debug or printmore then debug_print(msg, true) end
end

local visible_state = nil -- last emitted visibility, so we only signal on change
local hide_timer = nil    -- debounces hiding to ride out transient empty lines
local last_title = ''     -- keep song text stable across empty-metadata blips

-- Emit the visibility signal only when it actually changes. Spotify pushes many
-- property updates while playing; re-signalling every time makes the widget flicker.
local function set_visible(v)
  if visible_state == v then return end
  visible_state = v
  awesome.emit_signal("widget::spotify::visible", v)
end

local function cancel_hide()
  if hide_timer then
    hide_timer:stop()
    hide_timer = nil
  end
end

local function apply_line(line)
  local sep = line:find(SEP, 1, true)
  local status, title
  if sep then
    status = line:sub(1, sep - 1)
    title = line:sub(sep + 1)
  else
    -- playerctl emits an empty line when the player goes away
    status = line
    title = ''
  end

  dbg('[spotify] parsed status=[' .. status .. '] title=[' .. title .. ']')

  if status == '' then
    -- Empty lines also appear transiently during track changes / dbus churn.
    -- Debounce the hide so the widget stays put unless spotify is really gone.
    if not hide_timer then
      hide_timer = gears.timer.start_new(2, function()
        hide_timer = nil
        spotifywidget.forced_width = dpi(0)
        set_visible(false)
        return false
      end)
    end
    return
  end

  cancel_hide()
  -- metadata can momentarily arrive empty mid-track; reuse the last good title
  if title ~= '' then last_title = title end
  -- keep the previous semantics: only 'Paused' shows the paused icon
  local is_playing = status ~= 'Paused'
  spotifywidget:set(last_title, is_playing)
  spotifywidget.forced_width = nil
  set_visible(true)
end

local function start_follow()
  -- argv table (no shell), so the 0x1f delimiter and titles pass through verbatim.
  -- NOTE: `metadata` is the required subcommand; --follow makes it stream.
  local cmd = { 'playerctl', '-p', 'spotify', 'metadata', '--follow',
                '--format', '{{status}}' .. SEP .. '{{title}}' }
  dbg('[spotify] start_follow: ' .. table.concat(cmd, ' '))
  follow_pid = awful.spawn.with_line_callback(cmd, {
    stdout = function(line)
      dbg('[spotify] stdout: [' .. line .. ']')
      apply_line(line)
    end,
    stderr = function(line)
      dbg('[spotify] stderr: [' .. line .. ']')
    end,
    exit = function(reason, code)
      dbg('[spotify] exit: ' .. tostring(reason) .. ' ' .. tostring(code))
      follow_pid = nil
      -- playerctl exits if the dbus session drops; respawn after a short delay
      gears.timer.start_new(2, function() start_follow() return false end)
    end,
  })
  dbg('[spotify] follow_pid = ' .. tostring(follow_pid))
end

-- Cheap idempotent nudge: media keybindings/buttons call this to guarantee the
-- follower is alive. Track/status updates themselves arrive via --follow.
function spotifywidget:check()
  if not follow_pid then start_follow() end
end

-- Start hidden; the follower reveals the widget once spotify appears.
set_visible(false)
start_follow()

spotifywidget:buttons(awful.util.table.join(
  awful.button({}, 1, function() -- left click
    fn_process_action('media', 'pausetoggle', 'spotify')
    spotifywidget:check()
  end),
  awful.button({}, 2, function() -- middle click
    awful.spawn('systemctl --user restart updatesong.service')
  end),
  awful.button({}, 3, function() -- right click
    spotifywidget:raise_toggle()
  end),
  awful.button({}, 4, function() -- scroll up
    fn_process_action('media', 'previous', 'spotify')
    spotifywidget:check()
  end),
  awful.button({}, 5, function() -- scroll down
    fn_process_action('media', 'next', 'spotify')
    spotifywidget:check()
  end)
))

return spotifywidget
