local backend = noctalia.pluginDir() .. "/backend.py"
local runtimeBase = noctalia.getenv("XDG_RUNTIME_DIR") or "/tmp"
local runtimeDir = runtimeBase .. "/noctalia-display-settings-panel"
local draftPath = runtimeDir .. "/draft.json"
local configPath = noctalia.expandPath("~/.config/niri/cfg/display.kdl")
local transformValues = { "normal", "90", "180", "270", "flipped", "flipped-90", "flipped-180", "flipped-270" }
local transformLabels = { "Normal", "90°", "180°", "270°", "Flipped", "Flipped 90°", "Flipped 180°", "Flipped 270°" }
local outputCallbacks = {
  "selectOutput1", "selectOutput2", "selectOutput3", "selectOutput4",
  "selectOutput5", "selectOutput6", "selectOutput7", "selectOutput8",
}

local opened = false
local busy = false
local draft = nil
local baselineOutputs = nil
local selectedIndex = 1
local statusText = "Loading connected displays…"
local statusError = false
local previewActive = false
local previewRemaining = 0
local previewId = nil
local previewExpires = 0
local previewStatus = "inactive"
local formRevision = 0

local render
local restorePreview

local function shellQuote(value)
  return "'" .. string.gsub(value, "'", "'\\''") .. "'"
end

local function clone(value)
  local encoded = noctalia.json.encode(value)
  if not encoded then
    return nil
  end
  return noctalia.json.decode(encoded)
end

local function selectedOutput()
  if not draft or type(draft.outputs) ~= "table" then
    return nil
  end
  return draft.outputs[selectedIndex]
end

local function outputSettingChanged(current, baseline)
  if tostring(current.name or "") ~= tostring(baseline.name or "") then
    return true
  end
  if (current.enabled == true) ~= (baseline.enabled == true) then
    return true
  end
  if tostring(current.mode or "") ~= tostring(baseline.mode or "") then
    return true
  end
  if (current.custom_mode == true) ~= (baseline.custom_mode == true) then
    return true
  end
  if math.abs((tonumber(current.scale) or 1) - (tonumber(baseline.scale) or 1)) > 0.0001 then
    return true
  end
  if tostring(current.transform or "normal") ~= tostring(baseline.transform or "normal") then
    return true
  end
  if math.floor(tonumber(current.x) or 0) ~= math.floor(tonumber(baseline.x) or 0) then
    return true
  end
  if math.floor(tonumber(current.y) or 0) ~= math.floor(tonumber(baseline.y) or 0) then
    return true
  end
  return (current.vrr_enabled == true) ~= (baseline.vrr_enabled == true)
end

local function draftHasChanges()
  if not draft or type(draft.outputs) ~= "table" or type(baselineOutputs) ~= "table" then
    return false
  end
  if #draft.outputs ~= #baselineOutputs then
    return true
  end
  for index, output in ipairs(draft.outputs) do
    if type(baselineOutputs[index]) ~= "table" or outputSettingChanged(output, baselineOutputs[index]) then
      return true
    end
  end
  return false
end

local function replaceDraft(outputs)
  if type(outputs) ~= "table" then
    return false
  end
  local nextDraft = clone(outputs)
  local nextBaseline = clone(outputs)
  if type(nextDraft) ~= "table" or type(nextBaseline) ~= "table" then
    return false
  end
  draft = { outputs = nextDraft }
  baselineOutputs = nextBaseline
  if selectedIndex > #draft.outputs then
    selectedIndex = 1
  end
  formRevision = formRevision + 1
  return true
end

local function setStatus(message, isError)
  statusText = message
  statusError = isError == true
end

local function clearPreviewState()
  previewActive = false
  previewRemaining = 0
  previewId = nil
  previewExpires = 0
  previewStatus = "inactive"
  panel.setWantsSecondTicks(false)
end

local function syncPreviewState(state)
  if type(state) ~= "table" then
    return false
  end
  if state.active == true and type(state.id) == "string" then
    previewActive = true
    previewId = state.id
    previewExpires = tonumber(state.expires) or 0
    previewStatus = tostring(state.status or "unknown")
    previewRemaining = math.max(0, previewExpires - os.time())
    panel.setWantsSecondTicks(true)
  else
    clearPreviewState()
  end
  return true
end

local function decodeBackendResult(result, fallback)
  local decoded = noctalia.json.decode(result.stdout or "")
  if decoded and decoded.ok == true then
    return decoded, nil, nil
  end
  if decoded and decoded.error then
    return nil, decoded.error, decoded.preview
  end
  local detail = result.stderr or ""
  if detail == "" then
    detail = fallback
  end
  return nil, detail, nil
end

local function runBackend(arguments, callback)
  busy = true
  render()
  local command = "python3 " .. shellQuote(backend) .. " " .. arguments
  local started = noctalia.runAsync(command, function(result)
    busy = false
    callback(result)
    render()
  end)
  if not started then
    busy = false
    setStatus("Could not start the display settings backend", true)
    render()
  end
end

local function queryOutputs(successMessage, pendingMessage)
  if busy then
    return
  end
  setStatus(pendingMessage or "Refreshing connected displays…", false)
  runBackend("query", function(result)
    local decoded, backendError = decodeBackendResult(result, "Could not query connected displays")
    if not decoded then
      setStatus(backendError, true)
      return
    end
    if type(decoded.outputs) ~= "table" or not replaceDraft(decoded.outputs) then
      setStatus("Niri returned an invalid output list", true)
      return
    end
    setStatus(successMessage or "Connected display state refreshed", false)
  end)
end

local function modeIndex(output)
  if type(output.mode_values) ~= "table" then
    return 0
  end
  for index, value in ipairs(output.mode_values) do
    if value == output.mode then
      return index - 1
    end
  end
  return 0
end

local function transformIndex(output)
  for index, value in ipairs(transformValues) do
    if value == output.transform then
      return index - 1
    end
  end
  return 0
end

local function logicalWidth(output)
  local width, height = string.match(output.mode or "", "^(%d+)x(%d+)@")
  width = tonumber(width) or output.logical_width or 0
  height = tonumber(height) or output.logical_height or 0
  if output.transform == "90" or output.transform == "270" or output.transform == "flipped-90" or output.transform == "flipped-270" then
    width = height
  end
  return math.floor(width / math.max(tonumber(output.scale) or 1, 0.1) + 0.5)
end

local function monitorButtons()
  local children = {}
  if not draft or type(draft.outputs) ~= "table" or #draft.outputs == 0 then
    table.insert(children, ui.label({ text = "No connected outputs", color = "on_surface_variant" }))
    return children
  end

  local count = math.min(#draft.outputs, #outputCallbacks)
  for index = 1, count do
    local output = draft.outputs[index]
    local marker = output.enabled and "●" or "○"
    local label = marker .. "  " .. output.name
    table.insert(children, ui.button({
      key = "output-" .. output.name,
      text = label,
      glyph = "device-desktop",
      variant = index == selectedIndex and "secondary" or "ghost",
      selected = index == selectedIndex,
      contentAlign = "start",
      onClick = outputCallbacks[index],
    }))
  end
  if #draft.outputs > #outputCallbacks then
    table.insert(children, ui.label({
      text = "Only the first eight outputs can be edited in this preview build",
      fontSize = 11,
      color = "secondary",
      maxLines = 2,
    }))
  end
  return children
end

local function settingRow(label, description, control)
  return ui.row({ gap = 8, align = "center" }, {
    ui.column({ gap = 2, flexGrow = 1 }, {
      ui.label({ text = label, fontWeight = "medium" }),
      ui.label({ text = description, fontSize = 11, color = "on_surface_variant", maxLines = 2 }),
    }),
    control,
  })
end

local function detailContent()
  local output = selectedOutput()
  if not output then
    return { ui.label({ text = "Select a connected output", color = "on_surface_variant" }) }
  end

  local modeLabels = output.mode_labels or {}
  if #modeLabels == 0 then
    modeLabels = { "No modes reported" }
  end

  local positionKey = output.name .. "-" .. tostring(formRevision)
  return {
    ui.row({ align = "center", gap = 8 }, {
      ui.glyph({ name = "device-desktop", size = 20, color = "primary" }),
      ui.label({ text = output.name, fontSize = 20, fontWeight = "bold" }),
      ui.label({ text = output.description or "Connected output", fontSize = 12, color = "on_surface_variant", maxLines = 1, flexGrow = 1 }),
      ui.label({
        text = output.enabled and "Enabled" or "Disabled",
        color = output.enabled and "primary" or "on_surface_variant",
        fontWeight = "bold",
      }),
    }),

    ui.separator({ spacing = 2 }),

    ui.label({ text = "Output", color = "secondary", fontWeight = "bold" }),
    settingRow(
      "Enabled",
      "At least one connected output must remain enabled",
      ui.toggle({ checked = output.enabled == true, enabled = not busy and not previewActive, onChange = "onEnabledChanged" })
    ),
    settingRow(
      "Mode",
      "Resolution and exact refresh rate reported by Niri",
      ui.select({
        options = modeLabels,
        selectedIndex = modeIndex(output),
        width = 260,
        enabled = not busy and not previewActive and #output.mode_values > 0,
        onChange = "onModeChanged",
      })
    ),
    settingRow(
      "Variable Refresh Rate",
      output.vrr_supported and "Reduce tearing when the output supports VRR" or "This output did not report VRR support",
      ui.toggle({
        checked = output.vrr_enabled == true,
        enabled = not busy and not previewActive and output.vrr_supported == true,
        onChange = "onVrrChanged",
      })
    ),

    ui.separator({ spacing = 2 }),

    ui.label({ text = "Layout", color = "secondary", fontWeight = "bold" }),
    settingRow(
      "Scale",
      "Logical output scale; fractional values are supported",
      ui.row({ gap = 8, width = 240, align = "center" }, {
        ui.slider({ min = 0.5, max = 3.0, step = 0.05, value = output.scale, flexGrow = 1, enabled = not busy and not previewActive, onChange = "onScaleChanged" }),
        ui.label({ text = string.format("%.2f×", output.scale), width = 52, textAlign = "end", color = "primary", fontWeight = "bold" }),
      })
    ),
    settingRow(
      "Transform",
      "Rotate counter-clockwise or flip this output",
      ui.select({
        options = transformLabels,
        selectedIndex = transformIndex(output),
        width = 190,
        enabled = not busy and not previewActive,
        onChange = "onTransformChanged",
      })
    ),
    ui.column({ gap = 6 }, {
      ui.row({ gap = 8, align = "center" }, {
        ui.column({ gap = 2, flexGrow = 1 }, {
          ui.label({ text = "Position", fontWeight = "medium" }),
          ui.label({ text = "Logical coordinates; buttons move by 10 logical pixels", fontSize = 11, color = "on_surface_variant", maxLines = 2 }),
        }),
        ui.button({ text = "Auto Arrange", glyph = "layout-columns", variant = "outline", enabled = not busy and not previewActive, onClick = "autoArrange" }),
      }),
      ui.row({ gap = 8, align = "center" }, {
        ui.label({ text = "Horizontal (X)", flexGrow = 1, color = "on_surface_variant" }),
        ui.row({ gap = 4, align = "center" }, {
          ui.button({ glyph = "minus", variant = "outline", width = 32, height = 32, enabled = not busy and not previewActive, onClick = "nudgeXMinus" }),
          ui.input({ key = "x-" .. positionKey, value = tostring(output.x), width = 84, enabled = not busy and not previewActive, onChange = "onXChanged" }),
          ui.button({ glyph = "plus", variant = "outline", width = 32, height = 32, enabled = not busy and not previewActive, onClick = "nudgeXPlus" }),
        }),
      }),
      ui.row({ gap = 8, align = "center" }, {
        ui.label({ text = "Vertical (Y)", flexGrow = 1, color = "on_surface_variant" }),
        ui.row({ gap = 4, align = "center" }, {
          ui.button({ glyph = "minus", variant = "outline", width = 32, height = 32, enabled = not busy and not previewActive, onClick = "nudgeYMinus" }),
          ui.input({ key = "y-" .. positionKey, value = tostring(output.y), width = 84, enabled = not busy and not previewActive, onChange = "onYChanged" }),
          ui.button({ glyph = "plus", variant = "outline", width = 32, height = 32, enabled = not busy and not previewActive, onClick = "nudgeYPlus" }),
        }),
      }),
    }),
  }
end

render = function()
  if not opened then
    return
  end

  local statusColor = statusError and "error" or "primary"
  local draftChanged = draftHasChanges()
  local previewText = draftChanged and "Changes are not applied until Preview is pressed" or "No unapplied changes"
  if previewActive then
    if previewStatus == "rollback" then
      previewText = "Restoring persistent display settings…"
    else
      previewText = "Preview reverts in " .. tostring(previewRemaining) .. " seconds"
    end
  end
  panel.render(ui.column({ gap = 12, padding = 14, flexGrow = 1 }, {
    ui.row({ gap = 8, align = "center" }, {
      ui.glyph({ name = "device-desktop-cog", size = 20, color = "primary" }),
      ui.label({ text = "Display Settings", fontSize = 20, fontWeight = "bold" }),
      ui.label({ text = "Configure connected Niri outputs", fontSize = 12, color = "on_surface_variant", flexGrow = 1 }),
      ui.button({ glyph = "refresh", variant = "ghost", width = 32, height = 32, enabled = not busy and not previewActive and not draftChanged, onClick = "refreshOutputs" }),
      ui.button({ glyph = "close", variant = "ghost", width = 32, height = 32, onClick = "closePanel" }),
    }),

    ui.row({ gap = 12, flexGrow = 1, align = "stretch" }, {
      ui.column({ gap = 8, padding = 6, width = 200, fill = "surface", radius = 12 }, {
        ui.label({ text = "Connected Outputs", fontWeight = "bold", color = "secondary" }),
        ui.scroll({ gap = 6, flexGrow = 1 }, monitorButtons()),
      }),
      ui.separator({ orientation = "vertical" }),
      ui.scroll({ gap = 8, padding = 4, flexGrow = 1 }, detailContent()),
    }),

    ui.separator({ spacing = 2 }),
    ui.row({ gap = 8, paddingH = 8, paddingV = 4, align = "center", fill = statusError and "error/0.14" or "secondary/0.14", radius = 6 }, {
      ui.glyph({ name = busy and "loader" or (statusError and "alert-triangle" or "info-circle"), size = 14, color = statusColor }),
      ui.label({ text = statusText, fontSize = 12, color = statusColor, flexGrow = 1, maxLines = 2 }),
      ui.label({ text = previewText, fontSize = 11, color = "on_surface_variant" }),
    }),
    ui.row({ gap = 10, align = "center" }, {
      ui.button({ text = "Reset", glyph = "restore", variant = "ghost", enabled = not busy and not previewActive and draftChanged, onClick = "resetDraft" }),
      ui.spacer({ flexGrow = 1 }),
      ui.button({ text = "Revert", glyph = "arrow-back-up", variant = "outline", enabled = not busy and previewActive, onClick = "revertPreview" }),
      ui.button({ text = busy and "Working…" or "Preview", glyph = "eye", variant = "secondary", enabled = not busy and not previewActive and draftChanged, onClick = "previewChanges" }),
      ui.button({ text = "Keep Settings", glyph = "device-floppy", variant = "primary", enabled = not busy and previewActive and previewStatus == "active" and draftChanged, onClick = "keepChanges" }),
    }),
  }))
end

local function chooseOutput(index)
  if draft and draft.outputs and draft.outputs[index] then
    selectedIndex = index
    formRevision = formRevision + 1
    render()
  end
end

function selectOutput1() chooseOutput(1) end
function selectOutput2() chooseOutput(2) end
function selectOutput3() chooseOutput(3) end
function selectOutput4() chooseOutput(4) end
function selectOutput5() chooseOutput(5) end
function selectOutput6() chooseOutput(6) end
function selectOutput7() chooseOutput(7) end
function selectOutput8() chooseOutput(8) end

function onEnabledChanged(value)
  local output = selectedOutput()
  if output then
    output.enabled = value == "true"
    render()
  end
end

function onModeChanged(value)
  local output = selectedOutput()
  local index = tonumber(value)
  if output and index and output.mode_values[index + 1] then
    output.mode = output.mode_values[index + 1]
    output.custom_mode = false
    render()
  end
end

function onScaleChanged(value)
  local output = selectedOutput()
  local number = tonumber(value)
  if output and number then
    output.scale = number
    render()
  end
end

function onTransformChanged(value)
  local output = selectedOutput()
  local index = tonumber(value)
  if output and index and transformValues[index + 1] then
    output.transform = transformValues[index + 1]
    render()
  end
end

function onXChanged(value)
  local output = selectedOutput()
  local number = tonumber(value)
  if output and number then
    output.x = math.floor(number)
    render()
  end
end

function onYChanged(value)
  local output = selectedOutput()
  local number = tonumber(value)
  if output and number then
    output.y = math.floor(number)
    render()
  end
end

function onVrrChanged(value)
  local output = selectedOutput()
  if output then
    output.vrr_enabled = value == "true"
    render()
  end
end

local function nudge(axis, amount)
  local output = selectedOutput()
  if output then
    output[axis] = (tonumber(output[axis]) or 0) + amount
    formRevision = formRevision + 1
    render()
  end
end

function nudgeXMinus() nudge("x", -10) end
function nudgeXPlus() nudge("x", 10) end
function nudgeYMinus() nudge("y", -10) end
function nudgeYPlus() nudge("y", 10) end

function autoArrange()
  if not draft or not draft.outputs then
    return
  end
  local x = 0
  for _, output in ipairs(draft.outputs) do
    if output.enabled then
      output.x = x
      output.y = 0
      x = x + logicalWidth(output)
    end
  end
  formRevision = formRevision + 1
  setStatus("Outputs arranged left to right in the draft", false)
  render()
end

function refreshOutputs()
  if not busy and not draftHasChanges() then
    queryOutputs("Connected display state refreshed", "Refreshing connected displays…")
  end
end

function resetDraft()
  if not busy and not previewActive then
    queryOutputs("Draft reset to the current Niri output state", "Resetting the display draft…")
  end
end

function previewChanges()
  if busy or not draft or not draftHasChanges() then
    return
  end
  noctalia.mkdirAll(runtimeDir)
  local encoded, encodeError = noctalia.json.encode(draft, true)
  if not encoded then
    setStatus(encodeError or "Could not encode the display draft", true)
    render()
    return
  end
  local written, writeError = noctalia.writeFile(draftPath, encoded)
  if not written then
    setStatus(writeError or "Could not save the display draft", true)
    render()
    return
  end

  local timeout = tonumber(panel.getConfig("confirm_timeout")) or 15
  local arguments = "preview --draft " .. shellQuote(draftPath) .. " --config " .. shellQuote(configPath) .. " --timeout " .. tostring(timeout)
  setStatus("Applying a temporary display preview…", false)
  runBackend(arguments, function(result)
    local decoded, backendError, previewState = decodeBackendResult(result, "Could not preview display settings")
    if not decoded then
      if not syncPreviewState(previewState) then
        clearPreviewState()
      end
      setStatus(backendError, true)
      return
    end
    previewActive = true
    previewId = decoded.preview_id
    previewExpires = decoded.expires or (os.time() + (decoded.timeout or timeout))
    previewStatus = "active"
    previewRemaining = math.max(0, previewExpires - os.time())
    panel.setWantsSecondTicks(true)
    setStatus("Preview applied — confirm it before the countdown expires", false)
  end)
end

function keepChanges()
  if busy or not previewActive or previewStatus ~= "active" or not draftHasChanges() then
    return
  end
  local arguments = "keep --draft " .. shellQuote(draftPath) .. " --config " .. shellQuote(configPath) .. " --preview-id " .. shellQuote(previewId)
  setStatus("Validating and saving the Niri display configuration…", false)
  runBackend(arguments, function(result)
    local decoded, backendError, previewState = decodeBackendResult(result, "Could not save display settings")
    if not decoded then
      syncPreviewState(previewState)
      setStatus(backendError, true)
      return
    end
    clearPreviewState()
    baselineOutputs = clone(draft.outputs)
    setStatus("Display settings saved to " .. decoded.config_path, false)
  end)
end

restorePreview = function(successMessage)
  if busy or not previewActive then
    return
  end
  setStatus("Restoring the persistent Niri display configuration…", false)
  runBackend("revert --preview-id " .. shellQuote(previewId), function(result)
    local decoded, backendError, previewState = decodeBackendResult(result, "Could not revert display settings")
    if not decoded then
      syncPreviewState(previewState)
      setStatus(backendError, true)
      return
    end
    clearPreviewState()
    setStatus(successMessage, false)
  end)
end

function revertPreview()
  restorePreview("Preview reverted")
end

function update()
  if previewActive then
    if previewStatus == "rollback" then
      restorePreview("Persistent display configuration restored")
    else
      previewRemaining = math.max(0, previewExpires - os.time())
      if previewRemaining == 0 then
        restorePreview("Preview timed out and the persistent display configuration was restored")
      else
        render()
      end
    end
  end
end

function closePanel()
  panel.close()
end

function onOpen(context)
  opened = true
  if previewActive then
    if previewStatus == "rollback" then
      panel.setWantsSecondTicks(true)
      restorePreview("Persistent display configuration restored")
    else
      previewRemaining = math.max(0, previewExpires - os.time())
      if previewRemaining == 0 then
        panel.setWantsSecondTicks(true)
        restorePreview("Preview timed out and the persistent display configuration was restored")
      else
        panel.setWantsSecondTicks(true)
      end
    end
  end
  if not previewActive then
    queryOutputs("Edit a display, then use Preview to test it safely", "Loading connected displays…")
  else
    render()
  end
end

function onClose()
  opened = false
end
