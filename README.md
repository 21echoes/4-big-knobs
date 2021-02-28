# 4 Big Knobs
Send control voltages out of Crow. Intended for use with Arc, where each Arc encoder controls the voltage sent from the corresponding Crow output.

## UI
![home](screenshots/4-big-knobs.png)
* 4 dials showing current voltage values
* Ships with helper text to help you learn the ropes (disable helper text in params menu)

## Controls
### Arc (optional)
* Each encoder is mapped to the corresponding dial on screen

### Norns
* E1 changes which dials are focused
* E2 & E3 are mapped to the highlighted dials on screen

### Quantize mode
* Switch modes via Params menu. Defaults to Quantize mode if launched with an Arc connected
* E1 changes focused scale for editing
* E2 & E3 select scale root and scale type
* K2 & K3 quantize all outputs to their respective scales

## Additional Parameters
* Crow Outputs
  * Minimum and Maximum voltage
  * Customize dial -> Crow output mapping
  * Direct control over dial values (can be used for MIDI mapping if you'd like a different control surface)
* Crow Inputs
  * Each Crow input can exert influence over all the Crow outputs via Attenuation or Offset
  * Defaults to Offset
* Misc
  * If you have a Norns shield, you can switch top left and right text to match where your E1 is
  * You can turn off the helper text once you understand how it works

## Requirements
* norns
* crow
* arc optional, but encouraged
  * use a MIDI device in place of an arc by going into the params menu, clicking “map”, scrolling to “crow outputs”, scroll to “1_volt” and the other 4 options, and map each of them to a different control on the MIDI device

## Roadmap
### Quantize mode
* Continuous quantization

### Snapshot mode
* K2 & K3 save current state to one of two snapshot banks
* E1 interpolates between two snapshots

### Download
Latest version: v0.9.0 (028bc6c)

Not yet available in the Maiden Library. Instead, install by visiting http://norns.local/maiden when your norns is on WiFi and typing
```
;install https://github.com/21echoes/4-big-knobs.git
```
into the command entry box at the bottom of the screen.

Also available as a [direct download ](https://github.com/21echoes/4-big-knobs/archive/master.zip). Unzip it, rename the folder to just “4-big-knobs”, and put the whole folder onto your norns inside the `/home/we/dust/code` folder

https://github.com/21echoes/4-big-knobs