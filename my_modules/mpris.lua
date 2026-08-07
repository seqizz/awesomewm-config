local awful = require('awful')
local wibox = require('wibox')
local my_utils = require('my_modules/my_utils')
local my_theme = require('my_modules/my_theme')
local dpi = require('beautiful').xresources.apply_dpi
local gears = require('gears')

-- Players we follow, in priority order. playerctl picks the first present one.
-- Keeping an explicit allowlist stops browser video (firefox/chromium) from
-- hijacking the widget when it starts playing an MPRIS stream.
local PLAYERS = 'spotify,jellyfin-tui'

local mpristext = wibox.widget({
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

-- inner imagebox (for :set_image) + lifted container (for the layout);
-- lift = 1px bottom margin to match visually
local mprisimage, mprisimage_lifted = my_utils.svg_icon({
  image = my_theme.music_icon,
  size = dpi(25),
  color = my_theme.fg_normal,
})

local mpriswidget = wibox.widget({
  mprisimage_lifted,
  mpristext,
  layout = wibox.layout.fixed.horizontal,
})

-- set text of the widget
function mpriswidget:set(state, is_playing)
  -- Do not use gears.color.recolor_image() here: it rasterizes the SVG first,
  -- then imagebox scales that raster, which can look terrible.
  if is_playing then
    mprisimage:set_image(my_theme.music_icon)
  else
    mprisimage:set_image(my_theme.music_icon_paused)
  end

  mpristext.widget:set_markup_silently(' ' .. state)
end

local _raise_tag_of_client = function(c)
  local tags = root.tags()
  for _, t in ipairs(tags) do
    if my_utils.table_contains(t:clients(), c, false) then
      t:view_only()
    end
  end
end

-- Hide / show the Spotify window. Only meaningful for spotify: jellyfin-tui runs
-- inside a terminal with no dedicated window to raise, so this is a no-op there.
function mpriswidget:raise_toggle()
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
  mpriswidget:check()
end

-- Event-driven: one long-running `playerctl --follow` pushes a line on every
-- track/status change instead of polling+forking every 15s. The follower is the
-- single source of truth for widget state.
local follow_pid = nil

-- Name of the player that produced the last update. Media buttons act on this
-- player explicitly so controls always hit whatever the widget is showing.
local current_player = nil

-- ASCII Unit Separator (0x1f): never appears in a track title or player name, so
-- it is a safe field delimiter in the playerctl format template.
local SEP = '\31'

local debug = false -- flip to true to trace the playerctl follow stream

-- debug print: fires on the module-local flag OR the global printmore master switch
local function dbg(msg)
  if debug or printmore then
    debug_print(msg, true)
  end
end

local visible_state = nil -- last emitted visibility, so we only signal on change
local hide_timer = nil -- debounces hiding to ride out transient empty lines
local last_title = '' -- keep song text stable across empty-metadata blips

-- Emit the visibility signal only when it actually changes. Players push many
-- property updates while playing; re-signalling every time makes the widget flicker.
local function set_visible(v)
  if visible_state == v then
    return
  end
  visible_state = v
  awesome.emit_signal('widget::mpris::visible', v)
end

local function cancel_hide()
  if hide_timer then
    hide_timer:stop()
    hide_timer = nil
  end
end

local function apply_line(line)
  -- format is: status \31 playerName \31 title
  local status, player, title = '', nil, ''
  local a = line:find(SEP, 1, true)
  if a then
    status = line:sub(1, a - 1)
    local rest = line:sub(a + 1)
    local b = rest:find(SEP, 1, true)
    if b then
      player = rest:sub(1, b - 1)
      title = rest:sub(b + 1)
    else
      player = rest
    end
  else
    -- playerctl emits an empty line when no followed player is present
    status = line
  end

  dbg('[mpris] parsed status=[' .. status .. '] player=[' .. tostring(player) .. '] title=[' .. title .. ']')

  if status == '' then
    -- Empty lines also appear transiently during track changes / dbus churn.
    -- Debounce the hide so the widget stays put unless the player is really gone.
    if not hide_timer then
      hide_timer = gears.timer.start_new(2, function()
        hide_timer = nil
        current_player = nil
        mpriswidget.forced_width = dpi(0)
        set_visible(false)
        return false
      end)
    end
    return
  end

  cancel_hide()
  current_player = player

  -- metadata can momentarily arrive empty mid-track; reuse the last good title
  if title ~= '' then
    last_title = title
  end

  -- keep the previous semantics: only 'Paused' shows the paused icon
  local is_playing = status ~= 'Paused'

  mpriswidget:set(last_title, is_playing)
  mpriswidget.forced_width = nil
  set_visible(true)
end

local function start_follow()
  -- argv table (no shell), so the 0x1f delimiter and titles pass through verbatim.
  -- NOTE: `metadata` is the required subcommand; --follow makes it stream.
  local cmd = {
    'playerctl',
    '-p',
    PLAYERS,
    'metadata',
    '--follow',
    '--format',
    '{{status}}' .. SEP .. '{{playerName}}' .. SEP .. '{{title}}',
  }

  dbg('[mpris] start_follow: ' .. table.concat(cmd, ' '))

  follow_pid = awful.spawn.with_line_callback(cmd, {
    stdout = function(line)
      dbg('[mpris] stdout: [' .. line .. ']')
      apply_line(line)
    end,

    stderr = function(line) dbg('[mpris] stderr: [' .. line .. ']') end,

    exit = function(reason, code)
      dbg('[mpris] exit: ' .. tostring(reason) .. ' ' .. tostring(code))
      follow_pid = nil

      -- playerctl exits if the dbus session drops; respawn after a short delay
      gears.timer.start_new(2, function()
        start_follow()
        return false
      end)
    end,
  })

  dbg('[mpris] follow_pid = ' .. tostring(follow_pid))
end

-- Cheap idempotent nudge: media keybindings/buttons call this to guarantee the
-- follower is alive. Track/status updates themselves arrive via --follow.
function mpriswidget:check()
  if not follow_pid then
    start_follow()
  end
end

-- Start hidden; the follower reveals the widget once a player appears.
mpriswidget.forced_width = dpi(0)
set_visible(false)
start_follow()

mpriswidget:buttons(gears.table.join(
  awful.button({}, 1, function() -- left click
    fn_process_action('media', 'pausetoggle', current_player)
    mpriswidget:check()
  end),

  awful.button({}, 2, function() -- middle click
    awful.spawn('systemctl --user restart updatesong.service')
  end),

  awful.button({}, 3, function() -- right click
    mpriswidget:raise_toggle()
  end),

  awful.button({}, 4, function() -- scroll up
    fn_process_action('media', 'previous', current_player)
    mpriswidget:check()
  end),

  awful.button({}, 5, function() -- scroll down
    fn_process_action('media', 'next', current_player)
    mpriswidget:check()
  end)
))

return mpriswidget
