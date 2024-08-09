local awful = require('awful')
local l = awful.layout.suit

-- create tags
tag_web = awful.tag.add('web', {
  layout = l.max,
  layouts = { l.max, l.tile },
  gap_single_client = false,
  gap = 4,
  selected = true,
})
if hostname == 'innodellix' or hostname == 'splinter' then
  tag_mail = awful.tag.add('mail', {
    layout = l.max,
    layouts = { l.max, l.tile },
  })
end
tag_term = awful.tag.add('term', {
  layout = l.max,
  layouts = { l.max, l.tile },
  gap_single_client = false,
  gap = 4,
})
tag_chat = awful.tag.add('chat', {
  layout = l.max,
  layouts = { l.max, l.tile },
  gap_single_client = false,
  gap = 4,
  master_width_factor = 0.5,
})
