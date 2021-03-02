-- 4 Big Knobs
-- Control crow output voltage
-- via 4 arc encoders
-- (or just the norns encoders,
--  or a MIDI device)
--
-- Snapshot mode,
-- quantization mode,
-- and more options
-- available in params menu
--
-- v0.9.7 @21echoes

local UI = require 'ui'
local MusicUtil = require "musicutil"
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
local crow_input_values = {0,0}
local crow_refresh_rate = 1/25
local quantization_bank = {}
local reset_slew_metro
local snapshot_midpoint = {0, {0,0,0,0}}

local scale_names = {}
for index, value in ipairs(MusicUtil.SCALES) do
  table.insert(scale_names, value.name)
end

function is_arc_connected()
  return arc_device and arc_device.device
end

function arc.add()
  UIState.set_dirty()
end

function arc.remove()
  UIState.set_dirty()
end

local function param_name_for_ctrl(ctrl)
  return ctrl.."_volt"
end

local function compute_voltage(ctrl)
  -- Default value
  local v = params:get(param_name_for_ctrl(ctrl))

  -- Attenuate
  for crow_input=1,#crow_input_values do
    local input_mode = params:get("input_"..crow_input)
    if input_mode == 3 then
      local ratio = util.clamp((crow_input_values[crow_input] / params:get("input_"..crow_input.."_atten")), 0, 1)
      v = v * ratio
    end
  end

  -- Offset
  for crow_input=1,#crow_input_values do
    local input_mode = params:get("input_"..crow_input)
    if input_mode == 2 then
      v = v + crow_input_values[crow_input]
    end
  end

  -- Min & Max
  return util.clamp(v, params:get("min_volts"), params:get("max_volts"))
end

local function ctrl_changed(ctrl, refresh_ui)
  local voltage = compute_voltage(ctrl)
  for crow_out=1,NUM_CONTROLS do
    if params:get("output_"..crow_out) == ctrl then
      crow.output[crow_out].volts = voltage
    end
  end
  if refresh_ui then
    UIState.set_dirty()
  end
end

local function refresh_crow_outs(refresh_ui)
  for ctrl=1,NUM_CONTROLS do
    ctrl_changed(ctrl, false)
  end
  if refresh_ui then
    UIState.set_dirty()
  end
end

local function minmax_changed()
  local faked_controlspec = ControlSpec.new(params:get("min_volts"), params:get("max_volts"), "lin", 0.01, 0)
  for ctrl=1,NUM_CONTROLS do
    arcify.params_[param_name_for_ctrl(ctrl)].controlspec = faked_controlspec
  end
  refresh_crow_outs(true)
end

function volts_for_midi(note_num)
  return (note_num-36)/12
end

function generate_crow_scale()
  local midi_root = -1 + params:get("scale_root")
  local midi_scale = MusicUtil.generate_scale(midi_root, params:get("scale_type"), 1)
  local intervals_scale = {}
  for i=1,(#midi_scale - 1) do
    table.insert(intervals_scale, midi_scale[i] % 12)
  end
  table.sort(intervals_scale)
  return intervals_scale
end

function update_quantization_bank()
  local midi_root = -1 + params:get("scale_root")
  local midi_scale = MusicUtil.generate_scale(midi_root, params:get("scale_type"), 10)
  local volts_scale = {}
  for i=1,#midi_scale do
    table.insert(volts_scale, volts_for_midi(midi_scale[i]))
  end
  quantization_bank = volts_scale
  update_crow_scale()
  UIState.set_dirty()
end

function get_quantized_voltage(volts)
  local closeness = {0,10}
  -- TODO: binary search this
  for i=1,#quantization_bank do
    local distance = math.abs(quantization_bank[i] - volts)
    if distance < closeness[2] then
      closeness[1] = i
      closeness[2] = distance
    end
  end
  return quantization_bank[closeness[1]]
end

local function set_output_slew(slew)
  for crow_output=1,NUM_CONTROLS do
    crow.output[crow_output].slew = slew
  end
end

function quantize()
  local change_slew = params:get("quantize_slew") ~= params:get("output_slew")
  if change_slew then
    if reset_slew_metro then
      metro.free(reset_slew_metro.id)
      reset_slew_metro = nil
    end
    set_output_slew(params:get("quantize_slew"))
    reset_slew_metro = metro.init(function()
      set_output_slew(params:get("output_slew"))
      metro.free(reset_slew_metro.id)
      reset_slew_metro = nil
    end)
    reset_slew_metro:start(params:get("quantize_slew"), 1)
  end
  for ctrl=1,NUM_CONTROLS do
    local unquantized = params:get(param_name_for_ctrl(ctrl))
    local quantized = get_quantized_voltage(unquantized)
    params:set(param_name_for_ctrl(ctrl), quantized)
  end
end

function update_crow_scale()
  if params:get("quantize_mode") == 2 then
    local crow_scale = generate_crow_scale()
    for i=1,NUM_CONTROLS do
      crow.output[i].scale(crow_scale)
    end
  end
end

function set_quantize_mode(quantize_mode)
  if quantize_mode == 1 then
    params:set("quantize", 1)
    for i=1,NUM_CONTROLS do
      crow.output[i].scale('none')
    end
  else
    update_crow_scale()
  end
  UIState.set_dirty()
end

local function init_crow_inputs()
  for crow_input=1,#crow_input_values do
    crow.input[crow_input].stream = function(v)
      local changed = crow_input_values[crow_input] ~= v
      crow_input_values[crow_input] = v
      if changed then
        refresh_crow_outs(false)
      end
    end
    crow.input[crow_input].mode("stream", crow_refresh_rate)
  end
  set_output_slew(params:get("output_slew"))
end

local function capture_snapshot(snapshot)
  for ctrl=1,NUM_CONTROLS do
    params:set("snapshot_"..snapshot.."_"..ctrl, params:get(param_name_for_ctrl(ctrl)))
  end
end

local function set_snapshot_interpolation(interpolation)
  for ctrl=1,NUM_CONTROLS do
    local snapshot_1_value = params:get("snapshot_1_"..ctrl)
    local snapshot_2_value = params:get("snapshot_2_"..ctrl)
    local averaged = snapshot_1_value
    if snapshot_midpoint[1] ~= 0 then
      local snapshot_midpoint_value = snapshot_midpoint[2][ctrl]
      if snapshot_midpoint[1] < interpolation then
        local midpoint_to_2 = 2 - snapshot_midpoint[1]
        averaged = (((2-interpolation)*snapshot_midpoint_value) + ((interpolation-snapshot_midpoint[1])*snapshot_2_value))/midpoint_to_2
      else
        local midpoint_to_1 = snapshot_midpoint[1] - 1
        averaged = (((snapshot_midpoint[1]-interpolation)*snapshot_1_value) + ((interpolation-1)*snapshot_midpoint_value))/midpoint_to_1
      end
    else
      averaged = ((2-interpolation)*snapshot_1_value) + ((interpolation-1)*snapshot_2_value)
    end
    params:set(param_name_for_ctrl(ctrl), averaged)
  end
end

local function init_params()
  params:add_separator()

  params:add_option("mode", "Mode", {"Norns Control", "Snapshot", "Quantize"}, is_arc_connected() and 2 or 1)

  params:add_group("Crow Outputs", 11)
  params:add_control("output_slew", "Slew", ControlSpec.new(crow_refresh_rate, 10, "exp", 0, crow_refresh_rate))
  params:set_action("output_slew", function(value) set_output_slew(value) end)
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
    params:add_option("output_"..ctrl, "Output "..ctrl.. " mapping", {"Dial 1", "Dial 2", "Dial 3", "Dial 4"}, ctrl)
    params:set_action("output_"..ctrl, function()
      refresh_crow_outs(false)
    end)
  end
  for ctrl=1,NUM_CONTROLS do
    params:add_control(param_name_for_ctrl(ctrl), "Dial "..ctrl..": Voltage", ControlSpec.new(MIN_VOLTS, MAX_VOLTS, "lin", 0.002, 0))
    params:set_action(param_name_for_ctrl(ctrl), function(value)
      ctrl_changed(ctrl, true)
      params:set(param_name_for_ctrl(ctrl), util.clamp(value, params:get("min_volts"), params:get("max_volts")))
    end)
    arcify:register(param_name_for_ctrl(ctrl))
  end

  params:add_group("Crow Inputs", #crow_input_values*2)
  for crow_in=1,#crow_input_values do
    params:add_option("input_"..crow_in, "Input Function", {"None", "Offset", "Attenuate"}, 1)
    params:set_action("input_"..crow_in, function()
      refresh_crow_outs(false)
    end)
  end
  for crow_in=1,#crow_input_values do
    params:add_number("input_"..crow_in.."_atten", "Input "..crow_in.." Atten Range", 1, 10, 5)
    params:set_action("input_"..crow_in.."_atten", function()
      refresh_crow_outs(false)
    end)
  end

  params:add_group("Quantization", 5)
  params:add_option("scale_type", "Scale Type", scale_names, 1)
  params:set_action("scale_type", function()
    update_quantization_bank()
  end)
  params:add_option("scale_root", "Scale Root ", MusicUtil.NOTE_NAMES, 1)
  params:set_action("scale_root", function()
    update_quantization_bank()
  end)
  params:add_option("quantize_mode", "Quantize Mode", {"On Demand", "Continuous"}, 1)
  params:set_action("quantize_mode", function(value) set_quantize_mode(value) end)
  params:add_trigger("quantize", "Quantize!")
  params:set_action("quantize", function() quantize() end)
  params:add_control("quantize_slew", "Slew", ControlSpec.new(crow_refresh_rate, 10, "exp", 0, crow_refresh_rate))

  params:add_group("Snapshots", 1+(2*(NUM_CONTROLS+1)))
  params:add_control("snapshot_interpolation", "Snapshot interpolation", ControlSpec.new(1, 2, "lin", 0.01, 1))
  params:set_action("snapshot_interpolation", function(value) set_snapshot_interpolation(value) end)
  for snapshot=1,2 do
    for ctrl=1,NUM_CONTROLS do
      params:add_control(
        "snapshot_"..snapshot.."_"..ctrl,
        "Snapshot "..snapshot..": "..ctrl,
        ControlSpec.new(MIN_VOLTS, MAX_VOLTS, "lin", 0.002, 0)
      )
    end
    params:add_trigger("snapshot_"..snapshot.."_capture", "Capture snapshot "..snapshot)
    params:set_action("snapshot_"..snapshot.."_capture", function()
      capture_snapshot(snapshot)
      snapshot_midpoint[1] = 0
      params:set("snapshot_interpolation", snapshot)
    end)
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

  params:add_group("Arc", 4)
  arcify:add_params()
  for ctrl=1,NUM_CONTROLS do
    arcify:map_encoder_via_params(ctrl, param_name_for_ctrl(ctrl))
  end
end

function get_scale_name()
  local full_name = MusicUtil.NOTE_NAMES[params:get("scale_root")].." "..scale_names[params:get("scale_type")]
  if #full_name > 22 then
    local prefix = string.sub(full_name, 1, 9)
    local suffix = string.sub(full_name, #full_name - 9)
    return prefix..".."..suffix
  else
    return full_name
  end
end

function update_bottom_text()
  local mode = params:get("mode")
  local show_instructions = params:get("show_instructions") == 2
  if mode == 1 then
    corner_labels[3][1].text = ""
    corner_labels[3][2].text = ""
    if show_instructions then
      if dial_focus == 1 then
        corner_labels[4].text = "Dial 1 | Dial 2"
      else
        corner_labels[4].text = "Dial 3 | Dial 4"
      end
    end
  elseif mode == 2 then
    if show_instructions then
      corner_labels[3][1].text = "K2: Snapshot 1"
      corner_labels[3][2].text = "K3: Snapshot 2"
    end
    corner_labels[4].text = ""
  elseif mode == 3 then
    -- Quantize
    local quantize_mode = params:get("quantize_mode")
    if quantize_mode == 1 then
      if show_instructions then
        corner_labels[3][1].text = "K2: -> Continuous"
        corner_labels[3][2].text = "K3: Qnt!"
      else
        corner_labels[3][1].text = "On-Demand"
        corner_labels[3][2].text = ""
      end
    else
      if show_instructions then
        corner_labels[3][1].text = "K2: -> On-Demand"
        corner_labels[3][2].text = ""
      else
        corner_labels[3][1].text = "Continuous"
        corner_labels[3][2].text = ""
      end
    end
    corner_labels[4].text = get_scale_name()
  end
end

function redraw()
  -- TODO: why is there an open line when this starts?
  screen.move(dials[1].x+5, dials[1].y+20)
  screen.close()
  screen.stroke()
  screen.clear()
  local mode = params:get("mode")
  local is_quantize_mode = mode == 3
  for ctrl=1,#dials do
    dials[ctrl].min_value = params:get("min_volts")
    dials[ctrl].max_value = params:get("max_volts")
    dials[ctrl]:set_value(params:get(param_name_for_ctrl(ctrl)))
    dials[ctrl].active = mode ~= 1 or (dial_focus == 1 and ctrl < 3) or (dial_focus == 2 and ctrl >= 3)
    if mode == 1 then
      dials[ctrl].y = 19.5
    else
      dials[ctrl].y = 16
    end
    dials[ctrl]:redraw()
  end

  local show_instructions = params:get("show_instructions") == 2

  -- Top left (top right if is_shield)
  if show_instructions then
    if mode == 1 then
      corner_labels[1].text = "E1: Switch Focus"
    elseif mode == 2 then
      corner_labels[1].text = "E1: Interp."
    elseif mode == 3 then
      corner_labels[1].text = ""
    end
    corner_labels[1]:redraw()
  end

  -- Top right (top left if is_shield)
  if mode == 1 then
    if is_arc_connected() and show_instructions then
      corner_labels[2].text = "Arc Found"
    end
  elseif mode == 2 then
    if is_arc_connected() and show_instructions then
      corner_labels[2].text = "Snapshot w/Arc"
    else
      corner_labels[2].text = "Snapshot"
    end
  elseif mode == 3 then
    if is_arc_connected() and show_instructions then
      corner_labels[2].text = "Quantize w/Arc"
    else
      corner_labels[2].text = "Quantize"
    end
  end
  corner_labels[2]:redraw()

  -- update_bottom_text takes show_instructions into account
  update_bottom_text()
  -- Bottom left
  for i=1,#corner_labels[3] do
    corner_labels[3][i]:redraw()
  end
  -- Bottom right
  corner_labels[4]:redraw()

  screen.update()
end

local function init_ui()
  dials[1] = UI.Dial.new(4, 16, 22, 0, MIN_VOLTS, MAX_VOLTS, 0.01, 0, {}, 'V')
  dials[2] = UI.Dial.new(37, 16, 22, 0, MIN_VOLTS, MAX_VOLTS, 0.01, 0, {}, 'V')
  dials[3] = UI.Dial.new(69, 16, 22, 0, MIN_VOLTS, MAX_VOLTS, 0.01, 0, {}, 'V')
  dials[4] = UI.Dial.new(102, 16, 22, 0, MIN_VOLTS, MAX_VOLTS, 0.01, 0, {}, 'V')
  corner_labels[1] = Label.new({x = 0, y = 8, text="E1: Switch Focus"})
  corner_labels[2] = Label.new({x = 128, y = 8, text="Arc Found", align=Label.ALIGN_RIGHT})
  corner_labels[3] = {
    Label.new({x = 0, y = 55}),
    Label.new({x = 0, y = 63})
  }
  corner_labels[4] = Label.new({x = 128, y = 63, text="Dial 1 | Dial 2", align=Label.ALIGN_RIGHT})

  UIState.init_arc({
    device = arc_device,
    delta_callback = function(n, delta)
      arcify:update(n, delta)
      snapshot_midpoint[1] = params:get("snapshot_interpolation")
      snapshot_midpoint[2] = {
        params:get(param_name_for_ctrl(1)),
        params:get(param_name_for_ctrl(2)),
        params:get(param_name_for_ctrl(3)),
        params:get(param_name_for_ctrl(4))
      }
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
  local mode = params:get("mode")
  if mode == 2 then
    if z == 1 then
      return
    end
    if n == 2 then
      params:set("snapshot_1_capture", 1)
    elseif n == 3 then
      params:set("snapshot_2_capture", 1)
    end
  elseif mode == 3 then
    -- Quantize
    if z == 1 then
      return
    end
    if n == 2 then
      params:set("quantize_mode", (params:get("quantize_mode") % 2) + 1)
    elseif n == 3 then
      params:set("quantize", 1)
    end
  end
end

function enc(n, delta)
  local mode = params:get("mode")
  if mode == 1 then
    -- Norns Control mode
    if n == 1 then
      dial_focus = util.clamp(dial_focus + delta, 1, 2)
      UIState.set_dirty()
    else
      local dial_index = (dial_focus == 2 and 2 or 0) + n - 1
      params:delta(param_name_for_ctrl(dial_index), delta)
    end
  elseif mode == 2 then
    if n == 1 then
      params:delta("snapshot_interpolation", delta)
    end
  elseif mode == 3 then
    -- Quantize mode
    if n == 2 then
      params:delta("scale_root", delta)
    elseif n == 3 then
      params:delta("scale_type", delta)
    end
  end
end

function init()
  init_params()
  init_crow_inputs()
  init_ui()
  params:bang()
  UIState.set_dirty()
end

function cleanup()
  params:write()
  metro.free(ui_refresh_metro.id)
  ui_refresh_metro = nil
  metro.free(reset_slew_metro.id)
  reset_slew_metro = nil
end

function rerun()
  norns.script.load(norns.state.script)
end
