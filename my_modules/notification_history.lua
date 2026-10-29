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
local nnotif = require('naughty.notification')
local lgi = require('lgi')
local Gio, GLib = lgi.Gio, lgi.GLib
local beautiful = require('beautiful')
local my_utils = require('my_modules/my_utils')
local dpi = beautiful.xresources.apply_dpi

local notification_history = {}

-- Reasons meaning "the app that posted this took it back", as opposed to the
-- popup merely going away.
--
-- The freedesktop spec fixes 3 for "closed by a call to CloseNotification" and
-- that is the value arriving over the wire, so it is listed outright; the
-- naughty constant is added when present because the two should agree and a
-- local build is the authority if they ever do not. Listing the raw 3 is safe
-- even on a naughty that happens to use it for something internal, because
-- every close this module initiates is marked (`_hub_closed`) and skipped
-- before this table is consulted.
local APP_RETRACT_REASONS = { [3] = true }
if naughty_reason.dismissed_by_command then
  APP_RETRACT_REASONS[naughty_reason.dismissed_by_command] = true
end

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

-- Debug print, defined next to the hub debug switch further down. Declared
-- here because the dbus activation section below it is needed by trim_entries,
-- which sits above that switch.
local dbg

-- Close a still-visible popup quietly. Defined in the hub sync section, but
-- trim_entries sits far above it and has to reach it: a row leaving the ring
-- must take its popup with it, or the popup outlives the row it belongs to and
-- the app that posted it is never told the notification ended.
local close_live

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
-- freedesktop activation: a row click says what a popup click says
--------------------------------------------------------------------------------

-- Clicking a naughty popup and clicking the same notification's row here were
-- never the same gesture. The popup click ends in
-- notification:destroy(dismissed_by_user), and naughty/dbus.lua answers that
-- reason by emitting ActionInvoked(id, "default") on the session bus ahead of
-- NotificationClosed. That signal is what makes Telegram open the chat the
-- message came from, a mail client open the mail, a build bot open the job. A
-- row click only ever raised the client naughty guessed from the sender's PID,
-- so the app surfaced on whatever it happened to be showing.
--
-- Emitting that ActionInvoked later only works while the id still means
-- something to the app that posted it, and apps forget an id as soon as they
-- see its NotificationClosed. So for a notification that got a row here, the
-- close naughty emits when the popup times out is withheld, and the close is
-- sent from this module instead when the row leaves: acted on, dropped,
-- cleared, evicted, or the WM exiting. That is the point the last copy on this
-- machine is really gone, which is the same line trim_entries already draws
-- for the hub.
--
-- The action is emitted unconditionally rather than only for notifications
-- that declared a "default" action, because naughty's own popup click does
-- exactly that (sendNotificationClosed in naughty/dbus.lua emits it for every
-- dismissed_by_user, action or no action). Apps that registered none ignore
-- the signal, so matching naughty costs nothing and avoids guessing at an
-- action table the app may never have sent.
--
-- What is deliberately not handled: an app that retires its notification by
-- calling CloseNotification while the row is still here. naughty drops that on
-- the floor once the notification object is destroyed, so this module never
-- learns, keeps offering the row, and the activation lands on an id the app
-- has forgotten. The click then falls back to raising the client, which is the
-- old behaviour.

-- Senders whose ids must not be held open past their popup, matched against a
-- lowercased app_name. Escape hatch for an app that keys something off its own
-- notification being closed; nothing has needed it so far.
local NO_HOLD_APPS = {}

local NOTIFY_PATH  = '/org/freedesktop/Notifications'
local NOTIFY_IFACE = 'org.freedesktop.Notifications'

-- A signal only reaches the apps if it comes from the connection that owns
-- org.freedesktop.Notifications, which is naughty's. GDBus hands out one
-- shared connection per bus type per process and naughty acquires the name on
-- it via g_bus_own_name, so this handle is that same connection rather than a
-- second one that would emit under a unique name nobody is subscribed to.
local session_bus
local function notify_bus()
  if session_bus == nil then
    local ok, conn = pcall(Gio.bus_get_sync, Gio.BusType.SESSION, nil)
    session_bus = (ok and conn) or false
  end
  return session_bus or nil
end

local function emit_notify_signal(name, variant)
  local conn = notify_bus()
  if not conn then return false end
  local ok = pcall(function()
    conn:emit_signal(nil, NOTIFY_PATH, NOTIFY_IFACE, name, variant)
  end)
  if not ok then dbg('dbus emit failed: ' .. name) end
  return ok
end

-- True while this module is holding e's notification id open on behalf of the
-- app that posted it.
local function holding(e)
  return (e and e.dbus_id and e.dbus_open) and true or false
end

-- Whether clicking the row can still reach the app that posted it: either the
-- id is held open here, or naughty still owns a live popup for it.
local function activatable(e)
  if not e or not e.dbus_id then return false end
  if e.dbus_open then return true end
  local n = e.notification
  return (n and n._private and not n._private.is_destroyed
    and not (n._hub_closed or n._hub_veto)) and true or false
end

-- Report the row as clicked to the app that posted it. Returns whether the
-- app was actually told, so the caller knows an app is about to surface a
-- window of its own choosing.
--
-- A row can be clicked while its popup is still on screen (the history popup
-- opens over them). In that case naughty still owns the notification and
-- dismissing it emits the same pair, so it is destroyed through naughty rather
-- than hand-rolled. The close is marked as this module's so the hub handler
-- does not report a resolution act_jump is already reporting itself.
local function dbus_activate(e)
  if not e or not e.dbus_id then return false end

  if not e.dbus_open then
    local n = e.notification
    if n and n._private and not n._private.is_destroyed
       and not (n._hub_closed or n._hub_veto) then
      n._hub_closed = true
      n:destroy(naughty_reason.dismissed_by_user)
      return true
    end
    return false
  end

  e.dbus_open = false
  emit_notify_signal('ActionInvoked',
    GLib.Variant('(us)', { e.dbus_id, 'default' }))
  emit_notify_signal('NotificationClosed',
    GLib.Variant('(uu)', { e.dbus_id, naughty_reason.dismissed_by_user }))
  dbg('activated notification ' .. tostring(e.dbus_id))
  return true
end

-- Hand a held id back without claiming anybody acted on it.
local function dbus_release(e, reason)
  if not holding(e) then return end
  e.dbus_open = false
  emit_notify_signal('NotificationClosed',
    GLib.Variant('(uu)', { e.dbus_id, reason or naughty_reason.expired }))
end

-- Entries are removed from the list by value, so identity is the only way to
-- ask whether a given row is still readable.
local function entry_is_live(e)
  for i = 1, #entries do
    if entries[i] == e then return true end
  end
  return false
end

-- Reasons that only take the popup off the screen. Every other reason (the app
-- calling CloseNotification, a click, a close this module initiated) really
-- ends the notification, and its close goes out untouched.
local HOLD_REASONS = {
  [naughty_reason.expired] = true,
  [naughty_reason.silent]  = true, -- right click on the popup: hide, do not act
}

-- Withhold the dbus close for `n` so `e` can still invoke its default action.
--
-- naughty/dbus.lua reads `n.id` from a 'destroyed' handler that cannot be
-- unsubscribed (it closes over a table this module has no reach into), and
-- running before it is not an option either: gears.object dispatches handlers
-- with pairs(), so connection order buys nothing. destroy() itself is the one
-- deterministic point, so it is wrapped per notification. For the duration of
-- the call `n.id` points at a number no client was ever given, the close goes
-- out naming that number and every app ignores it, and the real id is put back
-- on the way out. _gen_next_id() supplies the decoy so it can never collide
-- with a notification that is actually live somewhere.
--
-- The swap writes straight to _private: set_id() asserts an id is assigned
-- only once, and the property path would additionally re-index a notification
-- that is in the middle of being destroyed.
--
-- rawset is required for the wrapper. crush() copied destroy() onto the object
-- as a plain field, while a plain assignment is caught by the property
-- system's __newindex and would land in _private.destroy, an unrelated
-- callback that leaves the real method untouched.
local function hold_open(n, e)
  local inner = rawget(n, 'destroy')
  if type(inner) ~= 'function' then return end

  rawset(n, 'destroy', function(self, reason, keep_visible)
    local hold = HOLD_REASONS[reason]
      and not (self._hub_closed or self._hub_veto)
      and entry_is_live(e)
    if not hold then return inner(self, reason, keep_visible) end

    local real = self._private.id
    self._private.id = nnotif._gen_next_id()
    local ok, res = pcall(inner, self, reason, keep_visible)
    self._private.id = real
    if not ok then error(res, 0) end
    -- Only a destroy that actually ran swallowed a close worth replacing; a
    -- repeat destroy returns false and its close went out long ago.
    if res then e.dbus_open = true end
    return res
  end)
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

-- Generation for the next posting (SPEC 1). The hub requires a value that
-- strictly increases per native id, and uses it to tell one posting under a
-- reused key from another: an answer naming a generation this device is not
-- showing is about a copy that is already gone, and acting on it would cancel
-- the notification currently on screen.
--
-- A plain counter is enough, and increasing it globally rather than per key
-- satisfies "per key" for free. Native ids are already scoped by HUB_SESSION,
-- so a restart cannot collide with a posting from before it; the counter
-- restarting at 1 alongside is therefore safe.
local hub_generation = 0

local function next_generation()
  hub_generation = hub_generation + 1
  return hub_generation
end

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

-- Whether this device renders other devices' notifications at all.
--
-- The only echo decision left here. Which notifications reach this device, when
-- and why is the hub's: it sends an `echo` frame once, after its grace, and
-- only to devices holding no copy of their own (SPEC 8.4, D-67).
--   'no'    = ignore remote notifications (local only)
--   'yes'   = show them in the history popup
--   'popup' = also fire a normal system popup "$device: ($app) title · body"
local REMOTE_NOTIFICATIONS = 'popup'

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

-- Report what happened to one of this device's own postings (SPEC 7.2).
--
-- `ended` is a value of the hub's closed enum and nothing else: the hub answers
-- 400 for anything outside it and never substitutes the nearest human action,
-- so a reason this client cannot classify is reported as 'not_readable' rather
-- than guessed at (D-63). `platform` is what actually happened here, recorded
-- by the hub for its detail page and never branched on there (D-62).
--
-- One shape where v2 had four endpoints (resolve and removed, each addressable
-- by instance id or by native key). A posting is named by (device, native id,
-- generation), and this client knows all three from the moment it ingested.
--
-- Returns false for a row with no posting of its own, which is what an echo is.
local function hub_event(e, ended, platform)
  if not (e and e.hub_native and e.hub_generation) then return false end
  hub_report_async('/api/v1/events', table.concat({
    '{"device_id":' .. json_str(hub_device()),
    ',"events":[{',
    '"native_id":' .. json_str(e.hub_native),
    ',"generation":' .. tostring(e.hub_generation),
    ',"ended":' .. json_str(ended),
    ',"at":' .. json_str(os.date('!%Y-%m-%dT%H:%M:%SZ')),
    platform and (',"platform_reason":' .. json_str(platform)) or '',
    '}]}',
  }))
  return true
end

-- End a logical outright. Only ever for an echo: a row this device renders on
-- another device's behalf has no posting here to report against, and dropping
-- one is a full ending for everybody, because the hub can cancel a notification
-- on a device but never create one (D-47).
local function hub_end_logical(logical_id, cause)
  if not logical_id or logical_id == '' then return end
  hub_report_async('/api/v1/notifications/' .. logical_id .. '/end',
    '{"cause":' .. json_str(cause) .. '}')
end

-- Evict entries past MAX_ENTRIES, telling the hub about each one.
--
-- This is the only moment a notification really leaves this device, and it is
-- what the hub's orphan sweep waits for (D-12, D-13). A popup timing out is not
-- one of them: it only hides the toast, while the row stays readable here and
-- in the cache file. Reporting a close there would claim the last copy vanished
-- while it is still sitting unread.
--
-- 'not_readable', because nobody finished with it: the row aged out. That ends
-- no logical and suppresses nothing on its own.
--
-- Sync would reach the same place on its next pass, since an evicted row is no
-- longer in `holding` and the hub closes what this device stops naming. Doing
-- it here is the same answer a minute earlier, and the two agree: closing a row
-- twice is idempotent.
local function trim_entries()
  while #entries > MAX_ENTRIES do
    local e = table.remove(entries)
    -- Tell the app first: the id was held open only for as long as the row was
    -- readable, and close_live hands it back whether it was held or the
    -- notification is somehow still alive.
    --
    -- A notification that was recorded without ever being displayed (the echo
    -- takeover in record()) is the case that needs the second half. Nothing
    -- made it expire, so nothing ever withheld its close, and releasing the
    -- held id alone would leave the object alive and the app still believing
    -- its notification is on screen.
    close_live(e)
    hub_event(e, 'not_readable', 'history_evicted')
  end
end

-- Bulk ending for "clear history": one request instead of one curl per entry
-- (the hub caps it at 500 ids per call).
local function hub_bulk_end(logical_ids)
  if #logical_ids == 0 then return end
  local parts = {}
  for _, id in ipairs(logical_ids) do parts[#parts + 1] = json_str(id) end
  hub_report_async('/api/v1/notifications/end-many',
    '{"cause":"user_dismiss","logical_ids":['
      .. table.concat(parts, ',') .. ']}')
end

-- Async POST that hands the response body back. Used by the reconcile probe,
-- which is a read despite the verb: the id set it sends is past what a query
-- string should carry (AGENTS.md 11.2).
local function hub_post_async(path, body_json, cb)
  awful.spawn.easy_async({
    'curl', '-sS',
    '--connect-timeout', '3', '--max-time', '10',
    '-X', 'POST',
    '-H', 'Authorization: Bearer ' .. HUB_TOKEN,
    '-H', 'Content-Type: application/json',
    '-d', body_json,
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
  local generation = next_generation()
  local urgency = n.urgency or 'normal'
  if urgency == 'critical' then urgency = 'high' end
  local body = table.concat({
    '{',
    '"device_id":' .. json_str(hub_device()),
    ',"client_type":"linux"',
    ',"mode":"pre_show"',
    ',"native_id":' .. json_str(tostring(native_id)),
    ',"generation":' .. tostring(generation),
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
  local out = hub_request('/api/v1/ingest', body)
  if not out then return nil end
  local meta = {
    decision    = parse_field(out, 'decision'),
    reason      = parse_field(out, 'reason'),
    logical_id  = parse_field(out, 'logical_id'),
    instance_id = parse_field(out, 'instance_id'),
    native_id   = native_id,
    generation  = generation,
    -- Whether the hub already announced this notification to the devices
    -- without it, this one included. It replaces the table this client used to
    -- keep of what it had echoed (D-67).
    echoed      = out:match('"echoed":true') ~= nil,
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
    -- Persisted for the same reason the ids are: without it a restored entry
    -- the hub was told to ignore turns into an ordinary id-less row and goes
    -- back to being matched by content.
    tostring(e.hub_ignored or false),
    -- Where the row came from. Only the display marker depends on it, but a
    -- restored echo that lost it reads as a local notification whose window is
    -- merely gone, which is a different and more actionable thing.
    tostring(e.remote or false),
    -- The posting identity, appended last so a cache file written before this
    -- existed still parses: those lines restore with no posting and are simply
    -- never named in a sync, which is the same place a fail-open row sits.
    esc(e.hub_native or ''),
    tostring(e.hub_generation or 0),
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
        -- Absent on older lines too, which reads as false: a row written
        -- before ignore rules existed cannot have been ignored.
        hub_ignored  = (fields[9] or 'false') == 'true',
        -- Same for the origin marker; an old line is assumed local, which is
        -- what every line written before echoes existed actually was.
        remote       = (fields[10] or 'false') == 'true',
        -- Absent on every line written before generations. A row restored
        -- without one keeps its logical id but can no longer be reported
        -- against, so it is left out of `holding` and ages out of the ring.
        hub_native     = unesc_optional(fields[11]),
        hub_generation = tonumber(fields[12]),
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
local focus_handler  -- dismiss signals, connected on show, disconnected on hide

-- Signals meaning "the user went somewhere else", so the popup should get out
-- of the way.
--
-- 'focus' alone misses the commonest case. This popup is a wibox, not a
-- client, so opening it never takes client focus: whatever was focused before
-- still is. Clicking back into that same window therefore changes no focus and
-- reports nothing, and the popup sits there over the window being used.
--
-- 'request::activate' is emitted on every click into a client whether or not
-- it already had focus (rc_clientbuttons), plus by the tasklist, titlebars and
-- unminimise. Nothing emits it on a timer, so this stays event-driven and
-- costs nothing while the popup is closed, which is whenever these are not
-- connected at all.
local DISMISS_SIGNALS = { 'focus', 'request::activate' }

local function disconnect_dismiss()
  if not focus_handler then return end
  for _, sig in ipairs(DISMISS_SIGNALS) do
    client.disconnect_signal(sig, focus_handler)
  end
  focus_handler = nil
end

local function connect_dismiss()
  -- Replaced rather than added to on each show(), so there is never more than
  -- one connection per signal.
  disconnect_dismiss()
  focus_handler = function() notification_history.hide() end
  for _, sig in ipairs(DISMISS_SIGNALS) do
    client.connect_signal(sig, focus_handler)
  end
end

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
local render, act_jump, act_delete

local function make_row(e, index)
  local is_sel = (index == selected)
  local fg = urgency_fg(e.urgency)
  local body = e.text
  if e.title ~= '' then
    body = (e.text ~= '' and e.title ~= e.text) and (e.title .. ' · ' .. e.text) or e.title
  end

  -- Echoes carry the *sending* app's name (QKSMS, the phone's mail client),
  -- which reads exactly like a local one and invites a click that can never go
  -- anywhere: there is no window here and no dbus id to activate. The marker
  -- says so up front rather than after the fact.
  local app_label = e.remote and ('[R] ' .. e.app) or e.app

  local row = wibox.widget {
    {
      {
        label(relative_time(e.time), is_sel and beautiful.fg_normal_alt or DIM, COL_TIME),
        label(app_label, is_sel and beautiful.fg_normal_alt or beautiful.fg_normal, COL_APP),
        label(body, is_sel and beautiful.fg_focus or fg, COL_BODY),
        -- Marker for entries a click still gets somewhere: either the source
        -- window is alive to raise, or the app still holds the notification
        -- and can be told to act on it.
        label(((e.client and e.client.valid) or activatable(e)) and '⏎' or '',
          DIM, COL_MARK),
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
  local footer = 'j/k move · ⏎ open · y yank · d drop · C clear · click row · Esc/q close'

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
  disconnect_dismiss()
  if popup then popup.visible = false end
end

-- Clicking a row says the same thing as clicking the popup it came from: you
-- have dealt with this one. Reported as `click`, the hub's strongest
-- resolution kind, which closes the notification on every other device, and
-- handed to the posting app as its default action where the id is still held
-- open, which is what gets Telegram to the right chat rather than merely to
-- its window.
--
-- The row goes whether or not there was a window to raise. A row with neither
-- a live client nor a held id is the case where clicking is most clearly
-- terminal: it was restored from disk, or the thing that posted it is gone, so
-- there is nowhere to go and look and the click was the whole interaction.
--
-- Jumping is therefore not a way to visit a notification without answering for
-- it. `d` sends the same row away with `user_dismiss` instead, which is the
-- difference between "I went and looked" and "I do not need this".
act_jump = function()
  local e = entries[selected]
  if not e then return end
  local target = (e.client and e.client.valid) and e.client or nil

  -- Before close_live, which would otherwise release the id as a plain
  -- expiry and lose the click.
  local activated = dbus_activate(e)

  -- Entries shown while the hub was unreachable carry no ids and stay local.
  if not hub_event(e, 'user_click', 'history_row_click') then
    -- An echo has no posting of its own; end the logical instead.
    hub_end_logical(e.hub_logical, 'user_click')
  end
  table.remove(entries, selected)
  -- Entry is gone before the destroy, so the 'destroyed' handler cannot
  -- double-report the resolution just sent.
  close_live(e)
  flush_cache()
  refresh_count_widget()

  if target then
    notification_history.hide()
    target:jump_to()
    return
  end
  -- The app was handed the click and brings up whatever window it considers
  -- right for it, so there is nothing here left to raise or to report.
  if activated then
    return notification_history.hide()
  end
  naughty.notification {
    app_name = SELF_APP,
    text     = 'No live client - dismissed',
    timeout  = 2,
  }
  if #entries == 0 then
    return notification_history.hide()
  end
  -- render() reclamps `selected`, which the removal above may have put past
  -- the end of the list.
  render()
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
  -- Dropping a row means "gone everywhere": the hub ends the logical and the
  -- other devices drop their copies. Entries shown while the hub was offline
  -- have no ids and stay local-only.
  if not hub_event(e, 'user_dismiss', 'history_row_delete') then
    hub_end_logical(e.hub_logical, 'user_dismiss')
  end
  table.remove(entries, selected)
  -- Dropping a row is a deliberate dismissal, so the app hears that rather
  -- than the plain expiry close_live would otherwise send.
  dbus_release(e, naughty_reason.dismissed_by_user)
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
  hub_bulk_end(ids)
  -- Detach first, then close: the 'destroyed' handler must not double-report
  -- what the bulk dismiss already tombstoned.
  local old = entries
  entries = {}
  for _, e in ipairs(old) do
    dbus_release(e, naughty_reason.dismissed_by_user)
    close_live(e)
  end
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

-- Two paths converge here, and only one of them is load-bearing:
--   1. the SSE stream, which says "this ended, here is what you may retract"
--      within a second of it happening;
--   2. hub_sync, which says the same thing about everything this device holds,
--      once a minute and whenever a notification arrives.
--
-- The stream is a doorbell. Everything it carries is also reachable from the
-- next sync, so a client that misses every frame is still correct, one minute
-- behind (SPEC 7.4). That is a deliberate inversion: in v2 the stream carried
-- a vocabulary the catch-up path could not reconstruct, so a dropped frame and
-- a missing `expiry_reason` column between them could leave a stale row on
-- screen for good.
--
-- Sync is also the reverse direction. The hub closes whatever it believed was
-- live on this device that `holding` did not name, which is how a row that
-- left the ring, or a popup vetoed before it was ever recorded, stops pinning
-- a logical to the Active list. v2 had no equivalent here at all: only
-- trim_entries ever told the hub a copy was gone, so anything that left by
-- another route leaked an open instance forever.
--
-- What still lives outside it: act_delete, act_clear, act_jump and the
-- 'destroyed' handler report immediately rather than waiting for the next
-- pass, because a cross-device cancel should land in a second.

local SYNC_INTERVAL = 60  -- sync every N seconds
local SYNC_LIMIT    = 500 -- hub's per-call cap on `holding`; MAX_ENTRIES is below it

local debug = false -- flip to true to trace hub sync activity

-- debug print: fires on the module-local flag OR the global printmore master
-- switch (same convention as mpris/mpris_lyrics). Hub sync feedback goes
-- through here so drops are silent in normal use and traceable when needed.
dbg = function(msg)
  if debug or printmore then
    debug_print(msg, true)
  end
end

-- Close a still-visible popup quietly. The entry is removed from `entries`
-- before this runs, so the 'destroyed' handler finds nothing and never
-- reports the hub-driven removal back as a user dismissal (no echo loop).
close_live = function(e)
  -- A row leaving the list is the moment the app can be told its notification
  -- is gone here, whether or not a popup for it is still on screen. Callers
  -- that mean something more specific than "it expired" release it themselves
  -- first; this is the catch-all.
  dbus_release(e)
  local n = e.notification
  -- `_hub_closed` doubles as the re-entrancy guard, and has to, because
  -- `is_destroyed` is not a usable one: notification:destroy() emits
  -- 'destroyed' first and only sets the flag after every handler returned.
  -- Anything reached from inside that emit therefore still sees a live-looking
  -- notification, and a second destroy() runs naughty's cleanup() twice, which
  -- trips `assert(naughty.notifications[scr][position][idx] == self)` because
  -- the first pass already unindexed it. The flag also survives such an abort:
  -- the error unwinds destroy() before it can set `is_destroyed`, leaving the
  -- object permanently destroy-able-looking, so later clears would re-trip the
  -- same assert.
  if n and n._private and not n._private.is_destroyed and not n._hub_closed then
    -- Marked before the destroy, read by the 'destroyed' handler: a close this
    -- module initiated is never a report. Detaching the entry first would do
    -- the same job and act_delete/act_clear do exactly that, but
    -- drop_matching() closes while the entry is still in `entries`, so the
    -- ordering is not something the handler can rely on.
    n._hub_closed = true
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

-- Logical ids an echo is on screen for. Cleared when the local copy turns up
-- and takes the row over (take_over_echo).
--
-- Not a dedup table any more: the hub sends an echo once, to the devices that
-- do not hold the notification, so there is nothing here to deduplicate. What
-- is left is the one fact only this process knows - whether a toast was
-- actually put on screen - which is what decides whether the takeover is
-- silent (D-67).
local remote_shown = {}

local render_echo

-- An echo frame: the hub has decided this device should render another
-- device's notification.
--
-- Everything that used to be decided here is decided there now. Whether the
-- frame is this device's own notification, whether this device already holds a
-- copy, and whether to wait in case a local copy is about to arrive were all
-- answered by guesswork against a broadcast that went to everyone; the hub
-- knows the origin, knows every instance, and is the only thing that can see
-- the second copy arrive (D-67).
--
-- So this is now: render it, unless the operator does not want echoes at all.
local function handle_echo(data_json)
  if REMOTE_NOTIFICATIONS == 'no' then return end
  local logical = parse_field(data_json, 'logical_id')
  if not logical or logical == '' then return end
  if remote_shown[logical] then return end
  render_echo(data_json, logical)
end

render_echo = function(data_json, logical)
  local device_id = parse_field(data_json, 'device_id')
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
    remote  = true,
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

-- The real local notification turned up for a logical an echo is already
-- showing. The echo row goes and the local one takes its place.
--
-- Always a straight swap, never a veto of the local copy. The echo is the
-- weaker row of the two: it has no dbus id and no client, so clicking it ends
-- the notification but can never raise the app that sent it, while the local
-- copy can do both. Keeping the echo and throwing the local one away - which
-- is what this did before - traded the only actionable copy for the one that
-- arrived first.
--
-- Returns whether the echo had already put a popup on screen, which is the one
-- thing about this only the local process knows. The caller uses it to take
-- over silently: the message has been announced once already and does not
-- deserve a second toast.
--
-- Nothing is reported to the hub. Both rows are the same logical, and dropping
-- the echo here is this device rearranging what it renders, not a decision
-- about the notification (close_live marks its own closes, so the 'destroyed'
-- handler stays quiet too).
local function take_over_echo(logical)
  local popped = false
  for _, e in ipairs(entries) do
    if e.remote and e.hub_logical == logical and e.notification then
      popped = true
      break
    end
  end
  drop_matching(function(e)
    return e.remote and e.hub_logical == logical
  end, 'local copy took over the echo')
  remote_shown[logical] = nil
  return popped
end

-- What a hub answer licenses this client to take off a screen (SPEC 2).
--
-- The hub sends two facts with every ending - `retract` and `suppresses` - and
-- this client acts on `retract` alone. The cause string is for the log. That is
-- the whole of the rule now; v2 decoded an event `kind` and a row's
-- `expiry_reason` through two hand-written tables that had to be kept in step
-- with the hub by hand, and the hub knowingly shipped one misleading reason
-- string rather than break them (D-03).
--
--   'all'  - the thing the row is about is finished or gone at the source. The
--            row goes, read or unread.
--   'echo' - only a row this device renders on another device's behalf. One of
--            this device's own stays, popup and all: an ending that merely says
--            "every copy the hub knew about went away" says nothing about
--            whether anybody read this one, and this client reports its own
--            copy gone only when the row leaves the ring (D-13, D-14).
--   'none' - the hub has no opinion and no row. Forget the ids, leave the
--            notification exactly where it is (D-25).
--
-- An echo is a row with no posting of this device's own, which is exactly the
-- rows carrying no instance id (section 14.1).
local function is_echo(e)
  return not e.hub_instance
end

-- Whether `retract` licenses dropping this row. An unrecognised value licenses
-- nothing, which is the safe direction: it keeps a duplicate.
local function retract_drops(retract, e)
  if retract == 'all' then return true end
  if retract == 'echo' then return is_echo(e) end
  return false
end

-- Forget the hub ids on a row the hub no longer tracks, keeping the row itself.
-- Returns whether anything changed, so the caller knows to rewrite the cache.
local function forget_ids(e)
  if not (e.hub_logical or e.hub_instance or e.hub_native) then return false end
  e.hub_logical, e.hub_instance = nil, nil
  e.hub_native, e.hub_generation = nil, nil
  return true
end

-- One SSE frame. The stream is a doorbell: everything it carries is also
-- reachable from the next sync, so a missed frame costs a minute and never
-- correctness (SPEC 7.4).
local function handle_hub_event(data_json)
  local ev_type = parse_field(data_json, 'type')
  if ev_type == 'echo' then
    handle_echo(data_json)
    return
  end
  -- `created` is a doorbell: it says a notification arrived somewhere and
  -- carries no content. Whether this device should render it is the hub's
  -- decision, and it arrives later as an `echo` frame (SPEC 8.4).
  if ev_type ~= 'ended' and ev_type ~= 'untracked' then return end

  local logical = parse_field(data_json, 'logical_id')
  if not logical or logical == '' then return end
  local retract = parse_field(data_json, 'retract')
  local cause = parse_field(data_json, 'cause') or 'unknown'

  -- Nothing to cancel here any more. A notification that ends before its echo
  -- grace elapses leaves the hub's active pool, so no echo is ever sent for it;
  -- this client used to hold the pending echo itself and had to remember to
  -- drop it (D-67).

  if retract == 'none' then
    local changed = false
    for _, e in ipairs(entries) do
      if e.hub_logical == logical and forget_ids(e) then changed = true end
    end
    if changed then
      flush_cache()
      dbg('hub stopped tracking (' .. cause .. '), ids forgotten')
    end
    return
  end

  drop_matching(function(e)
    if e.hub_logical ~= logical then return false end
    return retract_drops(retract, e)
  end, 'ended elsewhere (' .. cause .. ')')
end

-- Pull the flat objects out of one named array of a sync response. The objects
-- are flat and carry no brackets of their own, so a non-greedy match to the
-- first ']' is exact. Good enough for our own responses; a title carrying an
-- escaped quote is not in any of these arrays, which is why this is safe here
-- and was a caveat on the listing parse it replaces.
local function parse_array(out, name)
  local items = {}
  local arr = out:match('"' .. name .. '":%[(.-)%]')
  if not arr then return items end
  for obj in arr:gmatch('{(.-)}') do items[#items + 1] = obj end
  return items
end

local function obj_str(obj, name)
  return obj:match('"' .. name .. '":"([^"]*)"')
end

local function obj_num(obj, name)
  return tonumber(obj:match('"' .. name .. '":(%-?%d+)'))
end

local sync_pending = false

-- The one repair path (SPEC 7.3).
--
-- This device says what it is holding and the hub answers with everything it
-- should do. Both directions in one request: the hub also closes whatever it
-- believed was live here that `holding` did not name, which is what v2 needed
-- a second pass for on the Android side and had no equivalent of at all here.
--
-- Asked, never listed. A listing is ranked and capped, so once a page fills
-- with normal and high urgency rows a `low` one is on no page this client can
-- ask for: a Firefox download expiry survived seven hours of 60-second
-- rechecks that way (D-24). A set of ids has no ranking to fall off, needs no
-- cursor and no clock agreement, and it reaches the one case no listing can -
-- a logical the hub deleted on purpose comes back as an explicit answer rather
-- than as an absence (D-25).
--
-- Rows with no hub ids (shown while the hub was unreachable, fail-open) are not
-- in `holding`. The hub has no instance for them either, since their ingest
-- never landed, so there is nothing for it to close and nothing to ask about;
-- they age out of the ring. This client has no outbox by design (SPEC 13).
local function hub_sync()
  if sync_pending then return end

  local holding, seen = {}, {}
  for _, e in ipairs(entries) do
    if e.hub_native and e.hub_generation then
      -- One of this device's own postings. Naming it is also what keeps the
      -- hub from closing its row: anything this device stops naming is closed.
      holding[#holding + 1] = table.concat({
        '{"native_id":' .. json_str(e.hub_native),
        ',"generation":' .. tostring(e.hub_generation),
        e.hub_logical and (',"logical_id":' .. json_str(e.hub_logical)) or '',
        '}',
      })
    elseif is_echo(e) and e.hub_logical and e.hub_logical ~= ''
       and not seen[e.hub_logical] then
      -- An echo: no posting here, so it is named by logical id alone and the
      -- hub answers it in `echoes` (SPEC 8.4). It holds no instance either, so
      -- there is nothing for the hub to close on its behalf.
      seen[e.hub_logical] = true
      holding[#holding + 1] = '{"logical_id":' .. json_str(e.hub_logical) .. '}'
    end
    -- Anything left is a row restored from a cache file written before
    -- generations existed: it holds an instance id but no posting identity, so
    -- it cannot be named here. The hub closes that instance on this pass and
    -- its logical ages out as all_copies_gone, whose retract is `echo` and
    -- therefore cannot touch a row of this device's own. The row stays
    -- readable until the ring evicts it. One-time, bounded by MAX_ENTRIES, and
    -- it costs a hub Active-list row rather than anything on a screen.
    if #holding >= SYNC_LIMIT then break end
  end

  sync_pending = true
  -- Deadman switch: a curl that never spawns means no callback ever arrives,
  -- and the flag would otherwise disable re-checking forever.
  gears.timer.start_new(20, function()
    sync_pending = false
    return false
  end)

  local body = '{"device_id":' .. json_str(hub_device())
    .. ',"holding":[' .. table.concat(holding, ',') .. ']}'

  hub_post_async('/api/v1/sync', body, function(out)
    sync_pending = false
    if not out then return end

    local changed = false

    -- Mapping repairs first: a cancel below may name a row whose ids only just
    -- arrived.
    for _, obj in ipairs(parse_array(out, 'ids')) do
      local native, gen = obj_str(obj, 'native_id'), obj_num(obj, 'generation')
      for _, e in ipairs(entries) do
        if e.hub_native == native and e.hub_generation == gen then
          e.hub_logical = obj_str(obj, 'logical_id') or e.hub_logical
          e.hub_instance = obj_str(obj, 'instance_id') or e.hub_instance
          changed = true
        end
      end
    end

    -- Verdicts, keyed the way the rows are.
    local by_native, by_logical = {}, {}
    for _, obj in ipairs(parse_array(out, 'cancel')) do
      local native = obj_str(obj, 'native_id')
      if native then
        by_native[native] = {
          generation = obj_num(obj, 'generation'),
          retract = obj_str(obj, 'retract'),
          cause = obj_str(obj, 'cause') or 'unknown',
        }
      end
    end
    for _, obj in ipairs(parse_array(out, 'echoes')) do
      local logical = obj_str(obj, 'logical_id')
      if logical then
        by_logical[logical] = {
          retract = obj_str(obj, 'retract'),
          cause = obj_str(obj, 'cause') or 'unknown',
        }
      end
    end
    -- The hub holds no row for these, deliberately or because it never knew
    -- them. retract is none: forget the ids, keep the notification.
    local untracked = {}
    for _, obj in ipairs(parse_array(out, 'untracked')) do
      local native = obj_str(obj, 'native_id')
      if native then untracked[native] = true end
    end

    for _, e in ipairs(entries) do
      if e.hub_native and untracked[e.hub_native] and forget_ids(e) then
        changed = true
      end
    end

    drop_matching(function(e)
      if e.hub_native then
        local v = by_native[e.hub_native]
        if not v then return false end
        -- The hub is describing a different posting under this reusable key,
        -- so it is not about what is on screen (D-27).
        if v.generation ~= e.hub_generation then return false end
        if v.retract == 'none' then
          if forget_ids(e) then changed = true end
          return false
        end
        return retract_drops(v.retract, e)
      end
      if e.hub_logical then
        local v = by_logical[e.hub_logical]
        if not v then return false end
        if v.retract == 'none' then
          if forget_ids(e) then changed = true end
          return false
        end
        return retract_drops(v.retract, e)
      end
      return false
    end, 'hub sync')

    -- drop_matching rewrites the cache when it removes something; a pass that
    -- only repaired or forgot ids still has to.
    if changed then flush_cache() end
  end)
end

-- Debounced reconcile trigger for the record() path ("ask again about kept
-- notifications on each new one"): notification bursts must not stack list
-- requests.
local sync_wakeup = nil

local function schedule_sync(delay)
  if sync_wakeup then sync_wakeup:stop() end
  sync_wakeup = gears.timer.start_new(delay or 10, function()
    sync_wakeup = nil
    hub_sync()
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
          hub_sync()
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

  -- The same message reached this device twice: once as an echo of whichever
  -- device the hub heard from first, and once as the real local notification.
  -- The local copy always wins, because it is the only one of the two that can
  -- raise the app that sent it.
  --
  -- The hub's grace means this is the uncommon case: usually the local copy
  -- arrives before any echo is sent, and the hub then never sends one, because
  -- this device holds a copy by the time the grace elapses (D-66).
  local silent = false
  if meta and meta.echoed and meta.logical_id and meta.logical_id ~= '' then
    -- The hub says it announced this notification to the devices that did not
    -- have it, which at the time included this one. Whatever is on screen for
    -- that logical is an echo of the message now arriving locally, and the
    -- local copy is the better row: it can raise the app that sent it (D-66).
    silent = take_over_echo(meta.logical_id)
    dbg('local copy took over the echo for ' .. meta.logical_id)
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

  -- Taking over an echo that already announced this message: display is
  -- skipped, the notification is not. `ignore` keeps naughty from building a
  -- box; everything else about the object stays, which is what matters, since
  -- the whole point of preferring the local copy is its dbus id. The row stays
  -- clickable through exactly the path a popup that timed out leaves behind
  -- (hold_open, then dbus_activate).
  --
  -- Deliberately not destroyed, unlike a suppression: destroying it would send
  -- the close straight away and hand the id back, and clicking the row would
  -- then reach nothing.
  if silent then
    n.ignore = true
  end

  -- First still-valid client naughty associated with the notification, so the
  -- entry can raise its source window later.
  local target
  if n.clients then
    for _, c in ipairs(n.clients) do
      if c and c.valid then target = c break end
    end
  end

  -- Whether the hub holds a row for this notification. False when it was
  -- unreachable (fail-open, no ids at all) and when an ignore rule covers it
  -- (the hub stored nothing and never will). Both leave the row local-only:
  -- it is displayed like any other, it is simply not something the hub has an
  -- opinion about.
  local tracked = meta ~= nil
    and meta.decision ~= 'ignore'
    and meta.logical_id ~= nil and meta.logical_id ~= ''

  -- Only dbus-delivered notifications have an id an app knows about; the
  -- config's own internal toasts come in under INTERNAL_APP with no hints and
  -- nothing on the other end to activate.
  local dbus_id
  if n._private and n._private.freedesktop_hints
     and not matches_any(app, NO_HOLD_APPS) then
    dbus_id = n.id
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
    -- Hub ids from the pre-show answer, used to report back and to name this
    -- row in a sync. Unlike `notification` these are persisted: the hub rows
    -- outlive the WM, so dropping a restored entry still has somewhere to
    -- report to.
    hub_instance = tracked and meta.instance_id or nil,
    hub_logical  = tracked and meta.logical_id or nil,
    -- The posting this row is, as the hub names it (SPEC 1). Persisted for the
    -- same reason the ids are, and needed for the same report: an ending is
    -- addressed by (device, native id, generation), and after a restart the
    -- native id cannot be rederived - HUB_SESSION has changed, and naughty's
    -- counter has restarted underneath it.
    hub_native     = tracked and meta.native_id or nil,
    hub_generation = tracked and meta.generation or nil,
    -- The hub answered 'ignore': an ignore rule covers this notification, so
    -- it holds no row for it and never will. The entry is kept and displayed
    -- like any other, because ignore means "bother does not manage this", not
    -- "hide it". Recorded to tell the two id-less cases apart when reading a
    -- cache file or the debug log: this one is permanent and deliberate, while
    -- "shown while the hub was unreachable" is neither.
    hub_ignored  = meta ~= nil and meta.decision == 'ignore',
    -- Native notification id, used to invoke the default action from the row
    -- long after the popup is gone. Not persisted, unlike the hub ids: an id
    -- only means anything to the running process that was given it, and a
    -- restart has already dropped every one of them.
    dbus_id   = dbus_id,
    dbus_open = false, -- set once the expiring popup's close has been withheld
    seen    = false,  -- track whether this notification was viewed
  })
  if dbus_id then hold_open(n, entries[1]) end
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
  schedule_sync(10)
end

--------------------------------------------------------------------------------
-- public API
--------------------------------------------------------------------------------

function notification_history.show()
  if #entries == 0 then return toast_empty() end

  -- Opening the popup is a natural "show me the truth now" moment: run the
  -- reconcile shortly after so stale rows do not survive a popup session.
  schedule_sync(1)

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

  -- Close the popup as soon as the user goes back to a window.
  connect_dismiss()
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
-- locally, which propagates the cancel to every device. Reports are async and
-- only fire for rows carrying a posting identity, which a suppressed or
-- vetoed notification never gets, so a suppression here can never echo back to
-- the hub as a human action.
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
-- An app retracting its own notification is reported, as a removal rather than
-- a resolution: see the branch below.
--
-- Every other reason is left alone, and closes this module initiated are left
-- alone whatever reason they carry. They are recognised by the `_hub_closed`
-- mark that close_live() sets, not by their reason and not by the entry having
-- been detached first: act_delete and act_clear do detach first, but
-- drop_matching() closes while the entry is still in `entries`, so an echo
-- guard resting on that ordering would hold for two call sites out of three.
naughty.connect_signal('destroyed', function(n, reason)
  -- Anything this module closed itself, whatever reason it used.
  if n and (n._hub_closed or n._hub_veto) then
    return
  end

  -- The source took the notification back: the app called CloseNotification
  -- because whatever it was about stopped being true (the mail was read in
  -- another client, the build finished, the call was answered elsewhere).
  --
  -- Unlike a timeout this does say the copy here is finished, so the row goes
  -- rather than staying readable in the ring, and the hub hears `app_cancel`,
  -- which is what feeds its withdrawal expiry (AGENTS.md 6.2) and clears the
  -- same notification off the phone. A removal, not a resolution: nobody
  -- necessarily read it, so nothing is suppressed and the cost of a wrong one
  -- is the notification arriving again.
  if APP_RETRACT_REASONS[reason] then
    local e
    for i = 1, #entries do
      if entries[i].notification == n then e = entries[i] break end
    end
    if not e then return end
    hub_event(e, 'source_withdrew', 'dismissed_by_command')
    -- This runs inside n's own destroy(), so n must not be destroyed again on
    -- the way out. drop_matching() -> close_live() would otherwise do exactly
    -- that; the mark makes close_live skip it (see the guard there).
    n._hub_closed = true
    drop_matching(function(x) return x.notification == n end, 'app retracted')
    return
  end

  if reason ~= naughty_reason.dismissed_by_user then
    return
  end
  for i = 1, #entries do
    if entries[i].notification == n then
      entries[i].seen = true
      hub_event(entries[i], 'user_click', 'dismissed_by_user')
      refresh_count_widget()
      if popup and popup.visible then render() end
      return
    end
  end
end)

-- An exit or a restart (Win+Ctrl+R) takes every popup and every held id with
-- it, so the apps are told rather than left holding notifications against a
-- server that will come back as a different connection with a fresh id
-- counter. The flush is not optional: awesome execs itself straight after this
-- signal and a message still sitting in the GDBus output queue never leaves.
awesome.connect_signal('exit', function()
  local sent = false
  for _, e in ipairs(entries) do
    if holding(e) then
      dbus_release(e)
      sent = true
    end
  end
  if sent then
    local conn = notify_bus()
    if conn then pcall(function() conn:flush_sync(nil) end) end
  end
end)

-- Hub sync startup: live event stream immediately, first reconcile delayed
-- (does not race network bring-up), then periodic.
start_hub_stream()
gears.timer.start_new(5, function() hub_sync() return false end)
gears.timer.start_new(SYNC_INTERVAL, function() hub_sync() return true end)

return notification_history
-- vim: set ts=2 sw=2 tw=0 et :
