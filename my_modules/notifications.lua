-- Notification popups drawn to match the OSD (my_modules/osd.lua).
--
-- naughty stays in charge of everything that makes a notification more than an
-- OSD card: the dbus service, stacking, timeouts, actions, click-to-dismiss.
-- Only the rendering is taken over, so a notification and an OSD card on screen
-- at the same moment share one surface (translucent bg, hairline border, small
-- corner radius) and one color language: the accent on the border and title
-- says what kind of event it is before the text is read.
--
-- Must be required after beautiful.init(), the theme is read at display time
-- but the naughty widgets below resolve their defaults when first loaded.

local beautiful = require('beautiful')
local naughty = require('naughty')
local wibox = require('wibox')
local dpi = beautiful.xresources.apply_dpi
local my_utils = require('my_modules/my_utils')

-- Urgency is the only thing that picks the accent. Colors a sender or a rule
-- puts on the notification itself (bg, border_color) are deliberately not
-- honored: one app with its own palette is enough to break the family look.
local function accent_for(n)
  return beautiful['notification_accent_' .. tostring(n.urgency)]
    or beautiful.notification_accent_normal
    or beautiful.fg_normal
end

-- naughty.widget.title colors itself from the notification's fg, which is also
-- what the message uses, so the two could never differ. This one takes the
-- accent instead, mirroring the OSD card: first line in the accent, the rest in
-- the regular foreground.
local function title_widget(accent)
  local tb = wibox.widget({
    widget = wibox.widget.textbox,
    font = beautiful.font,
    valign = 'center',
  })

  local function update(n)
    local title = n.title or ''
    -- an empty textbox still claims a line (lain's calendar has no title)
    tb.visible = title ~= ''
    tb:set_markup_silently(
      string.format('<span foreground="%s">%s</span>', accent, my_utils.pango_escape(title))
    )
  end

  -- naughty.layout.box hands the notification to every widget in the template
  -- that has this setter. rawset because the widget's __newindex would treat a
  -- plain assignment as a property write.
  rawset(tb, 'set_notification', function(_, n)
    update(n)
    -- apps update a live notification in place (replaces_id), e.g. progress
    n:connect_signal('property::title', update)
  end)

  return tb
end

naughty.connect_signal('request::display', function(n)
  local accent = accent_for(n)

  -- bg, shape and border width come from beautiful.notification_*, which the
  -- theme derives from the OSD's values. No `background_role` widget in the
  -- template on purpose: naughty would then restyle it from the notification's
  -- own colors and zero the popup border.
  naughty.layout.box({
    notification = n,
    border_color = accent,
    widget_template = {
      {
        {
          {
            naughty.widget.icon,
            {
              title_widget(accent),
              naughty.widget.message,
              spacing = dpi(2),
              layout = wibox.layout.fixed.vertical,
            },
            fill_space = true,
            spacing = dpi(10),
            layout = wibox.layout.fixed.horizontal,
          },
          naughty.list.actions,
          spacing = dpi(8),
          layout = wibox.layout.fixed.vertical,
        },
        margins = beautiful.notification_margin,
        widget = wibox.container.margin,
      },
      strategy = 'max',
      width = beautiful.notification_max_width,
      widget = wibox.container.constraint,
    },
  })
end)
