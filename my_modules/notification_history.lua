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
local dpi = beautiful.xresources.apply_dpi

local notification_history = {}

-- Tunables
local MAX_ENTRIES = 200 -- ring buffer size, also the on-disk trim target
local VIEWPORT    = 14  -- rows rendered at once; list scrolls inside this
local TEXT_LIMIT  = 140 -- chars before the message column gets truncated
local POPUP_WIDTH = 900
local EDGE_MARGIN = 8   -- gap from the screen edge when placed top right

-- Row geometry. Every column is forced, and the message column is whatever is
-- left over, so the popup width is fixed no matter what a notification
-- contains. Without this a long message makes the textbox request its natural
-- width and the popup grows off the screen edge.
local COL_TIME    = 45
local COL_APP     = 130
local COL_MARK    = 20  -- the '⏎' raise-target marker
local ROW_SPACING = 8
local ROW_PADDING = 10  -- left/right margin inside a row
local COL_BODY    = POPUP_WIDTH - COL_TIME - COL_APP - COL_MARK
                    - (3 * ROW_SPACING) - (2 * ROW_PADDING)

local CACHE_FILE = gears.filesystem.get_cache_dir() .. 'notification_history'

-- app_name stamped on this module's own feedback toasts. Recorded notifications
-- carrying it are dropped, otherwise every "No live client" toast would land in
-- the buffer and the popup would fill with its own output.
local SELF_APP = 'notification_history'

-- Apps whose notification payload is a plaintext secret. Their entries stay in
-- the in-memory list for the session but are never written to the cache file.
local NO_PERSIST_APPS = {
  'rofi%-rbw', 'rbw', 'pass', 'gopass', 'keepassxc', 'bitwarden',
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
      })
    end
  end
  f:close()

  entries = loaded
  while #entries > MAX_ENTRIES do table.remove(entries) end
  -- Trim the file back down; without this it grows forever across restarts.
  flush_cache()
end

--------------------------------------------------------------------------------
-- popup
--------------------------------------------------------------------------------

local popup
local grabber

-- Top right, the same corner naughty itself uses, so re-reading history lands
-- where the notifications originally appeared. honor_workarea keeps it below
-- the wibar instead of behind it.
--
-- Handed to awful.popup as its `placement` property rather than being called
-- manually after showing the popup: awful.popup only learns its real size
-- during the first widget layout pass, so a manual placement call right after
-- `visible = true` computes x from a stale width and lands the window off the
-- right edge. As a property, the popup reapplies it on every resize.
local function place_top_right(d)
  awful.placement.top_right(d, {
    parent         = awful.screen.focused(),
    honor_workarea = true,
    margins        = dpi(EDGE_MARGIN),
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
    maximum_width = dpi(POPUP_WIDTH),
    minimum_width = dpi(POPUP_WIDTH),
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
        label(relative_time(e.time), is_sel and beautiful.fg_normal_alt or DIM, dpi(COL_TIME)),
        label(e.app, is_sel and beautiful.fg_normal_alt or beautiful.fg_normal, dpi(COL_APP)),
        label(body, is_sel and beautiful.fg_focus or fg, dpi(COL_BODY)),
        -- Marker for entries that can still raise their source window.
        label((e.client and e.client.valid) and '⏎' or '', DIM, dpi(COL_MARK)),
        spacing = dpi(ROW_SPACING),
        layout  = wibox.layout.fixed.horizontal,
      },
      left = dpi(ROW_PADDING), right = dpi(ROW_PADDING), top = dpi(3), bottom = dpi(3),
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
  local footer = 'j/k move  ⏎ raise  y yank  d drop  C clear  q close'

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
  if grabber then grabber:stop() end
  if popup then popup.visible = false end
end

act_jump = function()
  local e = entries[selected]
  if not e then return end
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
  if #entries == 0 then
    notification_history.hide()
    return toast_empty()
  end
  render()
end

local function act_clear()
  entries = {}
  flush_cache()
  notification_history.hide()
  toast_empty()
end

--------------------------------------------------------------------------------
-- recording
--------------------------------------------------------------------------------

local function record(n)
  -- Our own feedback toasts must never be recorded, or acting on an entry
  -- appends a new entry and the buffer grows on every keypress.
  if n.app_name == SELF_APP then return end

  local title = oneline(n.title)
  local text = oneline(n.message or n.text)
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
  })
  while #entries > MAX_ENTRIES do table.remove(entries) end

  append_cache(entries[1])

  if popup and popup.visible then
    -- A new entry shifts everything down; follow the selection so the popup
    -- does not silently jump to a different notification under the cursor.
    if selected > 1 then selected = selected + 1 end
    render()
  end
end

--------------------------------------------------------------------------------
-- key handling
--------------------------------------------------------------------------------

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

grabber = awful.keygrabber {
  stop_key      = { 'Escape', 'q', 'n' },
  stop_event    = 'press',
  stop_callback = function() if popup then popup.visible = false end end,
  keypressed_callback = function(_, mod, key)
    handle_key(mod, key)
  end,
}

--------------------------------------------------------------------------------
-- public API
--------------------------------------------------------------------------------

function notification_history.show()
  if #entries == 0 then return toast_empty() end

  selected, offset = 1, 0
  render()
  local p = ensure_popup()
  p.visible = true
  -- Reassigning the placement property forces a resize-and-reposition pass, so
  -- the popup follows the currently focused screen when reopened elsewhere.
  p.placement = place_top_right
  grabber:start()
end

function notification_history.toggle()
  if popup and popup.visible then
    notification_history.hide()
  else
    notification_history.show()
  end
end

-- Exposed for other widgets/scripts that may want the raw list.
function notification_history.get_entries()
  return entries
end

load_cache()
naughty.connect_signal('added', function(n) record(n) end)

return notification_history
-- vim: set ts=2 sw=2 tw=0 et :
