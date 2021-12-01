local awful = require("awful")
local beautiful = require("beautiful")
local gears = require("gears")
local helpers = require("my_modules/geo_helpers")
local wibox = require("wibox")

-- {{{ Brightness / mute / sound slider - notify stuff
vb_slider = awful.popup {
  widget =
  {
    max_value        = 100,
    value            = 33,
    forced_height    = 8,
    forced_width     = 300,
    --border_width     = 0,
    border_color     = beautiful.border_normal, -- .. " 00",
    background_color = beautiful.slider_bg,
    color            = beautiful.slider_bg,
    bar_shape        = helpers.rrect(beautiful.border_radius),
    widget           = wibox.widget.progressbar,
  },
  visible   = false,
  ontop     = true,
  shape     = helpers.rrect(beautiful.border_radius),
  placement = awful.placement.centered,
}

vb_textinfo= awful.popup {
  widget =
  {
    forced_height    = 30,
    forced_width     = 200,
    border_color     = beautiful.border_normal, -- .. " 00",
    background_color = beautiful.slider_bg,
    color            = beautiful.slider_bg,
    bar_shape        = helpers.rrect(beautiful.border_radius),
    widget           = wibox.widget.textbox,
  },
  visible   = false,
  ontop     = true,
  shape     = helpers.rrect(beautiful.border_radius),
  placement = awful.placement.centered,
}

slider_timer = gears.timer({
	timeout = 1.2,
	callback = function()
		vb_slider.visible = false
		vb_textinfo.visible = false
	end
})

triggerwibox = function(action)
  vb_slider.screen = awful.screen.focused()
  vb_textinfo.screen = awful.screen.focused()
  if action == 'volume' then
    vb_slider.widget.color = beautiful.slider_sound_fg
    vb_textinfo.visible = false
    vb_slider.visible = true
  elseif action == 'brightness' then
    vb_slider.widget.color = beautiful.slider_brightness_fg
    vb_textinfo.visible = false
    vb_slider.visible = true
  elseif action == 'mute' then
    vb_textinfo.widget.markup = '  🔇 Mute Toggle'
    vb_slider.visible = false
    vb_textinfo.visible = true
  elseif string.match(action, 'Stopped') then
    vb_textinfo.widget.markup = '⬛ Stopped'
    vb_slider.visible = false
    vb_textinfo.visible = true
  elseif string.match(action, 'Playing') then
    vb_textinfo.widget.markup = '▶️ Playing'
    vb_slider.visible = false
    vb_textinfo.visible = true
  elseif string.match(action, 'Paused') then
    vb_textinfo.widget.markup = '⏸️ Paused'
    vb_slider.visible = false
    vb_textinfo.visible = true
  elseif action == 'micmute' then
    vb_textinfo.widget.markup = '🎙️🔇 Mic Mute Toggle'
    vb_slider.visible = false
    vb_textinfo.visible = true
  end
  slider_timer:again()
end

function handle_media(action)
  helpers.async("playerctl " .. action, function() end)
  if action == "play-pause" or action == "stop" then
    helpers.async("playerctl status", function(out)
      triggerwibox(out)
    end, 0.3)
  end
  return true
end

function reset_pulse()
  helpers.async("pacmd suspend 1", function(out)
    print("Resetting pulse..")
    helpers.async("pacmd suspend 0", function() end)
  end)
  return true
end

function get_screen_of_focused()
	-- check if any client is focused
	local c = client.focus
	if c then
			-- found focus, return its screen
			return c.screen
	end
end

function unminimize_client()
	local c = awful.client.restore()
	-- Focus restored client
	if c then
		c:emit_signal(
			"request::activate", "key.unminimize", {raise = true}
		)
	end
end

function set_brightness(val)
	helpers.async("sudo brightnessctl -q s " .. val, function()
		awesome.emit_signal("brightness:change")
	end)
end

function set_volume(action)
	helpers.async("pamixer -" .. action .. " 5", function(out)
		awesome.emit_signal("volume::change")
	end)
end

function audio_mute()
  helpers.async("pamixer -t", function(out)
		awesome.emit_signal("volume::change")
    triggerwibox('mute')
  end)
end

function mic_mute()
		awful.spawn("pulseaudio-toggle-hack")
		triggerwibox('micmute')
end
