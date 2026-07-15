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

-- flip to true to trace the follow stream + fetch decisions
local debug = false
-- debug print: fires on the module-local flag OR the global printmore master switch
local function dbg(msg)
  if debug or printmore then debug_print(msg, true) end
end

-- ─── config ───────────────────────────────────────────────────────────────────
local CONFIG = {
  player        = 'spotify',
  poll_playing  = 0.5,         -- local clock tick + redraw interval while playing
  no_lyric_text = '…',         -- shown before first timestamped line
  max_width     = dpi(500),    -- max widget width, sizes down to text width
  disable_on_battery = true,   -- stop polling when on battery power
}

-- ─── lyrics cache ─────────────────────────────────────────────────────────────
-- key: "artist - title (duration_s)" → { lines = {{t=seconds, text=string}, ...} }
-- nil value means "tried, no lyrics available"
local lyrics_cache = {}

-- disk cache dir for persisting lyrics across restarts
local cache_dir = os.getenv('HOME') .. '/.cache/awesome-lyrics'
os.execute('mkdir -p ' .. cache_dir)

-- sanitize cache key into safe filename
local function cache_filename(key)
  local safe = key:gsub('[/%z\n\r]', '_'):gsub('[^%w%s%-_%.%(%)]+', '_')
  return cache_dir .. '/' .. safe .. '.lrc'
end

-- write raw LRC string to disk; empty file = no lyrics available
local function cache_write(key, lrc_string)
  local f = io.open(cache_filename(key), 'w')
  if f then
    f:write(lrc_string or '')
    f:close()
  end
end

-- read cached LRC from disk; returns lrc_string, or "" for negative cache, or nil for miss
local function cache_read(key)
  local f = io.open(cache_filename(key), 'r')
  if not f then return nil end
  local content = f:read('*a')
  f:close()
  return content
end

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
  lyrics_paused = true, -- lyrics display paused (starts paused)
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
  if state.fetching then
    dbg('[lyrics] fetch SKIPPED (already fetching) for [' .. artist .. ' - ' .. title .. ']')
    return
  end
  state.fetching = true
  local key = make_cache_key(artist, title, duration)
  dbg('[lyrics] fetch START key=[' .. key .. ']')

  -- check memory cache first
  if lyrics_cache[key] ~= nil then
    dbg('[lyrics] mem cache hit, has_lyrics=' .. tostring(lyrics_cache[key] ~= false))
    if lyrics_cache[key] == false then
      state.lines = nil -- no lyrics available
    else
      state.lines = lyrics_cache[key]
    end
    state.fetching = false
    return
  end

  -- check disk cache before hitting network
  local cached_lrc = cache_read(key)
  if cached_lrc ~= nil then
    dbg('[lyrics] disk cache hit, empty=' .. tostring(cached_lrc == ''))
    if cached_lrc == '' then
      lyrics_cache[key] = false
      state.lines = nil
    else
      local parsed = split_long_lines(parse_lrc(cached_lrc), CONFIG.max_width)
      lyrics_cache[key] = (#parsed > 0) and parsed or false
      state.lines = lyrics_cache[key] or nil
    end
    state.fetching = false
    return
  end

  local dur_s = tostring(math.floor(duration))
  local url = 'https://lrclib.net/api/get?track_name=' .. url_encode(title)
    .. '&artist_name=' .. url_encode(artist)
    .. '&album_name=' .. url_encode(album)
    .. '&duration=' .. dur_s

  local cmd = "curl -sf --connect-timeout 5 --max-time 30 -H 'User-Agent: awesome-lyrics/1.0' '" .. url .. "'"
  dbg('[lyrics] GET ' .. url)

  awful.spawn.easy_async_with_shell(cmd, function(stdout, stderr, reason, exit_code)
    dbg('[lyrics] GET result exit=' .. tostring(exit_code) .. ' len=' ..
      tostring(stdout and #stdout or 0) .. ' has_synced=' ..
      tostring(stdout and json_has_synced_lyrics(stdout) or false))
    if exit_code == 0 and stdout and #stdout > 0 and json_has_synced_lyrics(stdout) then
      local synced = json_extract_string(stdout, 'syncedLyrics')
      if synced and #synced > 0 then
        local parsed = split_long_lines(parse_lrc(synced), CONFIG.max_width)
        dbg('[lyrics] GET parsed ' .. #parsed .. ' lines')
        if #parsed > 0 then
          lyrics_cache[key] = parsed
          cache_write(key, synced)
          state.lines = parsed
          state.fetching = false
          return
        end
      end
    end

    -- /api/get failed or no synced lyrics → try /api/search
    local search_url = 'https://lrclib.net/api/search?track_name=' .. url_encode(title)
      .. '&artist_name=' .. url_encode(artist)
    local search_cmd = "curl -sf --connect-timeout 5 --max-time 30 -H 'User-Agent: awesome-lyrics/1.0' '" .. search_url .. "'"

    dbg('[lyrics] SEARCH ' .. search_url)
    awful.spawn.easy_async_with_shell(search_cmd, function(out2, _, _, exit2)
      dbg('[lyrics] SEARCH result exit=' .. tostring(exit2) .. ' len=' ..
        tostring(out2 and #out2 or 0) .. ' has_synced=' ..
        tostring(out2 and json_has_synced_lyrics(out2) or false))
      if exit2 == 0 and out2 and #out2 > 0 and json_has_synced_lyrics(out2) then
        -- search returns an array; find first entry with syncedLyrics
        local synced2 = json_extract_string(out2, 'syncedLyrics')
        if synced2 and #synced2 > 0 then
          local parsed2 = split_long_lines(parse_lrc(synced2), CONFIG.max_width)
          if #parsed2 > 0 then
            lyrics_cache[key] = parsed2
            cache_write(key, synced2)
            state.lines = parsed2
            state.fetching = false
            return
          end
        end
      end
      -- Distinguish "server confirmed no lyrics" from "request failed". curl
      -- exit 0 means we got a real answer; anything else (28=timeout, DNS, etc.)
      -- is transient and must NOT be negative-cached, or one blip poisons the
      -- track forever.
      if exit2 == 0 then
        dbg('[lyrics] NO LYRICS (server confirmed) key=[' .. key .. '], negative-caching')
        lyrics_cache[key] = false
        cache_write(key, '') -- negative cache on disk too
      else
        dbg('[lyrics] fetch FAILED (curl exit=' .. tostring(exit2) .. ') key=[' .. key .. '], NOT caching')
      end
      state.lines = nil
      state.fetching = false
    end)
  end)
end

-- ─── playerctl queries ────────────────────────────────────────────────────────

-- Parse one line from the `playerctl metadata --follow` stream and update state.
-- Format: artist|||title|||album|||length(us)|||status . An empty line means the
-- player went away. Does not redraw; the caller does that.
local function parse_metadata_line(line)
  dbg('[lyrics] follow line: [' .. tostring(line) .. ']')
  if not line or #line == 0 then
    state.status = 'Stopped'
    state.lines = nil
    return
  end

  local parts = my_utils.split_string(line, '|||')

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

  dbg('[lyrics] parsed key=[' .. new_key .. '] status=[' .. status ..
    '] changed=' .. tostring(new_key ~= state.cache_key) .. ' fetching=' .. tostring(state.fetching))

  -- detect track change
  if new_key ~= state.cache_key then
    state.artist    = artist
    state.title     = title
    state.album     = album
    state.duration  = duration
    state.cache_key = new_key
    state.lines     = nil
    state.current_line_text = CONFIG.no_lyric_text
    state.position  = 0 -- new track starts at 0; resync will correct
    -- fetch lyrics for new track
    fetch_lyrics(artist, title, album, duration)
  end

  state.status = status
end

-- One-shot playback position query, used to anchor/correct the local clock.
-- Position advances continuously with no MPRIS change signal, so it can't be
-- event-driven; we integrate it locally and resync from here occasionally.
local function resync_position(callback)
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
  if state.lyrics_paused then
    lyrictext:set_markup_silently(' ' .. '(lyrics paused)')
    return
  end

  if state.status == 'Stopped' or not state.lines then
    local display_text = CONFIG.no_lyric_text
    if state.lines == nil and state.cache_key ~= '' and not state.fetching then
      -- no lyrics available for this track (fetch completed, confirmed missing)
      display_text = '(no lyrics)'
    end
    lyrictext:set_markup_silently(' ' .. display_text)
    lyrics_tooltip.text = state.artist ~= '' and (state.artist .. ' - ' .. state.title) or ''
    return
  end

  local current = find_current_line(state.lines, state.position)
  local line_text = current and current.text or CONFIG.no_lyric_text
  state.current_line_text = line_text
  lyrictext:set_markup_silently(' ' .. line_text:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'))

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

-- ─── widget visibility ───────────────────────────────────────────────────────
-- hide when no lyrics (complements existing spotify widget)
function lyrics_widget:set_visible_state(visible)
  if visible then
    self.forced_width = nil
  else
    self.forced_width = dpi(0)
  end
end

-- ─── timers & metadata event stream ─────────────────────────────────────────────
-- Event-driven: `playerctl metadata --follow` pushes track/status changes, so we
-- never poll for them. Position has no change signal, so we integrate it locally
-- in a fork-free tick timer and resync from playerctl every RESYNC seconds to
-- correct drift and seeks.

local RESYNC = 5 -- seconds between position resyncs (seek/drift correction)

local display_timer -- local position clock + redraw, no fork
local resync_timer  -- periodic position correction
local vis_timer
local follow_pid = nil
local prev_status = 'Stopped'

-- advance the local position clock and redraw
local function tick()
  if state.status == 'Playing' and not state.lyrics_paused then
    state.position = state.position + CONFIG.poll_playing
  end
  update_display()
end

-- handle one line from the metadata follow stream
local function on_metadata(line)
  parse_metadata_line(line)
  -- anchor the local clock to reality whenever playback (re)starts
  if state.status == 'Playing' and prev_status ~= 'Playing' then
    resync_position(update_display)
  end
  prev_status = state.status
  update_display()
end

local function start_follow()
  if follow_pid then return end
  local cmd = { 'playerctl', '-p', CONFIG.player, 'metadata', '--follow',
                '--format', '{{artist}}|||{{title}}|||{{album}}|||{{mpris:length}}|||{{status}}' }
  follow_pid = awful.spawn.with_line_callback(cmd, {
    stdout = on_metadata,
    exit = function()
      follow_pid = nil
      -- respawn only if we are still meant to be running (e.g. dbus drop)
      if display_timer and display_timer.started then
        gears.timer.start_new(2, function() start_follow() return false end)
      end
    end,
  })
end

local function stop_follow()
  if follow_pid then
    -- SIGTERM (15); matches the `kill -N pid` convention used elsewhere in config
    awful.spawn('kill -15 ' .. tostring(follow_pid))
    follow_pid = nil
  end
end

display_timer = gears.timer({
  timeout = CONFIG.poll_playing,
  autostart = false, -- managed by battery watcher
  callback = tick,
})

resync_timer = gears.timer({
  timeout = RESYNC,
  autostart = false, -- managed by battery watcher
  callback = function()
    -- only worth a fork while actually playing
    if state.status == 'Playing' then resync_position() end
  end,
})

vis_timer = gears.timer({
  timeout = 2,
  autostart = false, -- managed by battery watcher
  callback = function()
    local has_lyrics = state.lines and #state.lines > 0
    local no_lyrics_known = state.lines == nil and state.cache_key ~= '' and not state.fetching
    local is_active = state.status == 'Playing' or state.status == 'Paused'
    lyrics_widget:set_visible_state((has_lyrics or no_lyrics_known) and is_active)
  end,
})

-- start/stop all lyrics machinery
local function start_timers()
  if display_timer.started then return end
  start_follow()
  display_timer:start()
  resync_timer:start()
  vis_timer:start()
  resync_position(update_display) -- immediate anchor
end

local function stop_timers()
  if display_timer.started then display_timer:stop() end
  if resync_timer.started then resync_timer:stop() end
  if vis_timer.started then vis_timer:stop() end
  stop_follow()
  -- clear display
  lyrictext:set_markup_silently('')
  lyrics_widget:set_visible_state(false)
end

-- ─── battery watcher ─────────────────────────────────────────────────────────
-- checks power state every 30s, starts/stops the lyrics machinery accordingly
-- when disable_on_battery is false, just start immediately
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
local spotify_main = require('my_modules/spotify')
lyrics_widget:buttons(gears.table.join(
  awful.button({}, 2, function() -- middle click: toggle lyrics pause
    state.lyrics_paused = not state.lyrics_paused
    update_display()
  end),
  awful.button({}, 3, function() -- right click: toggle spotify client visibility
    spotify_main:raise_toggle()
  end)
))

-- ─── public interface ─────────────────────────────────────────────────────────

-- force a refetch of the current track's lyrics. Track changes are auto-detected
-- by the metadata follow stream, so this is mainly used by clear_cache.
function lyrics_widget:check()
  if state.title ~= '' then
    state.lines = nil
    state.current_line_text = CONFIG.no_lyric_text
    fetch_lyrics(state.artist, state.title, state.album, state.duration)
  end
  resync_position(update_display)
end

-- clear cache (e.g. if lyrics were wrong)
function lyrics_widget:clear_cache()
  lyrics_cache = {}
  os.execute('rm -f ' .. cache_dir .. '/*.lrc')
  self:check()
end

return lyrics_widget
