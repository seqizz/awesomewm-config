-- Notification history.
--
-- naughty notifications disappear when their timeout expires and there is no
-- way to re-read them afterwards. This keeps a ring buffer of everything that
-- passed through naughty and shows it in a keyboard-driven popup.
--
-- The buffer is mirrored to a cache file so it survives an awesome restart
-- (Win+Ctrl+R) or an X crash. Client references cannot be persisted, so
-- entries restored from disk lose their jump-to-client target but keep text.
local awful = require('awful')
local wibox = require('wibox')
local gears = require('gears')
local naughty = require('naughty')
local naughty_reason = require('naughty.constants').notification_closed_reason
local beautiful = require('beautiful')
local my_utils = require('my_modules/my_utils')
local dpi = beautiful.xresources.apply_dpi

local notification_history = {}

-- Tunables
local MAX_ENTRIES = 200 -- ring buffer size, also the on-disk trim target
local VIEWPORT    = 5   -- rows rendered at once; list scrolls inside this
local TEXT_LIMIT  = 140 -- chars before the message column gets truncated
local EDGE_MARGIN = dpi(8)   -- gap from the screen edge when placed top right

-- Row geometry. Every column is forced, and the message column is whatever is
-- left over, so the popup width is fixed no matter what a notification
-- contains. Without this a long message makes the textbox request its natural
-- width and the popup grows off the screen edge.
local POPUP_WIDTH  = dpi(540)
local COL_TIME     = dpi(45)
local COL_APP      = dpi(130)
local COL_MARK     = dpi(20)  -- the '⏎' raise-target marker
local ROW_SPACING  = dpi(8)
local ROW_PADDING  = dpi(10)  -- left/right margin inside a row
local COL_BODY     = POPUP_WIDTH - COL_TIME - COL_APP - COL_MARK
                     - (3 * ROW_SPACING) - (2 * ROW_PADDING)

local CACHE_FILE = gears.filesystem.get_cache_dir() .. 'notification_history'

-- Per-count SVG icons for the wibar badge (numbers/1-square.svg ..
-- numbers/9-square.svg, numbers/plus-square.svg past nine). Icons are dropped
-- in by hand; a missing file just renders as an empty slot until it exists.
local COUNT_ICON_DIR = gears.filesystem.get_configuration_dir()
  .. 'my_modules/assets/numbers/'

-- app_name stamped on this module's own feedback toasts. Recorded notifications
-- carrying it are dropped, otherwise every "No live client" toast would land in
-- the buffer and the popup would fill with its own output.
local SELF_APP = 'notification_history'

-- app_name that config-internal toasts must carry to be recorded. dbus is the
-- only source that stamps freedesktop_hints on a notification (see
-- naughty/dbus.lua), so it is the discriminator between real notifications and
-- naughty-as-popup misuse (lain calendar on hover, OSD-style widgets). Anything
-- without it is dropped unless it opts in under this app_name.
local INTERNAL_APP = 'awesome_internal'

-- Apps whose notification payload is a plaintext secret. Their entries stay in
-- the in-memory list for the session but are never written to the cache file.
local NO_PERSIST_APPS = {
  'rofi%-rbw', 'rbw', 'pass', 'gopass', 'keepassxc', 'bitwarden'
}

-- WM self-chatter: state confirmations that are meaningless once read. Matched
-- against "title text" so they never enter the buffer at all.
-- Patterns are matched against a lowercased haystack, so keep them lowercase.
local IGNORE_PATTERNS = {
  '^sticky set to',
  '^recovering tag:',
  '^suspending client:',
  '^waking up client:',
  '^starting .+ once$',
}

-- Senders to drop entirely, matched against a lowercased app_name. Knob for
-- chatty apps whose toasts are never worth re-reading (e.g. a music player
-- announcing every track change).
local IGNORE_APPS = {
  '^screen_split$', -- Win+F6 split ratio readout, transient by design
  '^pasystray$',
  '^blueman$',
}

-- Dimmed gruvbox gray for secondary text (timestamps, hints, low urgency).
local DIM = '#928374'

-- Urgency -> message color. Resolved lazily: this module is required before
-- beautiful.init() runs in rc.lua, so theme keys are still nil at load time.
local function urgency_fg(urgency)
  if urgency == 'low' then return DIM end
  if urgency == 'critical' then return '#fb4934' end
  return beautiful.fg_normal
end

-- entries[1] is the newest. Prepending is O(n) but n <= MAX_ENTRIES.
local entries = {}
local selected = 1
local offset = 0 -- index of the first rendered row minus one
local hub_connected = false -- SSE stream state, shown in the popup header

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------

-- Truncate by codepoint, not by byte: '#s' would cut multibyte text (Turkish,
-- emoji) mid-sequence and produce an invalid UTF-8 string that pango refuses to
-- render. Lua 5.2 has no utf8 library, so walk the lead bytes by hand.
local function utf8_truncate(s, limit)
  local count, i = 0, 1
  while i <= #s do
    local b = s:byte(i)
    local width = (b < 0x80 and 1) or (b < 0xE0 and 2) or (b < 0xF0 and 3) or 4
    count = count + 1
    if count > limit then return s:sub(1, i - 1) .. '…' end
    i = i + width
  end
  return s
end

-- freedesktop notification bodies may carry a small markup subset (b/i/u/a/
-- img/br, per the spec's "body-markup" capability) plus escaped entities.
-- This history list only ever renders plain text (label() re-escapes for its
-- own colored span), so formatting is stripped rather than interpreted --
-- otherwise the raw tags/entities show up verbatim once xml_escape() runs on
-- them a second time at render time.
local function strip_notification_markup(s)
  if not s or s == '' then return s end
  s = s:gsub('<br%s*/?>', '\n')
  s = s:gsub('</?[biu]>', '')
  s = s:gsub('</?span[^>]*>', '')
  s = s:gsub('<a%s+href="[^"]*"%s*>', ''):gsub('</a>', '')
  s = s:gsub('<img%s+[^>]*/?>', '')
  -- &amp; must decode last, or "&amp;lt;" (an escaped literal "&lt;") would
  -- wrongly collapse all the way down to "<".
  s = s:gsub('&lt;', '<'):gsub('&gt;', '>'):gsub('&quot;', '"'):gsub('&apos;', "'")
  s = s:gsub('&amp;', '&')
  return s
end

-- Collapse a notification body into one displayable line.
local function oneline(s)
  if not s or s == '' then return '' end
  s = s:gsub('%s*\n%s*', ' · '):gsub('%s+', ' ')
  s = s:gsub('^%s*(.-)%s*$', '%1')
  return utf8_truncate(s, TEXT_LIMIT)
end

local function matches_any(text, patterns)
  for _, p in ipairs(patterns) do
    if text:lower():find(p) then return true end
  end
  return false
end

local function relative_time(t)
  local d = os.difftime(os.time(), t)
  if d < 60 then return 'now' end
  if d < 3600 then return math.floor(d / 60) .. 'm' end
  if d < 86400 then return math.floor(d / 3600) .. 'h' end
  return math.floor(d / 86400) .. 'd'
end

-- Single-quote for `sh -c`, safe for newlines and quotes in notification text.
local function shquote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

--------------------------------------------------------------------------------
-- notification-hub integration (linux pre_show client, PLAN.md section 2.2)
--------------------------------------------------------------------------------

-- Everything the remote notification hub needs is configured here. Defaults
-- point at the docker-compose test instance on this machine.
--
-- Pre-show semantics: the hub is asked before the notification is displayed
-- and a 'suppress' answer vetoes display completely -- no popup appears, so
-- nothing has to be cancelled after the fact (cross-device dismissal and
-- crap rules eat the notification here). Fail open: unreachable or slow hub
-- never eats notifications, it just loses its say for that one.
--
-- The call is synchronous and blocks awesome's main loop up to HUB_TIMEOUT
-- seconds per notification. That is the price of deciding before display;
-- the budget is bounded on purpose and on a LAN the round trip is a few ms.
local HUB_URL      = 'http://bother.bigchung.us'
local HUB_TOKEN    = 'ANANASOR4'
local HUB_TIMEOUT  = 2     -- seconds, tolerance budget for the hub answer
local HUB_PRE_SHOW = true  -- false = ask the hub but never veto display

-- Scope for native notification ids. naughty numbers notifications with a
-- counter that restarts at 1 with the WM, while a hub instance now stays open
-- for as long as its row is readable here (see trim_entries). Without a scope,
-- notification 1 after a restart would arrive as the same (device_id,
-- native_id) pair as the still-open instance 1 from before it, and the hub
-- would update that unrelated logical in place instead of creating a new one.
--
-- The timestamp alone collides on a quick restart (Win+Ctrl+R twice within a
-- second), so mix in a table address: ASLR makes it differ between processes.
local HUB_SESSION = tostring(os.time()) .. '-'
  .. (tostring({}):match('0x(%x+)') or '0')

-- Device id, resolved on first use rather than at load time.
--
-- rc.lua requires this module before it sets the `hostname` global, so reading
-- it here directly yields nil: every ingest then posts an empty device_id, the
-- hub rejects it, hub_ingest returns nil, and the client silently degrades to
-- fail-open forever -- no pre-show suppression, no hub ids on any entry, and
-- reconcile falling back to content matching on every row.
local hub_device_cached
local function hub_device()
  if hub_device_cached then return hub_device_cached end
  hub_device_cached = hostname
  if not hub_device_cached or hub_device_cached == '' then
    local f = io.popen('uname -n')
    if f then
      hub_device_cached = f:read('*l')
      f:close()
    end
  end
  -- Last resort: a constant is still better than an empty id, which the hub
  -- refuses outright.
  if not hub_device_cached or hub_device_cached == '' then
    hub_device_cached = 'linux'
  end
  return hub_device_cached
end

-- Remote notifications from other devices, delivered over the hub SSE stream
-- (notification_created). The hub deduplicates before broadcast, so the same
-- message lagging across devices is only ever announced once.
--   'no'    = ignore remote notifications (local only)
--   'yes'   = show them in the history popup
--   'popup' = also fire a normal system popup "$device: ($app) title · body"
local REMOTE_NOTIFICATIONS = 'yes'

-- Minimal JSON string encoding: awesome has no JSON library and the payload
-- is flat strings, so hand-rolling beats adding a dependency.
local function json_escape(s)
  s = tostring(s or '')
  return (s:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' end
    if c == '\\' then return '\\\\' end
    if c == '\n' then return '\\n' end
    if c == '\r' then return '\\r' end
    if c == '\t' then return '\\t' end
    return string.format('\\u%04x', c:byte())
  end))
end

local function json_str(s)
  return '"' .. json_escape(s) .. '"'
end

-- Synchronous hub call. curl owns the timeouts so a wedged hub can never
-- hang the WM past the budget. Returns the response body or nil on failure.
local function hub_request(path, body_json)
  local cmd = table.concat({
    'curl -sS',
    '--connect-timeout ' .. HUB_TIMEOUT,
    '--max-time ' .. HUB_TIMEOUT,
    '-H ' .. shquote('Authorization: Bearer ' .. HUB_TOKEN),
    '-H ' .. shquote('Content-Type: application/json'),
    '-d ' .. shquote(body_json),
    shquote(HUB_URL .. path),
  }, ' ')
  local f = io.popen(cmd, 'r')
  if not f then return nil end
  local out = f:read('*a')
  f:close()
  if not out or out:sub(1, 1) ~= '{' then return nil end
  return out
end

-- Fire-and-forget report (dismiss/removal). Async on purpose: the WM must
-- never wait on these. curl still gets an upper bound so zombies cannot pile
-- up while the hub is down.
local function hub_report_async(path, body_json)
  awful.spawn.easy_async({
    'curl', '-sS',
    '--connect-timeout', '3', '--max-time', '5',
    '-X', 'POST',
    '-H', 'Authorization: Bearer ' .. HUB_TOKEN,
    '-H', 'Content-Type: application/json',
    '-d', body_json or '',
    HUB_URL .. path,
  }, function() end)
end

-- Evict entries past MAX_ENTRIES, telling the hub about each one.
--
-- This is the only moment a notification really leaves this device, and the
-- hub's orphan sweep (AGENTS.md 6.1) depends on hearing about exactly those.
-- A popup timing out is not one of them: it only hides the toast, while the
-- row stays readable here and in the cache file. Reporting a removal there
-- would claim the last copy vanished while it is still sitting unread, and the
-- sweep would then expire it out of the hub's Active list.
--
-- Echoes carry no instance id of their own (section 14.1), so there is nothing
-- to close for them; dropping one is a local affair.
local function trim_entries()
  while #entries > MAX_ENTRIES do
    local e = table.remove(entries)
    if e.hub_instance then
      hub_report_async('/api/v1/instances/' .. e.hub_instance .. '/removed',
        '{"native_reason":"history_evicted"}')
    end
  end
end

-- Bulk resolve for "clear history": one request instead of one curl per
-- entry (the hub caps it at 500 ids per call).
local function hub_bulk_resolve(logical_ids)
  if #logical_ids == 0 then return end
  local parts = {}
  for _, id in ipairs(logical_ids) do parts[#parts + 1] = json_str(id) end
  hub_report_async('/api/v1/notifications/resolve-many',
    '{"kind":"user_dismiss","logical_ids":['
      .. table.concat(parts, ',') .. ']}')
end

-- Async GET for the reconcile pass. cb gets the body or nil on any failure;
-- never blocks the WM.
local function hub_get_async(path, cb)
  awful.spawn.easy_async({
    'curl', '-sS',
    '--connect-timeout', '3', '--max-time', '5',
    '-H', 'Authorization: Bearer ' .. HUB_TOKEN,
    HUB_URL .. path,
  }, function(out)
    if out and out:sub(1, 1) == '{' then cb(out) else cb(nil) end
  end)
end

-- The API responses are flat JSON objects; pattern extraction is enough.
local function parse_field(json, field)
  return json:match('"' .. field .. '":"([^"]*)"')
end

-- Ask the hub about one notification. Returns a metadata table
-- (decision/reason/logical_id/instance_id) or nil when the hub is
-- unreachable or answered garbage.
local function hub_ingest(n, title, text, app, args)
  local native_id = HUB_SESSION .. ':'
    .. tostring((args and args.id) or n.id or tostring(n))
  local urgency = n.urgency or 'normal'
  if urgency == 'critical' then urgency = 'high' end
  local body = table.concat({
    '{',
    '"device_id":' .. json_str(hub_device()),
    ',"client_type":"linux"',
    ',"mode":"pre_show"',
    ',"native_id":' .. json_str(tostring(native_id)),
    ',"app":' .. json_str(app),
    ',"app_name":' .. json_str((args and args.app_name) or n.app_name or app),
    ',"title":' .. json_str(title),
    ',"body":' .. json_str(text),
    ',"urgency":' .. json_str(urgency),
    ',"timestamp":' .. json_str(os.date('!%Y-%m-%dT%H:%M:%SZ')),
    ',"dismissable":true',
    ',"raw":{}',
    '}',
  })
  local out = hub_request('/api/v1/notifications/ingest', body)
  if not out then return nil end
  local meta = {
    decision    = parse_field(out, 'decision'),
    reason      = parse_field(out, 'reason'),
    logical_id  = parse_field(out, 'logical_id'),
    instance_id = parse_field(out, 'instance_id'),
  }
  if not meta.decision then return nil end
  return meta
end

--------------------------------------------------------------------------------
-- count widget
--------------------------------------------------------------------------------

-- Wibar badge with the current buffer size. Swaps an SVG per count, hides
-- itself while the buffer is empty: left click toggles the history popup,
-- middle click clears the buffer.
-- Built lazily: beautiful.init() has not run when this module is required.
local count_widget
local count_image
local count_tooltip

local function ensure_count_widget()
  if count_widget then return count_widget end

  count_image = wibox.widget.imagebox()
  count_image.resize = true
  count_image.forced_height = dpi(20)
  -- Recolor the hand-dropped icons to the wibar foreground instead of showing
  -- their raw black fills, matching the other SVG widgets. Outline art, so
  -- tint the stroke rather than flooding the silhouette.
  count_image.stylesheet = my_utils.svg_stylesheet(beautiful.fg_normal, 'stroke')

  local background_container = wibox.container.background(count_image)
  background_container.shape = function(cr, width, height)
    gears.shape.rounded_rect(cr, width, height, dpi(4))
  end

  count_widget = wibox.container.margin(
    background_container, dpi(1), nil, nil, dpi(2)
  )
  count_tooltip = awful.tooltip { objects = { count_widget }, text = '' }

  count_widget:buttons(gears.table.join(
    awful.button({}, 1, function() notification_history.toggle() end),
    -- Same action as 'C' in the popup.
    awful.button({}, 2, function() notification_history.clear() end)
  ))
  return count_widget
end

-- Drop the badge tooltip without waiting for a mouse::leave. Opening the popup
-- by clicking the badge leaves the pointer sitting on it, so awful.tooltip
-- keeps its label up over the popup the click just opened. It reappears on the
-- next mouse::enter, which needs the pointer to leave the badge first.
local function hide_count_tooltip()
  if count_tooltip then count_tooltip.visible = false end
end

local function refresh_count_widget()
  if not count_widget then return end

  local n = #entries
  if n == 0 then
    count_widget.visible = false
    return
  end

  local icon = (n <= 9) and (n .. '-square') or 'plus-square'
  count_image.image = COUNT_ICON_DIR .. icon .. '.svg'

  -- Check for unread notifications (any entry with seen = false)
  local has_unseen = false
  for i = 1, #entries do
    if not entries[i].seen then
      has_unseen = true
      break
    end
  end

  -- Update tooltip based on unread state
  if has_unseen then
    count_tooltip.text = n .. ' notification' .. (n == 1 and '' or 's')
      .. ' (including unread) in history'
    count_widget.widget.bg = beautiful.warning_bg
  else
    count_tooltip.text = n .. ' notification' .. (n == 1 and '' or 's')
      .. ' in history'
    count_widget.widget.bg = nil
  end

  count_widget.visible = true
end

--------------------------------------------------------------------------------
-- persistence
--------------------------------------------------------------------------------

-- Fields are tab separated; escape so a payload can never forge a field or a
-- record boundary. Backslash first, otherwise the other escapes get mangled.
local function esc(s)
  return (tostring(s or ''):gsub('\\', '\\\\'):gsub('\t', '\\t'):gsub('\n', '\\n'))
end

local function unesc(s)
  return (s:gsub('\\(.)', function(c)
    if c == 't' then return '\t' end
    if c == 'n' then return '\n' end
    return c
  end))
end

-- Optional cache column: a missing or empty field is "not set", not "".
local function unesc_optional(s)
  if not s or s == '' then return nil end
  return unesc(s)
end

local function split_tabs(line)
  local fields, start = {}, 1
  while true do
    local pos = line:find('\t', start, true)
    if not pos then
      fields[#fields + 1] = line:sub(start)
      return fields
    end
    fields[#fields + 1] = line:sub(start, pos - 1)
    start = pos + 1
  end
end

-- Hub ids are persisted along with the text: the instance/logical rows live in
-- the hub database and outlive this process, so a restored entry can still be
-- matched by id during reconcile and still report its dismissal upstream.
-- Without them every entry turns id-less on restart and falls back to content
-- matching, which drops recurring notifications against their own older twins.
local function serialize(e)
  return table.concat({
    tostring(e.time), esc(e.urgency), esc(e.app), esc(e.title), esc(e.text),
    tostring(e.seen or false), esc(e.hub_logical or ''), esc(e.hub_instance or ''),
  }, '\t')
end

local function persistable(e)
  return not matches_any(e.app, NO_PERSIST_APPS)
end

-- Rewrite the whole cache file. Used after delete/clear and on load-trim; the
-- hot path (a new notification) only appends.
local function flush_cache()
  local f = io.open(CACHE_FILE, 'w')
  if not f then return end
  -- Oldest first on disk so a plain `tail` on the file reads chronologically.
  for i = #entries, 1, -1 do
    if persistable(entries[i]) then f:write(serialize(entries[i]), '\n') end
  end
  f:close()
end

local function append_cache(e)
  if not persistable(e) then return end
  local f = io.open(CACHE_FILE, 'a')
  if not f then return end
  f:write(serialize(e), '\n')
  f:close()
end

local function load_cache()
  local f = io.open(CACHE_FILE, 'r')
  if not f then return end
  local loaded = {}
  for line in f:lines() do
    local fields = split_tabs(line)
    if #fields >= 5 and tonumber(fields[1]) then
      -- Prepend: file is oldest-first, entries[] is newest-first.
      table.insert(loaded, 1, {
        time    = tonumber(fields[1]),
        urgency = unesc(fields[2]),
        app     = unesc(fields[3]),
        title   = unesc(fields[4]),
        text    = unesc(fields[5]),
        seen    = (fields[6] or 'false') == 'true',
        -- Absent in cache files written before the ids were persisted, so
        -- these stay nil for old lines and the content fallback still covers
        -- them.
        hub_logical  = unesc_optional(fields[7]),
        hub_instance = unesc_optional(fields[8]),
      })
    end
  end
  f:close()

  entries = loaded
  trim_entries()
  -- Trim the file back down; without this it grows forever across restarts.
  flush_cache()
  refresh_count_widget()
end

--------------------------------------------------------------------------------
-- popup
--------------------------------------------------------------------------------

local popup
local grabber_func   -- installed raw keygrabber callback, nil while not grabbing
local focus_handler  -- client::focus signal, connected on show, disconnected on hide

-- Top right, below the wibar, same corner naughty itself uses, so
-- re-reading history lands where the notifications originally appeared.
-- honor_workarea keeps it in the workarea; the top margin then pushes it one
-- wibar height below the bar so the popup floats clear of it (wibar height
-- read from the workarea delta, so it tracks each screen's bar size).
--
-- Handed to awful.popup as its `placement` property rather than being called
-- manually after showing the popup: awful.popup only learns its real size
-- during the first widget layout pass, so a manual placement call right after
-- `visible = true` computes x from a stale width and lands the window off the
-- right edge. As a property, the popup reapplies it on every resize.
local function place_top_right(d)
  local s = awful.screen.focused()
  local wibar_h = s.geometry.height - s.workarea.height
  awful.placement.top_right(d, {
    parent         = s,
    honor_workarea = true,
    margins        = {
      top    = wibar_h + dpi(5),
      right  = EDGE_MARGIN,
      bottom = EDGE_MARGIN,
      left   = EDGE_MARGIN,
    },
  })
end

-- Built on first use, not at require time: beautiful.init() has not run yet
-- when rc.lua requires this module.
local function ensure_popup()
  if popup then return popup end
  popup = awful.popup {
    ontop         = true,
    visible       = false,
    shape         = gears.shape.rounded_rect,
    border_width  = dpi(1),
    border_color  = beautiful.border_focus,
    bg            = beautiful.bg_normal,
    maximum_width = POPUP_WIDTH,
    minimum_width = POPUP_WIDTH,
    placement     = place_top_right,
    widget        = wibox.widget.textbox(''),
  }
  return popup
end

local function label(text, fg, width, ellipsize)
  return {
    markup       = '<span foreground="' .. fg .. '">' .. gears.string.xml_escape(text) .. '</span>',
    forced_width = width,
    ellipsize    = ellipsize or 'end',
    widget       = wibox.widget.textbox,
  }
end

-- Forward declarations: rows need the actions, actions need render().
-- close_live lives in the hub sync section but act_delete/act_clear also
-- close popups of entries they drop.
local render, act_jump, act_delete, close_live

local function make_row(e, index)
  local is_sel = (index == selected)
  local fg = urgency_fg(e.urgency)
  local body = e.text
  if e.title ~= '' then
    body = (e.text ~= '' and e.title ~= e.text) and (e.title .. ' · ' .. e.text) or e.title
  end

  local row = wibox.widget {
    {
      {
        label(relative_time(e.time), is_sel and beautiful.fg_normal_alt or DIM, COL_TIME),
        label(e.app, is_sel and beautiful.fg_normal_alt or beautiful.fg_normal, COL_APP),
        label(body, is_sel and beautiful.fg_focus or fg, COL_BODY),
        -- Marker for entries that can still raise their source window.
        label((e.client and e.client.valid) and '⏎' or '', DIM, COL_MARK),
        spacing = ROW_SPACING,
        layout  = wibox.layout.fixed.horizontal,
      },
      left = ROW_PADDING, right = ROW_PADDING, top = dpi(3), bottom = dpi(3),
      widget = wibox.container.margin,
    },
    bg     = is_sel and beautiful.bg_focus or beautiful.bg_normal,
    widget = wibox.container.background,
  }

  row:buttons(gears.table.join(
    awful.button({}, 1, function() selected = index; act_jump() end),
    awful.button({}, 3, function() selected = index; act_delete() end)
  ))

  return row
end

-- Announce an empty list instead of rendering an empty popup. A popup with no
-- rows has nothing to constrain its layout and ends up mis-sized off-screen.
local function toast_empty()
  naughty.notification {
    app_name = SELF_APP,
    text     = 'No notifications in history',
    timeout  = 2,
  }
end

render = function()
  -- Callers must not render an empty list; show()/act_delete()/act_clear()
  -- close the popup and toast instead.
  if #entries == 0 then return end

  if selected < 1 then selected = 1 end
  if selected > #entries then selected = #entries end
  -- Keep the selection inside the viewport window.
  if selected <= offset then offset = selected - 1 end
  if selected > offset + VIEWPORT then offset = selected - VIEWPORT end
  if offset < 0 then offset = 0 end

  local rows = { layout = wibox.layout.fixed.vertical }
  for i = offset + 1, math.min(offset + VIEWPORT, #entries) do
    table.insert(rows, make_row(entries[i], i))
  end

  local header = string.format('Notifications  %d/%d   ·   %s', selected, #entries,
    hub_connected and 'hub ✓' or 'hub ✗')
  local footer = 'j/k move · ⏎ raise · y yank · d drop · C clear · click row · Esc/q close'

  ensure_popup():setup {
    {
      {
        label(header, beautiful.fg_normal_alt, nil),
        left = dpi(10), right = dpi(10), top = dpi(6), bottom = dpi(6),
        widget = wibox.container.margin,
      },
      bg     = beautiful.bg_focus,
      widget = wibox.container.background,
    },
    rows,
    {
      {
        label(footer, DIM, nil),
        left = dpi(10), right = dpi(10), top = dpi(4), bottom = dpi(4),
        widget = wibox.container.margin,
      },
      bg     = beautiful.bg_focus,
      widget = wibox.container.background,
    },
    layout = wibox.layout.fixed.vertical,
  }
end

--------------------------------------------------------------------------------
-- actions
--------------------------------------------------------------------------------

function notification_history.hide()
  if grabber_func then
    keygrabber.stop(grabber_func)
    grabber_func = nil
  end
  if focus_handler then
    client.disconnect_signal("focus", focus_handler)
    focus_handler = nil
  end
  if popup then popup.visible = false end
end

act_jump = function()
  local e = entries[selected]
  if not e then return end
  -- Mark this entry as seen after you jump to it
  e.seen = true
  if e.client and e.client.valid then
    notification_history.hide()
    e.client:jump_to()
  else
    -- Nothing to raise (restored from disk, or the notification had no client).
    naughty.notification {
      app_name = SELF_APP,
      text     = 'No live client for this notification',
      timeout  = 2,
    }
  end
end

local function act_yank()
  local e = entries[selected]
  if not e then return end
  local payload = (e.title ~= '' and e.text ~= '') and (e.title .. ': ' .. e.text) or (e.title .. e.text)
  awful.spawn.with_shell('printf %s ' .. shquote(payload) .. ' | xclip -selection clipboard')
  notification_history.hide()
end

act_delete = function()
  local e = entries[selected]
  if not e then return end
  -- Dropping a row means "gone everywhere": tombstone it on the hub so the
  -- other devices drop it too (PLAN.md 2.5). Entries that were shown while
  -- the hub was offline have no ids and stay local-only.
  if e.hub_instance then
    hub_report_async('/api/v1/instances/' .. e.hub_instance .. '/resolve',
      '{"kind":"user_dismiss"}')
  elseif e.hub_logical then
    -- Remote entries have no instance id of their own; resolve the logical.
    hub_report_async('/api/v1/notifications/' .. e.hub_logical .. '/resolve',
      '{"kind":"user_dismiss"}')
  end
  table.remove(entries, selected)
  -- Entry is gone before the destroy, so the 'destroyed' handler cannot
  -- double-report the dismissal we just sent.
  close_live(e)
  flush_cache()
  refresh_count_widget()
  if #entries == 0 then
    notification_history.hide()
    return toast_empty()
  end
  render()
end

local function act_clear()
  -- Same tombstone semantics as act_delete, for the whole buffer: one bulk
  -- request, the hub broadcasts the dismiss events from there.
  local ids = {}
  for _, e in ipairs(entries) do
    if e.hub_logical then ids[#ids + 1] = e.hub_logical end
  end
  hub_bulk_resolve(ids)
  -- Detach first, then close: the 'destroyed' handler must not double-report
  -- what the bulk dismiss already tombstoned.
  local old = entries
  entries = {}
  for _, e in ipairs(old) do close_live(e) end
  flush_cache()
  refresh_count_widget()
  -- The badge is hidden on an empty buffer, so a tooltip opened by hovering it
  -- has nothing left to leave and would otherwise stay on screen.
  hide_count_tooltip()
  notification_history.hide()
end

--------------------------------------------------------------------------------
-- key handling
--------------------------------------------------------------------------------

-- The popup is a wibox and can never take keyboard focus, so a global keygrab
-- is what makes the keys work at all. The raw core `keygrabber` API is used
-- instead of the awful.keygrabber object wrapper: that one refuses to start
-- (silently) whenever it thinks another instance is current, which left the
-- popup open with no keys and no way to close it.
local function handle_key(mod, key)
  local has_shift = false
  for _, m in ipairs(mod) do if m == 'Shift' then has_shift = true end end

  if key == 'j' or key == 'Down' then
    selected = selected + 1
  elseif key == 'k' or key == 'Up' then
    selected = selected - 1
  elseif key == 'Next' then
    selected = selected + VIEWPORT
  elseif key == 'Prior' then
    selected = selected - VIEWPORT
  elseif key == 'Home' or (key == 'g' and not has_shift) then
    selected = 1
  elseif key == 'End' or (key == 'G' or (key == 'g' and has_shift)) then
    selected = #entries
  elseif key == 'Return' then
    return act_jump()
  elseif key == 'y' then
    return act_yank()
  elseif key == 'd' or key == 'Delete' then
    return act_delete()
  elseif key == 'C' then
    -- Uppercase on purpose: clearing everything should not be a single
    -- accidental keystroke away.
    return act_clear()
  else
    return
  end

  render()
end

-- Install the global keygrab. Only handles 'press' events, so the key release
-- of the opening Win+n (grabber is installed during that press) is ignored.
local function grab_keys()
  if grabber_func then return end
  grabber_func = function(mod, key, event)
    if event ~= 'press' then return end
    if key == 'Escape' or key == 'q' or key == 'n' then
      return notification_history.hide()
    end
    handle_key(mod, key)
  end
  keygrabber.run(grabber_func)
end

--------------------------------------------------------------------------------
-- hub sync: retroactive cleanup of already-shown notifications
--------------------------------------------------------------------------------

-- Two paths converge here:
--   1. real-time: the hub's SSE stream reports dismiss/suppress from other
--      devices (or the web UI); the matching live popup is closed and the
--      history row dropped;
--   2. reconcile: periodically and on each new notification, pull the hub's
--      dismissed + crap lists and drop matching entries. This covers what the
--      stream cannot: notifications shown while the hub was offline (fail
--      open) and events missed during a stream outage.
--
-- The reverse direction (local drop/dismiss -> hub) lives in act_delete,
-- act_clear and the 'destroyed' handler above.

local SYNC_INTERVAL   = 60   -- reconcile every N seconds
local SYNC_LIST_LIMIT = 200  -- matches MAX_ENTRIES on the hub side

local debug = false -- flip to true to trace hub sync activity

-- debug print: fires on the module-local flag OR the global printmore master
-- switch (same convention as mpris/mpris_lyrics). Hub sync feedback goes
-- through here so drops are silent in normal use and traceable when needed.
local function dbg(msg)
  if debug or printmore then
    debug_print(msg, true)
  end
end

-- Close a still-visible popup quietly. The entry is removed from `entries`
-- before this runs, so the 'destroyed' handler finds nothing and never
-- reports the hub-driven removal back as a user dismissal (no echo loop).
close_live = function(e)
  local n = e.notification
  if n and n._private and not n._private.is_destroyed then
    -- Silent destroy: hub dismiss/suppress or history clear should not
    -- trigger the notification's run/click callback (the originating
    -- app would interpret that as a user action).
    n:destroy(naughty_reason.silent)
  end
end

-- Remove every entry matching pred; refresh badge/popup/cache when something
-- actually went away. `why` (optional) names the trigger for the debug log.
local function drop_matching(pred, why)
  local removed = 0
  for i = #entries, 1, -1 do
    if pred(entries[i]) then
      close_live(entries[i])
      table.remove(entries, i)
      removed = removed + 1
    end
  end
  if removed == 0 then return end
  flush_cache()
  refresh_count_widget()
  if popup and popup.visible then
    if #entries == 0 then
      notification_history.hide()
    else
      render()
    end
  end
  if why then
    dbg(why .. ': removed ' .. removed .. ' from history')
  end
end

-- Logical ids we already displayed as remote notifications. Used to veto the
-- local copy when the same message lags in from this device later (one popup,
-- never two).
local remote_shown = {}

-- A remote notification from another device. The event carries display fields
-- (server-enriched), so no follow-up fetch is needed. parse_field is the same
-- hand-rolled extractor the rest of the hub sync uses; a title with escaped
-- quotes truncates that field, same accepted limitation as the reconcile pass.
local function handle_remote_notification(data_json)
  local logical = parse_field(data_json, 'logical_id')
  if not logical or logical == '' then return end
  if remote_shown[logical] then return end

  local device_id = parse_field(data_json, 'device_id')
  if device_id and device_id ~= '' and device_id == hub_device() then return end

  local device_name = parse_field(data_json, 'device_name')
  local app         = parse_field(data_json, 'app')
  local app_name    = parse_field(data_json, 'app_name')
  local title       = oneline(parse_field(data_json, 'title') or '')
  local body        = oneline(parse_field(data_json, 'body') or '')

  local device_label = (device_name and device_name ~= '') and device_name
    or (device_id or 'remote')
  local app_label = (app_name and app_name ~= '') and app_name or (app or 'remote')

  local e = {
    time    = os.time(),
    urgency = 'normal',
    app     = oneline(app_label),
    title   = title,
    text    = body,
    client  = nil,
    notification = nil,
    hub_instance = nil,
    hub_logical  = logical,
    seen    = false,
    remote  = true,  -- session-only marker, never serialized to cache
  }
  table.insert(entries, 1, e)
  trim_entries()
  append_cache(e)
  refresh_count_widget()
  if popup and popup.visible then
    if selected > 1 then selected = selected + 1 end
    render()
  end
  remote_shown[logical] = true

  if REMOTE_NOTIFICATIONS == 'popup' then
    local n = naughty.notification {
      app_name = SELF_APP,  -- dropped by record(), so never re-ingested locally
      title    = device_label .. ': (' .. app_label .. ')',
      text     = (title ~= '' and body ~= '') and (title .. ' · ' .. body)
        or (title .. body),
      urgency  = 'normal',
    }
    -- Link the live popup: dropping the history row closes it, and a user
    -- dismissal only marks the entry seen (remote copy, never a tombstone).
    e.notification = n
  end
end

-- An expiry (kind 'expired') is the hub reporting that every copy it knows
-- about went away with nobody finishing it -- an app withdrawing its own
-- notification, or a timeout. It is not somebody dealing with the content, so
-- it may only retract what this device renders on the hub's behalf: an echo
-- of another device's notification (section 14.1), which has no instance id
-- because it was never ingested from here.
--
-- A local entry is kept, popup and all. This device only reports its own copy
-- removed once the row is evicted from the ring buffer (trim_entries), so an
-- expiry naming one of its logicals means some *other* device's copy went
-- away, which says nothing about whether anybody read this one. It leaves on a
-- real resolution, or when the operator clears the row.
--
-- The hub cannot make this call, because only this side knows which rows are
-- echoes and which are its own still-readable history.
local function expiry_may_drop(kind, e)
  if kind ~= 'expired' then return true end
  return not e.hub_instance
end

-- One SSE data frame: resolve (somebody finished with it on another device,
-- by dismissing, clicking or the app withdrawing it) and suppress (a new crap
-- rule covers it now) both mean "stop showing this here".
--
-- 'dismiss' is still accepted so a hub that has not been updated yet keeps
-- working; it was the pre-rename name for the same event.
local function handle_hub_event(data_json)
  local ev_type = parse_field(data_json, 'type')
  if ev_type == 'notification_created' then
    if REMOTE_NOTIFICATIONS ~= 'no' then
      handle_remote_notification(data_json)
    end
    return
  end
  if ev_type ~= 'resolve' and ev_type ~= 'dismiss' and ev_type ~= 'suppress' then return end
  local logical = parse_field(data_json, 'logical_id')
  local instance = parse_field(data_json, 'instance_id')
  local kind = parse_field(data_json, 'kind')
  local why = (ev_type == 'suppress') and 'suppressed by crap rule'
    or ('resolved elsewhere (' .. (kind or 'unknown') .. ')')
  drop_matching(function(e)
    if logical and logical ~= '' and e.hub_logical == logical then
      return expiry_may_drop(kind, e)
    end
    if instance and instance ~= '' and e.hub_instance == instance then return true end
    return false
  end, why)
end

-- Pull flat JSON objects out of a list response ("items": [ {...}, ... ]).
-- Good enough for our own responses: fields are flat and only strings are
-- needed. A title carrying an escaped quote truncates that field, the match
-- then fails and the row waits for manual cleanup - rare, harmless.
local function parse_items(out)
  local items = {}
  for obj in out:gmatch('{([^{}]*)}') do
    local id = obj:match('"id":"([^"]*)"')
    if id then
      items[#items + 1] = {
        id    = id,
        title = obj:match('"canonical_title":"([^"]*)"') or '',
        body  = obj:match('"canonical_body":"([^"]*)"') or '',
        -- 'resolved' and 'expired' both arrive on the resolved list and mean
        -- different things here: see expiry_may_drop. Missing reads as
        -- 'resolved', which is what every hub predating orphan expiry sent.
        state = obj:match('"state":"([^"]*)"') or 'resolved',
        -- Bounds the content fallback below. Always present on list items;
        -- resolved_at would be the closer stamp but is only set once resolved,
        -- and crap items never get one.
        last_seen = obj:match('"last_seen_at":"([^"]*)"') or '',
      }
    end
  end
  return items
end

-- Compare a history entry against a hub list item. Entries the hub knows
-- match by logical id; entries shown while the hub was offline have no ids
-- and match by content within a time window. Local bodies are oneline()-
-- collapsed and truncated to TEXT_LIMIT with a trailing '…', hub bodies are
-- full text, so accept a prefix match in either direction.
local function norm_text(s)
  s = (s or ''):lower():gsub('%s+', ' ')
  return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

-- Hub timestamps are RFC 3339 (UTC in practice). os.time() reads its table as
-- local time, so the local/UTC delta is added back; it is recomputed per call
-- because DST moves it.
local function rfc3339_to_epoch(ts)
  if not ts or ts == '' then return nil end
  local y, mo, d, h, mi, s = ts:match('^(%d+)-(%d+)-(%d+)[Tt ](%d+):(%d+):(%d+)')
  if not y then return nil end
  local epoch = os.time({
    year = tonumber(y), month = tonumber(mo), day = tonumber(d),
    hour = tonumber(h), min = tonumber(mi), sec = tonumber(s), isdst = false,
  })
  if not epoch then return nil end
  local now = os.time()
  epoch = epoch + os.difftime(now, os.time(os.date('!*t', now)))
  -- Numeric zone instead of 'Z' ("+02:00"): shift it back to UTC.
  local sign, oh, om = ts:match('([+%-])(%d%d):?(%d%d)$')
  if sign then
    local shift = tonumber(oh) * 3600 + tonumber(om) * 60
    epoch = epoch + ((sign == '+') and -shift or shift)
  end
  return epoch
end

-- How far apart a history entry and a hub item may be and still count as the
-- same observation. Only id-less entries ever reach this check, and without a
-- bound a recurring notification (same sender, same title, every week) matches
-- its own long-resolved twin and is dropped from history while the hub still
-- lists the new one as active.
local CONTENT_MATCH_WINDOW = 30 * 60

local function content_matches(e, item)
  -- Time gate first: cheaper than the text comparison, and it is what keeps
  -- the recurring-twin case out. An unreadable or missing stamp means "cannot
  -- tell", and not dropping a notification beats dropping the wrong one.
  local item_time = rfc3339_to_epoch(item.last_seen)
  if not item_time or not e.time then return false end
  if math.abs(os.difftime(item_time, e.time)) > CONTENT_MATCH_WINDOW then return false end
  if norm_text(e.title) ~= norm_text(item.title) then return false end
  local eb = norm_text(e.text):gsub('…$', '')
  local sb = norm_text(item.body)
  if eb == '' then return sb == '' end
  return sb:sub(1, #eb) == eb or eb:sub(1, #sb) == sb
end

local reconcile_pending = false

local function reconcile_with_hub()
  if reconcile_pending or #entries == 0 then return end
  reconcile_pending = true
  -- Deadman switch: a curl that never spawns means no callback ever arrives,
  -- and the flag would otherwise disable re-checking forever.
  gears.timer.start_new(20, function()
    reconcile_pending = false
    return false
  end)

  local lists, got = {}, 0
  local function finish()
    reconcile_pending = false
    if #lists == 0 then return end
    drop_matching(function(e)
      for _, item in ipairs(lists) do
        -- An expired item is the catch-up form of the kind='expired' event,
        -- so it gets the same restriction: echoes only, never a local row
        -- that may still be unread.
        if e.hub_logical and e.hub_logical == item.id then
          if expiry_may_drop(item.state, e) then return true end
        elseif not e.hub_logical and content_matches(e, item) then
          -- Id-less rows are matched by content alone. An expired item is too
          -- weak a signal to drop one on: it says nothing about whether the
          -- operator read this.
          if item.state ~= 'expired' then return true end
        end
      end
      return false
    end, 'hub sync')
  end
  local function on_list(out)
    if out then
      for _, item in ipairs(parse_items(out)) do lists[#lists + 1] = item end
    end
    got = got + 1
    if got == 2 then finish() end
  end

  hub_get_async('/api/v1/notifications?state=resolved&limit=' .. SYNC_LIST_LIMIT, on_list)
  hub_get_async('/api/v1/notifications?state=crap&limit=' .. SYNC_LIST_LIMIT, on_list)
end

-- Debounced reconcile trigger for the record() path ("ask again about kept
-- notifications on each new one"): notification bursts must not stack list
-- requests.
local reconcile_wakeup = nil

local function schedule_reconcile(delay)
  if reconcile_wakeup then reconcile_wakeup:stop() end
  reconcile_wakeup = gears.timer.start_new(delay or 10, function()
    reconcile_wakeup = nil
    reconcile_with_hub()
    return false
  end)
end

-- Consume the hub's SSE stream so dismissals made elsewhere close live popups
-- and drop history rows here in real time. curl -N keeps the stream
-- unbuffered; --max-time churns the connection so a half-dead stream cannot
-- pin itself forever. Frames arrive as "event: <type>", "data: <json>",
-- blank line; only data lines matter (the event name is inside the JSON).
local stream_gen = 0

local function start_hub_stream()
  stream_gen = stream_gen + 1
  local my_gen = stream_gen
  awful.spawn.with_line_callback({
    'curl', '-sSN',
    '--connect-timeout', '5',
    '--max-time', '600',
    '-H', 'Authorization: Bearer ' .. HUB_TOKEN,
    HUB_URL .. '/api/v1/events/stream',
  }, {
    stdout = function(line)
      if my_gen ~= stream_gen then return end
      hub_connected = true
      if line:sub(1, 6) == 'data: ' then
        handle_hub_event(line:sub(7))
      end
    end,
    stderr = function() end, -- curl -S messages are noise here
    exit = function(reason, code)
      if my_gen ~= stream_gen then return end
      hub_connected = false
      -- Includes the healthy --max-time churn every 10 minutes, so this is
      -- informational only. Reconnect shortly and reconcile to catch
      -- whatever was broadcast while the stream was down.
      dbg('hub stream exit (' .. tostring(reason) .. '/' .. tostring(code)
        .. '), reconnecting')
      gears.timer.start_new(5, function()
        if my_gen == stream_gen then
          start_hub_stream()
          reconcile_with_hub()
        end
        return false
      end)
    end,
  })
end

--------------------------------------------------------------------------------
-- recording
--------------------------------------------------------------------------------

-- Shared pre-flight filter. Returns cleaned (title, text, app) for
-- notifications worth tracking, nil for everything dropped (internal popups,
-- self-chatter, ignored senders). Both the hub gate and record() go through
-- it, so the two can never disagree about what is a real notification.
--
-- freedesktop_hints lives in _private (no getter exists for it), so access
-- it defensively in case a future awesome version renames the field.
local function tracked_fields(n, args)
  -- Our own feedback toasts must never be recorded, or acting on an entry
  -- appends a new entry and the buffer grows on every keypress.
  if n.app_name == SELF_APP then return end

  if not (n._private and n._private.freedesktop_hints)
     and n.app_name ~= INTERNAL_APP then
    return
  end

  local title = oneline(strip_notification_markup((args and args.title) or n.title))
  local text = oneline(strip_notification_markup(
    (args and (args.message or args.text)) or n.message or n.text))
  if title == '' and text == '' then return end
  if matches_any(title .. ' ' .. text, IGNORE_PATTERNS) then return end

  local app = (args and args.app_name) or n.app_name
  if not app or app == '' then app = 'awesome' end
  if matches_any(app, IGNORE_APPS) then return end

  return title, text, app
end

local function record(n, args)
  local title, text, app = tracked_fields(n, args)
  if not title then return end

  -- Pre-show hub gate. 'added' is emitted synchronously right before naughty
  -- decides whether to display (request::display/fallback), and that decision
  -- reads n.ignore afterwards: setting it here is the veto, the notification
  -- is never shown and there is nothing to cancel later. The deferred destroy
  -- is belt and braces for naughty versions that cache the flag earlier --
  -- worst case a suppression flashes for one loop iteration instead of
  -- lingering. If the hub is unreachable or slow past HUB_TIMEOUT, the
  -- notification is shown (fail open).
  local meta = hub_ingest(n, title, text, app, args)

  -- Dedup against a remote copy already shown this session: the same message
  -- lagged in from another device first. popup mode already notified via the
  -- remote popup, so veto the local copy; yes mode only mirrored it, so drop
  -- the mirror and record the real local notification (with its live client).
  if meta and meta.logical_id and remote_shown[meta.logical_id] then
    if REMOTE_NOTIFICATIONS == 'popup' then
      n._hub_veto = true
      n.ignore = true
      gears.timer.delayed_call(function()
        if n._private and not n._private.is_destroyed then
          n:destroy(naughty_reason.silent)
        end
      end)
      return
    end
    drop_matching(function(e)
      return e.remote and e.hub_logical == meta.logical_id
    end)
    remote_shown[meta.logical_id] = nil
  end

  -- Veto destroys use the 'silent' reason on purpose. The default reason is
  -- dismissed_by_user, which rc.lua's click-to-jump hack reads as "the user
  -- clicked this popup" and answers by raising the source (or, with no client
  -- attached, the latest urgent one). A notification the user never even saw
  -- must not move focus, so suppression stays silent.
  --
  -- A suppression is never shown and never recorded. There is no
  -- silent-but-recorded case: the hub only ever answers suppress for a
  -- resolution you already dealt with elsewhere or a crap rule you wrote.
  if meta and HUB_PRE_SHOW and meta.decision == 'suppress' then
    n._hub_veto = true
    n.ignore = true
    gears.timer.delayed_call(function()
      if n._private and not n._private.is_destroyed then
        n:destroy(naughty_reason.silent)
      end
    end)
    return
  end

  -- First still-valid client naughty associated with the notification, so the
  -- entry can raise its source window later.
  local target
  if n.clients then
    for _, c in ipairs(n.clients) do
      if c and c.valid then target = c break end
    end
  end

  table.insert(entries, 1, {
    time    = os.time(),
    urgency = n.urgency or 'normal',
    app     = oneline(app),
    title   = title,
    text    = text,
    client  = target,
    -- Kept only to match this entry against naughty's 'destroyed' signal
    -- below, so dismissing the popup itself marks it seen. Not persisted:
    -- entries reloaded from disk never had a live notification anyway.
    notification = n,
    -- Hub ids from the pre-show answer, used to report dismissal/removal back
    -- and to match this entry during reconcile. Unlike `notification` these
    -- are persisted: the hub rows outlive the WM, so dropping a restored entry
    -- still has somewhere to report to.
    hub_instance = meta and meta.instance_id,
    hub_logical  = meta and meta.logical_id,
    seen    = false,  -- track whether this notification was viewed
  })
  trim_entries()

  append_cache(entries[1])
  refresh_count_widget()

  if popup and popup.visible then
    -- A new entry shifts everything down; follow the selection so the popup
    -- does not silently jump to a different notification under the cursor.
    if selected > 1 then selected = selected + 1 end
    render()
  end

  -- New notifications are a cheap trigger to re-check what we still show:
  -- exactly the moment stale entries (offline-shown, stream-outage) are most
  -- annoying. Debounced.
  schedule_reconcile(10)
end

--------------------------------------------------------------------------------
-- public API
--------------------------------------------------------------------------------

function notification_history.show()
  if #entries == 0 then return toast_empty() end

  -- Opening the popup is a natural "show me the truth now" moment: run the
  -- reconcile shortly after so stale rows do not survive a popup session.
  schedule_reconcile(1)

  selected, offset = 1, 0
  -- Mark all entries as seen when popup opens (scroll, Win+n, etc.)
  for i = 1, #entries do
    entries[i].seen = true
  end
  refresh_count_widget()
  hide_count_tooltip()
  render()
  local p = ensure_popup()
  p.visible = true
  -- Reassigning the placement property forces a resize-and-reposition pass, so
  -- the popup follows the currently focused screen when reopened elsewhere.
  p.placement = place_top_right
  grab_keys()

  -- Close the popup when the user focuses another client (clicks a window
  -- outside the popup). The handler is replaced on each show() call so
  -- there's never more than one connection active.
  if focus_handler then
    client.disconnect_signal("focus", focus_handler)
  end
  focus_handler = function(c) notification_history.hide() end
  client.connect_signal("focus", focus_handler)
end

function notification_history.toggle()
  if popup and popup.visible then
    notification_history.hide()
  else
    notification_history.show()
  end
end

function notification_history.widget()
  local w = ensure_count_widget()
  refresh_count_widget()
  return w
end

-- Badge middle-click wrapper. act_clear is a chunk-local declared after the
-- widget builder, so the button closure cannot see it lexically (locals are
-- visible only from their declaration point); route through the table.
function notification_history.clear()
  act_clear()
end

-- Exposed for other widgets/scripts that may want the raw list.
function notification_history.get_entries()
  return entries
end

-- Config-internal toasts wanting a history entry must use this app_name.
notification_history.internal_app = INTERNAL_APP

load_cache()
naughty.connect_signal('added', function(n, args) record(n, args) end)

-- Dismissing the popup you actually saw should not leave the badge red. Only
-- dismissed_by_user counts: a timeout expiry means the user never necessarily
-- looked at it, so that case is left for the history popup to mark seen.
--
-- This is also where the hub learns that a notification was finished with
-- locally, which propagates the cancel to every device (AGENTS.md 6). Reports
-- are async and only fire for entries the hub pre-approved (hub_instance set),
-- so a suppression here can never echo back to the server as a resolution.
--
-- Kind is always 'click'. naughty.layout.box binds mouse button 1 to
-- dismissed_by_user and button 3 to silent, so the only way to reach this
-- handler through the popup is by clicking it, which is exactly the signal the
-- hub's strongest resolution kind describes. Swiping-style dismissal has no
-- equivalent here; the history popup's own delete reports user_dismiss.
--
-- A timeout expiry is deliberately NOT reported. On this client the popup is
-- not the notification: when it times out the row stays in `entries`, readable
-- with the history popup and persisted to the cache file. Reporting a removal
-- here would tell the hub that the last copy of a desktop-only notification is
-- gone, and its orphan sweep would expire the logical out of the Active list
-- minutes later while the text is still sitting here unread. The copy leaves
-- this device when the row leaves the ring buffer, which is where
-- trim_entries() reports it.
--
-- Every other reason is left alone. 'silent' in particular is what the hub
-- sync itself destroys popups with, and close_live() removes the entry from
-- `entries` before destroying, so the loop below cannot find it and a
-- server-driven cancel can never echo back as a local report.
naughty.connect_signal('destroyed', function(n, reason)
  if reason ~= naughty_reason.dismissed_by_user then
    return
  end
  for i = 1, #entries do
    if entries[i].notification == n then
      entries[i].seen = true
      if entries[i].hub_instance then
        hub_report_async(
          '/api/v1/instances/' .. entries[i].hub_instance .. '/resolve',
          '{"kind":"click"}')
      end
      refresh_count_widget()
      if popup and popup.visible then render() end
      return
    end
  end
end)

-- Hub sync startup: live event stream immediately, first reconcile delayed
-- (does not race network bring-up), then periodic.
start_hub_stream()
gears.timer.start_new(5, function() reconcile_with_hub() return false end)
gears.timer.start_new(SYNC_INTERVAL, function() reconcile_with_hub() return true end)

return notification_history
-- vim: set ts=2 sw=2 tw=0 et :
