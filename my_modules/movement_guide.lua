-- Floating-window movement guide. F10 (in rc.lua) toggles a set of four small
-- panels, each parked just off one edge of the focused floating client,
-- listing the Move / Expand / Shrink chords that act on that direction. The
-- panels reuse the OSD surface family so they read as part of the same UI.
--
-- Dismissed on any movement action (move_or_expand emits nothing special; the
-- tracked client simply changes geometry), on the tracked client losing focus,
-- or on a second F10. It is only ever shown for a floating, focused client.
--
-- The four wiboxes are destroyed at dismiss and re-created at the target
-- position on the next show, all within the same frame. Creating them already
-- at their final geometry (rather than moving a cached wibox) keeps compositor
-- move-animations (picom) from firing on the panel windows.

local beautiful = require('beautiful')
local wibox = require('wibox')
local gears = require('gears')

local dpi = beautiful.xresources.apply_dpi

local COLOR_MOVE = '#d79921' -- amber, profile of fg_normal
local COLOR_EXPAND = '#98971a' -- green, outward / grow
local COLOR_SHRINK = '#fb4934' -- soft red, inward / shrink
local COLOR_LABEL = '#ffffff'

-- Per-direction action -> keyboard chord.
local COMBOS = {
  up = { move = 'Win+Shift+W', expand = 'Ctrl+Win+↑', shrink = 'Ctrl+Win+Shift+↑' },
  down = { move = 'Win+Shift+S', expand = 'Ctrl+Win+↓', shrink = 'Ctrl+Win+Shift+↓' },
  left = { move = 'Win+Shift+A', expand = 'Ctrl+Win+←', shrink = 'Ctrl+Win+Shift+←' },
  right = { move = 'Win+Shift+D', expand = 'Ctrl+Win+→', shrink = 'Ctrl+Win+Shift+→' },
}
local ACTION_LABEL = { move = 'Move', expand = 'Expand', shrink = 'Shrink' }
local ACTION_COLOR = { move = COLOR_MOVE, expand = COLOR_EXPAND, shrink = COLOR_SHRINK }
local ACTION_ORDER = { 'move', 'expand', 'shrink' }
local DIR_ORDER = { 'up', 'down', 'left', 'right' }

-- Longest action label (Expand/Shrink at 6 chars); Move is shorter, so pad the
-- label column to this width for the combos to line up on one x across rows.
local MAX_LABEL_LEN = 0
for _, a in ipairs(ACTION_ORDER) do
  MAX_LABEL_LEN = math.max(MAX_LABEL_LEN, #ACTION_LABEL[a])
end

local PANEL_WIDTH = dpi(210)
local PANEL_HEIGHT = dpi(62)
local EDGE_GAP = dpi(6)

local tracked = nil -- client the guide is currently drawn around
local panels = {} -- live wiboxes, destroyed on dismiss / next show

local function clamp(v, lo, hi)
  if hi < lo then
    lo, hi = hi, lo
  end
  return math.max(lo, math.min(v, hi))
end

local function make_row(action, combo)
  local axcol = ACTION_COLOR[action]
  local label = ACTION_LABEL[action]

  -- FiraCode is monospace, so padding the label with nbsp to the longest label
  -- width aligns the following combo column on the same x in every row.
  local pad = string.rep('&#160;', math.max(0, MAX_LABEL_LEN - #label))
  local text = wibox.widget.textbox()
  text.markup = '<span font="'
    .. beautiful.font
    .. '">'
    .. '<span foreground="'
    .. COLOR_LABEL
    .. '">'
    .. label
    .. pad
    .. '</span>'
    .. '&#160;&#160;&#160;&#160;'
    .. '<span foreground="'
    .. axcol
    .. '">'
    .. combo
    .. '</span>'
    .. '</span>'

  return wibox.widget({
    widget = wibox.container.margin,
    left = 4,
    right = 4,
    top = 1,
    bottom = 1,
    {
      layout = wibox.layout.fixed.horizontal,
      spacing = 6,
      {
        widget = wibox.container.background,
        bg = axcol,
        forced_width = 3,
        forced_height = 16,
      },
      text,
    },
  })
end

local function build_panel(direction)
  local vbox = wibox.layout.fixed.vertical()
  vbox.spacing = 1
  for _, action in ipairs(ACTION_ORDER) do
    vbox:add(make_row(action, COMBOS[direction][action]))
  end
  return vbox
end

-- Screen-space slot for one direction's panel. Each panel sits just off its own
-- edge; when the window is flush to a screen border the outside slot has no
-- room, so it is clamped into the workarea and ends up overlapping the window's
-- own edge. That keeps it on the correct side: flipping it across to the
-- opposite edge would stack it on that side's panel (a bug surfaced when moving
-- a window already flush to the right border).
local function panel_slot(direction, cg, wa)
  local pw, ph, gap = PANEL_WIDTH, PANEL_HEIGHT, EDGE_GAP
  local x, y
  if direction == 'up' then
    x = clamp(cg.x + (cg.width - pw) / 2, wa.x, wa.x + wa.width - pw)
    y = clamp(cg.y - gap - ph, wa.y, wa.y + wa.height - ph)
  elseif direction == 'down' then
    x = clamp(cg.x + (cg.width - pw) / 2, wa.x, wa.x + wa.width - pw)
    y = clamp(cg.y + cg.height + gap, wa.y, wa.y + wa.height - ph)
  elseif direction == 'left' then
    y = clamp(cg.y + (cg.height - ph) / 2, wa.y, wa.y + wa.height - ph)
    x = clamp(cg.x - gap - pw, wa.x, wa.x + wa.width - pw)
  else -- right
    y = clamp(cg.y + (cg.height - ph) / 2, wa.y, wa.y + wa.height - ph)
    x = clamp(cg.x + cg.width + gap, wa.x, wa.x + wa.width - pw)
  end
  return x, y
end

-- Create one panel as a brand-new wibox already at its final geometry. x/y are
-- set before mapping so the compositor never sees the window move.
local function make_panel(c, direction, cg, wa)
  local x, y = panel_slot(direction, cg, wa)
  return wibox({
    widget = build_panel(direction),
    screen = c.screen,
    x = x,
    y = y,
    width = PANEL_WIDTH,
    height = PANEL_HEIGHT,
    visible = true,
    ontop = true,
    bg = beautiful.osd_bg,
    shape = function(cr, w, h) gears.shape.rounded_rect(cr, w, h, 2) end,
    shape_border_width = 1,
    shape_border_color = beautiful.border_focus,
  })
end

local function destroy_panels()
  for _, p in pairs(panels) do
    if p and p.valid then
      p.visible = false
      if p.destroy then
        p:destroy()
      end
    end
  end
  panels = {}
end

local movement_guide = {}

function movement_guide.show(c)
  if not c or not c.valid or not c.floating then
    return
  end
  destroy_panels()
  tracked = c
  local cg = c:geometry()
  local wa = c.screen.workarea
  for _, dir in ipairs(DIR_ORDER) do
    panels[dir] = make_panel(c, dir, cg, wa)
  end
end

function movement_guide.dismiss()
  destroy_panels()
  tracked = nil
end

function movement_guide.toggle()
  local c = client.focus
  if tracked then
    movement_guide.dismiss()
    return
  end
  if c and c.valid and c.floating then
    movement_guide.show(c)
  end
end

-- Dismissal backstops. The primary one is the geometry hook: any movement /
-- resize action on the tracked client fires it, and that also covers mouse
-- driven moves while the guide is up. move_or_expand also dismisses directly
-- (so a chord pressed at a clamped edge, where geometry does not change, still
-- closes the guide).
client.connect_signal('property::geometry', function(c)
  if tracked == c then
    movement_guide.dismiss()
  end
end)
client.connect_signal('unfocus', function(c)
  if tracked == c then
    movement_guide.dismiss()
  end
end)

-- Exposed globally so move_or_expand (dofile'd earlier than this module can be
-- required) can dismiss without a circular require.
_G.movement_guide = movement_guide

return movement_guide
