local awful = require('awful')
local gears = require('gears')
local wibox = require('wibox')
local dpi = require('beautiful').xresources.apply_dpi

-- Helpful functions
dofile(gears.filesystem.get_configuration_dir() .. "my_modules/rc_functions.lua")

-- Default colors (solarized)
local COLOR_ENABLED = '#268bd2'
local COLOR_DISABLED = '#cb4b16'
local COLOR_ERROR = '#FF0000'

--[[
  Create a generic toggle widget.

  opts = {
    check_cmd = "command to check state",
    enabled_pattern = "string that indicates enabled state in check_cmd output",
    disabled_pattern = "string that indicates disabled state (optional, safer matching)",

    -- Either provide toggle_cmd OR enable_cmd + disable_cmd
    toggle_cmd = "single command that toggles state",
    enable_cmd = "command to enable",
    disable_cmd = "command to disable",

    -- Icon (SVG/PNG image path)
    icon = "/path/to/icon.svg",

    -- Tooltips
    tooltip_on = "Tooltip when enabled",
    tooltip_off = "Tooltip when disabled",
    tooltip_error = "Tooltip on error",  -- optional

    -- Optional color overrides
    color_enabled = "#268bd2",
    color_disabled = "#cb4b16",

    -- Optional background colors (nil = transparent)
    background_enabled = nil,
    background_disabled = nil,

    -- Optional visibility control
    visible_when_disabled = true,  -- set to false to hide widget when disabled
  }
]]
local function create_toggle_widget(opts)
  local color_enabled = opts.color_enabled or COLOR_ENABLED
  local color_disabled = opts.color_disabled or COLOR_DISABLED
  local color_error = opts.color_error or COLOR_ERROR
  local visible_when_disabled = opts.visible_when_disabled ~= false  -- default true

  local inner_widget = wibox.widget({
    image = opts.icon,
    resize = true,
    widget = wibox.widget.imagebox,
  })

  local background_container = wibox.container.background(inner_widget)
  background_container.shape = function(cr, width, height)
    gears.shape.rounded_rect(cr, width, height, dpi(4))
  end

  local widget = wibox.container.margin(
    background_container,
    dpi(1),
    nil,
    nil,
    dpi(2)
  )

  local tooltip = get_tooltip(widget)

  -- Update visual appearance based on state
  local function update_visual(enabled)
    local fg = enabled and color_enabled or color_disabled
    local tip = enabled and opts.tooltip_on or opts.tooltip_off
    local bg = enabled and opts.background_enabled or opts.background_disabled

    if opts.icon and opts.icon ~= '' then
      inner_widget.image = gears.color.recolor_image(opts.icon, fg)
    end
    background_container.bg = bg
    tooltip.text = tip

    -- Handle visibility
    if not visible_when_disabled then
      widget.visible = enabled
    end
  end

  local function update_visual_error()
    if opts.icon and opts.icon ~= '' then
      inner_widget.image = gears.color.recolor_image(opts.icon, color_error)
    end
    background_container.bg = nil
    tooltip.text = opts.tooltip_error or 'Error checking state'
  end

  -- Check current state
  function widget:check()
    awful.spawn.with_line_callback(opts.check_cmd, {
      stdout = function(line)
        if line:find(opts.enabled_pattern, 1, true) then
          update_visual(true)
        elseif opts.disabled_pattern and line:find(opts.disabled_pattern, 1, true) then
          update_visual(false)
        elseif not opts.disabled_pattern and line ~= '' then
          -- Fallback: non-empty non-matching line = disabled (only if no disabled_pattern)
          update_visual(false)
        end
        -- If disabled_pattern is set but line matches neither, ignore the line
      end,
      stderr = function(line)
        if line ~= '' then
          update_visual_error()
        end
      end,
    })
  end

  -- Set state directly (for external use)
  function widget:set(enabled)
    update_visual(enabled)
  end

  -- Toggle state
  function widget:toggle()
    awful.spawn.with_line_callback(opts.check_cmd, {
      stdout = function(line)
        local is_enabled = line:find(opts.enabled_pattern, 1, true) ~= nil
        local is_disabled = opts.disabled_pattern and line:find(opts.disabled_pattern, 1, true) ~= nil

        -- Only act if we matched a known state
        if not is_enabled and not is_disabled and opts.disabled_pattern then
          return  -- Unknown line, ignore
        end

        if opts.toggle_cmd then
          -- Single toggle command
          awful.spawn(opts.toggle_cmd)
          update_visual(not is_enabled)
        else
          -- Separate enable/disable commands
          if is_enabled then
            awful.spawn(opts.disable_cmd)
            update_visual(false)
          else
            awful.spawn(opts.enable_cmd)
            update_visual(true)
          end
        end
      end,
    })
  end

  -- Initial state check
  widget:check()

  -- Left click to toggle
  widget:buttons(awful.util.table.join(
    awful.button({}, 1, function()
      widget:toggle()
    end)
  ))

  return widget
end

return create_toggle_widget
