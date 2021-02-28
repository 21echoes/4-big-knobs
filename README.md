# 4 Big Knobs
Send control voltages out of Crow. Intended for use with Arc, where each Arc encoder controls the voltage sent from the corresponding Crow output.

## UI
![home](screenshots/4-big-knobs.png)
- 4 dials showing current voltage values

- If helper text enabled (on by default):
  - Top left text showing what E1 does
  - Top right text showing if arc is detected or not
    - Will eventually show current mode, once mulitple modes are available
  - Bottom text shows current behavior of E2 & E3
    - Will eventually show K2 & K3 behavior, once they do something depending on current mode

## Controls
### Arc (optional)
- Each encoder is mapped to the corresponding dial on screen

### Norns
- E1 changes which dials are focused
- E2 & E3 are mapped to the highlighted dials on screen

## Additional Parameters
- Crow Outputs
  - Minimum and Maximum voltage
  - Customize dial -> Crow output mapping
  - Direct control over dial values (can be used for MIDI mapping if you'd like a different control surface)

- Crow Inputs
  - Each Crow input can exert influence over all the Crow outputs via Attenuation or Offset
  - Defaults to Offset

- Misc
  - If you have a Norns shield, you can switch top left and right text to match where your E1 is
  - You can turn off the helper text once you understand how it works

## Requirements
* norns
* crow
* arc optional, but encouraged

## Roadmap
### Quantize mode
- E2 & E3 select scales 1 and 2, respectively
- K2 & K3 quantize all outputs to their respective scales
- Can also turn on continuous quantization mode

### Snapshot mode
- K2 & K3 save current state to one of two snapshot banks
- E1 interpolates between two snapshots
