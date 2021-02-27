-- small utility library for single-grid, single-arc, single-midi device script UIs
-- written to track dirty states of UI, provide a generic refresh function
-- written to not be directly dependent on norns global variables

local UI = {}

-- refresh logic

function UI.refresh()
  if UI.arc_inited then
    UI.check_arc_connected()

    if UI.arc_dirty then
      if UI.arc_refresh_callback then
        UI.arc_refresh_callback(UI.my_arc)
      end
      UI.my_arc:refresh()
      UI.arc_dirty = false
    end
  end

  if UI.screen_dirty then
    if UI.refresh_screen_callback then
      UI.refresh_screen_callback()
    end
    screen.update()
    UI.screen_dirty = false
  end
end

function UI.set_dirty()
  UI.arc_dirty = true
  UI.grid_dirty = true
  UI.screen_dirty = true
end

-- arc

UI.arc_connected = false
UI.arc_dirty = false

function UI.init_arc(config)
  local my_arc = config.device
  UI.arc_delta_callback = config.delta_callback
  my_arc.delta = function(n, delta)
    UI.arc_delta_callback(n, delta)
  end
  UI.my_arc = my_arc
  UI.arc_refresh_callback = config.refresh_callback
  UI.arc_inited = true
end

function UI.check_arc_connected()
  local arc_check = UI.my_arc.device ~= nil
  if UI.arc_connected ~= arc_check then
    UI.arc_connected = arc_check
    UI.arc_dirty = true
  end
end

-- screen

function UI.init_screen(config)
  UI.refresh_screen_callback = config.refresh_callback
end

-- Make sure there's only one copy
if _UI == nil then
  _UI = UI
end

return _UI
