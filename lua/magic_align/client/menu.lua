MAGIC_ALIGN = MAGIC_ALIGN or include("autorun/magic_align.lua")
include("magic_align/client/dmagic_align_numslider.lua")

local M = MAGIC_ALIGN
local client = M.Client or {}
local spaceLabels = client.spaceLabels or {}
local magicSliderClass = "DMagicAlignNumSlider"
local anchorInterpolationSliderClass = "DMagicAlignNumSliders"
local FormulaManager = M.FormulaManager or include("magic_align/client/formula_manager.lua")

M.FormulaManager = FormulaManager

client.getFormulaEnvironment = client.getFormulaEnvironment or function()
    return {}
end

M.GetFormulaEnvironment = M.GetFormulaEnvironment or function(_, slider, cvarName)
    local provider = client.getFormulaEnvironment
    if isfunction(provider) then
        local ok, value = pcall(provider, slider, cvarName)
        if ok and istable(value) then
            return value
        end
    end

    return {}
end

local function setValue(space, key, value)
    if client.setValue then
        return client.setValue(space, key, value)
    end

    RunConsoleCommand("magic_align_" .. space .. "_" .. key, M.FormatConVarNumber(value))
end

local sliderRows = {
    { label = "Position X", key = "px", min = -256, max = 256, decimals = 2 },
    { label = "Position Y", key = "py", min = -256, max = 256, decimals = 2 },
    { label = "Position Z", key = "pz", min = -256, max = 256, decimals = 2 },
    { label = "Pitch", key = "pitch", min = -180, max = 180, decimals = 1 },
    { label = "Yaw", key = "yaw", min = -180, max = 180, decimals = 1 },
    { label = "Roll", key = "roll", min = -180, max = 180, decimals = 1 }
}
local rotationSnapDivisors = client.rotationSnapDivisors or { 2, 3, 4, 5, 6, 8, 9, 10, 12, 15, 18, 20, 24, 30, 36, 40, 45, 60, 72, 90, 120, 180 }
local defaultRotationSnapIndex = client.defaultRotationSnapIndex or 13
local ringQualityPresets = client.ringQualityPresets
local defaultRingQualityIndex = client.defaultRingQualityIndex or 2
local setStringConVar
local getStringConVar
local menuFooterText = "Thank you for using Magic Align.\nI hope it helps your builds click into place a little faster, cleaner, and calmer."
local menuFooterCreditPrefix = "Have fun creating - "
local menuCreditSteamID64 = "76561198023595888"
local menuCreditFallbackName = "SirRanjid"
local menuCreditOnlineColor = Color(100, 255, 150, 255)
local menuCreditName = menuCreditFallbackName
local menuCreditNextNameUpdate = 0
local menuCreditPlayerIndex = 0
local menuCreditFoundInPlayerPass = false
local menuCreditOnline = false

if steamworks and steamworks.RequestPlayerInfo then
    steamworks.RequestPlayerInfo(menuCreditSteamID64)
end

local function getMenuCreditName()
    local now = RealTime()
    if now < menuCreditNextNameUpdate then
        return menuCreditName
    end

    menuCreditNextNameUpdate = now + 1

    local name = steamworks and steamworks.GetPlayerName and steamworks.GetPlayerName(menuCreditSteamID64) or nil
    name = tostring(name or "")

    if name == "" or name == "[unknown]" then
        menuCreditName = menuCreditFallbackName
    else
        menuCreditName = string.Replace(name, "[unknown]", menuCreditFallbackName)
    end

    return menuCreditName
end

local function updateMenuCreditOnline()
    local players = player.GetAll()
    local playerCount = #players

    if playerCount <= 0 then
        menuCreditPlayerIndex = 0
        menuCreditFoundInPlayerPass = false
        menuCreditOnline = false
        return menuCreditOnline
    end

    menuCreditPlayerIndex = menuCreditPlayerIndex + 1
    if menuCreditPlayerIndex > playerCount then
        menuCreditPlayerIndex = 1
        menuCreditFoundInPlayerPass = false
    end

    local ply = players[menuCreditPlayerIndex]
    if IsValid(ply) and ply.SteamID64 and ply:SteamID64() == menuCreditSteamID64 then
        menuCreditFoundInPlayerPass = true
        menuCreditOnline = true
    end

    if menuCreditPlayerIndex >= playerCount then
        menuCreditOnline = menuCreditFoundInPlayerPass
        menuCreditFoundInPlayerPass = false
        menuCreditPlayerIndex = 0
    end

    return menuCreditOnline
end

local function clampRotationSnapIndex(index)
    return math.Clamp(math.Round(tonumber(index) or defaultRotationSnapIndex), 1, #rotationSnapDivisors)
end

local function clampTranslationSnapStep(step)
    return tonumber(step) or 0 --math.Clamp(tonumber(step) or 0, 0, 62) --no clamping TODO Remove also functions using it unnecessarily
end

local function clampTraceSnapLength(length)
    return tonumber(length) or 0 --math.Clamp(tonumber(length) or 0, 0, 32) --no clamping TODO Remove also functions using it unnecessarily
end

local function rotationSnapInfo(index)
    index = clampRotationSnapIndex(index)

    local divisions = rotationSnapDivisors[index] or rotationSnapDivisors[defaultRotationSnapIndex]
    local step = 360 / math.max(divisions, 1)

    return index, divisions, step
end

local function clampRingQualityIndex(index)
    return math.Clamp(math.Round(tonumber(index) or defaultRingQualityIndex), 1, #ringQualityPresets)
end

local function ringQualityInfo(index)
    index = clampRingQualityIndex(index)
    return index, ringQualityPresets[index] or ringQualityPresets[defaultRingQualityIndex]
end

local persistedMenuConVars = {
    "magic_align_rotation_snap",
    "magic_align_translation_snap",
    "magic_align_trace_snap_length",
    "magic_align_world_target",
    "magic_align_grid_label_percent",
    "magic_align_grid_label_reduce_fraction",
    "magic_align_grid_alpha",
    "magic_align_display_rounding",
    "magic_align_preview_occluded",
    "magic_align_preview_occluded_r",
    "magic_align_preview_occluded_g",
    "magic_align_preview_occluded_b",
    "magic_align_preview_occluded_a",
    "magic_align_ring_quality",
    "magic_align_highlight_context_menu",
    "magic_align_disable_smartsnap_active"
}
local tabOffsetSuffixes = { "px", "py", "pz", "pitch", "yaw", "roll" }
local sessionTabCallbacksRegistered = false

local function formatDisplayRoundedValue(value)
    local setting = M.GetDisplayRounding()
    return M.FormatDisplayNumber(value, setting, {
        fallback = M.DEFAULT_DISPLAY_ROUNDING,
        trim = M.RoundingSettingToDecimals(setting, M.DEFAULT_DISPLAY_ROUNDING) == nil
    })
end

local function getBoolConVar(name, fallback)
    local cvar = GetConVar(name)
    if cvar then
        return cvar:GetBool()
    end

    return fallback == true
end

local function persistMenuConVar(name)
    if not name or name == "" then return end

    local cookieKey = "magic_align_menu_" .. name
    local callbackId = "magic_align_menu_" .. name
    local cvar = GetConVar(name)
    if cvar then
        local saved = cookie.GetString(cookieKey, "")
        if saved ~= "" then
            local current = cvar:GetString()
            local defaultValue = cvar.GetDefault and cvar:GetDefault() or nil
            if current == "" or (defaultValue ~= nil and current == defaultValue) then
                RunConsoleCommand(name, saved)
            end
        end
    end

    if not cvars or not cvars.AddChangeCallback then return end

    if cvars.RemoveChangeCallback then
        cvars.RemoveChangeCallback(name, callbackId)
    end

    cvars.AddChangeCallback(name, function(_, _, newValue)
        cookie.Set(cookieKey, tostring(newValue or ""))
    end, callbackId)
end

local function applyPersistedMenuConVars()
    for i = 1, #persistedMenuConVars do
        persistMenuConVar(persistedMenuConVars[i])
    end
end

local function currentRotationSnapIndex()
    return clampRotationSnapIndex(getStringConVar("magic_align_rotation_snap", defaultRotationSnapIndex))
end

local function setRotationSnapIndex(index)
    setStringConVar("magic_align_rotation_snap", tostring(clampRotationSnapIndex(index)))
end

local function currentTranslationSnapStep()
    return clampTranslationSnapStep(getStringConVar("magic_align_translation_snap", 0))
end

local function setTranslationSnapStep(step)
    setStringConVar("magic_align_translation_snap", M.FormatConVarNumber(clampTranslationSnapStep(step)))
end

local function currentTraceSnapLength()
    return clampTraceSnapLength(getStringConVar("magic_align_trace_snap_length", 5))
end

local function setTraceSnapLength(length)
    setStringConVar("magic_align_trace_snap_length", M.FormatConVarNumber(clampTraceSnapLength(length)))
end

local function currentRingQualityIndex()
    return clampRingQualityIndex(getStringConVar("magic_align_ring_quality", defaultRingQualityIndex))
end

local function setRingQualityIndex(index)
    setStringConVar("magic_align_ring_quality", tostring(clampRingQualityIndex(index)))
end

local function isOffsetNeutral(value)
    return math.abs(tonumber(value) or 0) <= M.UI_COMPARE_EPSILON
end

local function spaceHasOffsetChanges(space)
    for i = 1, #tabOffsetSuffixes do
        local name = ("magic_align_%s_%s"):format(space, tabOffsetSuffixes[i])
        if not isOffsetNeutral(getStringConVar(name, "0")) then
            return true
        end
    end

    return false
end

local function relayoutSessionTabs()
    local sheet = M.ClientSheet
    if not IsValid(sheet) then return end

    local scroller = sheet.tabScroller
    if IsValid(scroller) then
        local panels = scroller.Panels or {}
        for i = 1, #panels do
            local tab = panels[i]
            if IsValid(tab) then
                if tab.SizeToContentsX then
                    tab:SizeToContentsX(24)
                end
                tab:InvalidateLayout(true)
            end
        end

        if IsValid(scroller.pnlCanvas) then
            scroller.pnlCanvas:InvalidateLayout(true)
        end
        scroller:InvalidateLayout(true)
    end

    sheet:InvalidateLayout(true)
end

local function updateSessionTabTitle(space)
    local tab = M.ClientTabs and M.ClientTabs[space]
    if not IsValid(tab) then return false end

    local baseLabel = spaceLabels[space] or space
    local label = spaceHasOffsetChanges(space) and ("* " .. baseLabel) or baseLabel
    if tab.GetText and tab:GetText() == label then return false end

    tab:SetText(label)
    if tab.SizeToContentsX then
        tab:SizeToContentsX(24)
    end
    tab:InvalidateLayout(true)
    return true
end

local function updateSessionTabTitles()
    local changed = false
    for i = 1, #(M.SPACES or {}) do
        changed = updateSessionTabTitle(M.SPACES[i]) or changed
    end

    if changed then
        relayoutSessionTabs()
    end
end

local function registerSessionTabCallbacks()
    if sessionTabCallbacksRegistered or not cvars or not cvars.AddChangeCallback then return end

    sessionTabCallbacksRegistered = true

    for i = 1, #(M.SPACES or {}) do
        local space = M.SPACES[i]
        for j = 1, #tabOffsetSuffixes do
            local suffix = tabOffsetSuffixes[j]
            local name = ("magic_align_%s_%s"):format(space, suffix)
            local callbackId = ("magic_align_tab_%s_%s"):format(space, suffix)

            if cvars.RemoveChangeCallback then
                cvars.RemoveChangeCallback(name, callbackId)
            end

            cvars.AddChangeCallback(name, function()
                updateSessionTabTitles()
            end, callbackId)
        end
    end
end

applyPersistedMenuConVars()
registerSessionTabCallbacks()

local panelSliderRows = {
    { label = "Pos X", key = "px", min = -16, max = 16, decimals = 3 },
    { label = "Pos Y", key = "py", min = -16, max = 16, decimals = 3 },
    { label = "Pos Z", key = "pz", min = -16, max = 16, decimals = 3 },
    { label = "Pitch", key = "pitch", min = -180, max = 180, decimals = 3 },
    { label = "Yaw", key = "yaw", min = -180, max = 180, decimals = 3 },
    { label = "Roll", key = "roll", min = -180, max = 180, decimals = 3 }
}

local function registerFormulaConVars()
    if not FormulaManager then
        return
    end

    for _, space in ipairs(M.SPACES or {}) do
        for _, row in ipairs(panelSliderRows) do
            FormulaManager:RegisterConVar(("magic_align_%s_%s"):format(space, row.key))
        end
    end

    FormulaManager:RegisterConVar("magic_align_translation_snap")
    FormulaManager:RegisterConVar("magic_align_trace_snap_length")
end

registerFormulaConVars()

local anchorShortLabels = {
    p1 = "P1",
    p2 = "P2",
    p3 = "P3",
    mid12 = "Mid 1-2",
    mid23 = "Mid 2-3",
    mid13 = "Mid 1-3",
    mid123 = "Mid All"
}

local anchorPercentLabels = {
    mid12 = "1-2",
    mid23 = "2-3",
    mid13 = "1-3"
}

local menuColors = {
    text = Color(18, 18, 18),
    textMuted = Color(118, 118, 118),
    textOutline = Color(255, 255, 255, 230),
    panel = Color(232, 232, 232),
    panelSoft = Color(243, 243, 243),
    border = Color(138, 138, 138),
    input = Color(247, 247, 247),
    inputFocus = Color(255, 255, 255),
    inputBorder = Color(124, 124, 124),
    tabStrip = Color(176, 176, 176),
    tabIdle = Color(156, 156, 156),
    tabHover = Color(166, 166, 166),
    tabActive = Color(206, 206, 206),
    tabActiveLine = Color(94, 94, 94),
    button = Color(214, 214, 214),
    buttonHover = Color(224, 224, 224),
    buttonDown = Color(196, 196, 196),
    anchorBody = Color(238, 238, 238),
    anchorRow = Color(249, 249, 249),
    anchorRowHover = Color(255, 255, 255),
    anchorRowDisabled = Color(226, 226, 226),
    anchorRowDisabledHover = Color(232, 232, 232),
    anchorRowActiveDisabled = Color(221, 221, 221)
}

client.menuColors = menuColors
client.updateSessionTabTitles = updateSessionTabTitles

local function wrapLabelText(text, font, maxWidth)
    text = tostring(text or "")
    maxWidth = math.max(math.floor(tonumber(maxWidth) or 0), 0)

    if maxWidth <= 0 then
        return { text }
    end

    surface.SetFont(font)

    local lines = {}
    local function textFits(value)
        local width = surface.GetTextSize(value)
        return width <= maxWidth
    end

    local function appendWrappedLine(line)
        line = tostring(line or "")

        if line == "" then
            lines[#lines + 1] = ""
            return
        end

        local current = ""
        for word in string.gmatch(line, "%S+") do
            local candidate = current == "" and word or (current .. " " .. word)

            if current ~= "" and not textFits(candidate) then
                lines[#lines + 1] = current
                current = word
            else
                current = candidate
            end
        end

        lines[#lines + 1] = current
    end

    local startIndex = 1
    while true do
        local newline = string.find(text, "\n", startIndex, true)
        local line = newline and string.sub(text, startIndex, newline - 1) or string.sub(text, startIndex)
        appendWrappedLine(line)

        if not newline then
            break
        end

        startIndex = newline + 1
    end

    return lines
end

local outlinedLabelVersion = "native-hidden-v4"
local outlinedLabelPad = 1
local transparentTextColor = Color(0, 0, 0, 0)

local function getOutlinedLabelFont(label)
    if label.GetFont then
        return label:GetFont() or "DermaDefault"
    end

    return "DermaDefault"
end

local function hideNativeLabelText(label)
    if label.MagicAlignBaseSetText and (not label.MagicAlignBaseGetText or label.MagicAlignBaseGetText(label) ~= "") then
        label.MagicAlignBaseSetText(label, "")
    end

    if label.MagicAlignBaseSetTextColor and not label.MagicAlignNativeTextColorHidden then
        label.MagicAlignBaseSetTextColor(label, transparentTextColor)
        label.MagicAlignNativeTextColorHidden = true
    end

    if label.SetFGColor then
        label:SetFGColor(0, 0, 0, 0)
    end

    if label.SetExpensiveShadow then
        label:SetExpensiveShadow(0, transparentTextColor)
    end
end

local function getOutlinedLabelTextSize(label)
    local font = getOutlinedLabelFont(label)
    local text = label:GetText()

    surface.SetFont(font)

    if label.MagicAlignWrapText or (label.GetWrap and label:GetWrap()) then
        local lines = wrapLabelText(text, font, math.max(label:GetWide() - outlinedLabelPad * 2, 0))
        local maxWidth = 0
        for i = 1, #lines do
            local lineWidth = surface.GetTextSize(lines[i])
            maxWidth = math.max(maxWidth, lineWidth)
        end

        local _, lineHeight = surface.GetTextSize("W")
        return maxWidth + outlinedLabelPad * 2, math.max(#lines * lineHeight + outlinedLabelPad * 2, lineHeight)
    end

    local width, height = surface.GetTextSize(text)
    return width + outlinedLabelPad * 2, height + outlinedLabelPad * 2
end

local function paintOutlinedLabel(label, w, h)
    hideNativeLabelText(label)

    local text = label:GetText() or ""
    if text == "" then return true end

    local font = getOutlinedLabelFont(label)
    local color = label.MagicAlignOutlinedTextColor or menuColors.text
    local align = label.GetContentAlignment and label:GetContentAlignment() or 4
    local xAlign = (align == 2 or align == 5 or align == 8) and TEXT_ALIGN_CENTER or ((align == 3 or align == 6 or align == 9) and TEXT_ALIGN_RIGHT or TEXT_ALIGN_LEFT)
    local yAlign = (align == 1 or align == 2 or align == 3) and TEXT_ALIGN_BOTTOM or ((align == 4 or align == 5 or align == 6) and TEXT_ALIGN_CENTER or TEXT_ALIGN_TOP)
    local x = xAlign == TEXT_ALIGN_CENTER and w * 0.5 or (xAlign == TEXT_ALIGN_RIGHT and w - outlinedLabelPad or outlinedLabelPad)

    if label.MagicAlignWrapText or (label.GetWrap and label:GetWrap()) then
        surface.SetFont(font)
        local _, lineHeight = surface.GetTextSize("W")
        lineHeight = math.max(lineHeight, 1)

        local lines = wrapLabelText(text, font, math.max(w - outlinedLabelPad * 2, 0))
        local totalHeight = #lines * lineHeight
        local y = yAlign == TEXT_ALIGN_CENTER and (h - totalHeight) * 0.5
            or (yAlign == TEXT_ALIGN_BOTTOM and h - totalHeight - outlinedLabelPad or outlinedLabelPad)
        y = math.max(math.floor(y), outlinedLabelPad)

        for i = 1, #lines do
            draw.SimpleTextOutlined(lines[i], font, x, y + (i - 1) * lineHeight, color, xAlign, TEXT_ALIGN_TOP, 1, menuColors.textOutline)
        end

        return true
    end

    local y = yAlign == TEXT_ALIGN_CENTER and h * 0.5 or (yAlign == TEXT_ALIGN_BOTTOM and h - outlinedLabelPad or outlinedLabelPad)
    draw.SimpleTextOutlined(text, font, x, y, color, xAlign, yAlign, 1, menuColors.textOutline)
    return true
end

local function styleOutlinedLabel(label, textColor)
    if not IsValid(label) then return end

    local currentText = label.MagicAlignOutlinedText
    if currentText == nil and label.GetText then
        currentText = label:GetText()
    end

    if label.MagicAlignTextOutlined ~= outlinedLabelVersion then
        label.MagicAlignBaseSetText = label.MagicAlignBaseSetText or label.SetText
        label.MagicAlignBaseGetText = label.MagicAlignBaseGetText or label.GetText
        label.MagicAlignBaseSetTextColor = label.MagicAlignBaseSetTextColor or label.SetTextColor

        label.SetText = function(self, value)
            value = tostring(value or "")
            if self.MagicAlignOutlinedText == value then
                hideNativeLabelText(self)
                return
            end

            self.MagicAlignOutlinedText = value
            hideNativeLabelText(self)
            self:InvalidateLayout(true)
        end

        label.GetText = function(self)
            return self.MagicAlignOutlinedText or ""
        end

        label.SetTextColor = function(self, color)
            color = color or menuColors.text
            if self.MagicAlignOutlinedTextColor == color then
                hideNativeLabelText(self)
                return
            end

            self.MagicAlignOutlinedTextColor = color
            hideNativeLabelText(self)
            self:InvalidateLayout(false)
        end
        label.SetColor = label.SetTextColor

        label.GetTextColor = function(self)
            return self.MagicAlignOutlinedTextColor
        end
        label.GetColor = label.GetTextColor

        label.GetTextSize = getOutlinedLabelTextSize

        label.SizeToContentsY = function(self, extra)
            local _, h = self:GetTextSize()
            self:SetTall(math.max(math.ceil(h + (tonumber(extra) or 0)), 1))
        end

        label.SizeToContents = function(self, extraX, extraY)
            local labelWidth, labelHeight = self:GetTextSize()
            self:SetSize(
                math.max(math.ceil(labelWidth + (tonumber(extraX) or 0)), 1),
                math.max(math.ceil(labelHeight + (tonumber(extraY) or 0)), 1)
            )
        end

        label.ApplySchemeSettings = function(self)
            hideNativeLabelText(self)
        end

        label.Paint = paintOutlinedLabel
        label.MagicAlignTextOutlined = outlinedLabelVersion
    end

    label:SetText(currentText or "")
    label:SetTextColor(textColor or label.MagicAlignOutlinedTextColor or menuColors.text)
    hideNativeLabelText(label)
end

local anchorLookup = {}
for _, anchor in ipairs(M.ANCHORS or {}) do
    anchorLookup[anchor.id] = anchor
end

setStringConVar = function(name, value)
    RunConsoleCommand(name, tostring(value or ""))
end

getStringConVar = function(name, fallback)
    local cvar = GetConVar(name)
    if cvar then
        return cvar:GetString()
    end

    return fallback or ""
end

local function sliderDisplaySetting(baseDecimals)
    baseDecimals = tonumber(baseDecimals)
    if baseDecimals ~= nil and baseDecimals <= 0 then
        return 0
    end

    return M.GetDisplayRounding()
end

local function formatSliderDisplayValue(value, baseDecimals)
    local setting = sliderDisplaySetting(baseDecimals)
    return M.FormatDisplayNumber(value, setting, {
        fallback = M.DEFAULT_DISPLAY_ROUNDING,
        trim = M.RoundingSettingToDecimals(setting, M.DEFAULT_DISPLAY_ROUNDING) == nil
    })
end

local function syncStandardSliderDisplay(slider, force)
    if not IsValid(slider) or slider.MagicAlignExpressionInput == true then return end
    if not IsValid(slider.TextArea) or slider.TextArea:HasFocus() or slider.MagicAlignDisplayApplying then return end

    local numeric = isfunction(slider.GetValue) and tonumber(slider:GetValue()) or tonumber(slider.TextArea:GetValue())
    if numeric == nil then return end

    local baseDecimals = tonumber(slider.MagicAlignBaseDecimals) or 0
    local setting = sliderDisplaySetting(baseDecimals)
    local displayText = formatSliderDisplayValue(numeric, baseDecimals)
    local signature = table.concat({
        tostring(setting),
        M.FormatConVarNumber(numeric)
    }, "\30")

    if not force
        and slider.MagicAlignDisplaySignature == signature
        and tostring(slider.TextArea:GetValue() or "") == displayText then
        return
    end

    slider.MagicAlignDisplaySignature = signature
    slider.MagicAlignDisplayApplying = true
    slider.TextArea:SetValue(displayText)
    slider.MagicAlignDisplayApplying = false
end

local function installSliderDisplayRounding(slider, baseDecimals)
    if not IsValid(slider) or slider.MagicAlignExpressionInput == true then
        return slider
    end

    slider.MagicAlignBaseDecimals = tonumber(baseDecimals) or 0

    local originalThink = slider.Think
    slider.Think = function(self)
        if isfunction(originalThink) then
            originalThink(self)
        end

        syncStandardSliderDisplay(self, false)
    end

    syncStandardSliderDisplay(slider, true)

    return slider
end

local function currentRotationSnapStep()
    local index, _, step = rotationSnapInfo(getStringConVar("magic_align_rotation_snap", defaultRotationSnapIndex))
    return index, step
end

local function resetInterpolationPercentages(side)
    local value = tostring(M.ClampAnchorPercent and M.ClampAnchorPercent(50) or 50)

    for _, anchorId in ipairs(M.ANCHOR_PERCENT_KEYS or {}) do
        setStringConVar(("magic_align_%s_%s_pct"):format(side, anchorId), value)
    end
end

local function anchorLabel(id)
    local anchor = anchorLookup[id]
    if anchor and anchorShortLabels[id] then
        return anchorShortLabels[id]
    end
    if anchor and anchor.label then
        return anchor.label
    end

    return string.upper(tostring(id or ""))
end

local function completeAnchorOrder(priorityText)
    local order = {}
    local seen = {}

    for _, id in ipairs(M.ParsePriority(priorityText)) do
        if anchorLookup[id] and not seen[id] then
            order[#order + 1] = id
            seen[id] = true
        end
    end

    for _, anchor in ipairs(M.ANCHORS) do
        if not seen[anchor.id] then
            order[#order + 1] = anchor.id
            seen[anchor.id] = true
        end
    end

    return order
end

local function serializeAnchorOrder(order)
    return table.concat(order or {}, ",")
end

local function anchorAvailable(id, count)
    return M.AnchorAvailable(id, count)
end

local function priorityIndex(order, id)
    for index, name in ipairs(order or {}) do
        if name == id then
            return index
        end
    end

    return math.huge
end

local function highestAvailableAnchor(order, count)
    for _, id in ipairs(order or {}) do
        if anchorAvailable(id, count) then
            return id
        end
    end
end

local function activeState()
    if client.activeTool then
        local _, state = client.activeTool()
        if state then
            return state
        end
    end

    return M.ClientState
end

local function pointCount(side)
    local state = activeState()
    if not state then return 0 end

    local points = side == "from" and state.source or state.target
    return istable(points) and #points or 0
end

local function styleTextEntry(entry)
    if entry.MagicAlignStyled then return end

    entry.MagicAlignStyled = true
    entry:SetPaintBackground(false)
    entry:SetTextInset(6, 0)
    entry:SetDrawLanguageID(false)
    entry:SetTextColor(menuColors.text)

    entry.Paint = function(self, w, h)
        local bg = self:HasFocus() and menuColors.inputFocus or menuColors.input
        draw.RoundedBox(4, 0, 0, w, h, bg)
        surface.SetDrawColor(menuColors.inputBorder)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
        self:DrawTextEntryText(menuColors.text, menuColors.text, menuColors.text)
    end
end

local function stylePanelSlider(slider, options)
    options = options or {}
    local labelMarginRight = options.labelMarginRight or 8
    local textMarginLeft = options.textMarginLeft or 8
    local sliderMarginY = options.sliderMarginY or 8
    local customTextSlider = slider.MagicAlignExpressionInput == true
    local labelWide = options.labelWide or (customTextSlider and 46 or 60)
    local textWide = options.textWide or 56

    slider:SetDark(true)
    slider:SetTall(options.tall or 30)
    slider.Label:SetTextColor(options.textColor or menuColors.text)
    slider.TextArea:SetTextColor(options.textColor or menuColors.text)
    slider.TextArea:SetFont("DermaDefault")
    slider.TextArea:SetNumeric(not customTextSlider)

    if options.outlineLabel then
        styleOutlinedLabel(slider.Label, options.textColor or menuColors.text)
    end

    if not customTextSlider then
        styleTextEntry(slider.TextArea)
    end

    if customTextSlider and isfunction(slider.SetLayoutMetrics) then
        slider:SetLayoutMetrics({
            labelWide = labelWide,
            textWide = textWide,
            labelMarginRight = labelMarginRight,
            textMarginLeft = textMarginLeft,
            sliderMarginY = sliderMarginY
        })
    else
        slider.PerformLayout = function(self, w, h)
            local textHolder = self.TextAreaSlot or self.TextArea
            self.Label:SetWide(labelWide)
            self.Label:DockMargin(0, 0, labelMarginRight, 0)
            textHolder:SetWide(textWide)
            textHolder:DockMargin(textMarginLeft, 4, 0, 4)
            self.Slider:DockMargin(0, sliderMarginY, 0, sliderMarginY)
        end
    end

    slider:InvalidateLayout(true)
end

local function styleFlatButton(button, text)
    button.displayText = text or button:GetText()
    button:SetText("")

    button.Paint = function(self, w, h)
        local bg = menuColors.button
        if self:IsDown() then
            bg = menuColors.buttonDown
        elseif self:IsHovered() then
            bg = menuColors.buttonHover
        end

        draw.RoundedBox(6, 0, 0, w, h, bg)
        surface.SetDrawColor(menuColors.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
        draw.SimpleText(self.displayText, "DermaDefaultBold", w * 0.5, h * 0.5, menuColors.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end

local function stylePropertySheet(sheet)
    sheet:SetPadding(10)
    sheet:SetFadeTime(0)

    sheet.Paint = function(self, w, h)
        local top = IsValid(self.tabScroller) and self.tabScroller:GetTall() or 24
        draw.RoundedBox(8, 0, math.max(top - 1, 0), w, h - math.max(top - 1, 0), menuColors.panel)
        surface.SetDrawColor(menuColors.border)
        surface.DrawOutlinedRect(0, math.max(top - 1, 0), w, h - math.max(top - 1, 0), 1)
    end

    if IsValid(sheet.tabScroller) then
        sheet.tabScroller.Paint = function(self, w, h)
            draw.RoundedBoxEx(8, 0, 0, w, h, menuColors.tabStrip, true, true, false, false)
        end
    end
end

local function stylePropertyTab(tabButton)
    tabButton.GetTabHeight = function()
        return 24
    end

    tabButton.UpdateColours = function(self)
        return self:SetTextStyleColor(menuColors.text)
    end

    tabButton.Paint = function(self, w, h)
        local bg = menuColors.tabIdle
        if self:IsActive() then
            bg = menuColors.tabActive
        elseif self:IsHovered() then
            bg = menuColors.tabHover
        end

        draw.RoundedBoxEx(6, 0, 0, w, h, bg, true, true, false, false)
        surface.SetDrawColor(menuColors.border)
        surface.DrawOutlinedRect(0, 0, w, h - 1, 1)

        if self:IsActive() then
            surface.SetDrawColor(menuColors.tabActiveLine)
            surface.DrawRect(1, h - 3, w - 2, 3)
        end
    end

    tabButton:InvalidateLayout(true)
end

local function styleCheckBox(checkBox)
    if not IsValid(checkBox) then return end

    if checkBox.SetDark then
        checkBox:SetDark(true)
    end

    if IsValid(checkBox.Label) then
        styleOutlinedLabel(checkBox.Label, menuColors.text)
    end

    if IsValid(checkBox.Button) then
        checkBox.Button.Paint = function(self, w, h)
            local owner = self:GetParent()
            local forced = owner.MagicAlignForced == true
            local checked = owner.MagicAlignVisualValue

            if checked == nil and self.GetChecked then
                checked = self:GetChecked()
            end

            local bg = forced and menuColors.anchorRowDisabled or menuColors.input
            if self:IsHovered() and not forced then
                bg = menuColors.inputFocus
            end

            draw.RoundedBox(4, 0, 0, w, h, bg)
            surface.SetDrawColor(menuColors.inputBorder)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            if checked then
                local color = forced and menuColors.textMuted or menuColors.text
                local startX = math.floor(w * 0.18)
                local midX = math.floor(w * 0.42)
                local endX = math.floor(w * 0.82)
                local startY = math.floor(h * 0.56)
                local midY = math.floor(h * 0.8)
                local endY = math.floor(h * 0.22)

                surface.SetDrawColor(color)
                for offset = 0, 1 do
                    surface.DrawLine(startX, startY + offset, midX, midY + offset)
                    surface.DrawLine(midX, midY + offset, endX, endY + offset)
                end
            end
        end
    end
end

local function addStyledSlider(panel, label, convar, min, max, decimals, options)
    options = options or {}
    if options.outlineLabel == nil then
        options.outlineLabel = true
    end

    local slider = vgui.Create("DNumSlider", panel)
    slider:SetText(label)
    slider:SetMinMax(min, max)
    slider:SetDecimals(decimals or 0)
    slider:SetConVar(convar)
    stylePanelSlider(slider, options)
    installSliderDisplayRounding(slider, decimals or 0)
    panel:AddItem(slider)
    return slider
end

local function createStackPanel(parent, options)
    options = options or {}

    local stack = vgui.Create("DPanel", parent)
    stack.Paint = nil
    stack.items = {}
    stack.spacing = options.spacing or 6
    stack.padX = options.padX or 0
    stack.padY = options.padY or 0

    function stack:AddItem(item, gapAfter)
        if not IsValid(item) then return item end

        item:SetParent(self)
        self.items[#self.items + 1] = {
            panel = item,
            gapAfter = gapAfter
        }
        self:InvalidateLayout(true)
        return item
    end

    stack.PerformLayout = function(self, w, h)
        local y = self.padY
        local contentWidth = math.max(w - self.padX * 2, 0)

        for index, entry in ipairs(self.items) do
            local item = entry.panel
            if IsValid(item) then
                item:SetPos(self.padX, y)
                item:SetWide(contentWidth)

                if item.GetWrap and item:GetWrap() and item.SizeToContentsY then
                    item:SizeToContentsY()
                else
                    item:InvalidateLayout(true)
                end

                local gap = entry.gapAfter
                if gap == nil then
                    gap = index < #self.items and self.spacing or 0
                end

                y = y + item:GetTall() + gap
            end
        end

        self:SetTall(y + self.padY)
    end

    return stack
end

local function createHelpLabel(parent, text, textColor, outlined)
    local label = vgui.Create("DLabel", parent)
    label:SetText(text or "")
    label:SetWrap(true)
    label.MagicAlignWrapText = true
    label:SetAutoStretchVertical(true)
    label:SetFont("DermaDefault")
    label:SetTextColor(textColor or menuColors.text)
    label:SetContentAlignment(7)

    if outlined then
        styleOutlinedLabel(label, textColor or menuColors.text)
    end

    return label
end

local function createMenuCreditRow(parent)
    local row = vgui.Create("DPanel", parent)
    row.Paint = nil
    row:SetTall(18)

    local prefixLabel = vgui.Create("DLabel", row)
    prefixLabel:SetText(menuFooterCreditPrefix)
    prefixLabel:SetFont("DermaDefault")
    prefixLabel:SetContentAlignment(7)
    styleOutlinedLabel(prefixLabel, menuColors.text)

    local nameLabel = vgui.Create("DLabel", row)
    nameLabel:SetText(getMenuCreditName())
    nameLabel:SetFont("DermaDefault")
    nameLabel:SetContentAlignment(7)
    styleOutlinedLabel(nameLabel, menuColors.text)

    nameLabel.Think = function(self)
        local name = getMenuCreditName()
        if self:GetText() ~= name then
            self:SetText(name)
            if IsValid(row) then
                row:InvalidateLayout(true)
            end
        end

        self:SetTextColor(updateMenuCreditOnline() and menuCreditOnlineColor or menuColors.text)
    end

    row.PerformLayout = function(self)
        prefixLabel:SizeToContents()
        nameLabel:SizeToContents()

        local rowHeight = math.max(prefixLabel:GetTall(), nameLabel:GetTall(), 18)
        prefixLabel:SetPos(0, 0)
        nameLabel:SetPos(prefixLabel:GetWide(), 0)
        self:SetTall(rowHeight)
    end

    return row
end

local function createMenuFooter(parent)
    local footer = createStackPanel(parent, {
        spacing = 0,
        padY = 4
    })

    local label = createHelpLabel(footer, menuFooterText, menuColors.text, true)
    label:SetFont("DermaDefault")
    footer:AddItem(label, 0)
    footer:AddItem(createMenuCreditRow(footer), 0)

    return footer
end

local function addStyledCheckBox(panel, label, convar)
    local checkBox = vgui.Create("DCheckBoxLabel", panel)
    checkBox:SetText(label)
    checkBox:SetConVar(convar)
    checkBox:SizeToContents()
    checkBox:SetTall(22)
    styleCheckBox(checkBox)
    panel:AddItem(checkBox)
    return checkBox
end

local function createInlineCheckBoxRow(parent, items, options)
    options = options or {}

    local row = vgui.Create("DPanel", parent)
    row.Paint = nil
    row.items = {}
    row.gap = options.gap or 12
    row.itemTall = options.itemTall or 22

    for i = 1, #(items or {}) do
        local item = items[i] or {}
        local checkBox = vgui.Create("DCheckBoxLabel", row)
        checkBox:SetText(item.label or "")
        if item.convar then
            checkBox:SetConVar(item.convar)
        end
        checkBox:SizeToContents()
        checkBox:SetTall(row.itemTall)
        styleCheckBox(checkBox)
        row.items[#row.items + 1] = checkBox
    end

    row.PerformLayout = function(self, w, _)
        local x = 0
        local tallest = self.itemTall

        for i = 1, #self.items do
            local checkBox = self.items[i]
            if IsValid(checkBox) then
                checkBox:SizeToContents()
                checkBox:SetTall(self.itemTall)
                checkBox:SetPos(x, 0)
                checkBox:SetWide(math.min(checkBox:GetWide(), math.max(w - x, 0)))
                checkBox:InvalidateLayout(true)

                x = x + checkBox:GetWide() + self.gap
                tallest = math.max(tallest, checkBox:GetTall())
            end
        end

        self:SetTall(tallest)
    end

    return row
end

local function readColorConVar(name, fallback)
    local cvar = GetConVar(name)
    local value = cvar and cvar:GetInt() or fallback

    return math.Clamp(math.floor(tonumber(value) or fallback or 0), 0, 255)
end

local function createPreviewOccludedColorPicker(parent)
    local holder = vgui.Create("DPanel", parent)
    holder:SetTall(154)
    holder.Paint = nil

    holder.label = vgui.Create("DLabel", holder)
    holder.label:SetText("Hidden Preview Color")
    holder.label:SetFont("DermaDefaultBold")
    styleOutlinedLabel(holder.label, menuColors.text)
    holder.label:SetDark(true)

    holder.mixer = vgui.Create("DColorMixer", holder)
    holder.mixer:SetPalette(false)
    holder.mixer:SetAlphaBar(true)
    holder.mixer:SetWangs(true)
    holder.mixer:SetConVarR("magic_align_preview_occluded_r")
    holder.mixer:SetConVarG("magic_align_preview_occluded_g")
    holder.mixer:SetConVarB("magic_align_preview_occluded_b")
    holder.mixer:SetConVarA("magic_align_preview_occluded_a")
    holder.mixer:SetColor(Color(
        readColorConVar("magic_align_preview_occluded_r", 18),
        readColorConVar("magic_align_preview_occluded_g", 52),
        readColorConVar("magic_align_preview_occluded_b", 70),
        readColorConVar("magic_align_preview_occluded_a", 160)
    ))

    holder.PerformLayout = function(self, w, h)
        self.label:SetPos(0, 0)
        self.label:SetSize(w, 18)

        self.mixer:SetPos(0, 22)
        self.mixer:SetSize(w, math.max(h - 22, 0))
    end

    return holder
end

local function bindForcedVisualCheckBox(checkBox, valueConVar, forceConVar)
    if not IsValid(checkBox) then return checkBox end

    checkBox.Think = function(self)
        local forced = forceConVar and getBoolConVar(forceConVar, false) or false
        local checked = forced or getBoolConVar(valueConVar, false)

        self.MagicAlignForced = forced
        self.MagicAlignVisualValue = checked

        if IsValid(self.Label) then
            styleOutlinedLabel(self.Label, menuColors.text)
            self.Label:SetMouseInputEnabled(not forced)
        end

        if IsValid(self.Button) then
            self.Button:SetMouseInputEnabled(not forced)
        end

        self:SetMouseInputEnabled(not forced)
    end

    return checkBox
end

local function createPersistedCategory(panel, categoryId, label, content)
    local category = vgui.Create("DCollapsibleCategory", panel)
    local cookieKey = "magic_align_menu_category_" .. tostring(categoryId or label or "category")

    if IsValid(content) then
        content:InvalidateLayout(true)
    end

    category:SetLabel(label)
    category:SetContents(content)
    category:SetExpanded(cookie.GetString(cookieKey, "1") ~= "0")
    panel:AddItem(category)

    category.OnToggle = function(_, expanded)
        cookie.Set(cookieKey, expanded and "1" or "0")
        if IsValid(content) then
            content:InvalidateLayout(true)
        end
        if IsValid(panel) then
            panel:InvalidateLayout(true)
        end
    end

    return category
end

local function createAnchorPercentSlider(parent, label, convar, accent)
    local slider = vgui.Create(anchorInterpolationSliderClass, parent)
    local baseNormalizeValue = slider.NormalizeValue
    slider:SetText(label)
    slider:SetMinMax(M.ANCHOR_PERCENT_MIN or 0, M.ANCHOR_PERCENT_MAX or 100)
    slider:SetDecimals(3)
    slider:SetConVar(convar)
    slider:SetInputDecimals("slider", 3)
    slider:SetInputSnap("slider", function()
        return math.max(tonumber(M.ANCHOR_PERCENT_STEP) or 1, 1)
    end)
    slider:SetInputDecimals("label", 3)
    slider:SetInputSnap("label", nil)
    slider:SetInputDecimals("text", nil)
    slider:SetInputSnap("text", nil)
    slider.NormalizeValue = function(self, value, source)
        local normalized = isfunction(baseNormalizeValue) and baseNormalizeValue(self, value, source) or tonumber(value) or 0
        if source == "text" then
            return M.ClampAnchorPercent(normalized)
        end

        return normalized
    end
    stylePanelSlider(slider, {
        labelWide = 20,
        textWide = 32,
        labelMarginRight = 1,
        textMarginLeft = 1,
        sliderMarginY = 1,
        tall = 18,
        textColor = menuColors.text
    })
    installSliderDisplayRounding(slider, 3)

    if IsValid(slider.Slider) then
        slider.Slider.Paint = function(_, w, h)
            draw.RoundedBox(2, 0, math.floor(h * 0.5) - 2, w, 4, menuColors.inputBorder)
        end

        if IsValid(slider.Slider.Knob) then
            slider.Slider.Knob.Paint = function(self, w, h)
                local knobColor = self:IsHovered() and accent or Color(accent.r, accent.g, accent.b, 220)
                draw.RoundedBox(3, 0, 0, w, h, knobColor)
            end
        end
    end

    return slider
end

local function createAnchorColumn(parent, options)
    local rowHeight = 30
    local rowGap = 6

    local column = vgui.Create("DPanel", parent)
    column.title = options.title
    column.side = options.side
    column.anchorConVar = options.anchorConVar
    column.priorityConVar = options.priorityConVar
    column.accent = options.accent
    column.accentSoft = Color(options.accent.r, options.accent.g, options.accent.b, 54)
    column.order = completeAnchorOrder(getStringConVar(column.priorityConVar, serializeAnchorOrder(M.DEFAULT_PRIORITY)))
    column.activeAnchor = string.lower(getStringConVar(column.anchorConVar, column.order[1] or ""))
    column.pointCount = pointCount(column.side)
    column.displayIndexLookup = {}
    column.rows = {}
    column.Paint = nil

    column.header = vgui.Create("DLabel", column)
    column.header:SetText(column.title)
    column.header:SetFont("DermaDefaultBold")
    styleOutlinedLabel(column.header, menuColors.text)
    column.header:SetContentAlignment(4)

    column.body = vgui.Create("DPanel", column)
    column.body.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, menuColors.anchorBody)
        surface.SetDrawColor(menuColors.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end

    function column:GetDisplayOrder()
        local display = {}

        if self.dragging and self.draggingId then
            for _, id in ipairs(self.order) do
                if id ~= self.draggingId then
                    display[#display + 1] = id
                end
            end

            table.insert(display, math.Clamp(self.placeholderIndex or 1, 1, #display + 1), self.draggingId)
            return display
        end

        for i = 1, #self.order do
            display[i] = self.order[i]
        end

        return display
    end

    function column:ComputePlaceholderIndex(centerY)
        local count = math.max(#self.order - 1, 0)
        local slot = 1

        for index = 1, count do
            local slotCenter = (index - 1) * (rowHeight + rowGap) + rowHeight * 0.5
            if centerY > slotCenter then
                slot = index + 1
            else
                break
            end
        end

        return math.Clamp(slot, 1, count + 1)
    end

    function column:LayoutRows()
        local display = self:GetDisplayOrder()
        local bodyWidth = math.max(self.body:GetWide(), 0)
        local maxY = math.max(self.body:GetTall() - rowHeight, 0)

        self.displayIndexLookup = {}

        for index, id in ipairs(display) do
            self.displayIndexLookup[id] = index
        end

        for _, id in ipairs(display) do
            local row = self.rows[id]
            if IsValid(row) then
                local index = self.displayIndexLookup[id] or 1
                local targetY = (index - 1) * (rowHeight + rowGap)

                if self.dragging and id == self.draggingId then
                    row:SetWide(math.max(bodyWidth - 4, 0))
                    row:SetPos(4, math.Clamp(self.dragY or targetY, 0, maxY))
                    row:MoveToFront()
                    row.dragging = true
                else
                    row:SetWide(bodyWidth)
                    row:SetPos(0, targetY)
                    row.dragging = false
                end
            end
        end
    end

    function column:Sync(force)
        local previousPointCount = self.lastPointCount or 0
        self.pointCount = pointCount(self.side)

        if not self.dragging then
            local priorityString = getStringConVar(self.priorityConVar, serializeAnchorOrder(M.DEFAULT_PRIORITY))
            if force or priorityString ~= self.lastPriorityString then
                self.order = completeAnchorOrder(priorityString)
                self.lastPriorityString = priorityString
            end
        end

        self.activeAnchor = string.lower(getStringConVar(self.anchorConVar, self.activeAnchor or ""))

        local bestAvailable = highestAvailableAnchor(self.order, self.pointCount)
        local activeAvailable = anchorAvailable(self.activeAnchor, self.pointCount)
        local pointCountIncreased = self.pointCount > previousPointCount
        if bestAvailable and (not activeAvailable or (pointCountIncreased and priorityIndex(self.order, bestAvailable) < priorityIndex(self.order, self.activeAnchor))) then
            self.activeAnchor = bestAvailable
            setStringConVar(self.anchorConVar, bestAvailable)
        end

        self.lastPointCount = self.pointCount
        self:LayoutRows()
    end

    function column:BeginInteraction(row)
        self.pressRow = row
        self.draggingId = row.anchorId
        self.dragging = false
        self.placeholderIndex = self.displayIndexLookup[row.anchorId] or 1

        local _, localY = self.body:ScreenToLocal(gui.MousePos())
        self.pressStartY = localY
        self.pressOffsetY = localY - row:GetY()
        self.dragY = row:GetY()

        row:MouseCapture(true)
    end

    function column:EndInteraction(cancelled)
        local row = self.pressRow
        if IsValid(row) then
            row:MouseCapture(false)
        end

        if not cancelled and IsValid(row) then
            if self.dragging and self.draggingId then
                self.order = self:GetDisplayOrder()
                self.lastPriorityString = serializeAnchorOrder(self.order)
                setStringConVar(self.priorityConVar, self.lastPriorityString)
            elseif anchorAvailable(row.anchorId, self.pointCount) then
                self.activeAnchor = row.anchorId
                setStringConVar(self.anchorConVar, row.anchorId)
            end
        end

        self.pressRow = nil
        self.dragging = false
        self.draggingId = nil
        self.placeholderIndex = nil
        self.pressStartY = nil
        self.pressOffsetY = nil
        self.dragY = nil

        self:Sync(true)
    end

    column.Think = function(self)
        self:Sync(false)

        if not self.pressRow then
            return
        end

        if not input.IsMouseDown(MOUSE_LEFT) then
            self:EndInteraction(false)
            return
        end

        local _, localY = self.body:ScreenToLocal(gui.MousePos())
        if not self.dragging and math.abs(localY - (self.pressStartY or localY)) > 4 then
            self.dragging = true
        end

        if self.dragging and IsValid(self.pressRow) then
            local maxY = math.max(self.body:GetTall() - self.pressRow:GetTall(), 0)
            self.dragY = math.Clamp(localY - (self.pressOffsetY or 0), 0, maxY)
            self.placeholderIndex = self:ComputePlaceholderIndex(self.dragY + self.pressRow:GetTall() * 0.5)
            self:LayoutRows()
        end
    end

    column.PerformLayout = function(self, w, h)
        self.header:SetPos(0, 0)
        self.header:SetSize(w, 18)

        self.body:SetPos(0, 24)
        self.body:SetSize(w, math.max(h - 24, 0))

        self:LayoutRows()
    end

    for _, anchor in ipairs(M.ANCHORS) do
        local row = vgui.Create("DPanel", column.body)
        row.anchorId = anchor.id
        row.column = column
        row:SetTall(rowHeight)
        row:SetMouseInputEnabled(true)
        row:SetCursor("sizens")

        row.Think = function(self)
            self:SetCursor(self.dragging and "sizeall" or "sizens")
        end

        row.Paint = function(self, w, h)
            local available = anchorAvailable(self.anchorId, self.column.pointCount)
            local active = self.column.activeAnchor == self.anchorId
            local bg = menuColors.anchorRow
            local textColor = menuColors.text
            local badge = ("#%d"):format(self.column.displayIndexLookup[self.anchorId] or 0)
            local badgeColor = menuColors.textMuted

            if not available then
                bg = active and menuColors.anchorRowActiveDisabled or menuColors.anchorRowDisabled
                textColor = menuColors.text
                badge = "N/A"
            elseif self:IsHovered() and not self.dragging then
                bg = menuColors.anchorRowHover
            end

            if not available and self:IsHovered() and not self.dragging then
                bg = menuColors.anchorRowDisabledHover
            end

            if active and available then
                bg = self.column.accentSoft
                badge = "ACTIVE"
                badgeColor = self.column.accent
            elseif self.dragging then
                badgeColor = self.column.accent
            end

            draw.RoundedBox(6, 0, 0, w, h, bg)
            surface.SetDrawColor(menuColors.border)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            if active then
                draw.RoundedBox(6, 0, 0, 5, h, self.column.accent)
            end

            if self.dragging then
                surface.SetDrawColor(self.column.accent)
                surface.DrawOutlinedRect(0, 0, w, h, 2)
            end

            draw.SimpleText(anchorLabel(self.anchorId), "DermaDefaultBold", 12, h * 0.5, textColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(badge, "DermaDefault", w - 12, h * 0.5, badgeColor, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end

        row.OnMousePressed = function(self, code)
            if code ~= MOUSE_LEFT then return end
            self.column:BeginInteraction(self)
        end

        column.rows[anchor.id] = row
    end

    column:InvalidateLayout(true)
    column:Sync(true)

    return column
end

local function createInterpolationColumn(parent, options)
    local bodyPad = 10
    local rowTall = 22
    local rowGap = 4
    local resetButtonWidth = 52

    local column = vgui.Create("DPanel", parent)
    column.Paint = nil
    column.accent = options.accent
    column.percentSliders = {}

    column.header = vgui.Create("DLabel", column)
    column.header:SetText(options.title)
    column.header:SetFont("DermaDefaultBold")
    styleOutlinedLabel(column.header, menuColors.text)
    column.header:SetContentAlignment(4)

    column.resetButton = vgui.Create("DButton", column)
    styleFlatButton(column.resetButton, "Reset")
    column.resetButton:SetTooltip("Reset this column to 50% on all axes.")
    column.resetButton.DoClick = function()
        resetInterpolationPercentages(options.side)
    end

    column.body = vgui.Create("DPanel", column)
    column.body.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, menuColors.panelSoft)
        surface.SetDrawColor(menuColors.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
        draw.RoundedBox(8, 0, 0, 4, h, column.accent)
    end

    for _, anchorId in ipairs(M.ANCHOR_PERCENT_KEYS or {}) do
        column.percentSliders[#column.percentSliders + 1] = createAnchorPercentSlider(
            column.body,
            anchorPercentLabels[anchorId] or anchorLabel(anchorId),
            ("magic_align_%s_%s_pct"):format(options.side, anchorId),
            column.accent
        )
    end

    column.body.PerformLayout = function(self, w, h)
        local y = bodyPad
        local innerWidth = math.max(w - bodyPad * 2, 0)

        for _, slider in ipairs(column.percentSliders) do
            slider:SetPos(bodyPad, y)
            slider:SetSize(innerWidth, rowTall)
            y = y + rowTall + rowGap
        end
    end

    column.PerformLayout = function(self, w, h)
        self.header:SetPos(0, 0)
        self.header:SetSize(math.max(w - resetButtonWidth - 6, 0), 18)

        self.resetButton:SetPos(math.max(w - resetButtonWidth, 0), 0)
        self.resetButton:SetSize(math.min(resetButtonWidth, w), 18)

        self.body:SetPos(0, 24)
        self.body:SetSize(w, math.max(h - 24, 0))
    end

    column:InvalidateLayout(true)

    return column
end

local function createAnchorBoard(parent)
    local board = vgui.Create("DPanel", parent)
    local rowHeight = 30
    local rowGap = 6
    local count = #M.ANCHORS

    board:SetTall(24 + count * rowHeight + math.max(count - 1, 0) * rowGap)
    board.Paint = nil

    local fromColumn = createAnchorColumn(board, {
        title = "Move From",
        side = "from",
        anchorConVar = "magic_align_from_anchor",
        priorityConVar = "magic_align_from_priority",
        accent = Color(240, 167, 68)
    })

    local toColumn = createAnchorColumn(board, {
        title = "Move To",
        side = "to",
        anchorConVar = "magic_align_to_anchor",
        priorityConVar = "magic_align_to_priority",
        accent = Color(82, 158, 238)
    })

    board.PerformLayout = function(self, w, h)
        local gap = 6
        local columnWidth = math.floor((w - gap) * 0.5)
        fromColumn:SetPos(0, 0)
        fromColumn:SetSize(columnWidth, h)
        toColumn:SetPos(columnWidth + gap, 0)
        toColumn:SetSize(w - columnWidth - gap, h)
    end

    return board
end

local function createInterpolationBoard(parent)
    local board = vgui.Create("DPanel", parent)
    board:SetTall(110)
    board.Paint = nil

    local fromColumn = createInterpolationColumn(board, {
        title = "Move From",
        side = "from",
        accent = Color(240, 167, 68)
    })

    local toColumn = createInterpolationColumn(board, {
        title = "Move To",
        side = "to",
        accent = Color(82, 158, 238)
    })

    board.PerformLayout = function(self, w, h)
        local gap = 6
        local columnWidth = math.floor((w - gap) * 0.5)
        fromColumn:SetPos(0, 0)
        fromColumn:SetSize(columnWidth, h)
        toColumn:SetPos(columnWidth + gap, 0)
        toColumn:SetSize(w - columnWidth - gap, h)
    end

    return board
end

function TOOL.BuildCPanel(panel)
    applyPersistedMenuConVars()
    registerSessionTabCallbacks()

    local anchorCategoryContent = createStackPanel(panel, {
        spacing = 8
    })
    anchorCategoryContent:AddItem(createHelpLabel(
        anchorCategoryContent,
        "Drag anchors to change priority. Left click a usable anchor to make it active."
    ), 8)
    anchorCategoryContent:AddItem(createAnchorBoard(anchorCategoryContent), 0)
    createPersistedCategory(panel, "anchor_priority", "Anchor Priorities", anchorCategoryContent)

    local interpolationCategoryContent = createStackPanel(panel, {
        spacing = 8
    })
    interpolationCategoryContent:AddItem(createHelpLabel(
        interpolationCategoryContent,
        "Adjust the midpoint positions on the axes."
    ), 8)
    interpolationCategoryContent:AddItem(createInterpolationBoard(interpolationCategoryContent), 0)
    createPersistedCategory(panel, "anchor_interpolation", "Anchor Interpolation", interpolationCategoryContent)

    local sheet = vgui.Create("DPropertySheet")
    sheet:SetTall(278)
    stylePropertySheet(sheet)

    M.ClientSheet = sheet
    M.ClientTabs = {}

    for _, space in ipairs(M.SPACES) do
        local holder = vgui.Create("DPanel", sheet)
        holder.Paint = function(self, w, h)
            draw.RoundedBox(8, 0, 0, w, h, menuColors.panelSoft)
            surface.SetDrawColor(menuColors.border)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
        end

        holder.rows = {}

        for _, row in ipairs(panelSliderRows) do
            local slider = vgui.Create(magicSliderClass, holder)
            local isRotationRow = row.key == "pitch" or row.key == "yaw" or row.key == "roll"
            slider:SetText(row.label)
            slider:SetMinMax(row.min, row.max)
            slider:SetDecimals(row.decimals)
            slider:SetConVar("magic_align_" .. space .. "_" .. row.key)
            slider:SetInputDecimals("slider", row.decimals)
            slider:SetInputSnap("slider", function()
                if isRotationRow then
                    local _, step = currentRotationSnapStep()
                    return step
                end

                return currentTranslationSnapStep()
            end)
            slider:SetInputDecimals("label", 3)
            slider:SetInputSnap("label", 0.001)
            slider:SetInputDecimals("text", nil)
            slider:SetInputSnap("text", nil)
            stylePanelSlider(slider, {
                labelWide = 46,
                textWide = 56,
                tall = 30
            })

            holder.rows[#holder.rows + 1] = slider
        end

        local resetPos = vgui.Create("DButton", holder)
        styleFlatButton(resetPos, "Reset Pos")
        resetPos.DoClick = function()
            setValue(space, "px", 0)
            setValue(space, "py", 0)
            setValue(space, "pz", 0)
        end

        local resetRot = vgui.Create("DButton", holder)
        styleFlatButton(resetRot, "Reset Rot")
        resetRot.DoClick = function()
            setValue(space, "pitch", 0)
            setValue(space, "yaw", 0)
            setValue(space, "roll", 0)
        end

        holder.PerformLayout = function(self, w, h)
            local pad = 12
            local y = pad
            local innerWidth = math.max(w - pad * 2, 0)

            for _, slider in ipairs(self.rows) do
                slider:SetPos(pad, y)
                slider:SetSize(innerWidth, 30)
                y = y + 32
            end

            local buttonWidth = math.floor((innerWidth - 8) * 0.5)
            resetPos:SetPos(pad, y + 6)
            resetPos:SetSize(buttonWidth, 24)
            resetRot:SetPos(pad + buttonWidth + 8, y + 6)
            resetRot:SetSize(innerWidth - buttonWidth - 8, 24)
        end

        local tab = sheet:AddSheet(spaceLabels[space] or space, holder)
        stylePropertyTab(tab.Tab)

        M.ClientTabs[space] = tab.Tab

        local click = tab.Tab.DoClick
        tab.Tab.DoClick = function(btn, ...)
            RunConsoleCommand("magic_align_space", space)
            return click(btn, ...)
        end
    end

    panel:AddItem(sheet)
    updateSessionTabTitles()

    local currentSpace = getStringConVar("magic_align_space", "points")
    local activeTab = M.ClientTabs[currentSpace]
    if IsValid(activeTab) then
        sheet:SetActiveTab(activeTab)
    end

    local snapCategoryContent = createStackPanel(panel, {
        spacing = 6
    })

    local function setSnapTitleText(label, text)
        if not IsValid(label) then
            return
        end

        text = tostring(text or "")
        if label:GetText() == text then
            return
        end

        label:SetText(text)
        label:SetTall(18)
        label:InvalidateLayout(true)

        local parent = label:GetParent()
        if IsValid(parent) then
            parent:InvalidateLayout(true)
        end
    end

    local rotationSnapTitle = vgui.Create("DLabel", snapCategoryContent)
    rotationSnapTitle:SetText("")
    rotationSnapTitle:SetFont("DermaDefaultBold")
    styleOutlinedLabel(rotationSnapTitle, menuColors.text)
    rotationSnapTitle:SetDark(true)
    rotationSnapTitle:SetTall(18)
    snapCategoryContent:AddItem(rotationSnapTitle, 0)
    
    local rotationSnapSlider = vgui.Create("DNumSlider", snapCategoryContent)
    rotationSnapSlider:SetText("Preset")
    rotationSnapSlider:SetMinMax(1, #rotationSnapDivisors)
    rotationSnapSlider:SetDecimals(0)
    stylePanelSlider(rotationSnapSlider, {
        labelWide = 44,
        textWide = 56,
        tall = 30,
        textColor = menuColors.text,
        outlineLabel = true
    })
    installSliderDisplayRounding(rotationSnapSlider, 0)
    snapCategoryContent:AddItem(rotationSnapSlider, 8)

    local updatingRotationSnap = false
    local function updateRotationSnapUi(value)
        local index, divisions, step = rotationSnapInfo(value)

        setSnapTitleText(rotationSnapTitle, ("Rotation Snap: %d deg steps (360/%d)"):format(step, divisions))

        if not updatingRotationSnap and math.abs((tonumber(rotationSnapSlider:GetValue()) or index) - index) > 1e-4 then
            updatingRotationSnap = true
            rotationSnapSlider:SetValue(index)
            updatingRotationSnap = false
        end
    end

    rotationSnapSlider.OnValueChanged = function(self, value)
        if updatingRotationSnap then return end
        local index = clampRotationSnapIndex(value)
        if math.abs((tonumber(value) or index) - index) > 1e-4 then
            updatingRotationSnap = true
            self:SetValue(index)
            updatingRotationSnap = false
        end
        setRotationSnapIndex(index)
        updateRotationSnapUi(index)
    end

    local initialRotationSnap = currentRotationSnapIndex()
    setRotationSnapIndex(initialRotationSnap)
    rotationSnapSlider:SetValue(initialRotationSnap)
    updateRotationSnapUi(initialRotationSnap)

    local translationSnapTitle = vgui.Create("DLabel", snapCategoryContent)
    translationSnapTitle:SetText("")
    translationSnapTitle:SetFont("DermaDefaultBold")
    styleOutlinedLabel(translationSnapTitle, menuColors.text)
    translationSnapTitle:SetDark(true)
    translationSnapTitle:SetTall(18)
    snapCategoryContent:AddItem(translationSnapTitle, 0)

    local translationSnapSlider = vgui.Create(magicSliderClass, snapCategoryContent)
    translationSnapSlider:SetText("Step")
    translationSnapSlider:SetMinMax(0, 128)
    translationSnapSlider:SetDecimals(0)
    translationSnapSlider:SetConVar("magic_align_translation_snap")
    translationSnapSlider:SetInputDecimals("slider", 0)
    translationSnapSlider:SetInputSnap("slider", 1)
    translationSnapSlider:SetInputDecimals("label", 3)
    translationSnapSlider:SetInputSnap("label", 0.001)
    translationSnapSlider:SetInputDecimals("text", nil)
    translationSnapSlider:SetInputSnap("text", nil)
    stylePanelSlider(translationSnapSlider, {
        labelWide = 44,
        textWide = 56,
        tall = 30,
        textColor = menuColors.text,
        outlineLabel = true
    })
    snapCategoryContent:AddItem(translationSnapSlider, 8)

    local updatingTranslationSnap = false
    local function updateTranslationSnapUi(value)
        local step = value or 0 --clampTranslationSnapStep(value)
        if step <= 0 then
            setSnapTitleText(translationSnapTitle, "Translation Snap: Off")
        else
            setSnapTitleText(translationSnapTitle, ("Translation Snap: %s units"):format(formatDisplayRoundedValue(step)))
        end

        if not updatingTranslationSnap and math.abs((tonumber(translationSnapSlider:GetValue()) or step) - step) > 1e-4 then
            updatingTranslationSnap = true
            --translationSnapSlider:SetValue(step) --prevents slider and label drag
            updatingTranslationSnap = false
        end
    end

    translationSnapSlider.OnValueChanged = function(_, value)
        if updatingTranslationSnap then return end
        updateTranslationSnapUi(value)
    end

    local initialTranslationSnap = currentTranslationSnapStep()
    setTranslationSnapStep(initialTranslationSnap)
    translationSnapSlider:SyncFromConVar(true)
    updateTranslationSnapUi(initialTranslationSnap)

    local traceSnapTitle = vgui.Create("DLabel", snapCategoryContent)
    traceSnapTitle:SetText("")
    traceSnapTitle:SetFont("DermaDefaultBold")
    styleOutlinedLabel(traceSnapTitle, menuColors.text)
    traceSnapTitle:SetDark(true)
    traceSnapTitle:SetTall(18)
    snapCategoryContent:AddItem(traceSnapTitle, 0)

    local traceSnapSlider = vgui.Create(magicSliderClass, snapCategoryContent)
    traceSnapSlider:SetText("Radius")
    traceSnapSlider:SetMinMax(0, 32)
    traceSnapSlider:SetDecimals(0)
    traceSnapSlider:SetConVar("magic_align_trace_snap_length")
    traceSnapSlider:SetInputDecimals("slider", 0)
    traceSnapSlider:SetInputSnap("slider", 1)
    traceSnapSlider:SetInputDecimals("label", 3)
    traceSnapSlider:SetInputSnap("label", 0.001)
    traceSnapSlider:SetInputDecimals("text", nil)
    traceSnapSlider:SetInputSnap("text", nil)
    stylePanelSlider(traceSnapSlider, {
        labelWide = 44,
        textWide = 56,
        tall = 30,
        textColor = menuColors.text,
        outlineLabel = true
    })
    snapCategoryContent:AddItem(traceSnapSlider, 4)

    local traceSnapHelp = createHelpLabel(
        snapCategoryContent,
        "Gizmo surface snapping search radius.",
        nil,
        true
    )
    snapCategoryContent:AddItem(traceSnapHelp, 0)

    local updatingTraceSnap = false
    local function updateTraceSnapUi(value)
        local length = value or 0 --clampTraceSnapLength(value)
        if length <= 0 then
            setSnapTitleText(traceSnapTitle, "Trace Snap: Off")
        else
            setSnapTitleText(traceSnapTitle, ("Trace Snap: %s units"):format(formatDisplayRoundedValue(length)))
        end

        if not updatingTraceSnap and math.abs((tonumber(traceSnapSlider:GetValue()) or length) - length) > 1e-4 then
            updatingTraceSnap = true
            --traceSnapSlider:SetValue(length) --prevents slider and label drag
            updatingTraceSnap = false
        end
    end

    traceSnapSlider.OnValueChanged = function(_, value)
        if updatingTraceSnap then return end
        updateTraceSnapUi(value)
    end

    local initialTraceSnap = currentTraceSnapLength()
    setTraceSnapLength(initialTraceSnap)
    traceSnapSlider:SyncFromConVar(true)
    updateTraceSnapUi(initialTraceSnap)

    snapCategoryContent.Think = function()
        if not rotationSnapSlider:IsEditing() then
            updateRotationSnapUi(currentRotationSnapIndex())
        end
        updateTranslationSnapUi(currentTranslationSnapStep())
        updateTraceSnapUi(currentTraceSnapLength())
    end

    createPersistedCategory(panel, "snap_settings", "Snap Settings", snapCategoryContent)

    local gridCategoryContent = createStackPanel(panel, {
        spacing = 6
    })
    gridCategoryContent:AddItem(createHelpLabel(
        gridCategoryContent,
        "Grid A/B are the standard divisions per face axis. Grid A/B Min are used as fallback divisions when the spacing between parallel lines on that axis drops below Min Length.",
        nil,
        true
    ), 8)
    addStyledSlider(gridCategoryContent, "Grid A Std", "magic_align_grid_a", 2, 24, 0, { labelWide = 72, textWide = 56, tall = 30 })
    addStyledSlider(gridCategoryContent, "Grid A Min", "magic_align_grid_a_min", 2, 24, 0, { labelWide = 72, textWide = 56, tall = 30 })
    addStyledCheckBox(gridCategoryContent, "Use Grid B", "magic_align_grid_b_enable")
    addStyledSlider(gridCategoryContent, "Grid B Std", "magic_align_grid_b", 2, 24, 0, { labelWide = 72, textWide = 56, tall = 30 })
    addStyledSlider(gridCategoryContent, "Grid B Min", "magic_align_grid_b_min", 2, 24, 0, { labelWide = 72, textWide = 56, tall = 30 })
    addStyledSlider(gridCategoryContent, "Min Len", "magic_align_min_length", 0, 12, 0, { labelWide = 72, textWide = 56, tall = 30 })
    addStyledSlider(gridCategoryContent, "Grid Alpha", "magic_align_grid_alpha", 0, 255, 0, { labelWide = 72, textWide = 56, tall = 30 })
    gridCategoryContent:AddItem(createInlineCheckBoxRow(gridCategoryContent, {
        { label = "Grid Labels as Percent", convar = "magic_align_grid_label_percent" },
        { label = "Reduce Fractions", convar = "magic_align_grid_label_reduce_fraction" }
    }))
    createPersistedCategory(panel, "grid_settings", "Grid A/B", gridCategoryContent)

    local constraintsCategoryContent = createStackPanel(panel, {
        spacing = 4
    })
    addStyledCheckBox(constraintsCategoryContent, "Weld On Commit", "magic_align_weld")
    bindForcedVisualCheckBox(
        addStyledCheckBox(constraintsCategoryContent, "NoCollide On Commit", "magic_align_nocollide"),
        "magic_align_nocollide",
        "magic_align_weld"
    )

    local parentHelp = createHelpLabel(
        constraintsCategoryContent,
        "Parenting removes prop collision. With Weld, stationary props may still support players, but collisions are unreliable.",
        nil,
        true
    )
    constraintsCategoryContent:AddItem(parentHelp, 0)
    addStyledCheckBox(constraintsCategoryContent, "Parent On Commit", "magic_align_parent")

    createPersistedCategory(panel, "constraints", "Constraints", constraintsCategoryContent)

    local performanceCategoryContent = createStackPanel(panel, {
        spacing = 6
    })

    local ringQualityTitle = vgui.Create("DLabel", performanceCategoryContent)
    ringQualityTitle:SetText("")
    ringQualityTitle:SetFont("DermaDefaultBold")
    styleOutlinedLabel(ringQualityTitle, menuColors.text)
    ringQualityTitle:SetDark(true)
    ringQualityTitle:SetTall(18)
    performanceCategoryContent:AddItem(ringQualityTitle, 0)

    local ringQualitySlider = vgui.Create("DNumSlider", performanceCategoryContent)
    ringQualitySlider:SetText("Preset")
    ringQualitySlider:SetMinMax(1, #ringQualityPresets)
    ringQualitySlider:SetDecimals(0)
    stylePanelSlider(ringQualitySlider, {
        labelWide = 44,
        textWide = 56,
        tall = 30,
        textColor = menuColors.text,
        outlineLabel = true
    })
    installSliderDisplayRounding(ringQualitySlider, 0)
    performanceCategoryContent:AddItem(ringQualitySlider, 8)

    local updatingRingQuality = false
    local function updateRingQualityUi(value)
        local index, preset = ringQualityInfo(value)
        local text = preset and preset.realtime
            and ("Quality: Expensive %s. Costs more CPU."):format(
                preset.label
            )
            or ("Quality: Cheap %s. Costs more VRAM."):format(
                preset.label
            )

        setSnapTitleText(ringQualityTitle, text)

        if not updatingRingQuality and math.abs((tonumber(ringQualitySlider:GetValue()) or index) - index) > 1e-4 then
            updatingRingQuality = true
            ringQualitySlider:SetValue(index)
            updatingRingQuality = false
        end
    end

    ringQualitySlider.OnValueChanged = function(self, value)
        if updatingRingQuality then return end
        local index = clampRingQualityIndex(value)
        if math.abs((tonumber(value) or index) - index) > 1e-4 then
            updatingRingQuality = true
            self:SetValue(index)
            updatingRingQuality = false
        end
        setRingQualityIndex(index)
        updateRingQualityUi(index)
    end

    local initialRingQuality = currentRingQualityIndex()
    setRingQualityIndex(initialRingQuality)
    ringQualitySlider:SetValue(initialRingQuality)
    updateRingQualityUi(initialRingQuality)

    addStyledCheckBox(performanceCategoryContent, "Show Hidden Preview", "magic_align_preview_occluded")
    performanceCategoryContent:AddItem(createPreviewOccludedColorPicker(performanceCategoryContent), 8)

    performanceCategoryContent.Think = function()
        if not ringQualitySlider:IsEditing() then
            updateRingQualityUi(currentRingQualityIndex())
        end
    end

    createPersistedCategory(panel, "performance_settings", "Performance Settings", performanceCategoryContent)

    local miscCategoryContent = createStackPanel(panel, {
        spacing = 6
    })

    local displayRoundingLabel = createHelpLabel(miscCategoryContent, "", nil, true)
    miscCategoryContent:AddItem(displayRoundingLabel, 8)

    local displayRoundingSlider = addStyledSlider(
        miscCategoryContent,
        "Menu Display Rounding",
        "magic_align_display_rounding",
        0,
        11,
        0,
        { labelWide = 132, textWide = 56, tall = 30 }
    )

    local function currentDisplayRoundingSetting()
        return M.NormalizeRoundingSetting(
            getStringConVar("magic_align_display_rounding", M.DEFAULT_DISPLAY_ROUNDING),
            M.DEFAULT_DISPLAY_ROUNDING
        )
    end

    local function updateDisplayRoundingUi(value)
        local setting = M.NormalizeRoundingSetting(value, M.DEFAULT_DISPLAY_ROUNDING)
        local text = ("Menu Display Rounding: %s. Menu numbers only; 0-10 decimal places, 11 = Off."):format(
            M.DescribeRoundingSetting(setting, M.DEFAULT_DISPLAY_ROUNDING)
        )

        if displayRoundingLabel:GetText() == text then
            return
        end

        displayRoundingLabel:SetText(text)
        displayRoundingLabel:InvalidateLayout(true)
        miscCategoryContent:InvalidateLayout(true)
    end

    displayRoundingSlider.OnValueChanged = function(_, value)
        updateDisplayRoundingUi(value)
    end

    updateDisplayRoundingUi(currentDisplayRoundingSetting())

    miscCategoryContent.Think = function()
        updateDisplayRoundingUi(currentDisplayRoundingSetting())
    end

    addStyledCheckBox(miscCategoryContent, "Allow World as Target", "magic_align_world_target")
    addStyledCheckBox(miscCategoryContent, "Disable SmartSnap While Active", "magic_align_disable_smartsnap_active")
    addStyledCheckBox(miscCategoryContent, "Highlight Magic Align in Context Menu", "magic_align_highlight_context_menu")
    createPersistedCategory(panel, "misc_settings", "Misc Settings", miscCategoryContent)
    panel:AddItem(createMenuFooter(panel))

end
