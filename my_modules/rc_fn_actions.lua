local awful = require('awful')
local beautiful = require('beautiful')
local gears = require('gears')
local helpers = require('my_modules/geo_helpers')
local wibox = require('wibox')
local dpi = require('beautiful').xresources.apply_dpi

local function create_slider_widget(color)
  local sliderwidget = wibox.widget({
    {
      max_value = 100,
      value = 33,
      background_color = beautiful.slider_bg .. '50',
      color = color,
      shape = gears.shape.rounded_bar,
      bar_shape = gears.shape.rounded_bar,
      widget = wibox.widget.progressbar,
    },
    forced_height = dpi(250),
    forced_width = dpi(20),
    direction = 'east',
    layout = wibox.container.rotate,
  })

  return sliderwidget
end

sound_slider = create_slider_widget(beautiful.slider_sound_fg)
brightness_slider = create_slider_widget(beautiful.slider_brightness_fg)

widget_margins = {
  top = dpi(100),
  right = dpi(5),
}

-- {{{ Brightness / mute / sound slider - notify stuff
vb_slider = awful.popup({
  widget = sound_slider,
  visible = false,
  bg = '#00000000', -- fully transparent
  ontop = true,
  shape = helpers.rrect(beautiful.border_radius),
  placement = function(c)
    awful.placement.top_right(c, {
      margins = widget_margins,
    })
  end,
})

local function create_text_widget(markup)
  local textwidget = wibox.widget({
    {
      markup = markup,
      font = beautiful.font_name .. dpi(12),
      align = 'center',
      valign = 'center',
      widget = wibox.widget.textbox,
    },
    direction = 'west',
    layout = wibox.container.rotate,
  })

  return textwidget
end

textwidget = create_text_widget('')

vb_textinfo = awful.popup({
  widget = textwidget,
  visible = false,
  bg = beautiful.bg_notification .. '60',
  ontop = true,
  shape = helpers.rrect(beautiful.border_radius),
  placement = function(c)
    awful.placement.top_right(c, {
      margins = widget_margins,
    })
  end,
})

slider_timer = gears.timer({
  timeout = 1.2,
  callback = function()
    vb_slider.visible = false
    vb_textinfo.visible = false
  end,
})

triggerwibox = function(action)
  vb_slider.screen = awful.screen.focused()
  vb_textinfo.screen = awful.screen.focused()
  if action == 'volume' then
    vb_slider.widget = sound_slider
    vb_textinfo.visible = false
    vb_slider.visible = true
  elseif action == 'brightness' then
    vb_slider.widget = brightness_slider
    vb_textinfo.visible = false
    vb_slider.visible = true
  elseif action == 'mute' then
    textwidget.widget.markup = '  🔇 <i>Sound muted</i>'
    vb_slider.visible = false
    vb_textinfo.visible = true
  elseif string.match(action, 'Stopped') then
    textwidget.widget.markup = '⬛ <i>Stopped</i>'
    vb_slider.visible = false
    vb_textinfo.visible = true
  elseif string.match(action, 'Playing') then
    textwidget.widget.markup = '▶️ <i>Playing</i>'
    vb_slider.visible = false
    vb_textinfo.visible = true
  elseif string.match(action, 'Paused') then
    textwidget.widget.markup = '⏸️ <i>Paused</i>'
    vb_slider.visible = false
    vb_textinfo.visible = true
  elseif action == 'micmute' then
    textwidget.widget.markup = '🎙️🟥 <i>Mic Muted</i>'
    vb_slider.visible = false
    vb_textinfo.visible = true
  elseif action == 'micunmute' then
    textwidget.widget.markup = '🎙️🟩 <i>Mic Unmuted</i>'
    vb_slider.visible = false
    vb_textinfo.visible = true
  end
  slider_timer:again()
end

function fn_process_action(action, direction, player)
  direction = direction or 'toggle'
  player = player or nil

  -- Case 1: Sound mute toggle
  if action == 'sink' then
    if direction == 'toggle' then
      -- directly toggle and print the result
      awful.spawn.easy_async('pamixer -t --get-mute', function(stdout, stderr, reason, exit_code)
        stdout = stdout:gsub('%s+', '') -- f*king whitespaces
        if stdout == 'true' then
          triggerwibox('mute')
        else
          helpers.async('pamixer --get-volume', function(out)
            sound_slider.widget.value = tonumber(out)
            triggerwibox('volume')
          end)
        end
      end)
    else
      -- Case 2: Volume up/down
      if direction == 'up' then
        word = 'i'
      elseif direction == 'down' then
        word = 'd'
      end
      helpers.async('pamixer --get-volume --allow-boost -' .. word .. ' 5', function(out)
        sound_slider.widget.value = tonumber(out)
        if tonumber(out) > 100 then
          sound_slider.forced_height = dpi(250 + tonumber(out) - 100)
          sound_slider.widget.color = '#FF0000'
        else
          sound_slider.forced_height = dpi(250)
          sound_slider.widget.color = beautiful.slider_sound_fg
        end
        triggerwibox('volume')
      end)
    end

  -- Case 3: Mic mute toggle
  elseif action == 'source' then
    if direction == 'toggle' then
      -- Query current state first (forces sync with hardware), then toggle
      awful.spawn.easy_async(
        'pamixer --default-source --get-mute',
        function(stdout, stderr, reason, exit_code)
          stdout = stdout:gsub('%s+', '') -- f*king whitespaces
          local was_muted = (stdout == 'true')
          -- Toggle the state
          awful.spawn.easy_async('pamixer --default-source -t', function()
            -- Show notification for the NEW state (opposite of what it was)
            if was_muted then
              triggerwibox('micunmute')
            else
              triggerwibox('micmute')
            end
          end)
        end
      )
    end

  -- Case 4: Brightness up/down
  elseif action == 'brightness' then
    if direction == 'up' then
      symbol = '+'
    elseif direction == 'down' then
      symbol = '-'
    end

    -- use ddcutil if we are on external monitor, otherwise use brightnessctl
    if detect_external_monitor() then
      set_command = 'sudo ddcutil setvcp 10 ' .. symbol .. ' 5'
      get_command = 'get-ddc-current-brightness'
      max_command = 'get-ddc-max-brightness'
    else
      set_command = 'brightnessctl -q s 5%-' .. symbol
      get_command = 'brightnessctl -q get'
      max_command = 'brightnessctl -q max'
    end

    helpers.async(set_command, function(out)
      awful.spawn.easy_async(get_command, function(current)
        awful.spawn.easy_async(max_command, function(max)
          brightness_slider.widget.value = 100 * tonumber(current) / tonumber(max)
          triggerwibox('brightness')
        end)
      end)
    end)

  -- Case 5: Media keys
  elseif action == 'media' then
    show_osd = false
    if direction == 'pausetoggle' then
      if player ~= nil then
        helpers.async('playerctl play-pause -p ' .. player, function(out) end)
      else
        helpers.async('playerctl play-pause', function(out) end)
      end
      show_osd = true
    elseif direction == 'stop' then
      if player ~= nil then
        helpers.async('playerctl stop -p ' .. player, function(out) end)
      else
        helpers.async('playerctl stop', function(out) end)
      end
      show_osd = true
    elseif direction == 'next' then
      if player ~= nil then
        helpers.async('playerctl next -p ' .. player, function(out) end)
      else
        helpers.async('playerctl next', function(out) end)
      end
    elseif direction == 'previous' then
      if player ~= nil then
        helpers.async('playerctl previous -p ' .. player, function(out) end)
      else
        helpers.async('playerctl previous', function(out) end)
      end
    end
    if show_osd then
      if player ~= nil then
        helpers.async('playerctl status -p ' .. player, function(out) triggerwibox(out) end, 0.3)
      else
        helpers.async('playerctl status', function(out) triggerwibox(out) end, 0.3)
      end
    end
  end
end
