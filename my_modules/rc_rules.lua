local awful = require('awful')
local beautiful = require('beautiful')
local ruled = require('ruled.client')
local my_utils = require('my_modules/my_utils')
local xresources = require('beautiful.xresources')
local dpi = xresources.apply_dpi

local function safe_no_overlap_func(c, args)
    local s = c.screen
    if not s or not s.selected_tag then return end
    return awful.placement.no_overlap(c, args)
end

-- hacky no_overlap definition for some edge cases, limited usage, might be removed later
local safe_no_overlap = setmetatable(
    { is_placement = true },
    {
        __call = function(_, ...) return safe_no_overlap_func(...) end,
        __add  = getmetatable(awful.placement.no_offscreen).__add,
    }
)

function set_rules(clientkeys)
  -- {{{ Rules
  -- Rules to apply to new clients (through the "manage" signal).
  ruled.append_rules {

    -- All clients will match this rule.
    {
      rule = {},
      properties = {
        border_width = beautiful.border_width,
        border_color = beautiful.border_normal,
        focus = awful.client.focus.filter,
        raise = true,
        keys = clientkeys,
        buttons = clientbuttons,
        screen = awful.screen.preferred,
        maximized_horizontal = false,
        maximized_vertical = false,
        maximized = false,
        placement = safe_no_overlap + awful.placement.no_offscreen,
      },
    },
    -- Floating clients.
    {
      rule_any = {
        instance = {
          'copyq', -- Includes session name in class.
          'pinentry',
        },
        type = {
          'popup_menu',
          'dropdown_menu',
          'toolbar',
          'dialog',
          'menu',
          'notification',
        },
        class = {
          'Arandr',
          'Blueman-manager',
          'Gpick',
          'Kruler',
          'MessageWin', -- kalarm.
          'myshittydropdown',
          'Sxiv',
          'Tor Browser', -- Needs a fixed window size to avoid fingerprinting by screen size.
          'Wpa_gui',
          'veromix',
          'xtightvncviewer',
          'gcr-prompter',
          'Gcr-prompter',
          'mpv',
          "No Man's Sky",
        },
        -- Note that the name property shown in xprop might be set slightly after creation of the client
        -- and the name shown there might not match defined rules here.
        name = {
          'Event Tester', -- xev.
          'myshittydropdown',
        },
        role = {
          'AlarmWindow', -- Thunderbird's calendar.
          'ConfigManager', -- Thunderbird's about:config.
          'pop-up', -- e.g. Google Chrome's (detached) Developer Tools.
          'menu',
        },
      },
      properties = {
        floating = true,
      },
    },

    {
      rule = {
        name = 'Media viewer',
        class = 'TelegramDesktop',
      },
      properties = {
        titlebars_enabled = false,
        ontop = true,
        floating = true,
        fullscreen = false,
        maximized = true,
        placement = awful.placement.centered,
      },
    },

    {
      rule = {
        name = 'Microsoft Teams Notification',
      },
      properties = {
        focus = false,
        draw_backdrop = false,
        titlebars_enabled = false,
        ontop = true,
        sticky = true,
        skip_taskbar = true,
        floating = true,
        callback = function(c) awful.placement.top_right(c, { honor_workarea = true }) end,
      },
    },

    {
      rule = {
        name = 'Picture-in-Picture',
      },
      properties = {
        ontop = true,
        sticky = true,
        skip_taskbar = true,
        floating = true,
        dockable = false,
      },
    },

    {
      rule = {
        name = 'Onboard',
      },
      properties = {
        focusable = false,
        ontop = true,
        sticky = true,
        skip_taskbar = true,
        floating = true,
      },
    },

    {
      rule_any = {
        class = {
          'chromium-browser',
          'gathertown',
        },
      },
      properties = {
        ontop = true,
        floating = true,
        sticky = true,
        skip_taskbar = true,
        width = dpi(1800),
        height = dpi(250),
        callback = function(c) awful.placement.top_right(c, { honor_workarea = true }) end,
      },
    },

    -- Titlebars
    {
      rule_any = {
        type = {
          'dialog',
        },
        class = {
          'gcr-prompter',
          'Gcr-prompter',
        },
        name = {
          'Discord Updater',
        },
      },
      properties = {
        titlebars_enabled = true,
        placement = awful.placement.centered,
        height = dpi(500),
        width = dpi(600),
      },
    },

    {
      rule = {
        type = 'normal',
      },
      except_any = {
        class = {
          'gcr-prompter',
          'Gcr-prompter',
        },
      },
      properties = {
        titlebars_enabled = false,
      },
    },

    -- Window binding
    {
      rule_any = {
        class = {
          'firefox',
          'browser',
        },
      },
      except_any = {
        class = {
          'gathertown',
        },
      },
      properties = {
        tag = awful.tag.find_by_name(nil, 'web'),
      },
    },

    {
      rule_any = {
        class = {
          'Alacritty',
          'org.wezfurlong.wezterm',
          'mainqterm',
        },
      },
      except_any = {
        class = {
          'myshittydropdown',
        },
      },
      properties = {
        tag = awful.tag.find_by_name(nil, 'term'),
        size_hints_honor = false, -- don't try to be clever
      },
    },
    {
      rule_any = {
        class = {
          'Slack',
          'TelegramDesktop',
          'org.telegram.desktop',
          'Microsoft Teams - Preview',
          'discord',
          '.zoom ',
        },
        name = {
          'Zoom - Free Account',
        },
      },
      except = {
        name = 'Media viewer',
      },
      properties = {
        tag = awful.tag.find_by_name(nil, 'chat'),
      },
    },
    {
      rule_any = {
        class = {
          'Daily',
          'Mail',
          'thunderbird',
          'betterbird',
          -- "Soffice" -- << Really? Hidden class for open files, FUCK LIBREOFFICE
        },
      },
      except_any = {
        type = {
          'dialog',
        },
      },
      properties = {
        tag = awful.tag.find_by_name(nil, 'mail'),
        maximized = true,
      },
    },

    -- Disable shadows on specific clients (same as picom rules)
    {
      id = "compositor_no_shadow",
      rule_any = {
        class = { "firefox", "thunderbird", "TelegramDesktop", "org.telegram.desktop" },
        type  = { "menu", "dropdown_menu", "popup_menu" },
        name  = { "", },
      },
      properties = { shadow = false },
    },
  }
end
