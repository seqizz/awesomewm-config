local awful = require('awful')
local gears = require('gears')
local helpers = require('my_modules/geo_helpers')

-- Global on purpose: rc.lua's volume::change / brightness:change handlers reach
-- for it at runtime, and this file is dofile'd (not required) after
-- beautiful.init, which is what the OSD module needs to already be in place.
osd = require('my_modules/osd')

-- Headset (Zone Vibe) mute is hardware-only: invisible to PipeWire/pamixer.
-- Only signal we get is XF86AudioMicMute key event. Track state locally.
-- Headset starts in muted position by default.
local mic_is_muted = true
local mic_debounce = false

-- {{{ media OSD, driven by the mpris follower

-- playerctl subcommand per direction. Every one of them puts the OSD on screen.
local MEDIA_CMD = {
  pausetoggle = 'play-pause',
  stop = 'stop',
  next = 'next',
  previous = 'previous',
}

-- How long after the last transport keypress follower updates may repaint the
-- card. This is a ceiling on how late an update still counts as "the user
-- asked for this", not a delay: nothing ever waits for it to expire.
local MEDIA_WINDOW = 3

-- Only armed when nothing is being followed, so the card is not left on the
-- bare action label for a player mpris.lua does not watch.
local MEDIA_WAIT = 0.6

-- Whether mpris.lua currently has a followed player. Tracked off its own
-- visibility signal rather than by requiring the module, which is loaded
-- earlier in rc.lua and would make the dependency circular.
local follower_live = false
awesome.connect_signal('widget::mpris::visible', function(v) follower_live = v end)

local media_window = nil -- running while follower updates may paint the OSD
local media_fallback = nil -- unfollowed players only, see MEDIA_WAIT
local media_echo = nil -- title from before the burst; lines carrying it are stale
local last_media = nil -- last state the follower reported

local function stop_timer(timer)
  if timer then
    timer:stop()
  end
  return nil
end

awesome.connect_signal('widget::mpris::update', function(info)
  last_media = info

  -- Only paint when the user asked for it. The follower also fires on track
  -- changes nobody pressed a key for, and a popup for those would be a
  -- now-playing toast, not an OSD.
  if not media_window then
    return
  end

  -- Any line at all proves the follower is alive, so the playerctl fallback is
  -- not needed even when this particular line is a stale echo.
  media_fallback = stop_timer(media_fallback)

  -- Spotify re-emits the pre-keypress metadata before it has the new track.
  -- That echo is the only line worth dropping; once the title has actually
  -- moved, every line is real and goes straight to the card.
  if media_echo then
    if info.title == '' or info.title == media_echo then
      return
    end
    media_echo = nil
  end

  osd.media(info)
end)

-- Show something true the instant the key is pressed, then let the follower
-- overwrite it. Nothing here blocks on the player, so a burst of presses paints
-- a burst of cards and ends on whatever the player ends on.
local function arm_media_osd(player, direction)
  local is_skip = direction == 'next' or direction == 'previous'

  -- Only a skip has an echo to drop, and only at the head of a burst: a
  -- play/pause legitimately reports the same title back, and re-reading the
  -- baseline mid-burst would adopt a track already skipped past and suppress
  -- the real updates still arriving for it.
  if is_skip and not media_window then
    media_echo = last_media and last_media.title
    if media_echo == '' then
      media_echo = nil
    end
  end

  media_window = stop_timer(media_window)
  media_window = gears.timer.start_new(MEDIA_WINDOW, function()
    media_window = nil
    media_echo = nil
    return false
  end)

  if is_skip then
    -- The track is changing and the only one known right now is the one being
    -- skipped away from, so name the action rather than show a song that is
    -- already wrong. The follower replaces this with the real track.
    osd.media_action(direction)
  else
    -- Play/pause and stop leave the track alone, so the card can be complete
    -- immediately; only the status is a guess, and the follower confirms or
    -- corrects it within milliseconds.
    osd.media({
      status = direction == 'stop' and 'Stopped'
        or (last_media and last_media.status == 'Playing' and 'Paused' or 'Playing'),
      player = last_media and last_media.player,
      title = last_media and last_media.title or '',
      artist = last_media and last_media.artist or '',
    })
  end

  media_fallback = stop_timer(media_fallback)

  -- A followed player answers over the signal. Racing it with `playerctl
  -- status` is how the card ended up exactly one track behind: the fallback
  -- has no metadata of its own and can only ever repeat what we already knew.
  if follower_live then
    return
  end

  media_fallback = gears.timer.start_new(MEDIA_WAIT, function()
    media_fallback = nil

    local cmd = 'playerctl status'
    if player ~= nil then
      cmd = cmd .. ' -p ' .. player
    end

    -- Status only: an unfollowed player gives us no metadata, and the title we
    -- hold belongs to whatever the follower saw last, which is a different
    -- player entirely.
    helpers.async(cmd, function(out) osd.media({ status = out:gsub('%s+$', '') }) end)

    return false
  end)
end

-- }}}

function fn_process_action(action, direction, player)
  direction = direction or 'toggle'
  player = player or nil

  -- Case 1: Sound mute toggle
  if action == 'sink' then
    if direction == 'toggle' then
      -- directly toggle and print the result
      awful.spawn.easy_async('pamixer -t --get-mute', function(stdout, stderr, reason, exit_code)
        stdout = stdout:gsub('%s+', '') -- f*king whitespaces
        if stdout == 'true' then
          osd.mute()
        else
          helpers.async('pamixer --get-volume', function(out) osd.volume(tonumber(out)) end)
        end
      end)
    else
      -- Case 2: Volume up/down
      if direction == 'up' then
        word = 'i'
      elseif direction == 'down' then
        word = 'd'
      end
      helpers.async('pamixer --get-volume --allow-boost -' .. word .. ' 5', function(out)
        osd.volume(tonumber(out))
      end)
    end

  -- Case 3: Mic mute toggle
  -- Headset mute is hardware-only (invisible to PipeWire), so we just track
  -- XF86AudioMicMute key events with a local boolean.
  -- Keyboard press generates two events (headset follows), so debounce 300ms.
  elseif action == 'source' then
    if direction == 'toggle' then
      if mic_debounce then
        debug_print('[MIC] debounce: ignoring event')
        return
      end
      mic_debounce = true
      gears.timer.start_new(0.3, function() mic_debounce = false return false end)
      mic_is_muted = not mic_is_muted
      debug_print('[MIC] toggled → mic_is_muted=' .. tostring(mic_is_muted))
      -- Software-toggle default source for keyboard-only case (harmless if headset handles it)
      awful.spawn('pamixer --default-source -t')
      osd.mic(mic_is_muted)
    end

  -- Case 4: Brightness up/down
  elseif action == 'brightness' then
    if direction == 'up' then
      symbol = '+'
    elseif direction == 'down' then
      symbol = '-'
    end

    -- use ddcutil if we are on external monitor, otherwise use brightnessctl
    if detect_external_monitor() then
      set_command = 'sudo ddcutil setvcp 10 ' .. symbol .. ' 5'
      get_command = 'get-ddc-current-brightness'
      max_command = 'get-ddc-max-brightness'
    else
      set_command = 'brightnessctl -q s 5%-' .. symbol
      get_command = 'brightnessctl -q get'
      max_command = 'brightnessctl -q max'
    end

    helpers.async(set_command, function(out)
      awful.spawn.easy_async(get_command, function(current)
        awful.spawn.easy_async(max_command, function(max)
          osd.brightness(100 * tonumber(current) / tonumber(max))
        end)
      end)
    end)

  -- Case 5: Media keys
  elseif action == 'media' then
    local subcommand = MEDIA_CMD[direction]
    if not subcommand then
      return
    end

    local cmd = 'playerctl ' .. subcommand
    if player ~= nil then
      cmd = cmd .. ' -p ' .. player
    end

    helpers.async(cmd, function(out) end)
    arm_media_osd(player, direction)
  end
end
