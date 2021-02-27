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
local Label = include("lib/label")
local tabutil = require "tabutil"

local arc_device = arc.connect()
local arcify = Arcify.new(arc_device, false)
local NUM_CONTROLS = 4
local MIN_VOLTS = -5
local MAX_VOLTS = 10
local MIN_SEPARATION = 0.01
local dials = {}
local corner_labels = {}
local dial_focus = 1
local ui_refresh_metro

  -- TODO: why does this app draw over the menu???

local function param_name_for_ctrl(ctrl)
  return ctrl.."_volt"
end

local function compute_voltage(ctrl)
  local v = params:get(param_name_for_ctrl(ctrl))
  return util.clamp(v, params:get("min_volts"), params:get("max_volts"))
end

local function ctrl_changed(ctrl)
  crow.output[ctrl].volts = compute_voltage(ctrl)
  UIState.set_dirty()
end

local function minmax_changed()
  local faked_controlspec = ControlSpec.new(params:get("min_volts"), params:get("max_volts"), "lin", 0.01, 0)
  for ctrl=1,NUM_CONTROLS do
    arcify.params_[param_name_for_ctrl(ctrl)].controlspec = faked_controlspec
    ctrl_changed(ctrl)
  end
end

local function init_params()
  params:add_group("Crow Outputs", 6)
  params:add_control("min_volts", "Min Volts", ControlSpec.new(MIN_VOLTS, MAX_VOLTS, "lin", MIN_SEPARATION, MIN_VOLTS))
  params:set_action("min_volts", function(value)
    if params:get("max_volts") < value + MIN_SEPARATION then
      params:set("max_volts", value + MIN_SEPARATION)
    end
    minmax_changed()
  end)
  params:add_control("max_volts", "Max Volts", ControlSpec.new(MIN_VOLTS, MAX_VOLTS, "lin", MIN_SEPARATION, 5))
  params:set_action("max_volts", function(value)
    if params:get("min_volts") > value - MIN_SEPARATION then
      params:set("min_volts", value - MIN_SEPARATION)
    end
    minmax_changed()
  end)
  for ctrl=1,NUM_CONTROLS do
    params:add_control(param_name_for_ctrl(ctrl), "Output "..ctrl..": Voltage", ControlSpec.new(MIN_VOLTS, MAX_VOLTS, "lin", 0.01, 0))
    params:set_action(param_name_for_ctrl(ctrl), function(value)
      ctrl_changed(ctrl)
      params:set(param_name_for_ctrl(ctrl), util.clamp(value, params:get("min_volts"), params:get("max_volts")))
    end)
    arcify:register(param_name_for_ctrl(ctrl))
  end
  params:add_option("show_instructions", "Show instructions?", {"No", "Yes"}, 2)
  params:add_option("is_shield", "Norns Shield?", {"No", "Yes"}, 1)
  params:set_action("is_shield", function(value)
    local top_left = value == 1 and 1 or 2
    local top_right = value == 1 and 2 or 1
    corner_labels[top_left].x = 0
    corner_labels[top_left].align = Label.ALIGN_LEFT
    corner_labels[top_right].x = 128
    corner_labels[top_right].align = Label.ALIGN_RIGHT
  end)
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
  for ctrl=1,#dials do
    dials[ctrl].min_value = params:get("min_volts")
    dials[ctrl].max_value = params:get("max_volts")
    dials[ctrl]:set_value(params:get(param_name_for_ctrl(ctrl)))
    dials[ctrl].active = (dial_focus == 1 and ctrl < 3) or (dial_focus == 2 and ctrl >= 3)
    dials[ctrl]:redraw()
  end
  if params:get("show_instructions") == 2 then
    -- Top left (top right if is_shield)
    corner_labels[1]:redraw()
    -- Top right (top left if is_shield)
    if arc_device then
      corner_labels[2]:redraw()
    end
    -- Bottom left
    if dial_focus == 1 then
      corner_labels[3].text = "Dial 1  Dial 2"
    else
      corner_labels[3].text = "Dial 3  Dial 4"
    end
    corner_labels[3]:redraw()
    -- Bottom right
    corner_labels[4]:redraw()
  end
end

local function init_ui()
  dials[1] = UI.Dial.new(2, 19.5, 22, 0, MIN_VOLTS, MAX_VOLTS, 0.01, 0, {}, 'V')
  dials[2] = UI.Dial.new(36, 19.5, 22, 0, MIN_VOLTS, MAX_VOLTS, 0.01, 0, {}, 'V')
  dials[3] = UI.Dial.new(70, 19.5, 22, 0, MIN_VOLTS, MAX_VOLTS, 0.01, 0, {}, 'V')
  dials[4] = UI.Dial.new(104, 19.5, 22, 0, MIN_VOLTS, MAX_VOLTS, 0.01, 0, {}, 'V')
  corner_labels[1] = Label.new({x = 0, y = 8, text="E1: Switch Focus"})
  corner_labels[2] = Label.new({x = 128, y = 8, text="Arc", align=Label.ALIGN_RIGHT})
  corner_labels[3] = Label.new({x = 0, y = 64, text="Dial 1  Dial 2"})
  corner_labels[4] = Label.new({x = 128, y = 64, align=Label.ALIGN_RIGHT})

  UIState.init_arc({
    device = arc_device,
    delta_callback = function(n, delta)
      arcify:update(n, delta)
    end,
    refresh_callback = function(my_arc)
      arcify:redraw()
    end
  })
  UIState.init_screen({
    refresh_callback = function()
      redraw()
    end
  })

  redraw()
  ui_refresh_metro = metro.init()
  ui_refresh_metro.event = UIState.refresh
  ui_refresh_metro.time = 1/25
  ui_refresh_metro:start()
end

function key(n, z)
  -- No key behavior yet
end

function enc(n, delta)
  if n == 1 then
    dial_focus = util.clamp(dial_focus + delta, 1, 2)
    UIState.set_dirty()
  else
    local dial_index = (dial_focus == 2 and 2 or 0) + n - 1
    params:delta(param_name_for_ctrl(dial_index), delta)
  end
end

function init()
  init_params()
  init_ui()
  params:bang()
  UIState.set_dirty()
end

function cleanup()
  params:write()
  metro.free(ui_refresh_metro.id)
  ui_refresh_metro = nil
end

function rerun()
  norns.script.load(norns.state.script)
end
