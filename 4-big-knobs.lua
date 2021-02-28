-- 4 Big Knobs
-- Control crow output voltage
-- via 4 arc encoders
-- (or just the norns encoders,
--  or a MIDI device)
--
-- Quantization mode
-- and more options
-- available in params menu
--
-- v0.9.3 @21echoes

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
    if input_mode == 2 then
      local ratio = util.clamp((crow_input_values[crow_input] / params:get("input_"..crow_input.."_atten")), 0, 1)
      v = v * ratio
    end
  end

  -- Offset
  for crow_input=1,#crow_input_values do
    local input_mode = params:get("input_"..crow_input)
    if input_mode == 1 then
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

function generate_quantization_bank(bank)
  local midi_root = -1 + params:get("scale_root_"..bank)
  local midi_scale = MusicUtil.generate_scale(midi_root, params:get("scale_"..bank), 10)
  local volts_scale = {}
  for i=1,#midi_scale do
    table.insert(volts_scale, volts_for_midi(midi_scale[i]))
  end
  return volts_scale
end

function quantize(bank)
  local volts_scale = generate_quantization_bank(bank)
  for ctrl=1,NUM_CONTROLS do
    local unquantized = params:get(param_name_for_ctrl(ctrl))
    local closeness = {0,10}
    -- TODO: binary search this
    for i=1,#volts_scale do
      local distance = math.abs(volts_scale[i] - unquantized)
      if distance < closeness[2] then
        closeness[1] = i
        closeness[2] = distance
      end
    end
    params:set(param_name_for_ctrl(ctrl), volts_scale[closeness[1]])
  end
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
  for crow_output=1,NUM_CONTROLS do
    crow.output[crow_output].slew = crow_refresh_rate
  end
end

local function init_params()
  params:add_separator()

  params:add_option("mode", "Mode", {"Norns Control", "Quantize"}, is_arc_connected() and 2 or 1)

  params:add_group("Crow Outputs", 10)
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
    params:add_option("input_"..crow_in, "Input Function", {"Offset", "Attenuate", "None"}, 1)
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

  params:add_group("Quantization", 2*3)
  for i=1,2 do
    params:add_option("scale_"..i, "Scale Bank "..i, scale_names, 1)
    params:set_action("scale_"..i, function() UIState.set_dirty() end)
    params:add_option("scale_root_"..i, "Scale Root "..i, MusicUtil.NOTE_NAMES, 1)
    params:set_action("scale_root_"..i, function() UIState.set_dirty() end)
    params:add_trigger("quantize_"..i, "Quantize to Bank "..i.."!")
    params:set_action("quantize_"..i, function() quantize(i) end)
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

function get_scale_name(bank)
  local full_name = MusicUtil.NOTE_NAMES[params:get("scale_root_"..bank)].." "..scale_names[params:get("scale_"..bank)]
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
  if mode == 1 then
    corner_labels[3].text = ""
    if dial_focus == 1 then
      corner_labels[4][1].text = "Dial 1"
      corner_labels[4][2].text = "Dial 2"
    else
      corner_labels[4][1].text = "Dial 3"
      corner_labels[4][2].text = "Dial 4"
    end
    corner_labels[4][1].level = 15
    corner_labels[4][2].level = 15
    corner_labels[4][1].x = corner_labels[4][2].x - (screen.text_extents(corner_labels[4][2].text) + 16)
    corner_labels[4][1].y = corner_labels[4][2].y
  elseif mode == 2 then
    corner_labels[3].text = "Qnt 1 2"
    corner_labels[4][1].text = get_scale_name(1)
    corner_labels[4][2].text = get_scale_name(2)
    if dial_focus == 1 then
      corner_labels[4][1].level = 15
      corner_labels[4][2].level = 3
    else
      corner_labels[4][1].level = 3
      corner_labels[4][2].level = 15
    end
    corner_labels[4][1].x = corner_labels[4][2].x
    corner_labels[4][1].y = corner_labels[4][2].y - 8
  end
end

function redraw()
  -- TODO: why is there an open line when this starts?
  screen.move(dials[1].x+5, dials[1].y+20)
  screen.close()
  screen.stroke()
  screen.clear()
  local mode = params:get("mode")
  for ctrl=1,#dials do
    dials[ctrl].min_value = params:get("min_volts")
    dials[ctrl].max_value = params:get("max_volts")
    dials[ctrl]:set_value(params:get(param_name_for_ctrl(ctrl)))
    dials[ctrl].active = mode ~= 1 or (dial_focus == 1 and ctrl < 3) or (dial_focus == 2 and ctrl >= 3)
    if mode == 2 then
      dials[ctrl].y = 16
    else
      dials[ctrl].y = 19.5
    end
    dials[ctrl]:redraw()
  end
  update_bottom_text()
  if params:get("show_instructions") == 2 then
    -- Top left (top right if is_shield)
    corner_labels[1]:redraw()
    -- Top right (top left if is_shield)
    if is_arc_connected() then
      corner_labels[2]:redraw()
    end
    -- Bottom left
    corner_labels[3]:redraw()
  end
  -- Show bottom right no matter what if in Quantize mode
  if params:get("show_instructions") == 2 or mode == 2 then
    -- Bottom right
    for i=1,#corner_labels[4] do
      corner_labels[4][i]:redraw()
    end
  end
  screen.update()
end

local function init_ui()
  dials[1] = UI.Dial.new(4, 16, 22, 0, MIN_VOLTS, MAX_VOLTS, 0.01, 0, {}, 'V')
  dials[2] = UI.Dial.new(37, 16, 22, 0, MIN_VOLTS, MAX_VOLTS, 0.01, 0, {}, 'V')
  dials[3] = UI.Dial.new(69, 16, 22, 0, MIN_VOLTS, MAX_VOLTS, 0.01, 0, {}, 'V')
  dials[4] = UI.Dial.new(102, 16, 22, 0, MIN_VOLTS, MAX_VOLTS, 0.01, 0, {}, 'V')
  corner_labels[1] = Label.new({x = 0, y = 8, text="E1: Switch Focus"})
  corner_labels[2] = Label.new({x = 128, y = 8, text="Arc Found", align=Label.ALIGN_RIGHT})
  corner_labels[3] = Label.new({x = 0, y = 63})
  corner_labels[4] = {
    Label.new({x = 128, y = 55, text="Dial 1", align=Label.ALIGN_RIGHT}),
    Label.new({x = 128, y = 63, text="Dial 2", align=Label.ALIGN_RIGHT})
  }

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
  local mode = params:get("mode")
  -- Quantize
  if mode == 2 then
    if z == 1 then
      return
    end
    if n == 2 then
      quantize(1)
    elseif n == 3 then
      quantize(2)
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
    -- Quantize mode
    if n == 1 then
      dial_focus = util.clamp(dial_focus + delta, 1, 2)
      UIState.set_dirty()
    elseif n == 2 then
      params:delta("scale_root_"..dial_focus, delta)
    elseif n == 3 then
      params:delta("scale_"..dial_focus, delta)
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
end

function rerun()
  norns.script.load(norns.state.script)
end
