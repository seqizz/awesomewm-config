-- Unified on-screen display for volume, brightness, mute and media state.
--
-- One popup serves every event type: content, accent color and width change per
-- mode. The previous split (a transparent slider popup plus a rotated textbox
-- popup) meant every handler had to remember to hide the other one, and a media
-- press landing on top of a volume press left both fighting for the same corner.
--
-- Accent colors stay per mode on purpose: gold for sound, blue for brightness,
-- red for mute, bright gold for media. The mode is readable before the text is.

local awful = require('awful')
local beautiful = require('beautiful')
local gears = require('gears')
local wibox = require('wibox')
local dpi = beautiful.xresources.apply_dpi
local helpers = require('my_modules/geo_helpers')

local osd = {}

-- rubato is symlinked under ~/.local/awesome-rubato and found through the
-- package.path rc.lua sets up for lain. The name must stay dot-separated:
-- rubato derives the prefix for its own submodules from whatever it was
-- required as, so the slash form used elsewhere in this config leaves it
-- looking for a top-level `rubato.timed`. Animation is optional, without the
-- module the OSD snaps into place instead of sliding.
local rubato = nil
for _, name in ipairs({ 'rubato', 'my_modules.rubato' }) do
  local ok, mod = pcall(require, name)
  if ok then
    rubato = mod
    break
  end
end

-- Tracing of what show() decided and what the popup really became. Gated on the
-- global printmore master switch only: one line per OSD is far too loud to want
-- a module-local flag that can be left on by accident.
local function dbg(msg)
  if printmore then
    debug_print('[osd] ' .. msg, true)
  end
end

local ANIM = 0.2 -- slide/fade duration, same both directions
local BAR_ANIM = 0.28 -- bar fill trails the popup slightly, reads as weight
local TIMEOUT = 1.8 -- on-screen time after the last event
local SLIDE = dpi(40) -- travel distance on show/hide

local MARGIN_TOP = dpi(100)
local MARGIN_RIGHT = dpi(5)
local PAD = dpi(10)

local WIDTH_LEVEL = dpi(56)
local WIDTH_MEDIA = dpi(320)
local WIDTH_CARD = dpi(170) -- short one-line cards (mic state)
local BAR_LEN = dpi(250)
local BAR_THICK = dpi(20)

-- Longest line the media card shows before cutting; the card width is fixed, so
-- this is a character budget rather than a pixel one.
local MEDIA_TITLE_CHARS = 28
local MEDIA_SUB_CHARS = 36

-- Nerd Font glyphs live in the private use area. Building them from codepoints
-- keeps this file readable in an editor without the font, and avoids \u{}
-- escapes (Lua 5.3+ only, awesome is also built against LuaJIT in places).
local function pua(cp)
  return string.char(
    0xe0 + math.floor(cp / 0x1000),
    0x80 + math.floor(cp % 0x1000 / 0x40),
    0x80 + cp % 0x40
  )
end

local GLYPH = {
  volume_high = pua(0xf028), -- nf-fa-volume_up
  volume_mid = pua(0xf027), -- nf-fa-volume_down
  volume_off = pua(0xf026), -- nf-fa-volume_off
  headphones = pua(0xf025), -- nf-fa-headphones
  bluetooth = pua(0xf293), -- nf-fa-bluetooth
  display = pua(0xf108), -- nf-fa-desktop (HDMI sink)
  usb = pua(0xf287), -- nf-fa-usb
  brightness = pua(0xf185), -- nf-fa-sun_o
  play = pua(0xf04b), -- nf-fa-play
  pause = pua(0xf04c), -- nf-fa-pause
  stop = pua(0xf04d), -- nf-fa-stop
  music = pua(0xf001), -- nf-fa-music
  mic = pua(0xf130), -- nf-fa-microphone
  mic_off = pua(0xf131), -- nf-fa-microphone_slash
}

local ACCENT = {
  volume = beautiful.slider_sound_fg,
  brightness = beautiful.slider_brightness_fg,
  mute = beautiful.osd_mute_fg or beautiful.warning_bg,
  media = beautiful.osd_media_fg or beautiful.fg_normal_alt,
}

-- {{{ small helpers

local function pango_escape(s)
  s = tostring(s or '')
  s = s:gsub('&', '&amp;')
  s = s:gsub('<', '&lt;')
  s = s:gsub('>', '&gt;')
  return s
end

-- Truncate by codepoint, not by byte: track titles are full of non-ASCII and a
-- byte-wise cut splits a sequence into something pango refuses to render. Same
-- lead-byte walk the notification history uses.
local function truncate(s, limit)
  s = tostring(s or '')

  local count, i = 0, 1
  while i <= #s do
    local b = s:byte(i)
    local width = (b < 0x80 and 1) or (b < 0xE0 and 2) or (b < 0xF0 and 3) or 4
    count = count + 1
    if count > limit then
      return s:sub(1, i - 1) .. '…'
    end
    i = i + width
  end

  return s
end

local function span(text, color, font)
  return string.format(
    '<span foreground="%s" font_desc="%s">%s</span>',
    color,
    font,
    pango_escape(text)
  )
end

-- }}}

-- {{{ widgets

local function textbox(font, align)
  return wibox.widget({
    widget = wibox.widget.textbox,
    align = align or 'center',
    valign = 'center',
    font = font,
  })
end

local level_icon = textbox(beautiful.font_name .. ' 16')
local level_value = textbox(beautiful.font_small)

local bar = wibox.widget({
  max_value = 100,
  value = 0,
  background_color = beautiful.slider_bg .. '40',
  color = ACCENT.volume,
  shape = gears.shape.rounded_bar,
  bar_shape = gears.shape.rounded_bar,
  widget = wibox.widget.progressbar,
})

local bar_rotated = wibox.widget({
  bar,
  forced_height = BAR_LEN,
  forced_width = BAR_THICK,
  direction = 'east',
  layout = wibox.container.rotate,
})

local level_layout = wibox.widget({
  {
    level_icon,
    wibox.container.place(bar_rotated, 'center', 'center'),
    level_value,
    spacing = dpi(8),
    layout = wibox.layout.fixed.vertical,
  },
  margins = PAD,
  widget = wibox.container.margin,
})

local media_icon = textbox(beautiful.font_name .. ' 20')
local media_title = textbox(beautiful.font, 'left')
local media_sub = textbox(beautiful.font_small, 'left')

local media_layout = wibox.widget({
  {
    media_icon,
    {
      media_title,
      media_sub,
      spacing = dpi(2),
      layout = wibox.layout.fixed.vertical,
    },
    spacing = dpi(10),
    layout = wibox.layout.fixed.horizontal,
  },
  margins = dpi(12),
  widget = wibox.container.margin,
})

local popup = awful.popup({
  widget = level_layout,
  visible = false,
  ontop = true,
  bg = beautiful.osd_bg or (beautiful.bg_normal .. 'd8'),
  border_width = dpi(1),
  border_color = ACCENT.volume,
  shape = helpers.rrect(beautiful.border_radius),
  -- No `placement` property on purpose: geometry is driven by the animation
  -- below. awful.popup only re-runs a placement callback after a redraw, so a
  -- placed popup revived on another screen first paints at its old coordinates
  -- and visibly jumps.
})

-- }}}

-- {{{ animation

local anchor_x, anchor_y = 0, 0 -- where the popup rests while visible
local last_screen = nil -- screen the popup was last placed on
local shown = false
local hide_timer, hide_done_timer

local function set_x(v) popup.x = math.floor(v + 0.5) end

local x_anim, fade_anim, bar_anim
if rubato then
  x_anim = rubato.timed({
    duration = ANIM,
    easing = rubato.easing.quadratic,
    subscribed = set_x,
  })
  fade_anim = rubato.timed({
    duration = ANIM,
    easing = rubato.easing.linear,
    subscribed = function(pos) popup.opacity = pos end,
  })
  bar_anim = rubato.timed({
    duration = BAR_ANIM,
    easing = rubato.easing.quadratic,
    subscribed = function(pos) bar.value = pos end,
  })
end

-- rubato's frame clock is a glib timeout that returns true forever: the first
-- animation of the session starts a 60Hz wakeup that then never stops, which is
-- not something a laptop should pay for an OSD that shows up for a second. The
-- sources are dropped once every tween in the manager has landed, and rubato
-- recreates them by itself on the next set(). Checking *all* timeds (not just
-- ours) keeps this honest if another module starts using rubato later.
local lgi_ok, lgi = pcall(require, 'lgi')

local function rubato_release_clock()
  if not rubato or not lgi_ok or not RUBATO_TIMEOUTS then
    return
  end

  for _, timed in pairs(RUBATO_MANAGER.timeds) do
    if timed.pos ~= timed.target then
      return
    end
  end

  for _, bucket in ipairs(RUBATO_TIMEOUTS) do
    for rate, source in pairs(bucket) do
      lgi.GLib.source_remove(source)
      bucket[rate] = nil
    end
  end
end

-- Jump without interpolating: used when the OSD reappears on a different screen,
-- where sliding would mean flying across the desktop.
local function snap(x, opacity)
  if x_anim then
    x_anim.pos = x
    x_anim:abort() -- fires the subscriber once, so popup.x follows
    fade_anim.pos = opacity
    fade_anim:abort()
  else
    set_x(x)
    popup.opacity = opacity
  end
end

local function animate_in()
  if x_anim then
    x_anim.target = anchor_x
    fade_anim.target = 1
  else
    snap(anchor_x, 1)
  end
end

local function animate_out()
  if x_anim then
    x_anim.target = anchor_x + SLIDE
    fade_anim.target = 0
  end
end

function osd.hide()
  if not shown then
    return
  end
  shown = false

  if hide_timer then
    hide_timer:stop()
  end

  animate_out()

  -- Opacity needs a compositor; the slide carries the animation on its own when
  -- there is none. Either way the popup is only really gone once the tween is.
  if hide_done_timer then
    hide_done_timer:stop()
  end
  hide_done_timer = gears.timer.start_new(rubato and ANIM or 0.01, function()
    hide_done_timer = nil
    popup.visible = false

    -- a hair after the slowest tween (the bar) can possibly still be running
    gears.timer.start_new(BAR_ANIM, function()
      rubato_release_clock()
      return false
    end)

    return false
  end)
end

-- }}}

-- {{{ audio sink detection

-- Asking pactl on every volume keypress would fork twice per repeat, so the
-- answer is cached. Short TTL because the interesting case (plugging headphones
-- in) is exactly when it goes stale.
local SINK_TTL = 5
local sink_glyph, sink_stamp = nil, 0

-- Default sink first, then just the Name/Active Port lines of every sink, so
-- the port of the default one can be looked up without parsing the whole dump.
-- Level-1 long bracket is mandatory: the grep pattern contains '[[:space:]]',
-- whose ']]' would close a plain [[ ]] string mid-command.
local SINK_CMD = [=[
d=$(pactl get-default-sink 2>/dev/null) || exit 0
printf 'DEFAULT %s\n' "$d"
pactl list sinks 2>/dev/null | grep -E '^[[:space:]]*(Name|Active Port):'
]=]

local function classify_sink(name, port)
  name, port = (name or ''):lower(), (port or ''):lower()

  -- Port wins over sink name: the same analog sink is speakers or headphones
  -- depending on which jack is live.
  if port:match('headphone') or port:match('headset') or name:match('headphone') then
    return GLYPH.headphones
  elseif name:match('bluez') then
    return GLYPH.bluetooth
  elseif port:match('hdmi') or name:match('hdmi') or port:match('displayport') then
    return GLYPH.display
  elseif name:match('usb') then
    return GLYPH.usb
  end

  return nil -- plain speakers: caller picks a glyph by volume level instead
end

local function refresh_sink(callback)
  awful.spawn.easy_async_with_shell(SINK_CMD, function(out)
    local default, name, port = nil, nil, nil

    for line in (out or ''):gmatch('[^\n]+') do
      local d = line:match('^DEFAULT%s+(.+)$')
      if d then
        default = d
      else
        local n = line:match('^%s*Name:%s*(%S+)')
        if n then
          name = n
        else
          local p = line:match('^%s*Active Port:%s*(%S+)')
          -- Active Port follows its own sink's Name in the dump
          if p and name == default then
            port = p
          end
        end
      end
    end

    sink_glyph = classify_sink(default, port)
    sink_stamp = os.time()

    if callback then
      callback()
    end
  end)
end

-- Called after a manual sink switch (sound-widget popup) so the next OSD does
-- not show the icon of the output that was just left behind.
function osd.invalidate_sink()
  sink_stamp = 0
end

local function volume_glyph(value)
  if sink_glyph then
    return sink_glyph
  elseif value <= 0 then
    return GLYPH.volume_off
  elseif value < 50 then
    return GLYPH.volume_mid
  end

  return GLYPH.volume_high
end

-- }}}

-- {{{ show

-- A fake screen covers half of a split ultrawide, so anchoring to the focused
-- screen's right edge drops the OSD in the middle of the physical panel, right
-- where the seam is. Anchor to the whole panel instead and hand the popup to
-- the half that owns its right edge. Both helpers are rc_functions globals and
-- are absent on somewm, where there are no fake screens to correct for anyway.
local function osd_target(s)
  if type(panel_right_screen) ~= 'function' or type(monitor_geometry) ~= 'function' then
    return s, s.geometry
  end

  local ok, geo = pcall(monitor_geometry, s)
  if not ok or not geo then
    return s, s.geometry
  end

  return panel_right_screen(s), geo
end

-- awful.popup resolves its width as min(max(fit, minimum_width), maximum_width),
-- so the two bounds must never be crossed while they are being moved: growing
-- the popup (the narrow level bar to the wide media card) with minimum first
-- leaves min > max, and the widget that gets assigned next is laid out against
-- the stale, far smaller maximum.
local function apply_width(width)
  if width >= (popup.maximum_width or 0) then
    popup.maximum_width = width
    popup.minimum_width = width
  else
    popup.minimum_width = width
    popup.maximum_width = width
  end
end

local function show(mode, width, widget)
  local s, geo = osd_target(awful.screen.focused())
  local new_anchor_x = geo.x + geo.width - width - MARGIN_RIGHT

  -- bounds before content: the widget is laid out the moment it is assigned
  apply_width(width)
  popup.widget = widget
  popup.border_color = ACCENT[mode] or ACCENT.volume

  -- Tracked here rather than read back from the popup: the anchor also moves
  -- when the mode changes, since each mode has its own width.
  local moved = last_screen ~= s or anchor_x ~= new_anchor_x
  last_screen = s
  anchor_x = new_anchor_x
  anchor_y = geo.y + MARGIN_TOP

  if hide_done_timer then
    hide_done_timer:stop()
    hide_done_timer = nil
  end

  if not shown then
    popup.screen = s
    popup.y = anchor_y
    snap(anchor_x + SLIDE, 0) -- start off to the right, then slide in
    popup.visible = true
    shown = true
    animate_in()
  else
    popup.y = anchor_y
    if moved then
      popup.screen = s
      snap(anchor_x, 1) -- different screen: no cross-desktop flight
    end
  end

  if hide_timer then
    hide_timer:stop()
  end
  hide_timer = gears.timer.start_new(TIMEOUT, function()
    hide_timer = nil
    osd.hide()
    return false
  end)

  -- The fade runs on rubato's own frame clock, which this module releases when
  -- idle; a popup that is mapped but still fully transparent is invisible while
  -- picom keeps blurring behind it, which looks like the OSD vanished. Check
  -- once the animation should be over and force the end state if it is not
  -- there, loudly enough to find out why.
  gears.timer.start_new(ANIM + 0.1, function()
    if shown and popup.opacity < 1 then
      dbg(string.format('fade stalled at %.2f, forcing', popup.opacity))
      snap(anchor_x, 1)
    end

    dbg(string.format(
      'mode=%s want_w=%d geo=%dx%d+%d+%d opacity=%.2f visible=%s',
      mode,
      width,
      popup.width,
      popup.height,
      popup.x,
      popup.y,
      popup.opacity,
      tostring(popup.visible)
    ))

    return false
  end)
end

-- value: 0..100 (or beyond for boosted volume)
-- mode:  'volume' | 'brightness' | 'mute'
local function show_level(mode, value, glyph, label)
  local accent = ACCENT[mode] or ACCENT.volume

  level_icon.markup = span(glyph, accent, beautiful.font_name .. ' 16')
  level_value.markup = span(label, accent, beautiful.font_small)

  -- Boost: the bar is already full at 100, so the overflow is shown by growing
  -- the bar past its normal length (and turning it red) rather than by a value
  -- the progressbar would clamp away anyway.
  if value > 100 then
    bar_rotated.forced_height = BAR_LEN + dpi(value - 100)
    bar.color = ACCENT.mute
  else
    bar_rotated.forced_height = BAR_LEN
    bar.color = accent
  end

  local target = math.min(value, 100)
  if bar_anim then
    bar_anim.target = target
  else
    bar.value = target
  end

  show(mode, WIDTH_LEVEL, level_layout)
end

function osd.volume(value)
  -- rounded here: the brightness path hands over a float and '%d' on a
  -- non-integer is an error in Lua 5.3+
  value = math.floor((tonumber(value) or 0) + 0.5)

  local function paint()
    show_level('volume', value, volume_glyph(value), string.format('%d%%', value))
  end

  paint()

  if os.time() - sink_stamp > SINK_TTL then
    -- Repaint when the answer lands: the popup is still up for ~1s.
    refresh_sink(function()
      if shown then
        paint()
      end
    end)
  end
end

function osd.mute()
  -- Bar keeps its last value, red: mute says nothing about the level, and
  -- blanking it would read as "volume went to zero".
  show_level('mute', bar.value, GLYPH.volume_off, 'muted')
end

function osd.brightness(value)
  value = math.floor((tonumber(value) or 0) + 0.5)
  show_level('brightness', value, GLYPH.brightness, string.format('%d%%', value))
end

-- Icon + one or two lines of text, no bar. Used by anything whose state is not
-- a level: media transport and the mic toggle.
local function show_card(mode, glyph, line1, line2, width)
  local accent = ACCENT[mode] or ACCENT.media

  media_icon.markup = span(glyph, accent, beautiful.font_name .. ' 20')
  media_title.markup = span(truncate(line1, MEDIA_TITLE_CHARS), accent, beautiful.font)

  -- an empty second textbox still claims a line, so drop it instead
  media_sub.visible = line2 ~= nil and line2 ~= ''
  if media_sub.visible then
    media_sub.markup = span(truncate(line2, MEDIA_SUB_CHARS), beautiful.fg_normal, beautiful.font_small)
  end

  show(mode, width or WIDTH_MEDIA, media_layout)
end

-- Mic state is tracked by hand in rc_fn_actions (the headset mutes in hardware,
-- PipeWire never sees it), so this is a plain acknowledgement of a keypress.
function osd.mic(muted)
  show_card(
    muted and 'mute' or 'volume',
    muted and GLYPH.mic_off or GLYPH.mic,
    muted and 'Mic muted' or 'Mic live',
    nil,
    WIDTH_CARD
  )
end

-- info comes straight from the mpris follower: { status, player, title, artist }
function osd.media(info)
  info = info or {}
  local status = info.status or ''

  local glyph, label = GLYPH.music, status
  if status == 'Playing' then
    glyph, label = GLYPH.play, 'Playing'
  elseif status == 'Paused' then
    glyph, label = GLYPH.pause, 'Paused'
  elseif status == 'Stopped' then
    glyph, label = GLYPH.stop, 'Stopped'
  elseif status == '' then
    glyph, label = GLYPH.stop, 'No player'
  end

  local title = (info.title ~= '' and info.title) or nil
  local artist = (info.artist ~= '' and info.artist) or info.player

  -- With a title present the status word moves down to the second line, so the
  -- card always says what just happened without eating the title's row.
  local line2 = label
  if title and artist then
    line2 = label .. ' · ' .. artist
  end

  show_card('media', glyph, title or label, title and line2 or artist)
end

-- }}}

return osd
