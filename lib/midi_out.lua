local ControlSpec = require "controlspec"
local tabutil = require "tabutil"

local MidiOut = {}
MidiOut.__index = MidiOut

local NUM_CONTROLS = 4

function MidiOut.new(i)
  i = i or {}
  setmetatable(i, MidiOut)
  i.__index = MidiOut
  i.devices = {}
  i.prior_note_nums = {}
  for _=1,NUM_CONTROLS do
    table.insert(i.devices, nil)
    table.insert(i.prior_note_nums, nil)
  end
  return i
end

function MidiOut:_param_name_for_ctrl(ctrl)
  return ctrl.."_volt"
end

function MidiOut:cleanup_ctrl(ctrl)
  if self.devices[ctrl] ~= nil and self.prior_note_nums[ctrl] ~= nil then
    local channel = params:get("midi_out_chan_"..ctrl)
    self.devices[ctrl]:note_off(self.prior_note_nums[ctrl], 100, channel)
  end
end

function MidiOut:refresh_ctrl(ctrl)
  if params:get("midi_out_mode_"..ctrl) ~= 1 then
    return
  end
  self:message_for_ctrl_change(ctrl, self:_param_name_for_ctrl(ctrl.."_volt"))
end

function MidiOut:init_params()
  params:add_group("MIDI Out", (7*NUM_CONTROLS)-1)
  for ctrl=1,NUM_CONTROLS do
    if ctrl ~= 1 then
      params:add_separator()
    end
    params:add_option("midi_out_mode_"..ctrl, "Dial "..ctrl..": Mode", {"Off", "CC", "Notes"}, 1)
    params:add_number("midi_device_"..ctrl, "Dial "..ctrl..": Device", 1, 16, 1)
    params:set_action("midi_device_"..ctrl, function(value)
      self:cleanup_ctrl(ctrl)
      self.devices[ctrl] = midi.connect(value)
      self:refresh_ctrl(ctrl)
    end)
    params:add_number("midi_out_chan_"..ctrl, "Dial "..ctrl..": Channel", 1, 16, ctrl)
    params:add_number("midi_out_cc_"..ctrl, "Dial "..ctrl..": CC #", 0, 127, ctrl)
    params:add_number("midi_out_cc_min_"..ctrl, "Dial "..ctrl..": CC Min", 0, 127, 0)
    params:set_action("midi_out_cc_min_"..ctrl, function(value)
      if params:get("midi_out_cc_max_"..ctrl) < value + 1 then
        params:set("midi_out_cc_max_"..ctrl, value + 1)
      end
      self:refresh_ctrl(ctrl)
    end)
    params:add_number("midi_out_cc_max_"..ctrl, "Dial "..ctrl..": CC Max", 0, 127, 127)
    params:set_action("midi_out_cc_max_"..ctrl, function(value)
      if params:get("midi_out_cc_min_"..ctrl) > value - 1 then
        params:set("midi_out_cc_min_"..ctrl, value - 1)
      end
      self:refresh_ctrl(ctrl)
    end)
  end
end

function midi_for_volts(volts)
  local note_num = (volts*12)+48
  return math.floor(note_num+0.5)
end

function MidiOut:message_for_ctrl_change(ctrl, value, get_quantized_voltage, already_quantized)
  local mode = params:get("midi_out_mode_"..ctrl)
  local device = self.devices[ctrl]
  if mode == 1 or device == nil then
    return
  end
  local channel = params:get("midi_out_chan_"..ctrl)
  if mode == 2 then
    local volt_spec = ControlSpec.new(params:get("min_volts"), params:get("max_volts"), "lin", 0.01, 0)
    local volt_raw = volt_spec:unmap(value)
    local cc_spec = ControlSpec.new(params:get("midi_out_cc_min_"..ctrl), params:get("midi_out_cc_max_"..ctrl), "lin", 1, 0)
    local cc = cc_spec:map(volt_raw)
    device:cc(params:get("midi_out_cc_"..ctrl), cc, channel)
  elseif mode == 3 then
    local quant = value
    if not already_quantized then
      quant = get_quantized_voltage(value)
    end
    if quant ~= nil then
      local note_num = midi_for_volts(quant)
      local prior_note_num = self.prior_note_nums[ctrl]
      if note_num ~= prior_note_num then
        if prior_note_num ~= nil then
          device:note_off(prior_note_num, 100, channel)
        end
        device:note_on(note_num, 100, channel)
        self.prior_note_nums[ctrl] = note_num
      end
    end
  end
end

function MidiOut:cleanup()
  for ctrl=1,NUM_CONTROLS do
    self:cleanup_ctrl(ctrl)
  end
end

return MidiOut
