local function render()
  barWidget.setGlyph("device-desktop-cog")
  barWidget.setTooltip(noctalia.tr("widget.tooltip"))
end

function onClick()
  noctalia.togglePanel("local/niri-outputs:manager")
end

render()
