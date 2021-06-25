local awful = require("awful")
local beautiful = require("beautiful")
local my_utils = require('my_modules/my_utils')

local function find_tag_for(tagname, role)
  role = role or 'primary'

  if my_utils.table_length(screen_table) == 1 and role ~= 'primary' then
    -- if there is only 1 screen, it's also secondary
    role = "primary"
  end

  for screen, values in pairs(screen_table) do
    if values["role"] == role then
      if my_utils.table_contains(values["tags"], tagname, true) then
        return values["tags"][tagname]
      end
    end
  end
end

function set_rules(clientkeys)
  -- {{{ Rules
  -- Rules to apply to new clients (through the "manage" signal).
  awful.rules.rules = {
    -- All clients will match this rule.
    { rule = { },
      properties = {
        border_width         = beautiful.border_width,
        border_color         = beautiful.border_normal,
        focus                = awful.client.focus.filter,
        raise                = true,
        keys                 = clientkeys,
        buttons              = clientbuttons,
        screen               = awful.screen.preferred,
        maximized_horizontal = false,
        maximized_vertical   = false,
        maximized            = false,
        placement            = awful.placement.no_overlap+awful.placement.no_offscreen
      }
    },
    -- Floating clients.
    {
      rule_any = {
        instance = {
          "copyq",  -- Includes session name in class.
          "pinentry",
        },
        type = {
          "popup_menu",
          "dropdown_menu",
          "toolbar",
          "dialog",
          "menu",
          "notification",
        },
        class = {
          "Arandr",
          "Blueman-manager",
          "Gpick",
          "Kruler",
          "MessageWin",  -- kalarm.
          "myshittydropdown",
          "Sxiv",
          "Tor Browser", -- Needs a fixed window size to avoid fingerprinting by screen size.
          "Wpa_gui",
          "veromix",
          "xtightvncviewer",
          "gcr-prompter",
          "Gcr-prompter"
        },
        -- Note that the name property shown in xprop might be set slightly after creation of the client
        -- and the name shown there might not match defined rules here.
        name = {
          "Event Tester",  -- xev.
          "myshittydropdown",
        },
        role = {
          "AlarmWindow",  -- Thunderbird's calendar.
          "ConfigManager",  -- Thunderbird's about:config.
          "pop-up",     -- e.g. Google Chrome's (detached) Developer Tools.
          "menu",
        }
      },
      properties = {
        floating = true
      }
    },

    {
      rule = {
        name = "Microsoft Teams Notification",
        type = "notification"
      },
      properties = {
        focusable = false,
        ontop = true,
        sticky = true,
        skip_taskbar = true,
        floating = true,
        -- placement = awful.placement.top_right,
        callback = function(c) awful.placement.top_right(c, {honor_workarea=true}) end,
      };
    },

    {
      rule_any = {
        class = {
          "chromium-browser",
          "gathertown",
        },
      },
      properties = {
        ontop = true,
        floating = true,
        screen = secondary_screen_name,
        sticky = true,
        skip_taskbar = true,
        width = 533,
        y = 20,
        height = 860,
        callback = function(c) awful.placement.top_right(c, {honor_workarea=true}) end,
      };
    },

    -- Titlebars
    {
      rule_any = {
        type = {
          "dialog"
        },
        class = {
          "gcr-prompter",
          "Gcr-prompter"
        }
      },
      properties = {
        titlebars_enabled = true,
        placement = awful.placement.centered,
      }
    },

    {
      rule = {
        type = "normal"
      },
      except_any = {
        class = {
          "gcr-prompter",
          "Gcr-prompter"
        }
      },
      properties = {
        titlebars_enabled = false
      }
    },

    -- Window binding
    {
      rule_any = {
        class = {
          "Firefox",
          "browser"
        },
      },
      except_any = {
        class = {
          "gathertown"
        }
      },
      properties = {
        tag    = find_tag_for("web"),
        screen = screen_table["primary"],
      }
    },

    {
      rule_any = {
        class = {
          "Alacritty",
          "org.wezfurlong.wezterm",
          "mainqterm"
        }
      },
      except_any = {
        class = {
          "myshittydropdown"
        }
      },
      properties = {
        tag    = find_tag_for("term", "secondary"),
        screen = screen_table["secondary"],
      }
    },
    {
      rule_any = {
        class = {
          "Slack",
          "TelegramDesktop",
          "Microsoft Teams - Preview",
          "discord",
          "zoom"
        }
      },
      properties = {
        tag    = find_tag_for("chat", "secondary"),
        screen = screen_table["secondary"],
      }
    },
    {
      rule_any = {
        class = {
          "Daily",
          "Mail",
          "Thunderbird"
          -- "Soffice" -- << Really? Hidden class per open files, FUCK LIBREOFFICE
        }
      },
      properties = {
        tag    = find_tag_for("mail"),
        screen = screen_table["primary"],
      }
    },
  }
end
