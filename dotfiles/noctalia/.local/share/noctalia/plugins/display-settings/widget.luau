local function render()
  barWidget.setGlyph("device-desktop-cog")
  barWidget.setTooltip("Display Settings")
end

function onClick()
  noctalia.togglePanel("local/display-settings:manager")
end

render()
