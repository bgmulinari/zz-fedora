shortcut.setLabel(noctalia.tr("shortcut.label"))
shortcut.setIcon("device-desktop-cog")
shortcut.setActive(false)
shortcut.setEnabled(noctalia.commandExists("niri"))

function onClick()
  noctalia.togglePanel("local/niri-outputs:manager")
end
