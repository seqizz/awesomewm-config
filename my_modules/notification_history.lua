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

local function serialize(e)
  return table.concat({
    tostring(e.time), esc(e.urgency), esc(e.app), esc(e.title), esc(e.text),
    tostring(e.seen or false),
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
      })
    end
  end
  f:close()

  entries = loaded
  while #entries > MAX_ENTRIES do table.remove(entries) end
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
local render, act_jump, act_delete

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

  local header = string.format('Notifications  %d/%d', selected, #entries)
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
  if not entries[selected] then return end
  table.remove(entries, selected)
  flush_cache()
  refresh_count_widget()
  if #entries == 0 then
    notification_history.hide()
    return toast_empty()
  end
  render()
end

local function act_clear()
  entries = {}
  flush_cache()
  refresh_count_widget()
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
-- recording
--------------------------------------------------------------------------------

local function record(n)
  -- Our own feedback toasts must never be recorded, or acting on an entry
  -- appends a new entry and the buffer grows on every keypress.
  if n.app_name == SELF_APP then return end

  -- freedesktop_hints lives in _private (no getter exists for it), so access
  -- it defensively in case a future awesome version renames the field.
  if not (n._private and n._private.freedesktop_hints)
     and n.app_name ~= INTERNAL_APP then
    return
  end

  local title = oneline(strip_notification_markup(n.title))
  local text = oneline(strip_notification_markup(n.message or n.text))
  if title == '' and text == '' then return end
  if matches_any(title .. ' ' .. text, IGNORE_PATTERNS) then return end

  local app = n.app_name
  if not app or app == '' then app = 'awesome' end
  if matches_any(app, IGNORE_APPS) then return end

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
    seen    = false,  -- track whether this notification was viewed
  })
  while #entries > MAX_ENTRIES do table.remove(entries) end

  append_cache(entries[1])
  refresh_count_widget()

  if popup and popup.visible then
    -- A new entry shifts everything down; follow the selection so the popup
    -- does not silently jump to a different notification under the cursor.
    if selected > 1 then selected = selected + 1 end
    render()
  end
end

--------------------------------------------------------------------------------
-- public API
--------------------------------------------------------------------------------

function notification_history.show()
  if #entries == 0 then return toast_empty() end

  selected, offset = 1, 0
  -- Mark all entries as seen when popup opens (scroll, Win+n, etc.)
  for i = 1, #entries do
    entries[i].seen = true
  end
  refresh_count_widget()
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
naughty.connect_signal('added', function(n) record(n) end)

-- Dismissing the popup you actually saw should not leave the badge red. Only
-- dismissed_by_user counts: a timeout expiry means the user never necessarily
-- looked at it, so that case is left for the history popup to mark seen.
naughty.connect_signal('destroyed', function(n, reason)
  if reason ~= require('naughty.constants').notification_closed_reason.dismissed_by_user then
    return
  end
  for i = 1, #entries do
    if entries[i].notification == n then
      entries[i].seen = true
      refresh_count_widget()
      if popup and popup.visible then render() end
      return
    end
  end
end)

return notification_history
-- vim: set ts=2 sw=2 tw=0 et :
