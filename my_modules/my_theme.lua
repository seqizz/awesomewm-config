---------------------------
-- Default awesome theme --
---------------------------

local theme_assets = require("beautiful.theme_assets")
local xresources = require("beautiful.xresources")
local dpi = xresources.apply_dpi

local gfs = require("gears.filesystem")
local shape = require("gears.shape")
local themes_path = gfs.get_themes_dir()

local theme = {}

theme.font_name = "FiraCode Nerd Font Medium"
theme.font = theme.font_name .. " 10"
theme.font_big = theme.font_name .. " 12"
theme.font_small = theme.font_name .. " 8"
theme.emoji_font = "Twitter Color Emoji"

theme.maximized_hide_border = true
theme.fullscreen_hide_border = true
theme.master_width_factor = 0.6

theme.bg_normal     = "#282828"
theme.bg_focus      = "#504945"
theme.bg_urgent     = "#dc322f"
theme.bg_minimize   = theme.bg_normal
theme.bg_systray    = theme.bg_normal

theme.nord_mid      = "#81a1c1"

theme.fg_normal       = "#d79921"
theme.fg_normal_alt   = "#fabd2f"
theme.fg_focus        = "#ffffff"
theme.fg_urgent       = "#ffffff"
theme.fg_minimize     = "#ffffff"
theme.bg_notification = theme.bg_normal

theme.useless_gap   = dpi(0)
theme.border_width  = dpi(1)
theme.border_marked = "#91231c"
theme.border_focus  = "#d65d0e"
theme.border_normal = "#252525"
-- theme.separator     = theme.bg_focus
theme.separator     = theme.bg_focus

theme.slider_bg            = "#e3e3e3"
theme.slider_sound_fg      = theme.fg_normal
theme.slider_brightness_fg = theme.nord_mid
theme.border_radius        = 2

-- relative paths, so fucking easy with lua..
local base_dir = string.gsub(debug.getinfo(1).source, "^@(.+/)[^/]+$", "%1")
theme.gauge_icon = base_dir .. 'assets/gauge.svg'
theme.battery_icon_empty = base_dir .. 'assets/battery.svg'
theme.battery_icon_charging = base_dir .. 'assets/battery-charging.svg'
theme.battery_icon_full = base_dir .. 'assets/battery-full.svg'
theme.battery_icon_medium = base_dir .. 'assets/battery-medium.svg'
theme.battery_icon_low = base_dir .. 'assets/battery-low.svg'
theme.music_icon = base_dir .. 'assets/music.svg'
theme.music_icon_paused = base_dir .. 'assets/pause.svg'
theme.thing_icon_left = base_dir .. 'assets/thing_icon_left.svg'
theme.thing_icon_right = base_dir .. 'assets/thing_icon_right.svg'

-- Notifications
-- theme.notification_font = "Operator Mono Lig, Twitter Color Emoji"
theme.notification_opacity = 0.9
theme.notification_margin = dpi(15)
theme.notification_icon_size = dpi(50)
theme.notification_max_width = dpi(600)
local ntf_shape = function(cr, width, height)
   shape.partially_rounded_rect(cr, width, height, true, false, true, true, 18)
end
theme.notification_shape = ntf_shape
theme.notification_bg = theme.bg_notification

-- Generate taglist squares:
local taglist_square_size = dpi(4)
theme.taglist_squares_sel = theme_assets.taglist_squares_sel(
    taglist_square_size, theme.fg_normal
)
theme.taglist_squares_unsel = theme_assets.taglist_squares_unsel(
    taglist_square_size, theme.fg_normal
)

local tagshape = function(cr, width, height)
    shape.powerline(cr,width,height)
end
theme.taglist_shape = tagshape
theme.taglist_shape_focus = tagshape
theme.taglist_shape_border_width = 2
theme.taglist_shape_border_color = theme.separator
-- theme.taglist_spacing0= 0

theme.menu_submenu_icon = themes_path.."default/submenu.png"
theme.menu_height = dpi(15)
theme.menu_width  = dpi(100)

theme.titlebar_close_button_normal = themes_path.."default/titlebar/close_normal.png"
theme.titlebar_close_button_focus  = themes_path.."default/titlebar/close_focus.png"

theme.titlebar_minimize_button_normal = themes_path.."default/titlebar/minimize_normal.png"
theme.titlebar_minimize_button_focus  = themes_path.."default/titlebar/minimize_focus.png"

theme.titlebar_ontop_button_normal_inactive = themes_path.."default/titlebar/ontop_normal_inactive.png"
theme.titlebar_ontop_button_focus_inactive  = themes_path.."default/titlebar/ontop_focus_inactive.png"
theme.titlebar_ontop_button_normal_active = themes_path.."default/titlebar/ontop_normal_active.png"
theme.titlebar_ontop_button_focus_active  = themes_path.."default/titlebar/ontop_focus_active.png"

theme.titlebar_sticky_button_normal_inactive = themes_path.."default/titlebar/sticky_normal_inactive.png"
theme.titlebar_sticky_button_focus_inactive  = themes_path.."default/titlebar/sticky_focus_inactive.png"
theme.titlebar_sticky_button_normal_active = themes_path.."default/titlebar/sticky_normal_active.png"
theme.titlebar_sticky_button_focus_active  = themes_path.."default/titlebar/sticky_focus_active.png"

theme.titlebar_floating_button_normal_inactive = themes_path.."default/titlebar/floating_normal_inactive.png"
theme.titlebar_floating_button_focus_inactive  = themes_path.."default/titlebar/floating_focus_inactive.png"
theme.titlebar_floating_button_normal_active = themes_path.."default/titlebar/floating_normal_active.png"
theme.titlebar_floating_button_focus_active  = themes_path.."default/titlebar/floating_focus_active.png"

theme.titlebar_maximized_button_normal_inactive = themes_path.."default/titlebar/maximized_normal_inactive.png"
theme.titlebar_maximized_button_focus_inactive  = themes_path.."default/titlebar/maximized_focus_inactive.png"
theme.titlebar_maximized_button_normal_active = themes_path.."default/titlebar/maximized_normal_active.png"
theme.titlebar_maximized_button_focus_active  = themes_path.."default/titlebar/maximized_focus_active.png"

theme.wallpaper = themes_path.."default/background.png"

-- You can use your own layout icons like this:
theme.layout_fairh = themes_path.."default/layouts/fairhw.png"
theme.layout_fairv = themes_path.."default/layouts/fairvw.png"
theme.layout_floating  = themes_path.."default/layouts/floatingw.png"
theme.layout_magnifier = themes_path.."default/layouts/magnifierw.png"
theme.layout_max = themes_path.."default/layouts/maxw.png"
theme.layout_fullscreen = themes_path.."default/layouts/fullscreenw.png"
theme.layout_tilebottom = themes_path.."default/layouts/tilebottomw.png"
theme.layout_tileleft   = themes_path.."default/layouts/tileleftw.png"
theme.layout_tile = themes_path.."default/layouts/tilew.png"
theme.layout_tiletop = themes_path.."default/layouts/tiletopw.png"
theme.layout_spiral  = themes_path.."default/layouts/spiralw.png"
theme.layout_dwindle = themes_path.."default/layouts/dwindlew.png"
theme.layout_cornernw = themes_path.."default/layouts/cornernww.png"
theme.layout_cornerne = themes_path.."default/layouts/cornernew.png"
theme.layout_cornersw = themes_path.."default/layouts/cornersww.png"
theme.layout_cornerse = themes_path.."default/layouts/cornersew.png"

-- Generate Awesome icon:
theme.awesome_icon = theme_assets.awesome_icon(
    theme.menu_height, theme.bg_focus, theme.fg_focus
)

theme.icon_theme = nil

return theme

-- vim: filetype=lua:expandtab:shiftwidth=4:tabstop=8:softtabstop=4:textwidth=80
