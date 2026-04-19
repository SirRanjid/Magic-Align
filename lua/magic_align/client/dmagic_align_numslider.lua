MAGIC_ALIGN = MAGIC_ALIGN or include("autorun/magic_align.lua")

local M = MAGIC_ALIGN
local MathParser = M.MathParser or include("magic_align/client/math_parser.lua")
local FormulaManager = M.FormulaManager or include("magic_align/client/formula_manager.lua")

M.MathParser = MathParser
M.FormulaManager = FormulaManager

local PANEL = {}

AccessorFunc(PANEL, "m_fDefaultValue", "DefaultValue")
AccessorFunc(PANEL, "m_fnExpressionContextProvider", "ExpressionContextProvider")

local EDITOR_COOKIE_SHOW_NA = "magic_align_editor_show_na"
local EDITOR_COOKIE_SHOW_WORLD = "magic_align_editor_show_world"
local EDITOR_COOKIE_SHOW_POINT_DISTANCES = "magic_align_editor_show_point_distances"
local EDITOR_COOKIE_SHOW_POINT_ANGLES = "magic_align_editor_show_point_angles"
local EDITOR_TOOLTIP = "Double-click the text field to open the editor."
local DOUBLE_CLICK_WINDOW = 0.28
local EDITOR_REFRESH_INTERVAL = 0.1
local EDITOR_ZPOS = 128
local TEXTAREA_EXPAND_EXTRA = 32
local TEXTAREA_SCREEN_MARGIN = 12
local TEXTAREA_FLOAT_ZPOS = 32766
local DOCK_NONE = NODOCK or 0

local theme = {
    text = Color(18, 18, 18),
    textMuted = Color(126, 126, 126),
    textInvalid = Color(176, 28, 28),
    input = Color(233, 244, 246),
    inputFocus = Color(242, 251, 252),
    inputFormula = Color(221, 240, 244),
    inputInvalid = Color(252, 232, 232),
    inputBorder = Color(88, 148, 156),
    inputBorderInvalid = Color(188, 64, 64),
    track = Color(120, 166, 172),
    trackDisabled = Color(176, 182, 184),
    knob = Color(68, 140, 148),
    knobHover = Color(55, 120, 127),
    knobDisabled = Color(171, 176, 178),
    knobBorder = Color(35, 74, 79),
    knobBorderDisabled = Color(126, 130, 132)
}

local editorFontsReady = false

local function cloneColor(color, alpha)
    color = color or color_white
    return Color(color.r or 255, color.g or 255, color.b or 255, alpha or color.a or 255)
end

local function getEditorPalette()
    local client = M.Client or {}
    local menuColors = client.menuColors or {}
    local colors = client.colors or {}
    local accentSource = colors.preview or menuColors.tabActiveLine or theme.inputBorder

    return {
        bg = cloneColor(menuColors.panelSoft or Color(243, 243, 243)),
        shell = cloneColor(menuColors.panel or Color(232, 232, 232)),
        card = cloneColor(menuColors.inputFocus or Color(255, 255, 255)),
        cardSoft = cloneColor(menuColors.input or Color(247, 247, 247)),
        border = cloneColor(menuColors.border or Color(138, 138, 138)),
        inputBorder = cloneColor(menuColors.inputBorder or Color(124, 124, 124)),
        text = cloneColor(menuColors.text or theme.text),
        textMuted = cloneColor(menuColors.textMuted or theme.textMuted),
        accent = cloneColor(accentSource, 255),
        accentSoft = cloneColor(accentSource, 26),
        sheen = Color(255, 255, 255, 48)
    }
end

local function ensureEditorFonts()
    if editorFontsReady then
        return
    end

    surface.CreateFont("MagicAlignEditorTitle", {
        font = "Roboto",
        size = 18,
        weight = 700,
        antialias = true,
        extended = true
    })

    surface.CreateFont("MagicAlignEditorBody", {
        font = "Roboto",
        size = 14,
        weight = 500,
        antialias = true,
        extended = true
    })

    surface.CreateFont("MagicAlignEditorCaption", {
        font = "Roboto",
        size = 12,
        weight = 700,
        antialias = true,
        extended = true
    })

    surface.CreateFont("MagicAlignEditorClose", {
        font = "Roboto",
        size = 14,
        weight = 900,
        antialias = true,
        extended = true
    })

    editorFontsReady = true
end

local function isPanelDescendant(panel, parent)
    while IsValid(panel) do
        if panel == parent then
            return true
        end

        panel = panel:GetParent()
    end

    return false
end

local function resolveTextAreaFloatParent(panel)
    if IsValid(g_ContextMenu) and isPanelDescendant(panel, g_ContextMenu) then
        return g_ContextMenu
    end

    if IsValid(g_SpawnMenu) and isPanelDescendant(panel, g_SpawnMenu) then
        return g_SpawnMenu
    end

    local world = vgui.GetWorldPanel()
    local current = panel
    local top = panel

    while IsValid(current) do
        local parent = current:GetParent()
        if not IsValid(parent) or parent == world then
            break
        end

        top = parent
        current = parent
    end

    return top
end

local function createEditorCard(parent, tone)
    local card = vgui.Create("DPanel", parent)
    card.MagicAlignEditorTone = tone or "card"
    card.Paint = function(self, w, h)
        local palette = getEditorPalette()
        local bg = self.MagicAlignEditorTone == "soft" and palette.cardSoft or palette.card

        draw.RoundedBox(10, 0, 0, w, h, bg)
        surface.SetDrawColor(palette.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
        surface.SetDrawColor(palette.accent)
        surface.DrawRect(1, 1, math.max(w - 2, 0), 3)
    end

    return card
end

local function paintEditorEntry(textarea, w, h, invalid)
    local palette = getEditorPalette()
    local background = textarea:HasFocus() and palette.card or palette.cardSoft
    local border = invalid and theme.inputBorderInvalid or palette.inputBorder
    local textColor = invalid and theme.textInvalid or palette.text

    draw.RoundedBox(8, 0, 0, w, h, background)
    surface.SetDrawColor(border)
    surface.DrawOutlinedRect(0, 0, w, h, 1)

    if textarea:HasFocus() and not invalid then
        surface.SetDrawColor(palette.accent)
        surface.DrawRect(1, math.max(h - 3, 1), math.max(w - 2, 0), 3)
    end

    textarea:DrawTextEntryText(textColor, textColor, textColor)
end

local function styleEditorCheckBox(checkBox)
    ensureEditorFonts()

    checkBox:SetFont("MagicAlignEditorBody")
    checkBox:SetTextColor(getEditorPalette().text)
    checkBox:SizeToContents()

    if IsValid(checkBox.Label) then
        checkBox.Label:SetFont("MagicAlignEditorBody")
        checkBox.Label:SetTextColor(getEditorPalette().text)
    end

    if IsValid(checkBox.Button) then
        checkBox.Button.Paint = function(button, w, h)
            local palette = getEditorPalette()
            local bg = button:IsHovered() and palette.card or palette.cardSoft
            local checked = button.GetChecked and button:GetChecked() or false

            draw.RoundedBox(6, 0, 0, w, h, bg)
            surface.SetDrawColor(palette.inputBorder)
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            if checked then
                surface.SetDrawColor(palette.accent)
                for offset = 0, 1 do
                    surface.DrawLine(math.floor(w * 0.2), math.floor(h * 0.58) + offset, math.floor(w * 0.44), math.floor(h * 0.8) + offset)
                    surface.DrawLine(math.floor(w * 0.44), math.floor(h * 0.8) + offset, math.floor(w * 0.82), math.floor(h * 0.22) + offset)
                end
            end
        end
    end
end

local function styleEditorScrollBar(vbar)
    if not IsValid(vbar) then
        return
    end

    vbar:SetWide(12)
    vbar.Paint = nil

    if IsValid(vbar.btnUp) then
        vbar.btnUp:SetTall(0)
        vbar.btnUp.Paint = nil
    end

    if IsValid(vbar.btnDown) then
        vbar.btnDown:SetTall(0)
        vbar.btnDown.Paint = nil
    end

    if IsValid(vbar.btnGrip) then
        vbar.btnGrip.Paint = function(button, w, h)
            local palette = getEditorPalette()
            local bg = button:IsHovered() and palette.inputBorder or palette.border

            draw.RoundedBox(6, 2, 0, math.max(w - 4, 0), h, bg)
        end
    end
end

local function measureTextWidth(font, text)
    surface.SetFont(font or "DermaDefault")
    return select(1, surface.GetTextSize(tostring(text or "")))
end

local function registerFloatingTextOwner(owner)
    M.ActiveFloatingTextOwners = M.ActiveFloatingTextOwners or {}
    M.ActiveFloatingTextOwners[owner] = true
end

local function unregisterFloatingTextOwner(owner)
    local owners = M.ActiveFloatingTextOwners
    if not owners then
        return
    end

    owners[owner] = nil
end

local function collapseAllFloatingTextOwners()
    local owners = M.ActiveFloatingTextOwners
    if not owners then
        return
    end

    for owner in pairs(owners) do
        if IsValid(owner) and isfunction(owner.CollapseTextArea) then
            owner:CollapseTextArea()
        else
            owners[owner] = nil
        end
    end
end

if hook and hook.Add then
    hook.Remove("OnContextMenuClose", "MagicAlignCollapseFloatingTextFields")
    hook.Add("OnContextMenuClose", "MagicAlignCollapseFloatingTextFields", collapseAllFloatingTextOwners)
    hook.Remove("OnSpawnMenuClose", "MagicAlignCollapseFloatingTextFields")
    hook.Add("OnSpawnMenuClose", "MagicAlignCollapseFloatingTextFields", collapseAllFloatingTextOwners)
end

local function nearlyEqual(a, b)
    return math.abs((tonumber(a) or 0) - (tonumber(b) or 0)) <= M.CONVAR_ROUNDTRIP_EPSILON
end

local function isFormulaText(text)
    return string.Trim(tostring(text or "")):sub(1, 1) == "="
end

local function isTransitionalExpressionText(text)
    text = string.Trim(tostring(text or ""))
    if text == "" or text == "=" then
        return true
    end

    if text:sub(1, 1) == "=" then
        text = string.Trim(text:sub(2))
    end

    return text == ""
        or text == "+"
        or text == "-"
        or text == "."
        or text == "+."
        or text == "-."
end

local function sanitizeDecimals(decimals)
    if decimals == nil then return nil end
    decimals = tonumber(decimals) or 0
    return math.max(math.floor(decimals), 0)
end

local function formatFormulaPreviewValue(value)
    return M.FormatDisplayPreviewNumber(value, M.GetDisplayRounding(), {
        fallback = M.DEFAULT_DISPLAY_ROUNDING
    })
end

local function formatVariableValue(value)
    local numeric = tonumber(value)
    if numeric == nil then
        return tostring(value)
    end

    return M.FormatDisplayNumber(numeric, M.GetDisplayRounding(), {
        fallback = M.DEFAULT_DISPLAY_ROUNDING,
        trim = true
    })
end

local function copySettings(defaultDecimals)
    return {
        slider = {
            decimals = defaultDecimals,
            snap = nil
        },
        label = {
            decimals = defaultDecimals,
            snap = nil
        },
        text = {
            decimals = defaultDecimals,
            snap = nil
        }
    }
end

local function buildEditorInfoSignature(text, options, entries)
    local parts = {
        tostring(text or ""),
        tostring(istable(options) and options.watchKey or ""),
        tostring(M.GetDisplayRounding()),
        tostring(#(entries or {}))
    }

    for index = 1, #(entries or {}) do
        local entry = entries[index] or {}
        parts[#parts + 1] = table.concat({
            tostring(entry.name or ""),
            tostring(entry.value or ""),
            tostring(entry.description or "")
        }, "\30")
    end

    return table.concat(parts, "\31")
end

local function setTextEntryValue(textEntry, text, caretPos)
    if not IsValid(textEntry) then
        return
    end

    text = tostring(text or "")
    local currentText = textEntry:GetText()
    local focus = vgui.GetKeyboardFocus() == textEntry
    if currentText == text and (not focus or caretPos == nil) then
        return
    end

    textEntry:SetText(text)

    if focus then
        local targetCaret = caretPos
        if targetCaret == nil then
            targetCaret = #text
        end
        textEntry:SetCaretPos(math.Clamp(math.floor(tonumber(targetCaret) or #text), 0, #text))
    end
end

local function closeOtherExpressionEditors(currentFrame)
    local world = vgui.GetWorldPanel()
    if not IsValid(world) or not isfunction(world.GetChildren) then
        return
    end

    local children = world:GetChildren()
    for index = 1, #children do
        local child = children[index]
        if IsValid(child) and child.MagicAlignExpressionEditor and child ~= currentFrame then
            child:Remove()
        end
    end
end

function PANEL:Init()
    self.MagicAlignExpressionInput = true
    self.m_strConVar = nil
    self.m_iDefaultDecimals = 2
    self.layoutMetrics = {}
    self.textAreaCollapsedWidth = 56
    self.textAreaFloating = false
    self.textAreaFloatParent = nil
    self.channelSettings = copySettings(self.m_iDefaultDecimals)
    self.storedText = nil
    self.storedTextMode = nil
    self.storedNumericValue = nil
    self.validationState = "ok"
    self.validationMessage = nil
    self.lastManagerRevision = nil
    self.formulaWatchKey = nil
    self.updatingText = false
    self.formulaLocked = false
    self.textMouseWasDown = false
    self.lastTextClickTime = 0
    self.editorSyncing = false
    self.EditorFrame = nil
    self.EditorEntry = nil
    self.EditorFunctionsLabel = nil
    self.EditorVariableFiltersPanel = nil
    self.EditorVariableSearchEntry = nil
    self.EditorShowNaCheckBox = nil
    self.EditorShowWorldCheckBox = nil
    self.EditorShowPointDistancesCheckBox = nil
    self.EditorShowPointAnglesCheckBox = nil
    self.EditorVariableNameHeader = nil
    self.EditorVariableValueHeader = nil
    self.EditorVariablesScroll = nil
    self.EditorVariablesEmptyLabel = nil
    self.EditorVariableRows = {}
    self.editorInfoSignature = nil
    self.editorNextRefreshAt = 0

    self.Label = vgui.Create("DLabel", self)
    self.Label:Dock(LEFT)
    self.Label:SetMouseInputEnabled(true)

    self.Scratch = self.Label:Add("DNumberScratch")
    self.Scratch:SetImageVisible(false)
    self.Scratch:Dock(FILL)
    self.Scratch.OnValueChanged = function()
        self:ApplyValue(self.Scratch:GetFloatValue(), "label")
    end

    local baseScratchOnMousePressed = self.Scratch.OnMousePressed
    self.Scratch.OnMousePressed = function(scratch, mousecode)
        if self:IsFormulaLocked() then
            return
        end

        self:PrepareScratch()
        if baseScratchOnMousePressed then
            return baseScratchOnMousePressed(scratch, mousecode)
        end
    end

    self.TextAreaSlot = self:Add("EditablePanel")
    self.TextAreaSlot:Dock(RIGHT)
    self.TextAreaSlot:SetWide(self.textAreaCollapsedWidth)
    self.TextAreaSlot.Paint = nil

    self.TextArea = self.TextAreaSlot:Add("DTextEntry")
    self.TextArea:Dock(FILL)
    self.TextArea:SetPaintBackground(false)
    self.TextArea:SetNumeric(false)
    self.TextArea:SetUpdateOnType(false)
    self.TextArea:SetDrawLanguageID(false)
    self.TextArea:SetTextInset(6, 0)
    local baseTextAreaOnGetFocus = self.TextArea.OnGetFocus
    local baseTextAreaOnLoseFocus = self.TextArea.OnLoseFocus
    self.TextArea.Paint = function(textarea, w, h)
        self:PaintTextEntry(textarea, w, h)
    end
    self.TextArea.OnChange = function(textarea)
        self:SetDraftText(textarea:GetText(), "main")
        if textarea:HasFocus() then
            self:UpdateFloatingTextAreaBounds()
        end
    end
    self.TextArea.OnEnter = function(textarea)
        self:CommitText(textarea:GetText())
    end
    self.TextArea.OnGetFocus = function(textarea)
        if baseTextAreaOnGetFocus then
            baseTextAreaOnGetFocus(textarea)
        end

        timer.Simple(0, function()
            if not IsValid(self) or not IsValid(textarea) then
                return
            end

            if vgui.GetKeyboardFocus() ~= textarea then
                return
            end

            self:ExpandTextArea(textarea:GetCaretPos())
        end)
    end
    self.TextArea.OnLoseFocus = function(textarea)
        if baseTextAreaOnLoseFocus then
            baseTextAreaOnLoseFocus(textarea)
        end

        self:CommitText(textarea:GetText())
        self:CollapseTextArea()
    end

    self.CenterSlot = self:Add("EditablePanel")
    self.CenterSlot:Dock(FILL)
    self.CenterSlot.Paint = nil
    self.CenterSlot.PerformLayout = function(_, w, h)
        local sliderMarginY = math.max(math.floor(tonumber((self.layoutMetrics or {}).sliderMarginY) or 0), 0)
        local innerY = sliderMarginY
        local innerH = math.max(h - sliderMarginY * 2, 0)

        if IsValid(self.Slider) then
            self.Slider:SetPos(0, innerY)
            self.Slider:SetSize(w, innerH)
        end

        if IsValid(self.FormulaValueLabel) then
            self.FormulaValueLabel:SetPos(0, innerY)
            self.FormulaValueLabel:SetSize(w, innerH)
        end
    end

    self.Slider = self.CenterSlot:Add("DSlider")
    self.Slider:SetLockY(0.5)
    self.Slider:SetTrapInside(true)
    self.Slider:Dock(DOCK_NONE)
    self.Slider:SetHeight(16)
    self.Slider.TranslateValues = function(_, x, y)
        if self:IsFormulaLocked() then
            local range = math.max(self:GetRange(), 1e-9)
            return math.Clamp((self:GetValue() - self:GetMin()) / range, 0, 1), y
        end

        return self:TranslateSliderValues(x, y)
    end
    self.Slider.ResetToDefaultValue = function()
        self:ResetToDefaultValue()
    end
    self.Slider.Paint = function(_, w, h)
        local y = math.floor(h * 0.5) - 2
        draw.RoundedBox(4, 0, y, w, 4, self:IsFormulaLocked() and theme.trackDisabled or theme.track)
    end

    if IsValid(self.Slider.Knob) then
        self.Slider.Knob.Paint = function(knob, w, h)
            local locked = self:IsFormulaLocked()
            local fill = locked and theme.knobDisabled or (knob:IsHovered() and theme.knobHover or theme.knob)
            local border = locked and theme.knobBorderDisabled or theme.knobBorder
            draw.RoundedBox(5, 0, 0, w, h, fill)
            surface.SetDrawColor(border)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
        end
    end

    self.FormulaValueLabel = self.CenterSlot:Add("DLabel")
    self.FormulaValueLabel:Dock(DOCK_NONE)
    self.FormulaValueLabel:SetVisible(false)
    self.FormulaValueLabel:SetMouseInputEnabled(false)
    self.FormulaValueLabel:SetContentAlignment(5)
    self.FormulaValueLabel:SetFont("DermaDefaultBold")
    self.FormulaValueLabel:SetTextColor(theme.text)

    self:SetTall(32)
    self:SetMin(0)
    self:SetMax(1)
    self:SetDecimals(2)
    self:SetText("")
    self:SetValue(0.5)
    self:UpdateTextAreaTooltip()

    self.Wang = self.Scratch
end

function PANEL:EnsureRuntimeState()
    if self.m_iDefaultDecimals == nil then
        self.m_iDefaultDecimals = 2
    end

    if not istable(self.channelSettings) then
        self.channelSettings = copySettings(self.m_iDefaultDecimals)
    end

    if self.validationState == nil then
        self.validationState = "ok"
    end

    if self.lastTextClickTime == nil then
        self.lastTextClickTime = 0
    end

    if self.textMouseWasDown == nil then
        self.textMouseWasDown = false
    end

    if self.editorSyncing == nil then
        self.editorSyncing = false
    end

    if self.formulaLocked == nil then
        self.formulaLocked = false
    end

    if not istable(self.EditorVariableRows) then
        self.EditorVariableRows = {}
    end

    if self.editorNextRefreshAt == nil then
        self.editorNextRefreshAt = 0
    end

    if self.textAreaCollapsedWidth == nil then
        self.textAreaCollapsedWidth = 56
    end

    if self.textAreaFloating == nil then
        self.textAreaFloating = false
    end

    if self.textAreaFloatParent == nil then
        self.textAreaFloatParent = nil
    end

    if not istable(self.layoutMetrics) then
        self.layoutMetrics = {}
    end
end

function PANEL:GetConVar()
    return self.m_strConVar
end

function PANEL:GetFormulaManager()
    return FormulaManager
end

function PANEL:SyncStoredStateFromManager(snapshot)
    local manager = self:GetFormulaManager()
    local cvar = self:GetConVar()
    if not manager or not cvar or cvar == "" then
        return nil
    end

    snapshot = snapshot or manager:GetSnapshot(cvar)
    if not snapshot then
        return nil
    end

    self.storedText = snapshot.rawText
    self.storedTextMode = snapshot.rawMode
    self.storedNumericValue = snapshot.storedNumericValue
    self.formulaWatchKey = snapshot.formulaWatchKey

    return snapshot
end

function PANEL:ApplyFormulaSnapshot(snapshot, force)
    snapshot = self:SyncStoredStateFromManager(snapshot)
    if not snapshot then
        return false
    end

    local applied = tonumber(snapshot.value) or 0
    local previousValue = self:GetValue()
    local displayText = snapshot.rawText

    self.Scratch:SetFloatValue(applied)
    self.Slider:SetSlideX(self:GetSliderFractionForValue(applied))
    if displayText == nil or displayText == "" then
        displayText = self:FormatDisplayValue(applied, "text")
    end
    self:SetDisplayedText(displayText)
    self:SetValidationState(snapshot.validationState or "ok", snapshot.validationMessage)

    if force or not nearlyEqual(previousValue, applied) then
        self:OnValueChanged(applied)
        self:SetCookie("slider_val", applied)
    end

    return true
end

function PANEL:HasFormulaPresentation()
    local currentText = IsValid(self.TextArea) and self.TextArea:GetText() or ""
    return isFormulaText(currentText) or self.storedTextMode == "formula"
end

function PANEL:GetFormulaPreviewValue()
    local currentText = IsValid(self.TextArea) and self.TextArea:GetText() or ""
    if not isFormulaText(currentText) then
        return self:GetValue()
    end

    if isTransitionalExpressionText(currentText) then
        return self:GetValue()
    end

    local commit = self:BuildTextCommit(currentText)
    if commit and commit.ok then
        return tonumber(commit.value) or 0
    end

    return 0
end

function PANEL:UpdateFormulaResultLabel()
    if not IsValid(self.FormulaValueLabel) then
        return
    end

    local hasFormula = self:HasFormulaPresentation()
    self.FormulaValueLabel:SetVisible(hasFormula)

    if IsValid(self.Slider) then
        self.Slider:SetVisible(not hasFormula)
    end

    if not hasFormula then
        self.FormulaValueLabel:SetText("")
        self:InvalidateLayout(true)
        return
    end

    local previewValue = self:GetFormulaPreviewValue()
    local textColor = self.validationState == "invalid" and theme.textInvalid or theme.text

    self.FormulaValueLabel:SetText(formatFormulaPreviewValue(previewValue))
    self.FormulaValueLabel:SetTextColor(textColor)
    self:InvalidateLayout(true)
end

function PANEL:SetConVar(cvar)
    self.m_strConVar = cvar
    if FormulaManager and cvar and cvar ~= "" then
        FormulaManager:RegisterConVar(cvar)
    end
    self.lastManagerRevision = nil
    self:SyncFromConVar(true)
end

function PANEL:GetInputDecimals(source)
    local settings = self.channelSettings[source]
    if not settings then
        return self.m_iDefaultDecimals
    end

    local decimals = settings.decimals
    if isfunction(decimals) then
        decimals = decimals(self, source)
    end

    return sanitizeDecimals(decimals)
end

function PANEL:SetInputDecimals(source, decimals)
    local settings = self.channelSettings[source]
    if not settings then return end

    settings.decimals = sanitizeDecimals(decimals)
    if source == "label" then
        self:PrepareScratch()
    end
end

function PANEL:GetInputSnap(source, value)
    local settings = self.channelSettings[source]
    if not settings then return nil end

    local snap = settings.snap
    if isfunction(snap) then
        snap = snap(self, source, value)
    end

    snap = tonumber(snap)
    if not snap or snap <= 0 then
        return nil
    end

    return math.abs(snap)
end

function PANEL:SetInputSnap(source, snap)
    local settings = self.channelSettings[source]
    if not settings then return end

    settings.snap = snap
end

function PANEL:PrepareScratch()
    self.Scratch:SetDecimals(self:GetInputDecimals("label") or self.m_iDefaultDecimals)
end

function PANEL:IsFormulaLocked()
    if self.formulaLocked ~= nil then
        return self.formulaLocked == true
    end

    return false
end

function PANEL:UpdateFormulaLockState()
    local editingFormula = IsValid(self.TextArea) and isFormulaText(self.TextArea:GetText())
    local locked = editingFormula or self.storedTextMode == "formula"
    local changed = self.formulaLocked ~= locked

    self.formulaLocked = locked

    if IsValid(self.Slider) then
        self.Slider:SetMouseInputEnabled(not locked)
        self.Slider:SetCursor(locked and "no" or "hand")
        if IsValid(self.Slider.Knob) then
            self.Slider.Knob:SetMouseInputEnabled(not locked)
            self.Slider.Knob:SetCursor(locked and "no" or "hand")
        end
    end

    if IsValid(self.Scratch) then
        self.Scratch:SetMouseInputEnabled(not locked)
        self.Scratch:SetCursor(locked and "no" or "sizewe")
    end

    if IsValid(self.Label) then
        self.Label:SetMouseInputEnabled(not locked)
        self.Label:SetCursor(locked and "no" or "arrow")
        self.Label:SetTextColor(locked and theme.textMuted or theme.text)
    end

    self:UpdateFormulaResultLabel()
    self:UpdateTextAreaTooltip()

    if changed then
        self:InvalidateLayout(true)
    end
end

function PANEL:UpdateTextAreaTooltip()
    if not IsValid(self.TextArea) then return end

    local lines = { EDITOR_TOOLTIP }
    if self.validationState == "invalid" and self.validationMessage and self.validationMessage ~= "" then
        lines[#lines + 1] = self.validationMessage
    elseif self.storedTextMode == "formula" then
        lines[#lines + 1] = "Formula active: slider and label drag are locked."
    end

    self.TextArea:SetTooltip(table.concat(lines, "\n"))
end

function PANEL:SyncEditorText(text, source)
    if source == "editor" or not IsValid(self.EditorEntry) then
        return
    end

    text = tostring(text or "")
    if self.editorSyncing or self.EditorEntry:GetText() == text then
        return
    end

    self.editorSyncing = true
    setTextEntryValue(self.EditorEntry, text)
    self.editorSyncing = false
end

function PANEL:SetDraftText(text, source)
    source = source or "main"
    text = tostring(text or "")

    if source ~= "main" and IsValid(self.TextArea) and self.TextArea:GetText() ~= text then
        self.updatingText = true
        setTextEntryValue(self.TextArea, text)
        self.updatingText = false
    end

    self:SyncEditorText(text, source)
    self:HandleTextChanged(text)
    self:RefreshEditorInfo()
end

function PANEL:GetExpressionOptions()
    local manager = self:GetFormulaManager()
    if manager then
        return manager:GetExpressionOptions(self:GetConVar(), self)
    end

    return {}
end

function PANEL:GetAvailableVariableRows(options)
    options = istable(options) and options or self:GetExpressionOptions()
    local variables = istable(options.variables) and options.variables or {}
    local descriptions = istable(options.variableDescriptions) and options.variableDescriptions or {}
    local names = {}
    local seen = {}

    if istable(options.variableNames) then
        for index = 1, #options.variableNames do
            local name = tostring(options.variableNames[index] or "")
            if name ~= "" and not seen[name] then
                seen[name] = true
                names[#names + 1] = name
            end
        end
    end

    for name in pairs(descriptions) do
        name = tostring(name or "")
        if name ~= "" and not seen[name] then
            seen[name] = true
            names[#names + 1] = name
        end
    end

    for name in pairs(variables) do
        name = tostring(name or "")
        if name ~= "" and not seen[name] then
            seen[name] = true
            names[#names + 1] = name
        end
    end

    table.sort(names)

    local rows = {}
    for index = 1, #names do
        local name = names[index]
        local value = variables[name]
        if value == nil then
            value = variables[string.lower(name)]
        end
        if value == nil then
            value = variables[string.upper(name)]
        end

        local description = descriptions[name]
        if description == nil then
            description = descriptions[string.lower(name)]
        end
        if description == nil then
            description = descriptions[string.upper(name)]
        end

        local suffix = description and tostring(description) or ""
        if suffix ~= "" then
            rows[#rows + 1] = ("%s - %s"):format(name, suffix)
        elseif value ~= nil then
            rows[#rows + 1] = ("%s = %s"):format(name, formatVariableValue(value))
        else
            rows[#rows + 1] = name
        end
    end

    return rows
end

function PANEL:ResolveExpressionIdentifierValue(name, options)
    options = istable(options) and options or {}

    local variables = istable(options.variables) and options.variables or nil
    if istable(variables) then
        local value = variables[name]
        if value == nil then
            value = variables[string.lower(name)]
        end
        if value == nil then
            value = variables[string.upper(name)]
        end
        if value ~= nil then
            return value, true
        end
    end

    local resolver = options.resolveIdentifier
    if isfunction(resolver) then
        local value, found = resolver(name, options)
        if found ~= false and value ~= nil then
            return value, true
        end
    end

    return nil, false
end

function PANEL:BuildFormulaWatchKey(text)
    local manager = self:GetFormulaManager()
    if manager then
        return manager:BuildFormulaWatchKey(self:GetConVar(), text, self)
    end

    return ""
end

function PANEL:GetAvailableVariableEntries(options)
    self:EnsureRuntimeState()

    options = istable(options) and options or self:GetExpressionOptions()
    local entries = {}

    if istable(options.variableRows) then
        for index = 1, #options.variableRows do
            local row = options.variableRows[index]
            if istable(row) then
                local name = string.lower(tostring(row.name or ""))
                if name ~= "" then
                    entries[#entries + 1] = {
                        name = name,
                        value = tostring(row.value or "n/a"),
                        description = tostring(row.description or "")
                    }
                end
            end
        end

        return entries
    end

    local rows = self:GetAvailableVariableRows(options)
    for index = 1, #rows do
        local text = tostring(rows[index] or "")
        local name, value = text:match("^(.-)%s=%s(.+)$")
        if name then
            entries[#entries + 1] = {
                name = name,
                value = value,
                description = ""
            }
        elseif text ~= "" then
            entries[#entries + 1] = {
                name = text,
                value = "n/a",
                description = ""
            }
        end
    end

    return entries
end

function PANEL:GetEditorVariableSearchText()
    if not IsValid(self.EditorVariableSearchEntry) then
        return ""
    end

    return string.Trim(string.lower(tostring(self.EditorVariableSearchEntry:GetText() or "")))
end

function PANEL:GetEditorShowNaEnabled()
    if not IsValid(self.EditorShowNaCheckBox) then
        return true
    end

    return self.EditorShowNaCheckBox:GetChecked()
end

function PANEL:GetEditorShowWorldEnabled()
    if not IsValid(self.EditorShowWorldCheckBox) then
        return false
    end

    return self.EditorShowWorldCheckBox:GetChecked()
end

function PANEL:GetEditorShowPointDistancesEnabled()
    if not IsValid(self.EditorShowPointDistancesCheckBox) then
        return true
    end

    return self.EditorShowPointDistancesCheckBox:GetChecked()
end

function PANEL:GetEditorShowPointAnglesEnabled()
    if not IsValid(self.EditorShowPointAnglesCheckBox) then
        return true
    end

    return self.EditorShowPointAnglesCheckBox:GetChecked()
end

function PANEL:IsWorldVariableEntryName(name)
    name = string.lower(tostring(name or ""))
    return name:find("^prop[12]_world_") ~= nil
        or name:find("^linked%d+_world_") ~= nil
end

function PANEL:IsPointDistanceEntryName(name)
    name = string.lower(tostring(name or ""))
    return name:find("^prop[12]_dist_") ~= nil
        or name:find("^dist_p[123]_p[123]$") ~= nil
end

function PANEL:IsPointAngleEntryName(name)
    name = string.lower(tostring(name or ""))
    return name:find("^prop[12]_p[123]_ang$") ~= nil
end

function PANEL:FilterEditorVariableEntries(entries)
    entries = entries or {}

    local searchText = self:GetEditorVariableSearchText()
    local showNa = self:GetEditorShowNaEnabled()
    local showWorld = self:GetEditorShowWorldEnabled()
    local showPointDistances = self:GetEditorShowPointDistancesEnabled()
    local showPointAngles = self:GetEditorShowPointAnglesEnabled()
    local filtered = {}

    for index = 1, #entries do
        local entry = entries[index]
        local name = string.lower(tostring(entry.name or ""))
        local value = tostring(entry.value or "")
        local valueLower = string.lower(value)
        local description = string.lower(tostring(entry.description or ""))

        if (showWorld or not self:IsWorldVariableEntryName(name))
            and (showPointDistances or not self:IsPointDistanceEntryName(name))
            and (showPointAngles or not self:IsPointAngleEntryName(name)) then
            if showNa or valueLower ~= "n/a" then
                local matchesSearch = true
                if searchText ~= "" then
                    local haystack = table.concat({
                        name,
                        valueLower,
                        description
                    }, "\n")
                    matchesSearch = haystack:find(searchText, 1, true) ~= nil
                end

                if matchesSearch then
                    filtered[#filtered + 1] = entry
                end
            end
        end
    end

    return filtered
end

function PANEL:SetEditorCellText(cell, text)
    if not IsValid(cell) then return end

    text = tostring(text or "")
    cell.MagicAlignLockedText = text
    if cell:GetText() == text or cell:HasFocus() then
        return
    end

    cell.MagicAlignApplyingText = true
    cell:SetValue(text)
    cell.MagicAlignApplyingText = false
end

function PANEL:CreateEditorReadOnlyCell(parent)
    ensureEditorFonts()

    local cell = vgui.Create("DTextEntry", parent)
    cell:SetFont("MagicAlignEditorBody")
    cell:SetNumeric(false)
    cell:SetMultiline(false)
    cell:SetEditable(true)
    cell:SetPaintBackground(false)
    cell:SetDrawLanguageID(false)
    cell:SetEnterAllowed(false)
    cell:SetUpdateOnType(false)
    cell:SetTextInset(5, 0)
    cell:SetTextColor(getEditorPalette().text)
    cell:SetCursor("beam")
    cell.AllowInput = function()
        return true
    end
    cell.OnChange = function(textarea)
        if textarea.MagicAlignApplyingText then
            return
        end

        local lockedText = tostring(textarea.MagicAlignLockedText or "")
        if textarea:GetText() == lockedText then
            return
        end

        local caretPos = textarea:GetCaretPos()
        textarea.MagicAlignApplyingText = true
        textarea:SetText(lockedText)
        textarea:SetCaretPos(math.min(caretPos, #lockedText))
        textarea.MagicAlignApplyingText = false
    end
    cell.OnLoseFocus = function(textarea)
        local lockedText = tostring(textarea.MagicAlignLockedText or "")
        if textarea:GetText() == lockedText then
            return
        end

        textarea.MagicAlignApplyingText = true
        textarea:SetText(lockedText)
        textarea:SetCaretPos(math.min(textarea:GetCaretPos(), #lockedText))
        textarea.MagicAlignApplyingText = false
    end
    cell.Paint = function(textarea, w, h)
        paintEditorEntry(textarea, w, h, false)
    end

    return cell
end

function PANEL:EnsureEditorVariableRow(index)
    local row = self.EditorVariableRows[index]
    if IsValid(row) then
        return row
    end

    if not IsValid(self.EditorVariablesScroll) then
        return nil
    end

    row = vgui.Create("DPanel", self.EditorVariablesScroll:GetCanvas())
    row:Dock(TOP)
    row:DockMargin(0, 0, 0, 4)
    row:SetTall(24)
    row.Paint = nil
    row.NameCell = self:CreateEditorReadOnlyCell(row)
    row.ValueCell = self:CreateEditorReadOnlyCell(row)
    row.PerformLayout = function(rowPanel, w, h)
        local gap = 8
        local nameWidth = math.Clamp(math.floor(w * 0.44), 150, 250)
        rowPanel.NameCell:SetPos(0, 0)
        rowPanel.NameCell:SetSize(nameWidth, h)
        rowPanel.ValueCell:SetPos(nameWidth + gap, 0)
        rowPanel.ValueCell:SetSize(math.max(w - nameWidth - gap, 0), h)
    end

    self.EditorVariableRows[index] = row
    return row
end

function PANEL:RefreshEditorVariableTable(entries, totalCount)
    self:EnsureRuntimeState()

    if not IsValid(self.EditorVariablesScroll) then
        return
    end

    entries = entries or self:GetAvailableVariableEntries()
    for index = 1, #entries do
        local row = self:EnsureEditorVariableRow(index)
        if IsValid(row) then
            local entry = entries[index]
            local tooltip = entry.description ~= "" and entry.description or nil

            self:SetEditorCellText(row.NameCell, entry.name)
            self:SetEditorCellText(row.ValueCell, entry.value)
            row.NameCell:SetTooltip(tooltip)
            row.ValueCell:SetTooltip(tooltip)
        end
    end

    for index = #entries + 1, #self.EditorVariableRows do
        local row = self.EditorVariableRows[index]
        if IsValid(row) then
            row:Remove()
        end
        self.EditorVariableRows[index] = nil
    end

    if IsValid(self.EditorVariablesEmptyLabel) then
        self.EditorVariablesEmptyLabel:SetVisible(#entries == 0)
        if #entries == 0 and (tonumber(totalCount) or 0) > 0 then
            self.EditorVariablesEmptyLabel:SetText("No variables match the current filters.")
        else
            self.EditorVariablesEmptyLabel:SetText("No environment variables are currently registered.")
        end
        self.EditorVariablesEmptyLabel:SizeToContentsY()
    end

    self.EditorVariablesScroll:GetCanvas():InvalidateLayout(true)
    self.EditorVariablesScroll:InvalidateLayout(true)
end

function PANEL:RefreshEditorInfo(force)
    if not IsValid(self.EditorFrame) then
        return
    end

    local text = IsValid(self.EditorEntry) and self.EditorEntry:GetText()
        or (IsValid(self.TextArea) and self.TextArea:GetText() or "")
    local options = self:GetExpressionOptions()
    local rawEntries = self:GetAvailableVariableEntries(options)
    local entries = self:FilterEditorVariableEntries(rawEntries)
    local signature = buildEditorInfoSignature(text, options, entries)
    if not force and self.editorInfoSignature == signature then
        return
    end

    self.editorInfoSignature = signature

    local functionsText = table.concat({
        "Operators: +  -  *  /  %  ^  ()",
        "Functions: " .. table.concat(MathParser.GetSupportedFunctions(), ", "),
        "Add a leading '=' to keep the expression as live formula."
    }, "\n")

    if IsValid(self.EditorFunctionsLabel) then
        self.EditorFunctionsLabel:SetText(functionsText)
        self.EditorFunctionsLabel:SizeToContentsY()
    end

    self:RefreshEditorVariableTable(entries, #rawEntries)

    self.EditorFrame:InvalidateLayout(true)
end

function PANEL:RestoreTextAreaFocusAfterEditorClose()
    if not IsValid(self) or not IsValid(self.TextArea) then
        return
    end

    local function restore(attempt)
        if not IsValid(self) or not IsValid(self.TextArea) then
            return
        end

        local parent = resolveTextAreaFloatParent(self)
        if not IsValid(parent) or not parent:IsVisible() then
            return
        end

        local caretPos = #self.TextArea:GetText()
        self.TextArea:RequestFocus()
        self.TextArea:SetCaretPos(caretPos)
        self:ExpandTextArea(caretPos)

        if vgui.GetKeyboardFocus() ~= self.TextArea and attempt < 2 then
            timer.Simple(0, function()
                restore(attempt + 1)
            end)
        end
    end

    timer.Simple(0, function()
        restore(0)
    end)
end

function PANEL:OpenExpressionEditor()
    self:EnsureRuntimeState()
    ensureEditorFonts()

    closeOtherExpressionEditors(self.EditorFrame)

    local editorParent = resolveTextAreaFloatParent(self) or vgui.GetWorldPanel()

    local activeFrame = M.ActiveExpressionEditorFrame
    if IsValid(activeFrame) and activeFrame ~= self.EditorFrame then
        activeFrame:Remove()
    end

    if IsValid(self.EditorFrame) and self.EditorFrame:GetParent() ~= editorParent then
        self.EditorFrame:Remove()
    end

    if IsValid(self.EditorFrame) then
        self.EditorFrame:MakePopup()
        self.EditorFrame:MoveToFront()
        if isfunction(self.EditorFrame.MagicAlignRefreshHeader) then
            self.EditorFrame:MagicAlignRefreshHeader()
        end
        if IsValid(self.EditorEntry) then
            self.EditorEntry:RequestFocus()
            self.EditorEntry:SetCaretPos(#self.EditorEntry:GetText())
        end
        M.ActiveExpressionEditorFrame = self.EditorFrame
        M.ActiveExpressionEditorOwner = self
        self.editorNextRefreshAt = 0
        self:RefreshEditorInfo(true)
        return
    end

    local frame = vgui.Create("DFrame", editorParent)
    frame.MagicAlignExpressionEditor = true
    frame:SetTitle("")
    frame:SetSize(680, 540)
    frame:Center()
    frame:SetZPos(EDITOR_ZPOS)
    frame:MakePopup()
    frame:MoveToFront()
    frame:SetDeleteOnClose(true)
    frame.MagicAlignOpenedAt = RealTime()
    frame.MagicAlignFocusLostAt = nil
    frame.Paint = function(editorFrame, w, h)
        local palette = getEditorPalette()

        draw.RoundedBox(12, 0, 0, w, h, palette.bg)
        surface.SetDrawColor(palette.border)
        surface.DrawOutlinedRect(0, 0, w, h, 1)
        draw.RoundedBoxEx(12, 0, 0, w, 42, palette.shell, true, true, false, false)
        surface.SetDrawColor(palette.sheen)
        surface.DrawRect(1, 1, math.max(w - 2, 0), 1)
        surface.SetDrawColor(palette.accent)
        surface.DrawRect(0, 40, w, 2)
    end
    if IsValid(frame.lblTitle) then
        frame.lblTitle:SetVisible(false)
    end
    if IsValid(frame.btnMaxim) then
        frame.btnMaxim:Remove()
        frame.btnMaxim = nil
    end
    if IsValid(frame.btnMinim) then
        frame.btnMinim:Remove()
        frame.btnMinim = nil
    end
    if IsValid(frame.btnClose) then
        frame.btnClose:SetText("")
        frame.btnClose.Paint = function(button, w, h)
            local palette = getEditorPalette()
            local bg = palette.cardSoft
            if button:IsDown() then
                bg = palette.shell
            elseif button:IsHovered() then
                bg = palette.card
            end

            draw.RoundedBox(8, 0, 0, w, h, bg)
            surface.SetDrawColor(palette.border)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
            draw.SimpleText("x", "MagicAlignEditorClose", w * 0.5, h * 0.46, palette.textMuted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    frame.OnRemove = function(editorFrame)
        local text = IsValid(self.EditorEntry) and self.EditorEntry:GetText() or nil
        self.EditorFrame = nil
        self.EditorEntry = nil
        self.EditorFunctionsLabel = nil
        self.EditorVariableFiltersPanel = nil
        self.EditorVariableSearchEntry = nil
        self.EditorShowNaCheckBox = nil
        self.EditorShowWorldCheckBox = nil
        self.EditorShowPointDistancesCheckBox = nil
        self.EditorShowPointAnglesCheckBox = nil
        self.EditorVariableNameHeader = nil
        self.EditorVariableValueHeader = nil
        self.EditorVariablesScroll = nil
        self.EditorVariablesEmptyLabel = nil
        self.EditorVariableRows = {}
        self.editorSyncing = false
        self.editorInfoSignature = nil
        self.editorNextRefreshAt = 0

        if M.ActiveExpressionEditorFrame == editorFrame then
            M.ActiveExpressionEditorFrame = nil
            M.ActiveExpressionEditorOwner = nil
        end

        if IsValid(self) and text ~= nil then
            self:CommitText(text)
            self:RestoreTextAreaFocusAfterEditorClose()
        end
    end
    frame.PerformLayout = function(editorFrame, w, h)
        local pad = 10
        local cardGap = 8
        local cardPad = 10
        local closeSize = 18
        local contentWidth = math.max(w - pad * 2, 0)

        if IsValid(editorFrame.btnClose) then
            editorFrame.btnClose:SetSize(closeSize, closeSize)
            editorFrame.btnClose:SetPos(w - pad - closeSize, 10)
        end

        if IsValid(editorFrame.TitleLabel) then
            editorFrame.TitleLabel:SetPos(pad, 10)
            editorFrame.TitleLabel:SetWide(math.max(contentWidth - closeSize - 8, 0))
            editorFrame.TitleLabel:SizeToContentsY()
        end

        local y = 50
        local entryCardHeight = 36
        if IsValid(editorFrame.EntryCard) then
            editorFrame.EntryCard:SetPos(pad, y)
            editorFrame.EntryCard:SetSize(contentWidth, entryCardHeight)
        end
        if IsValid(editorFrame.Entry) then
            editorFrame.Entry:SetPos(cardPad, 6)
            editorFrame.Entry:SetSize(math.max(contentWidth - cardPad * 2, 0), 24)
        end

        y = y + entryCardHeight + cardGap

        if IsValid(editorFrame.FunctionsLabel) then
            editorFrame.FunctionsLabel:SetWide(math.max(contentWidth - cardPad * 2, 0))
            editorFrame.FunctionsLabel:SizeToContentsY()
        end

        local functionsTall = IsValid(editorFrame.FunctionsLabel) and editorFrame.FunctionsLabel:GetTall() or 0
        local functionsCardHeight = 14 + 8 + functionsTall + 10
        if IsValid(editorFrame.FunctionsCard) then
            editorFrame.FunctionsCard:SetPos(pad, y)
            editorFrame.FunctionsCard:SetSize(contentWidth, functionsCardHeight)
        end
        if IsValid(editorFrame.FunctionsTitle) then
            editorFrame.FunctionsTitle:SetPos(cardPad, 8)
            editorFrame.FunctionsTitle:SizeToContents()
        end
        if IsValid(editorFrame.FunctionsLabel) then
            editorFrame.FunctionsLabel:SetPos(cardPad, 22)
        end

        y = y + functionsCardHeight + cardGap

        local variablesHeight = math.max(h - y - pad, 120)
        if IsValid(editorFrame.VariablesCard) then
            editorFrame.VariablesCard:SetPos(pad, y)
            editorFrame.VariablesCard:SetSize(contentWidth, variablesHeight)
        end

        if IsValid(editorFrame.VariablesTitle) then
            editorFrame.VariablesTitle:SetPos(cardPad, 8)
            editorFrame.VariablesTitle:SizeToContents()
        end

        local filterY = 24
        local filterHeight = 68
        if IsValid(editorFrame.VariableFiltersPanel) then
            editorFrame.VariableFiltersPanel:SetPos(cardPad, filterY)
            editorFrame.VariableFiltersPanel:SetSize(math.max(contentWidth - cardPad * 2, 0), filterHeight)
        end

        local headerY = filterY + filterHeight + 4
        local gap = 8
        local headerWidth = math.max(contentWidth - cardPad * 2, 0)
        local nameWidth = math.Clamp(math.floor((headerWidth - gap) * 0.44), 150, 250)
        local valueWidth = math.max(headerWidth - nameWidth - gap, 0)

        if IsValid(editorFrame.VariableNameHeader) then
            editorFrame.VariableNameHeader:SetPos(cardPad, headerY)
            editorFrame.VariableNameHeader:SetSize(nameWidth, 18)
        end

        if IsValid(editorFrame.VariableValueHeader) then
            editorFrame.VariableValueHeader:SetPos(cardPad + nameWidth + gap, headerY)
            editorFrame.VariableValueHeader:SetSize(valueWidth, 18)
        end

        local scrollY = headerY + 20
        if IsValid(editorFrame.VariablesScroll) then
            editorFrame.VariablesScroll:SetPos(cardPad, scrollY)
            editorFrame.VariablesScroll:SetSize(headerWidth, math.max(variablesHeight - scrollY - cardPad, 80))
        end

        if IsValid(editorFrame.VariablesEmptyLabel) and IsValid(editorFrame.VariablesScroll) then
            editorFrame.VariablesEmptyLabel:SetPos(0, 0)
            editorFrame.VariablesEmptyLabel:SetWide(math.max(editorFrame.VariablesScroll:GetWide() - 16, 0))
            editorFrame.VariablesEmptyLabel:SizeToContentsY()
        end
    end
    frame.Think = function(editorFrame)
        if not IsValid(self) then
            editorFrame:Remove()
            return
        end

        if M.ActiveExpressionEditorFrame ~= editorFrame then
            M.ActiveExpressionEditorFrame = editorFrame
            M.ActiveExpressionEditorOwner = self
        end

        local now = RealTime()
        if now >= (tonumber(self.editorNextRefreshAt) or 0) then
            self.editorNextRefreshAt = now + EDITOR_REFRESH_INTERVAL
            self:RefreshEditorInfo()
        end

        if now - (tonumber(editorFrame.MagicAlignOpenedAt) or now) < 0.15 then
            return
        end

        local keyboardFocus = vgui.GetKeyboardFocus()
        local hovered = vgui.GetHoveredPanel()
        if isPanelDescendant(keyboardFocus, editorFrame) or isPanelDescendant(hovered, editorFrame) then
            editorFrame.MagicAlignFocusLostAt = nil
            return
        end

        editorFrame.MagicAlignFocusLostAt = editorFrame.MagicAlignFocusLostAt or now
        if now - editorFrame.MagicAlignFocusLostAt >= 0.12 then
            self:RestoreTextAreaFocusAfterEditorClose()
            editorFrame:Close()
        end
    end

    local titleLabel = vgui.Create("DLabel", frame)
    titleLabel:SetFont("MagicAlignEditorTitle")
    titleLabel:SetWrap(true)
    titleLabel:SetAutoStretchVertical(true)
    titleLabel:SetTextColor(getEditorPalette().text)
    frame.TitleLabel = titleLabel

    frame.MagicAlignRefreshHeader = function(editorFrame)
        local label = string.Trim(tostring(self:GetText() or ""))
        if label == "" then
            label = "Expression"
        end

        if IsValid(editorFrame.TitleLabel) then
            editorFrame.TitleLabel:SetText(label .. " Editor")
        end
    end
    frame:MagicAlignRefreshHeader()

    local entryCard = createEditorCard(frame, "card")
    frame.EntryCard = entryCard

    local entry = vgui.Create("DTextEntry", entryCard)
    entry:SetFont("MagicAlignEditorBody")
    entry:SetMultiline(false)
    entry:SetNumeric(false)
    entry:SetPaintBackground(false)
    entry:SetDrawLanguageID(false)
    entry:SetUpdateOnType(false)
    entry:SetTextInset(6, 0)
    entry:SetText(self.TextArea:GetText())
    entry.Paint = function(textarea, w, h)
        self:PaintEditorTextEntry(textarea, w, h)
    end
    entry.OnChange = function(editorEntry)
        if self.editorSyncing then
            return
        end

        self:SetDraftText(editorEntry:GetText(), "editor")
    end
    entry.OnEnter = function(editorEntry)
        self:CommitText(editorEntry:GetText())
        editorEntry:RequestFocus()
        editorEntry:SetCaretPos(#editorEntry:GetText())
    end
    frame.Entry = entry

    local functionsCard = createEditorCard(frame, "soft")
    frame.FunctionsCard = functionsCard

    local functionsTitle = vgui.Create("DLabel", functionsCard)
    functionsTitle:SetFont("MagicAlignEditorCaption")
    functionsTitle:SetText("Allowed syntax")
    functionsTitle:SetTextColor(getEditorPalette().text)
    frame.FunctionsTitle = functionsTitle

    local functionsLabel = vgui.Create("DLabel", functionsCard)
    functionsLabel:SetFont("MagicAlignEditorBody")
    functionsLabel:SetWrap(true)
    functionsLabel:SetAutoStretchVertical(true)
    functionsLabel:SetTextColor(getEditorPalette().textMuted)
    frame.FunctionsLabel = functionsLabel
    self.EditorFunctionsLabel = functionsLabel

    local variablesCard = createEditorCard(frame, "soft")
    frame.VariablesCard = variablesCard

    local variablesTitle = vgui.Create("DLabel", variablesCard)
    variablesTitle:SetFont("MagicAlignEditorCaption")
    variablesTitle:SetText("Available environment variables")
    variablesTitle:SetTextColor(getEditorPalette().text)
    frame.VariablesTitle = variablesTitle

    local filterPanel = vgui.Create("DPanel", variablesCard)
    filterPanel.Paint = nil
    filterPanel.PerformLayout = function(filterRow, w, h)
        local gap = 8
        local searchTall = 24
        local checkTall = 18
        local rowOneY = searchTall + 4
        local rowTwoY = rowOneY + checkTall + 4
        local halfWidth = math.floor((w - gap) * 0.5)

        if IsValid(filterRow.SearchEntry) then
            filterRow.SearchEntry:SetPos(0, 0)
            filterRow.SearchEntry:SetSize(w, searchTall)
        end

        if IsValid(filterRow.ShowNaCheckBox) then
            filterRow.ShowNaCheckBox:SetPos(0, rowOneY)
            filterRow.ShowNaCheckBox:SetSize(halfWidth, checkTall)
        end

        if IsValid(filterRow.ShowWorldCheckBox) then
            filterRow.ShowWorldCheckBox:SetPos(halfWidth + gap, rowOneY)
            filterRow.ShowWorldCheckBox:SetSize(w - halfWidth - gap, checkTall)
        end

        if IsValid(filterRow.ShowPointDistancesCheckBox) then
            filterRow.ShowPointDistancesCheckBox:SetPos(0, rowTwoY)
            filterRow.ShowPointDistancesCheckBox:SetSize(halfWidth, checkTall)
        end

        if IsValid(filterRow.ShowPointAnglesCheckBox) then
            filterRow.ShowPointAnglesCheckBox:SetPos(halfWidth + gap, rowTwoY)
            filterRow.ShowPointAnglesCheckBox:SetSize(w - halfWidth - gap, checkTall)
        end
    end
    frame.VariableFiltersPanel = filterPanel
    self.EditorVariableFiltersPanel = filterPanel

    local searchEntry = vgui.Create("DTextEntry", filterPanel)
    searchEntry:SetFont("MagicAlignEditorBody")
    searchEntry:SetNumeric(false)
    searchEntry:SetMultiline(false)
    searchEntry:SetPaintBackground(false)
    searchEntry:SetDrawLanguageID(false)
    searchEntry:SetUpdateOnType(false)
    searchEntry:SetTextInset(5, 0)
    searchEntry:SetPlaceholderText("Search variables")
    searchEntry.Paint = function(textarea, w, h)
        paintEditorEntry(textarea, w, h, false)
    end
    searchEntry.OnChange = function()
        self.editorInfoSignature = nil
        self:RefreshEditorInfo(true)
    end
    filterPanel.SearchEntry = searchEntry
    self.EditorVariableSearchEntry = searchEntry

    local showNaCheckBox = vgui.Create("DCheckBoxLabel", filterPanel)
    showNaCheckBox:SetText("Show N/A")
    showNaCheckBox:SetValue(cookie.GetString(EDITOR_COOKIE_SHOW_NA, "1") ~= "0" and 1 or 0)
    showNaCheckBox.OnChange = function(_, checked)
        cookie.Set(EDITOR_COOKIE_SHOW_NA, checked and "1" or "0")
        self.editorInfoSignature = nil
        self:RefreshEditorInfo(true)
    end
    styleEditorCheckBox(showNaCheckBox)
    filterPanel.ShowNaCheckBox = showNaCheckBox
    self.EditorShowNaCheckBox = showNaCheckBox

    local showWorldCheckBox = vgui.Create("DCheckBoxLabel", filterPanel)
    showWorldCheckBox:SetText("Show world variables")
    showWorldCheckBox:SetValue(cookie.GetString(EDITOR_COOKIE_SHOW_WORLD, "0") == "1" and 1 or 0)
    showWorldCheckBox.OnChange = function(_, checked)
        cookie.Set(EDITOR_COOKIE_SHOW_WORLD, checked and "1" or "0")
        self.editorInfoSignature = nil
        self:RefreshEditorInfo(true)
    end
    styleEditorCheckBox(showWorldCheckBox)
    filterPanel.ShowWorldCheckBox = showWorldCheckBox
    self.EditorShowWorldCheckBox = showWorldCheckBox

    local showPointDistancesCheckBox = vgui.Create("DCheckBoxLabel", filterPanel)
    showPointDistancesCheckBox:SetText("Show Point Distances")
    showPointDistancesCheckBox:SetValue(cookie.GetString(EDITOR_COOKIE_SHOW_POINT_DISTANCES, "1") ~= "0" and 1 or 0)
    showPointDistancesCheckBox.OnChange = function(_, checked)
        cookie.Set(EDITOR_COOKIE_SHOW_POINT_DISTANCES, checked and "1" or "0")
        self.editorInfoSignature = nil
        self:RefreshEditorInfo(true)
    end
    styleEditorCheckBox(showPointDistancesCheckBox)
    filterPanel.ShowPointDistancesCheckBox = showPointDistancesCheckBox
    self.EditorShowPointDistancesCheckBox = showPointDistancesCheckBox

    local showPointAnglesCheckBox = vgui.Create("DCheckBoxLabel", filterPanel)
    showPointAnglesCheckBox:SetText("Show Point Angles")
    showPointAnglesCheckBox:SetValue(cookie.GetString(EDITOR_COOKIE_SHOW_POINT_ANGLES, "1") ~= "0" and 1 or 0)
    showPointAnglesCheckBox.OnChange = function(_, checked)
        cookie.Set(EDITOR_COOKIE_SHOW_POINT_ANGLES, checked and "1" or "0")
        self.editorInfoSignature = nil
        self:RefreshEditorInfo(true)
    end
    styleEditorCheckBox(showPointAnglesCheckBox)
    filterPanel.ShowPointAnglesCheckBox = showPointAnglesCheckBox
    self.EditorShowPointAnglesCheckBox = showPointAnglesCheckBox

    local variableNameHeader = vgui.Create("DLabel", variablesCard)
    variableNameHeader:SetFont("MagicAlignEditorCaption")
    variableNameHeader:SetText("Variable")
    variableNameHeader:SetTextColor(getEditorPalette().textMuted)
    frame.VariableNameHeader = variableNameHeader
    self.EditorVariableNameHeader = variableNameHeader

    local variableValueHeader = vgui.Create("DLabel", variablesCard)
    variableValueHeader:SetFont("MagicAlignEditorCaption")
    variableValueHeader:SetText("Value")
    variableValueHeader:SetTextColor(getEditorPalette().textMuted)
    frame.VariableValueHeader = variableValueHeader
    self.EditorVariableValueHeader = variableValueHeader

    local variablesScroll = vgui.Create("DScrollPanel", variablesCard)
    styleEditorScrollBar(variablesScroll:GetVBar())
    frame.VariablesScroll = variablesScroll
    self.EditorVariablesScroll = variablesScroll

    local variablesEmptyLabel = vgui.Create("DLabel", variablesScroll:GetCanvas())
    variablesEmptyLabel:SetFont("MagicAlignEditorBody")
    variablesEmptyLabel:SetWrap(true)
    variablesEmptyLabel:SetAutoStretchVertical(true)
    variablesEmptyLabel:SetTextColor(getEditorPalette().textMuted)
    variablesEmptyLabel:SetText("No environment variables are currently registered.")
    variablesEmptyLabel:Dock(TOP)
    variablesEmptyLabel:DockMargin(0, 0, 0, 6)
    frame.VariablesEmptyLabel = variablesEmptyLabel
    self.EditorVariablesEmptyLabel = variablesEmptyLabel

    self.EditorFrame = frame
    self.EditorEntry = entry
    M.ActiveExpressionEditorFrame = frame
    M.ActiveExpressionEditorOwner = self
    self.editorNextRefreshAt = 0
    self:UpdateTextAreaTooltip()
    self:RefreshEditorInfo(true)
    self:SyncEditorText(self.TextArea:GetText())
    entry:RequestFocus()
    entry:SetCaretPos(#entry:GetText())
end

function PANEL:PollTextAreaDoubleClick()
    self:EnsureRuntimeState()

    if not IsValid(self.TextArea) then
        return
    end

    local isDown = input.IsMouseDown(MOUSE_LEFT)
    local hovered = self.TextArea:IsHovered()
    local lastClickTime = tonumber(self.lastTextClickTime) or 0

    if isDown and not self.textMouseWasDown and hovered then
        local now = SysTime()
        if lastClickTime > 0 and now - lastClickTime <= DOUBLE_CLICK_WINDOW then
            self.lastTextClickTime = 0
            self:OpenExpressionEditor()
        else
            self.lastTextClickTime = now
        end
    elseif not isDown and lastClickTime > 0 and SysTime() - lastClickTime > DOUBLE_CLICK_WINDOW then
        self.lastTextClickTime = 0
    end

    self.textMouseWasDown = isDown
end

function PANEL:PaintTextEntry(textarea, w, h)
    local palette = getEditorPalette()
    local background = theme.input
    local border = palette.inputBorder
    local textColor = textarea:GetTextColor() or palette.text

    if self:IsFormulaLocked() then
        background = theme.inputFormula
    elseif textarea:IsHovered() then
        background = theme.inputFocus
    end

    if textarea:HasFocus() then
        background = self:IsFormulaLocked() and theme.inputFormula or theme.inputFocus
    end

    if self.validationState == "invalid" then
        background = theme.inputInvalid
        border = theme.inputBorderInvalid
        textColor = theme.textInvalid
    end

    draw.RoundedBox(8, 0, 0, w, h, background)
    surface.SetDrawColor(border)
    surface.DrawOutlinedRect(0, 0, w, h, 1)
    if textarea:HasFocus() and self.validationState ~= "invalid" then
        surface.SetDrawColor(palette.accent)
        surface.DrawRect(1, math.max(h - 3, 1), math.max(w - 2, 0), 3)
    end
    textarea:DrawTextEntryText(textColor, textColor, textColor)
end

function PANEL:PaintEditorTextEntry(textarea, w, h)
    paintEditorEntry(textarea, w, h, self.validationState == "invalid")
end

function PANEL:SetValidationState(state, message)
    self.validationState = state or "ok"
    self.validationMessage = message
    self:UpdateFormulaResultLabel()
    self:UpdateTextAreaTooltip()
end

function PANEL:SetDisplayedText(text)
    if not IsValid(self.TextArea) then return end

    text = tostring(text or "")
    self.updatingText = true
    setTextEntryValue(self.TextArea, text)
    self.updatingText = false
    self:SyncEditorText(text, "main")
    self:UpdateFormulaLockState()
    self:RefreshEditorInfo()
    self:UpdateFloatingTextAreaBounds()
end

function PANEL:HandleDisplayRoundingChange(force)
    local current = M.GetDisplayRounding()
    if not force and self.lastDisplayRounding == current then
        return
    end

    self.lastDisplayRounding = current

    if not self:IsEditing() and (self.storedText == nil or self.storedText == "") then
        self:SetDisplayedText(self:FormatDisplayValue(self:GetValue(), "text"))
    else
        self.editorInfoSignature = nil
        self:RefreshEditorInfo(true)
    end

    self:UpdateFormulaResultLabel()
end

function PANEL:FormatDisplayValue(value, source)
    return M.FormatDisplayNumber(value, M.GetDisplayRounding(), {
        fallback = M.DEFAULT_DISPLAY_ROUNDING
    })
end

function PANEL:FormatConVarValue(value, source, meta)
    if meta and meta.convarText then
        return tostring(meta.convarText)
    end

    local decimals = self:GetInputDecimals(source)
    if source == "text" and decimals == nil then
        return M.FormatConVarNumber(value)
    end

    if decimals == nil then
        return M.FormatConVarNumber(value)
    end

    return M.FormatFixedNumber(value, decimals, true)
end

function PANEL:ShouldClampValue(source)
    return source == "slider" or source == "label" or source == "api"
end

function PANEL:GetSliderFractionForValue(value)
    local range = math.max(self:GetRange(), 1e-9)
    return math.Clamp(((tonumber(value) or 0) - self:GetMin()) / range, 0, 1)
end

function PANEL:NormalizeValue(value, source)
    value = tonumber(value) or 0

    local snap = self:GetInputSnap(source, value)
    if snap then
        value = math.Round(value / snap) * snap
    end

    local decimals = self:GetInputDecimals(source)
    if decimals ~= nil then
        value = math.Round(value, decimals)
    end

    if self:ShouldClampValue(source) then
        value = math.Clamp(value, self:GetMin(), self:GetMax())
    end

    return value
end

function PANEL:UpdateBoundConVar(value, source, meta)
    local cvar = self:GetConVar()
    if not cvar or cvar == "" then return end

    if source == "external" then
        return
    end

    local manager = self:GetFormulaManager()
    if manager then
        manager:RegisterConVar(cvar)

        local snapshot
        if source == "text" then
            snapshot = manager:ApplyTextCommit(cvar, meta or {})
        elseif not (meta and meta.skipConVar) then
            snapshot = manager:ApplyDirectValue(cvar, value, self:FormatConVarValue(value, source, meta))
        end

        if snapshot then
            self.lastManagerRevision = snapshot.revision
            self:SyncStoredStateFromManager(snapshot)
        end

        return snapshot
    end
end

function PANEL:ApplyValue(value, source, meta)
    source = source or "external"
    meta = meta or {}

    local skipNormalization = meta.skipNormalization or source == "external"
    local applied = skipNormalization and (tonumber(value) or 0) or self:NormalizeValue(value, source)
    self.Scratch:SetFloatValue(applied)
    self.Slider:SetSlideX(self:GetSliderFractionForValue(applied))

    if source ~= "external" then
        self:UpdateBoundConVar(applied, source, meta)
    end

    self:SyncStoredStateFromManager()

    if source == "external" then
        local keepStored = self.storedText ~= nil
            and self.storedNumericValue ~= nil
            and nearlyEqual(applied, self.storedNumericValue)

        if keepStored then
            self:SetDisplayedText(self.storedText)
        else
            self:SetDisplayedText(meta.displayText or self:FormatDisplayValue(applied, "text"))
        end

        self:SetValidationState(meta.validationState or "ok", meta.validationMessage)
    elseif source == "text" then
        self:SetValidationState(meta.validationState or "ok", meta.validationMessage)

        if self.storedText ~= nil and self.storedText ~= "" then
            self:SetDisplayedText(meta.displayText or self.storedText)
        else
            self:SetDisplayedText(meta.displayText or self:FormatDisplayValue(applied, "text"))
        end
    else
        local displayText = meta.displayText or self:FormatDisplayValue(applied, source)
        if self.storedText ~= nil and self.storedText ~= "" then
            self:SetDisplayedText(self.storedText)
        else
            self:SetDisplayedText(displayText)
        end
        self:SetValidationState("ok")
    end

    self:OnValueChanged(applied)
    self:SetCookie("slider_val", applied)

    return applied
end

function PANEL:HandleTextChanged(text)
    if self.updatingText then return end

    text = tostring(text or "")

    if isTransitionalExpressionText(text) then
        self:SetValidationState("ok")
    else
        local commit = self:BuildTextCommit(text)
        if commit.ok then
            self:SetValidationState(commit.validationState or "ok", commit.validationMessage)
        else
            self:SetValidationState("invalid", commit.error or "Expression could not be evaluated")
        end
    end

    self:UpdateFormulaLockState()
end

function PANEL:BuildTextCommit(text)
    local manager = self:GetFormulaManager()
    if manager then
        return manager:BuildTextCommit(self:GetConVar(), text, self, nil, self:GetValue())
    end

    return {
        ok = false,
        error = "Formula manager is unavailable"
    }
end

function PANEL:CommitText(text)
    if self.updatingText then return end

    local commit = self:BuildTextCommit(text)
    if not commit.ok then
        self:SetDisplayedText(text)
        self:SetValidationState("invalid", commit.error)
        return false
    end

    self:ApplyValue(commit.value, "text", commit)
    return true
end

function PANEL:Think()
    self:EnsureRuntimeState()

    if self:IsTextAreaFloating() and (not IsValid(self.textAreaFloatParent) or not self.textAreaFloatParent:IsVisible()) then
        self:CollapseTextArea()
    end

    self:PollTextAreaDoubleClick()
    self:UpdateFormulaLockState()
    self:SyncFromConVar()
    self:HandleDisplayRoundingChange(false)
    self:UpdateFloatingTextAreaBounds()
end

function PANEL:SyncFromConVar(force)
    local cvarName = self:GetConVar()
    if not cvarName or cvarName == "" then return end
    if self:IsEditing() and not force then return end

    local manager = self:GetFormulaManager()
    if not manager then
        return
    end

    manager:RegisterConVar(cvarName)
    manager:PollConVar(cvarName, force)

    local snapshot = manager:GetSnapshot(cvarName)
    if not snapshot then
        return
    end

    if not force and self.lastManagerRevision == snapshot.revision then
        return
    end

    self.lastManagerRevision = snapshot.revision
    self:ApplyFormulaSnapshot(snapshot, force)
end

function PANEL:ReevaluateFormula()
    local manager = self:GetFormulaManager()
    if not manager then
        return
    end

    manager:ReevaluateFormula(self:GetConVar())
end

function PANEL:BackgroundFormulaThink()
    self:EnsureRuntimeState()
    self:ReevaluateFormula()
end

function PANEL:SetMinMax(min, max)
    self.Scratch:SetMin(tonumber(min))
    self.Scratch:SetMax(tonumber(max))
    self:UpdateNotches()
    self:ApplyValue(self:GetValue(), "external", {
        skipConVar = true
    })
end

function PANEL:ApplySchemeSettings()
    self.Label:ApplySchemeSettings()

    local color = self.Label:GetTextStyleColor()
    if self.Label:GetTextColor() then
        color = self.Label:GetTextColor()
    end

    self.TextArea:SetTextColor(color)

    local notchColor = table.Copy(color)
    notchColor.a = 100
    self.Slider:SetNotchColor(notchColor)
end

function PANEL:SetDark(enabled)
    self.Label:SetDark(enabled)
    self:ApplySchemeSettings()
end

function PANEL:SetLayoutMetrics(metrics)
    metrics = istable(metrics) and metrics or {}
    self.layoutMetrics = table.Copy(metrics)

    local textWide = tonumber(metrics.textWide)
    if textWide ~= nil then
        self.textAreaCollapsedWidth = math.max(math.floor(textWide), 24)
    end

    self:InvalidateLayout(true)
end

function PANEL:IsTextAreaFloating()
    return self.textAreaFloating == true
end

function PANEL:GetCollapsedTextAreaWidth()
    return math.max(math.floor(tonumber(self.textAreaCollapsedWidth) or 56), 24)
end

function PANEL:GetTextAreaAnchorBounds()
    local anchor = IsValid(self.TextAreaSlot) and self.TextAreaSlot or self.TextArea
    if not IsValid(anchor) then
        return 0, 0, self:GetCollapsedTextAreaWidth(), math.max(self:GetTall() - 8, 0)
    end

    local x, y = anchor:LocalToScreen(0, 0)
    return x, y, anchor:GetWide(), anchor:GetTall()
end

function PANEL:GetExpandedTextAreaWidth()
    if not IsValid(self.TextArea) then
        return self:GetCollapsedTextAreaWidth()
    end

    local font = self.TextArea.GetFont and self.TextArea:GetFont() or "DermaDefault"
    local text = tostring(self.TextArea:GetText() or "")
    if text == "" then
        text = self:FormatDisplayValue(self:GetValue(), "text")
    end

    return math.max(24, measureTextWidth(font, text) + TEXTAREA_EXPAND_EXTRA)
end

function PANEL:UpdateFloatingTextAreaBounds()
    if not self:IsTextAreaFloating() or not IsValid(self.TextArea) then
        return
    end

    local floatParent = self.textAreaFloatParent
    if not IsValid(floatParent) then
        self:CollapseTextArea()
        return
    end

    local x, y, _, h = self:GetTextAreaAnchorBounds()
    local width = math.min(self:GetExpandedTextAreaWidth(), math.max(ScrW() - TEXTAREA_SCREEN_MARGIN * 2, 24))
    local maxX = math.max(ScrW() - TEXTAREA_SCREEN_MARGIN - width, TEXTAREA_SCREEN_MARGIN)
    local maxY = math.max(ScrH() - TEXTAREA_SCREEN_MARGIN - h, TEXTAREA_SCREEN_MARGIN)
    local screenX = math.Clamp(x, TEXTAREA_SCREEN_MARGIN, maxX)
    local screenY = math.Clamp(y, TEXTAREA_SCREEN_MARGIN, maxY)
    local localX, localY = floatParent:ScreenToLocal(screenX, screenY)

    self.TextArea:SetPos(localX, localY)
    self.TextArea:SetSize(width, h)
    self.TextArea:SetZPos(TEXTAREA_FLOAT_ZPOS)
end

function PANEL:ExpandTextArea(caretPos)
    if not IsValid(self.TextArea) then
        return
    end

    if self:IsTextAreaFloating() then
        self:UpdateFloatingTextAreaBounds()
        self.TextArea:MoveToFront()
        if vgui.GetKeyboardFocus() ~= self.TextArea then
            self.TextArea:RequestFocus()
        end
        if caretPos ~= nil then
            self.TextArea:SetCaretPos(math.Clamp(math.floor(tonumber(caretPos) or 0), 0, #self.TextArea:GetText()))
        end
        return
    end

    local floatParent = resolveTextAreaFloatParent(self)
    if not IsValid(floatParent) then
        return
    end

    self.textAreaFloating = true
    self.textAreaFloatParent = floatParent
    self.TextArea:Dock(DOCK_NONE)
    self.TextArea:SetParent(floatParent)
    registerFloatingTextOwner(self)
    self:UpdateFloatingTextAreaBounds()
    self.TextArea:MoveToFront()

    if vgui.GetKeyboardFocus() ~= self.TextArea then
        self.TextArea:RequestFocus()
        if caretPos ~= nil then
            self.TextArea:SetCaretPos(math.Clamp(math.floor(tonumber(caretPos) or 0), 0, #self.TextArea:GetText()))
        end
    end
end

function PANEL:CollapseTextArea()
    if not self:IsTextAreaFloating() or not IsValid(self.TextArea) or not IsValid(self.TextAreaSlot) then
        self.textAreaFloating = false
        self.textAreaFloatParent = nil
        unregisterFloatingTextOwner(self)
        return
    end

    self.textAreaFloating = false
    self.textAreaFloatParent = nil
    unregisterFloatingTextOwner(self)
    self.TextArea:SetParent(self.TextAreaSlot)
    self.TextArea:Dock(FILL)
    self.TextArea:SetPos(0, 0)
    self.TextArea:SetSize(self.TextAreaSlot:GetWide(), self.TextAreaSlot:GetTall())
    self:InvalidateLayout(true)
end

function PANEL:GetMin()
    return self.Scratch:GetMin()
end

function PANEL:GetMax()
    return self.Scratch:GetMax()
end

function PANEL:GetRange()
    return self:GetMax() - self:GetMin()
end

function PANEL:ResetToDefaultValue()
    if not self:GetDefaultValue() then return end
    self:SetValue(self:GetDefaultValue())
end

function PANEL:SetMin(min)
    if not min then min = 0 end

    self.Scratch:SetMin(tonumber(min))
    self:UpdateNotches()
    self:ApplyValue(self:GetValue(), "external", {
        skipConVar = true
    })
end

function PANEL:SetMax(max)
    if not max then max = 0 end

    self.Scratch:SetMax(tonumber(max))
    self:UpdateNotches()
    self:ApplyValue(self:GetValue(), "external", {
        skipConVar = true
    })
end

function PANEL:SetValue(value)
    value = math.Clamp(tonumber(value) or 0, self:GetMin(), self:GetMax())
    self:ApplyValue(value, "api", {
        skipNormalization = true
    })
end

function PANEL:GetValue()
    return self.Scratch:GetFloatValue()
end

function PANEL:SetDecimals(decimals)
    self.m_iDefaultDecimals = sanitizeDecimals(decimals) or 0
    self.channelSettings = copySettings(self.m_iDefaultDecimals)
    self:PrepareScratch()
    self:UpdateNotches()
    self:ApplyValue(self:GetValue(), "external", {
        skipConVar = true
    })
end

function PANEL:GetDecimals()
    return self.Scratch:GetDecimals()
end

function PANEL:IsEditing()
    return self.Scratch:IsEditing()
        or self.TextArea:IsEditing()
        or self.Slider:IsEditing()
        or (IsValid(self.EditorEntry) and self.EditorEntry:IsEditing())
end

function PANEL:IsHovered()
    return self.Scratch:IsHovered() or self.TextArea:IsHovered() or self.Slider:IsHovered() or vgui.GetHoveredPanel() == self
end

function PANEL:PerformLayout()
    local metrics = self.layoutMetrics or {}
    local labelWide = tonumber(metrics.labelWide)
    local labelMarginRight = tonumber(metrics.labelMarginRight)
    local textMarginLeft = tonumber(metrics.textMarginLeft)

    self.Label:SetWide(math.max(math.floor(labelWide or (self:GetWide() / 2.4)), 0))
    self.Label:DockMargin(0, 0, math.max(math.floor(labelMarginRight or 0), 0), 0)

    if IsValid(self.TextAreaSlot) then
        self.TextAreaSlot:SetWide(self:GetCollapsedTextAreaWidth())
        self.TextAreaSlot:DockMargin(math.max(math.floor(textMarginLeft or 0), 0), 4, 0, 4)
    elseif IsValid(self.TextArea) and not self:IsTextAreaFloating() then
        self.TextArea:SetWide(self:GetCollapsedTextAreaWidth())
        self.TextArea:DockMargin(math.max(math.floor(textMarginLeft or 0), 0), 4, 0, 4)
    end

    if IsValid(self.CenterSlot) then
        self.CenterSlot:InvalidateLayout(true)
    end
end

function PANEL:SetText(text)
    self.Label:SetText(text)
end

function PANEL:GetText()
    return self.Label:GetText()
end

function PANEL:OnValueChanged(value)
end

function PANEL:TranslateSliderValues(x, y)
    local value = self:GetMin() + x * (self:GetMax() - self:GetMin())
    local applied = self:ApplyValue(value, "slider")

    local range = math.max(self:GetRange(), 1e-9)
    return math.Clamp((applied - self:GetMin()) / range, 0, 1), y
end

function PANEL:GetTextArea()
    return self.TextArea
end

function PANEL:UpdateNotches()
    local range = self:GetRange()
    self.Slider:SetNotches(nil)

    if range < self:GetWide() / 4 then
        return self.Slider:SetNotches(range)
    end

    self.Slider:SetNotches(self:GetWide() / 4)
end

function PANEL:OnRemove()
    if M.ActiveExpressionEditorOwner == self then
        M.ActiveExpressionEditorOwner = nil
        M.ActiveExpressionEditorFrame = nil
    end

    if IsValid(self.EditorFrame) then
        self.EditorFrame:Remove()
    end

    unregisterFloatingTextOwner(self)
    if self:IsTextAreaFloating() and IsValid(self.TextArea) then
        self.TextArea:Remove()
    end
end

function PANEL:SetEnabled(enabled)
    self.TextArea:SetEnabled(enabled)
    self.Slider:SetEnabled(enabled)
    self.Scratch:SetEnabled(enabled)
    self.Label:SetEnabled(enabled)
    FindMetaTable("Panel").SetEnabled(self, enabled)
end

function PANEL:LoadCookies()
    self:ApplyValue(self:GetCookie("slider_val"), "external", {
        skipConVar = true
    })
end

function PANEL:GenerateExample(className, propertySheet)
    local control = vgui.Create(className)
    control:SetWide(200)
    control:SetMin(1)
    control:SetMax(10)
    control:SetText("Example Slider")
    control:SetDecimals(0)

    propertySheet:AddSheet(className, control, nil, true, true)
end

function PANEL:PostMessage(name, _, value)
    if name == "SetInteger" then
        if value == "1" then
            self:SetDecimals(0)
        else
            self:SetDecimals(2)
        end
    elseif name == "SetLower" then
        self:SetMin(tonumber(value))
    elseif name == "SetHigher" then
        self:SetMax(tonumber(value))
    elseif name == "SetValue" then
        self:SetValue(tonumber(value))
    end
end

function PANEL:SetActionFunction(func)
    self.OnValueChanged = function(panel, value)
        func(panel, "SliderMoved", value, 0)
    end
end

PANEL.AllowAutoRefresh = true

local controlDescription = "DNumSlider with per-input precision, snapping and expression-aware text entry"

derma.DefineControl("DMagicAlignNumSlider", controlDescription, table.Copy(PANEL), "Panel")
derma.DefineControl("DMagicAlignNumSliders", controlDescription, table.Copy(PANEL), "Panel")

return PANEL
