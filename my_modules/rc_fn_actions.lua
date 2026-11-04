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

-- playerctl subcommand per direction, and whether that action puts the OSD on
-- screen. next/previous show it now because the follower hands us the new
-- track's title for free; they used to show nothing at all.
local MEDIA_CMD = {
  pausetoggle = 'play-pause',
  stop = 'stop',
  next = 'next',
  previous = 'previous',
}

local MEDIA_OSD = {
  pausetoggle = true,
  stop = true,
  next = true,
  previous = true,
}

-- How long follower updates keep repainting the OSD after a keypress. A skip
-- often produces two lines in a row (status first, then the new metadata), and
-- painting both means the card is never left showing the previous track.
local MEDIA_SETTLE = 0.5

-- How long to wait for the follower before falling back to asking playerctl.
-- The follower normally answers in a few ms; this only trips when the active
-- player is outside mpris.lua's allowlist (browser video, for instance), since
-- nothing is following it.
local MEDIA_WAIT = 0.6

local media_settle = nil -- running while follower updates may paint the OSD
local media_fallback = nil -- fires only when the follower stayed silent
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
  if media_settle then
    media_fallback = stop_timer(media_fallback)
    osd.media(info)
  end
end)

local function arm_media_osd(player)
  media_settle = stop_timer(media_settle)
  media_settle = gears.timer.start_new(MEDIA_SETTLE, function()
    media_settle = nil
    return false
  end)

  media_fallback = stop_timer(media_fallback)
  media_fallback = gears.timer.start_new(MEDIA_WAIT, function()
    media_fallback = nil

    local cmd = 'playerctl status'
    if player ~= nil then
      cmd = cmd .. ' -p ' .. player
    end

    helpers.async(cmd, function(out)
      osd.media({
        status = out:gsub('%s+$', ''),
        -- An unfollowed player gives us no metadata, so reuse whatever the
        -- follower last knew rather than showing an empty card.
        title = last_media and last_media.title or '',
        artist = last_media and last_media.artist or '',
      })
    end)

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

    if MEDIA_OSD[direction] then
      arm_media_osd(player)
    end
  end
end
