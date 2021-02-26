-- 4 Big Knobs
-- Control crow output voltage
-- via 4 arc encoders
--
-- Each arc encoder
-- controls the corresponding
-- crow output voltage,
-- ranging from -5V to +5V
--
-- v0.1.0 @21echoes

local UI = require 'ui'
local ControlSpec = require "controlspec"
local Arcify = include("lib/arcify")
local UIState = include('lib/ui_state')

local arc_device = arc.connect()
local arcify = Arcify.new(arc_device, false)
local NUM_CONTROLS = 4
local MIN_VOLTS = -5
local MAX_VOLTS = 5
local dials = {}
local ui_refresh_metro

-- TODO v2: also control via E2&E3
-- TODO beyond: min and max per output are their own params
-- TODO beyond: snapshot values, interpolate
-- TODO beyond: crow inputs do something?

local function param_name_for_ctrl(ctrl)
  return ctrl.."_volt"
end

local function ctrl_changed(ctrl, value)
  crow.output[ctrl].volts = value
  UIState.set_dirty()
end

local function init_params()
  for ctrl=1,NUM_CONTROLS do
    params:add_control(param_name_for_ctrl(ctrl), "Output "..ctrl..": Voltage", ControlSpec.new(MIN_VOLTS, MAX_VOLTS, "lin", 0.01, 0))
    params:set_action(param_name_for_ctrl(ctrl), function(value)
      ctrl_changed(ctrl, value)
    end)
    arcify:register(param_name_for_ctrl(ctrl))
  end
  arcify:add_params()
  for ctrl=1,NUM_CONTROLS do
    arcify:map_encoder_via_params(ctrl, param_name_for_ctrl(ctrl))
  end
end

local function redraw()
  -- TODO: why is there an open line when this starts?
  screen.move(dials[1].x+5, dials[1].y+20)
  screen.close()
  screen.clear()
  for ctrl=1,NUM_CONTROLS do
    dials[ctrl]:set_value(params:get(param_name_for_ctrl(ctrl)))
    dials[ctrl]:redraw()
  end
end

local function init_ui()
  dials[1] = UI.Dial.new(9, 13, 22, 0, MIN_VOLTS, MAX_VOLTS, 0.01, 0, {}, 'V')
  dials[2] = UI.Dial.new(39, 26, 22, 0, MIN_VOLTS, MAX_VOLTS, 0.01, 0, {}, 'V')
  dials[3] = UI.Dial.new(69, 13, 22, 0, MIN_VOLTS, MAX_VOLTS, 0.01, 0, {}, 'V')
  dials[4] = UI.Dial.new(98.5, 26, 22, 0, MIN_VOLTS, MAX_VOLTS, 0.01, 0, {}, 'V')

  UIState.init_arc {
    device = arc_device,
    delta_callback = function(n, delta)
      arcify:update(n, delta)
    end,
    refresh_callback = function(my_arc)
      arcify:redraw()
    end
  }
  UIState.init_screen({
    refresh_callback = function()
      redraw()
    end
  })

  redraw()
  ui_refresh_metro = metro.init()
  ui_refresh_metro.event = UIState.refresh
  ui_refresh_metro.time = 1/60
  ui_refresh_metro:start()
end

function init()
  init_params()
  init_ui()
  params:bang()
end

function cleanup()
  params:write()
  metro.free(ui_refresh_metro.id)
  ui_refresh_metro = nil
end