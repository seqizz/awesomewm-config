-- spotify_lyrics.lua - synced lyrics widget using LRCLIB + playerctl
-- Shows current lyric line for Spotify, non-blocking via async spawns.
--
-- Dependencies:
--   playerctl  (MPRIS client)
--   curl       (HTTP requests to lrclib.net)
--   awesome libs: awful, wibox, gears, naughty

local awful = require('awful')
local wibox = require('wibox')
local gears = require('gears')
local naughty = require('naughty')
local my_theme = require('my_modules/my_theme')
local my_utils = require('my_modules/my_utils')
local dpi = require('beautiful').xresources.apply_dpi

-- ─── config ───────────────────────────────────────────────────────────────────
local CONFIG = {
  player        = 'spotify',
  poll_playing  = 0.5,         -- seconds between position polls while playing
  poll_paused   = 5,           -- seconds between polls while paused/stopped
  no_lyric_text = '…',         -- shown before first timestamped line
  max_width     = dpi(500),    -- max widget width, sizes down to text width
  disable_on_battery = true,   -- stop polling when on battery power
}

-- ─── lyrics cache ─────────────────────────────────────────────────────────────
-- key: "artist - title (duration_s)" → { lines = {{t=seconds, text=string}, ...} }
-- nil value means "tried, no lyrics available"
local lyrics_cache = {}

-- ─── state ────────────────────────────────────────────────────────────────────
local state = {
  artist    = '',
  title     = '',
  album     = '',
  duration  = 0,        -- seconds
  position  = 0,        -- seconds
  status    = 'Stopped', -- Playing / Paused / Stopped
  cache_key = '',
  lines     = nil,      -- parsed LRC lines for current track (sorted)
  current_line_text = CONFIG.no_lyric_text,
  fetching  = false,    -- prevent duplicate fetches
}

-- ─── widget ───────────────────────────────────────────────────────────────────
local lyrictext = wibox.widget.textbox()
lyrictext.align = 'right'
lyrictext.valign = 'center'
lyrictext.font = my_theme.font

-- fixed-width container: always occupies max_width, text changes inside
local lyrics_widget = wibox.widget({
  lyrictext,
  widget = wibox.container.constraint,
  strategy = 'exact',
  width = CONFIG.max_width,
})

-- no-op tooltip stub (keeps rest of code simple, just discards text)
local lyrics_tooltip = { text = '' }

-- ─── helpers ──────────────────────────────────────────────────────────────────

-- URL-encode a string for use in query params
local function url_encode(str)
  str = str:gsub('\n', '\r\n')
  str = str:gsub('([^%w _~%.%-])', function(c)
    return string.format('%%%02X', string.byte(c))
  end)
  str = str:gsub(' ', '+')
  return str
end

-- Build cache key from metadata
local function make_cache_key(artist, title, duration)
  return artist .. ' - ' .. title .. ' (' .. tostring(math.floor(duration)) .. ')'
end

-- Parse LRC synced lyrics string into sorted list of {t=seconds, text=string}
local function parse_lrc(lrc_string)
  local lines = {}
  for line in lrc_string:gmatch('[^\r\n]+') do
    -- match all [mm:ss.xx] timestamps before the text
    local text = line:gsub('%[%d+:%d+%.?%d*%]', '')
    text = text:match('^%s*(.-)%s*$') -- trim
    for mm, ss, cs in line:gmatch('%[(%d+):(%d+)%.?(%d*)%]') do
      local t = tonumber(mm) * 60 + tonumber(ss)
      if cs and cs ~= '' then
        -- handle both .xx (centiseconds) and .xxx (milliseconds)
        if #cs <= 2 then
          t = t + tonumber(cs) / 100
        else
          t = t + tonumber(cs) / 1000
        end
      end
      table.insert(lines, { t = t, text = text })
    end
  end
  -- sort by timestamp
  table.sort(lines, function(a, b) return a.t < b.t end)
  return lines
end

-- Measure text pixel width using a scratch textbox with same font
local _measure_tb = wibox.widget.textbox()
_measure_tb.font = my_theme.font
local function measure_text_width(text)
  _measure_tb:set_text(text)
  local w, _ = _measure_tb:get_preferred_size(screen.primary)
  return w or 0
end

-- Split long lines into word-wrapped chunks that fit within max_width.
-- Each chunk gets a proportionally interpolated timestamp between
-- this line's time and the next line's time.
local function split_long_lines(lines, max_width)
  local result = {}
  for i, entry in ipairs(lines) do
    local text_w = measure_text_width(entry.text)
    if text_w <= max_width or entry.text == '' then
      -- fits, keep as-is
      table.insert(result, entry)
    else
      -- next line's timestamp (or +5s if last line)
      local next_t = (lines[i + 1] and lines[i + 1].t) or (entry.t + 5)
      local time_window = next_t - entry.t

      -- split text into words, greedily fill chunks that fit
      local words = {}
      for w in entry.text:gmatch('%S+') do
        table.insert(words, w)
      end

      local chunks = {}
      local current_chunk = ''
      for _, word in ipairs(words) do
        local candidate = current_chunk == '' and word or (current_chunk .. ' ' .. word)
        if measure_text_width(candidate) <= max_width then
          current_chunk = candidate
        else
          if current_chunk ~= '' then
            table.insert(chunks, current_chunk)
          end
          current_chunk = word
        end
      end
      if current_chunk ~= '' then
        table.insert(chunks, current_chunk)
      end

      -- distribute timestamps proportionally across chunks
      local n = #chunks
      for ci, chunk in ipairs(chunks) do
        local chunk_t = entry.t + (ci - 1) * (time_window / n)
        table.insert(result, { t = chunk_t, text = chunk })
      end
    end
  end
  return result
end

-- Find current lyric line given position in seconds
local function find_current_line(lines, pos)
  if not lines or #lines == 0 then return nil end
  local result = nil
  for _, entry in ipairs(lines) do
    if entry.t <= pos then
      result = entry
    else
      break
    end
  end
  return result
end

-- Find next lyric line after current position
local function find_next_line(lines, pos)
  if not lines or #lines == 0 then return nil end
  for _, entry in ipairs(lines) do
    if entry.t > pos then
      return entry
    end
  end
  return nil
end

-- Truncate string to max_chars
local function truncate(str, max)
  if not str then return '' end
  if #str > max then
    return str:sub(1, max - 1) .. '…'
  end
  return str
end

-- Simple JSON string value extractor (avoids needing a JSON lib)
-- Handles escaped quotes within values
local function json_extract_string(json_str, key)
  -- pattern: "key":"value" or "key": "value"
  local pattern = '"' .. key .. '"%s*:%s*"'
  local start = json_str:find(pattern)
  if not start then return nil end
  -- find opening quote of value
  local val_start = json_str:find('"%s*$', start)
  -- actually let's be more precise
  local _, quote_pos = json_str:find(pattern)
  if not quote_pos then return nil end
  -- now read until unescaped closing quote
  local i = quote_pos + 1
  local result = {}
  while i <= #json_str do
    local c = json_str:sub(i, i)
    if c == '\\' then
      -- escaped char
      i = i + 1
      local nc = json_str:sub(i, i)
      if nc == 'n' then
        table.insert(result, '\n')
      elseif nc == 't' then
        table.insert(result, '\t')
      elseif nc == '"' then
        table.insert(result, '"')
      elseif nc == '\\' then
        table.insert(result, '\\')
      else
        table.insert(result, nc)
      end
    elseif c == '"' then
      break
    else
      table.insert(result, c)
    end
    i = i + 1
  end
  return table.concat(result)
end

-- Check if JSON has "syncedLyrics": null (no synced lyrics)
local function json_has_synced_lyrics(json_str)
  if json_str:find('"syncedLyrics"%s*:%s*null') then return false end
  if json_str:find('"syncedLyrics"%s*:%s*"') then return true end
  return false
end

-- ─── LRCLIB fetch ─────────────────────────────────────────────────────────────

-- Try /api/get first, fall back to /api/search
local function fetch_lyrics(artist, title, album, duration)
  if state.fetching then return end
  state.fetching = true
  local key = make_cache_key(artist, title, duration)

  -- check cache first
  if lyrics_cache[key] ~= nil then
    if lyrics_cache[key] == false then
      state.lines = nil -- no lyrics available
    else
      state.lines = lyrics_cache[key]
    end
    state.fetching = false
    return
  end

  local dur_s = tostring(math.floor(duration))
  local url = 'https://lrclib.net/api/get?track_name=' .. url_encode(title)
    .. '&artist_name=' .. url_encode(artist)
    .. '&album_name=' .. url_encode(album)
    .. '&duration=' .. dur_s

  local cmd = "curl -sf --max-time 5 -H 'User-Agent: awesome-lyrics/1.0' '" .. url .. "'"

  awful.spawn.easy_async_with_shell(cmd, function(stdout, stderr, reason, exit_code)
    if exit_code == 0 and stdout and #stdout > 0 and json_has_synced_lyrics(stdout) then
      local synced = json_extract_string(stdout, 'syncedLyrics')
      if synced and #synced > 0 then
        local parsed = split_long_lines(parse_lrc(synced), CONFIG.max_width)
        if #parsed > 0 then
          lyrics_cache[key] = parsed
          state.lines = parsed
          state.fetching = false
          return
        end
      end
    end

    -- /api/get failed or no synced lyrics → try /api/search
    local search_url = 'https://lrclib.net/api/search?track_name=' .. url_encode(title)
      .. '&artist_name=' .. url_encode(artist)
    local search_cmd = "curl -sf --max-time 5 -H 'User-Agent: awesome-lyrics/1.0' '" .. search_url .. "'"

    awful.spawn.easy_async_with_shell(search_cmd, function(out2, _, _, exit2)
      if exit2 == 0 and out2 and #out2 > 0 and json_has_synced_lyrics(out2) then
        -- search returns an array; find first entry with syncedLyrics
        local synced2 = json_extract_string(out2, 'syncedLyrics')
        if synced2 and #synced2 > 0 then
          local parsed2 = split_long_lines(parse_lrc(synced2), CONFIG.max_width)
          if #parsed2 > 0 then
            lyrics_cache[key] = parsed2
            state.lines = parsed2
            state.fetching = false
            return
          end
        end
      end
      -- no lyrics found at all
      lyrics_cache[key] = false
      state.lines = nil
      state.fetching = false
    end)
  end)
end

-- ─── playerctl queries ────────────────────────────────────────────────────────

-- Fetch metadata + status in one shot
local function update_metadata(callback)
  local cmd = "playerctl -p " .. CONFIG.player .. " metadata --format "
    .. "'{{artist}}|||{{title}}|||{{album}}|||{{mpris:length}}|||{{status}}' 2>/dev/null"

  awful.spawn.easy_async_with_shell(cmd, function(stdout, stderr, reason, exit_code)
    if exit_code ~= 0 or not stdout or #stdout == 0 then
      state.status = 'Stopped'
      state.lines = nil
      if callback then callback() end
      return
    end

    local parts = my_utils.split_string(stdout, '|||')

    -- trim whitespace and newlines from each field
    local function trim(s) return (s or ''):match('^%s*(.-)%s*$') end
    local artist   = trim(parts[1])
    local title    = trim(parts[2])
    local album    = trim(parts[3])
    local length   = tonumber(trim(parts[4])) or 0 -- microseconds
    local status   = trim(parts[5])
    if status == '' then status = 'Stopped' end

    local duration = length / 1000000 -- convert to seconds
    local new_key  = make_cache_key(artist, title, duration)

    -- detect track change
    if new_key ~= state.cache_key then
      state.artist    = artist
      state.title     = title
      state.album     = album
      state.duration  = duration
      state.cache_key = new_key
      state.lines     = nil
      state.current_line_text = CONFIG.no_lyric_text
      -- fetch lyrics for new track
      fetch_lyrics(artist, title, album, duration)
    end

    state.status = status
    if callback then callback() end
  end)
end

-- Fetch current playback position
local function update_position(callback)
  -- LC_NUMERIC=C forces period as decimal separator
  local cmd = "LC_NUMERIC=C playerctl -p " .. CONFIG.player .. " position 2>/dev/null"
  awful.spawn.easy_async_with_shell(cmd, function(stdout, stderr, reason, exit_code)
    if exit_code == 0 and stdout and #stdout > 0 then
      -- manual parse: split on period, compute seconds + fraction
      local int_s, frac_s = stdout:match('(%d+)%.?(%d*)')
      state.position = (tonumber(int_s) or 0) + (tonumber(frac_s) or 0) / (10 ^ #(frac_s or ''))
    end
    if callback then callback() end
  end)
end

-- ─── display update ───────────────────────────────────────────────────────────

local function update_display()
  if state.status == 'Stopped' or not state.lines then
    local display_text = CONFIG.no_lyric_text
    if state.lines == nil and state.cache_key ~= '' then
      -- no lyrics available for this track
      display_text = ''
    end
    lyrictext:set_markup_silently(' ' .. awful.util.escape(display_text))
    lyrics_tooltip.text = state.artist ~= '' and (state.artist .. ' - ' .. state.title) or ''
    return
  end

  local current = find_current_line(state.lines, state.position)
  local line_text = current and current.text or CONFIG.no_lyric_text
  state.current_line_text = line_text
  lyrictext:set_markup_silently(' ' .. awful.util.escape(line_text))

  -- tooltip: artist - title + next line preview
  local tip = state.artist .. ' - ' .. state.title
  local next_line = find_next_line(state.lines, state.position)
  if next_line and next_line.text ~= '' then
    tip = tip .. '\n\nNext: ' .. next_line.text
  end
  lyrics_tooltip.text = tip
end

-- ─── battery check ────────────────────────────────────────────────────────────

local function is_on_battery()
  -- check AC power supply status; returns true if discharging
  local f = io.open('/sys/class/power_supply/AC/online', 'r')
  if not f then f = io.open('/sys/class/power_supply/AC0/online', 'r') end
  if not f then f = io.open('/sys/class/power_supply/ACAD/online', 'r') end
  if f then
    local val = f:read('*l')
    f:close()
    return val == '0'
  end
  return false -- no AC sysfs found, assume plugged in
end

-- ─── main poll loop ───────────────────────────────────────────────────────────

local poll_timer
local vis_timer

local function poll()
  update_metadata(function()
    update_position(function()
      update_display()
    end)
  end)
end

-- adaptive timer: fast while playing, slow while paused
local function adjust_timer()
  if not poll_timer then return end
  local target = state.status == 'Playing' and CONFIG.poll_playing or CONFIG.poll_paused
  if poll_timer.timeout ~= target then
    poll_timer.timeout = target
    poll_timer:again()
  end
end

-- ─── widget visibility ───────────────────────────────────────────────────────
-- hide when no lyrics (complements existing spotify widget)
function lyrics_widget:set_visible_state(visible)
  if visible then
    self.forced_width = nil
  else
    self.forced_width = dpi(0)
  end
end

-- start/stop all lyrics timers
local function start_timers()
  if poll_timer and not poll_timer.started then
    poll_timer:start()
    poll() -- immediate first poll
  end
  if vis_timer and not vis_timer.started then
    vis_timer:start()
  end
end

local function stop_timers()
  if poll_timer and poll_timer.started then poll_timer:stop() end
  if vis_timer and vis_timer.started then vis_timer:stop() end
  -- clear display
  lyrictext:set_markup_silently('')
  lyrics_widget:set_visible_state(false)
end

poll_timer = gears.timer({
  timeout = CONFIG.poll_playing,
  autostart = false, -- managed by battery watcher
  callback = function()
    poll()
    adjust_timer()
  end,
})

vis_timer = gears.timer({
  timeout = 2,
  autostart = false, -- managed by battery watcher
  callback = function()
    local has_lyrics = state.lines and #state.lines > 0
    local is_active = state.status == 'Playing' or state.status == 'Paused'
    lyrics_widget:set_visible_state(has_lyrics and is_active)
  end,
})

-- ─── battery watcher ─────────────────────────────────────────────────────────
-- checks power state every 30s, starts/stops poll timers accordingly
-- when disable_on_battery is false, just start timers immediately
if CONFIG.disable_on_battery then
  gears.timer({
    timeout = 30,
    autostart = true,
    call_now = true,
    callback = function()
      if is_on_battery() then
        stop_timers()
      else
        start_timers()
      end
    end,
  })
else
  start_timers()
end

-- ─── click handlers ───────────────────────────────────────────────────────────
-- right-click: toggle spotify client visibility (reuse main spotify widget logic)
local spotify_main = require('my_modules/spotify')
lyrics_widget:buttons(awful.util.table.join(
  awful.button({}, 3, function() -- right click
    spotify_main:raise_toggle()
  end)
))

-- ─── public interface ─────────────────────────────────────────────────────────

-- force re-check (e.g. on track skip)
function lyrics_widget:check()
  state.cache_key = '' -- force refetch on next poll
  poll()
end

-- clear cache (e.g. if lyrics were wrong)
function lyrics_widget:clear_cache()
  lyrics_cache = {}
  self:check()
end

return lyrics_widget
