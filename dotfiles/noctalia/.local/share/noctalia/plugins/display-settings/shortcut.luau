shortcut.setLabel("Displays")
shortcut.setIcon("device-desktop-cog")
shortcut.setActive(false)
shortcut.setEnabled(noctalia.commandExists("niri"))

function onClick()
  noctalia.togglePanel("local/display-settings:manager")
end
