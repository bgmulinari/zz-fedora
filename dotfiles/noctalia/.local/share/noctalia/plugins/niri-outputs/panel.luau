local backend = noctalia.pluginDir() .. "/backend.py"
local runtimeBase = noctalia.getenv("XDG_RUNTIME_DIR") or "/tmp"
local runtimeDir = runtimeBase .. "/noctalia-niri-outputs-panel"
local draftPath = runtimeDir .. "/draft.json"
local displayConfigPath = noctalia.expandPath("~/.config/niri/cfg/display.kdl")
local mainConfigPath = noctalia.expandPath("~/.config/niri/config.kdl")
local transformValues = { "normal", "90", "180", "270", "flipped", "flipped-90", "flipped-180", "flipped-270" }
local outputCallbacks = {
  "selectOutput1", "selectOutput2", "selectOutput3", "selectOutput4",
  "selectOutput5", "selectOutput6", "selectOutput7", "selectOutput8",
}

local opened = false
local busy = false
local draft = nil
local baselineOutputs = nil
local selectedIndex = 1
local statusText = noctalia.tr("panel.status.loading_outputs")
local statusError = false
local previewActive = false
local previewRemaining = 0
local previewId = nil
local previewExpires = 0
local previewStatus = "inactive"
local formRevision = 0

local render
local restorePreview

local function tr(key, substitutions)
  return noctalia.tr(key, substitutions)
end

local function transformLabels()
  return {
    tr("transforms.normal"),
    tr("transforms.rotate_90"),
    tr("transforms.rotate_180"),
    tr("transforms.rotate_270"),
    tr("transforms.flipped"),
    tr("transforms.flipped_90"),
    tr("transforms.flipped_180"),
    tr("transforms.flipped_270"),
  }
end

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

local function translateBackendError(descriptor)
  if type(descriptor) ~= "table" or type(descriptor.key) ~= "string" then
    return nil
  end
  local substitutions = {}
  if type(descriptor.args) == "table" then
    for key, value in pairs(descriptor.args) do
      substitutions[key] = value
    end
  end
  if type(descriptor.cause) == "table" then
    substitutions.reason = translateBackendError(descriptor.cause) or ""
  end
  local translated = tr(descriptor.key, substitutions)
  if translated == descriptor.key then
    return nil
  end
  return translated
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
    return nil, translateBackendError(decoded.error_localization) or decoded.error, decoded.preview
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
    setStatus(tr("panel.errors.backend_start"), true)
    render()
  end
end

local function queryOutputs(successMessage, pendingMessage)
  if busy then
    return
  end
  setStatus(pendingMessage or tr("panel.status.refreshing_outputs"), false)
  runBackend("query", function(result)
    local decoded, backendError = decodeBackendResult(result, tr("panel.errors.query_outputs"))
    if not decoded then
      setStatus(backendError, true)
      return
    end
    if type(decoded.outputs) ~= "table" or not replaceDraft(decoded.outputs) then
      setStatus(tr("panel.errors.invalid_output_list"), true)
      return
    end
    if not syncPreviewState(decoded.preview) then
      clearPreviewState()
    end
    setStatus(successMessage or tr("panel.status.outputs_refreshed"), false)
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

local function localizedModeLabels(output)
  local labels = {}
  for index, value in ipairs(output.mode_values or {}) do
    local label = string.gsub(value, "@", " @ ") .. " " .. tr("units.hertz")
    if type(output.mode_preferred) == "table" and output.mode_preferred[index] == true then
      label = label .. "  • " .. tr("panel.mode_badges.preferred")
    end
    if output.custom_mode == true and value == output.mode then
      label = label .. "  • " .. tr("panel.mode_badges.custom")
    end
    table.insert(labels, label)
  end
  return labels
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
    table.insert(children, ui.label({ text = tr("panel.states.no_connected_outputs"), color = "on_surface_variant" }))
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
      text = tr("panel.limits.first_eight_outputs"),
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
    return { ui.label({ text = tr("panel.states.select_output"), color = "on_surface_variant" }) }
  end

  local modeLabels = localizedModeLabels(output)
  if #modeLabels == 0 then
    modeLabels = { tr("panel.states.no_modes") }
  end

  local positionKey = output.name .. "-" .. tostring(formRevision)
  return {
    ui.row({ align = "center", gap = 8 }, {
      ui.glyph({ name = "device-desktop", size = 20, color = "primary" }),
      ui.label({ text = output.name, fontSize = 20, fontWeight = "bold" }),
      ui.label({ text = output.description or tr("panel.states.connected_output"), fontSize = 12, color = "on_surface_variant", maxLines = 1, flexGrow = 1 }),
      ui.label({
        text = output.enabled and tr("panel.states.enabled") or tr("panel.states.disabled"),
        color = output.enabled and "primary" or "on_surface_variant",
        fontWeight = "bold",
      }),
    }),

    ui.separator({ spacing = 2 }),

    ui.label({ text = tr("panel.sections.output"), color = "secondary", fontWeight = "bold" }),
    settingRow(
      tr("panel.fields.enabled.label"),
      tr("panel.fields.enabled.description"),
      ui.toggle({ checked = output.enabled == true, enabled = not busy and not previewActive, onChange = "onEnabledChanged" })
    ),
    settingRow(
      tr("panel.fields.mode.label"),
      tr("panel.fields.mode.description"),
      ui.select({
        options = modeLabels,
        selectedIndex = modeIndex(output),
        width = 260,
        enabled = not busy and not previewActive and #output.mode_values > 0,
        onChange = "onModeChanged",
      })
    ),
    settingRow(
      tr("panel.fields.vrr.label"),
      output.vrr_supported and tr("panel.fields.vrr.supported_description") or tr("panel.fields.vrr.unsupported_description"),
      ui.toggle({
        checked = output.vrr_enabled == true,
        enabled = not busy and not previewActive and output.vrr_supported == true,
        onChange = "onVrrChanged",
      })
    ),

    ui.separator({ spacing = 2 }),

    ui.label({ text = tr("panel.sections.scale_transform_position"), color = "secondary", fontWeight = "bold" }),
    settingRow(
      tr("panel.fields.scale.label"),
      tr("panel.fields.scale.description"),
      ui.row({ gap = 8, width = 240, align = "center" }, {
        ui.slider({ min = 0.5, max = 3.0, step = 0.05, value = output.scale, flexGrow = 1, enabled = not busy and not previewActive, onChange = "onScaleChanged" }),
        ui.label({ text = string.format("%.2f×", output.scale), width = 52, textAlign = "end", color = "primary", fontWeight = "bold" }),
      })
    ),
    settingRow(
      tr("panel.fields.transform.label"),
      tr("panel.fields.transform.description"),
      ui.select({
        options = transformLabels(),
        selectedIndex = transformIndex(output),
        width = 190,
        enabled = not busy and not previewActive,
        onChange = "onTransformChanged",
      })
    ),
    ui.column({ gap = 6 }, {
      ui.row({ gap = 8, align = "center" }, {
        ui.column({ gap = 2, flexGrow = 1 }, {
          ui.label({ text = tr("panel.fields.position.label"), fontWeight = "medium" }),
          ui.label({ text = tr("panel.fields.position.description"), fontSize = 11, color = "on_surface_variant", maxLines = 2 }),
        }),
        ui.button({ text = tr("panel.buttons.auto_arrange"), glyph = "layout-columns", variant = "outline", enabled = not busy and not previewActive, onClick = "autoArrange" }),
      }),
      ui.row({ gap = 8, align = "center" }, {
        ui.label({ text = tr("panel.fields.position.horizontal"), flexGrow = 1, color = "on_surface_variant" }),
        ui.row({ gap = 4, align = "center" }, {
          ui.button({ glyph = "minus", variant = "outline", width = 32, height = 32, enabled = not busy and not previewActive, onClick = "nudgeXMinus" }),
          ui.input({ key = "x-" .. positionKey, value = tostring(output.x), width = 84, enabled = not busy and not previewActive, onChange = "onXChanged" }),
          ui.button({ glyph = "plus", variant = "outline", width = 32, height = 32, enabled = not busy and not previewActive, onClick = "nudgeXPlus" }),
        }),
      }),
      ui.row({ gap = 8, align = "center" }, {
        ui.label({ text = tr("panel.fields.position.vertical"), flexGrow = 1, color = "on_surface_variant" }),
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
  local previewText = draftChanged and tr("panel.preview.unapplied_changes") or tr("panel.preview.no_unapplied_changes")
  if previewActive then
    if previewStatus == "restoring" then
      previewText = tr("panel.preview.restoring")
    else
      previewText = noctalia.trp("panel.preview.reverts_in", previewRemaining)
    end
  end
  panel.render(ui.column({ gap = 12, padding = 14, flexGrow = 1 }, {
    ui.row({ gap = 8, align = "center" }, {
      ui.glyph({ name = "device-desktop-cog", size = 20, color = "primary" }),
      ui.label({ text = tr("panel.title"), fontSize = 20, fontWeight = "bold" }),
      ui.label({ text = tr("panel.subtitle"), fontSize = 12, color = "on_surface_variant", flexGrow = 1 }),
      ui.button({ glyph = "refresh", variant = "ghost", width = 32, height = 32, enabled = not busy and not previewActive and not draftChanged, onClick = "refreshOutputs" }),
      ui.button({ glyph = "close", variant = "ghost", width = 32, height = 32, onClick = "closePanel" }),
    }),

    ui.row({ gap = 12, flexGrow = 1, align = "stretch" }, {
      ui.column({ gap = 8, padding = 6, width = 200, fill = "surface", radius = 12 }, {
        ui.label({ text = tr("panel.sections.connected_outputs"), fontWeight = "bold", color = "secondary" }),
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
      ui.button({ text = tr("panel.buttons.reset"), glyph = "restore", variant = "ghost", enabled = not busy and not previewActive and draftChanged, onClick = "resetDraft" }),
      ui.spacer({ flexGrow = 1 }),
      ui.button({ text = tr("panel.buttons.revert"), glyph = "arrow-back-up", variant = "outline", enabled = not busy and previewActive, onClick = "revertPreview" }),
      ui.button({ text = busy and tr("panel.buttons.working") or tr("panel.buttons.preview"), glyph = "eye", variant = "secondary", enabled = not busy and not previewActive and draftChanged, onClick = "previewChanges" }),
      ui.button({ text = tr("panel.buttons.keep_settings"), glyph = "device-floppy", variant = "primary", enabled = not busy and previewActive and previewStatus == "active", onClick = "keepChanges" }),
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
  setStatus(tr("panel.status.outputs_arranged"), false)
  render()
end

function refreshOutputs()
  if not busy and not draftHasChanges() then
    queryOutputs(tr("panel.status.outputs_refreshed"), tr("panel.status.refreshing_outputs"))
  end
end

function resetDraft()
  if not busy and not previewActive then
    queryOutputs(tr("panel.status.draft_reset"), tr("panel.status.resetting_draft"))
  end
end

function previewChanges()
  if busy or not draft or not draftHasChanges() then
    return
  end
  noctalia.mkdirAll(runtimeDir)
  local encoded, encodeError = noctalia.json.encode(draft, true)
  if not encoded then
    setStatus(encodeError or tr("panel.errors.encode_draft"), true)
    render()
    return
  end
  local written, writeError = noctalia.writeFile(draftPath, encoded)
  if not written then
    setStatus(writeError or tr("panel.errors.write_draft"), true)
    render()
    return
  end

  local timeout = tonumber(noctalia.getConfig("confirm_timeout")) or 15
  local arguments = "preview --draft " .. shellQuote(draftPath)
    .. " --display-config " .. shellQuote(displayConfigPath)
    .. " --main-config " .. shellQuote(mainConfigPath)
    .. " --timeout " .. tostring(timeout)
  setStatus(tr("panel.status.applying_preview"), false)
  runBackend(arguments, function(result)
    local decoded, backendError, previewState = decodeBackendResult(result, tr("panel.errors.preview"))
    if not decoded then
      if not syncPreviewState(previewState) then
        clearPreviewState()
      end
      setStatus(backendError, true)
      return
    end
    if not syncPreviewState(decoded.preview) then
      previewActive = true
      previewId = decoded.preview_id
      previewExpires = decoded.expires or (os.time() + (decoded.timeout or timeout))
      previewStatus = "active"
      previewRemaining = math.max(0, previewExpires - os.time())
      panel.setWantsSecondTicks(true)
    end
    setStatus(tr("panel.status.preview_applied"), false)
  end)
end

function keepChanges()
  if busy or not previewActive or previewStatus ~= "active" then
    return
  end
  local arguments = "keep --preview-id " .. shellQuote(previewId)
  setStatus(tr("panel.status.saving_settings"), false)
  runBackend(arguments, function(result)
    local decoded, backendError, previewState = decodeBackendResult(result, tr("panel.errors.save"))
    if not decoded then
      syncPreviewState(previewState)
      setStatus(backendError, true)
      return
    end
    clearPreviewState()
    queryOutputs(
      tr("panel.status.settings_saved", { path = decoded.config_path }),
      tr("panel.status.loading_outputs")
    )
  end)
end

restorePreview = function(successMessage)
  if busy or not previewActive then
    return
  end
  setStatus(tr("panel.status.restoring_settings"), false)
  runBackend("revert --preview-id " .. shellQuote(previewId), function(result)
    local decoded, backendError, previewState = decodeBackendResult(result, tr("panel.errors.revert"))
    if not decoded then
      syncPreviewState(previewState)
      setStatus(backendError, true)
      return
    end
    clearPreviewState()
    queryOutputs(successMessage, tr("panel.status.loading_outputs"))
  end)
end

function revertPreview()
  restorePreview(tr("panel.status.preview_reverted"))
end

function update()
  if previewActive then
    if previewStatus == "restoring" then
      restorePreview(tr("panel.status.settings_restored"))
    else
      previewRemaining = math.max(0, previewExpires - os.time())
      if previewRemaining == 0 then
        restorePreview(tr("panel.status.preview_timed_out"))
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
  queryOutputs(tr("panel.status.ready"), tr("panel.status.loading_outputs"))
end

function onClose()
  opened = false
end
