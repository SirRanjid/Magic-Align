MAGIC_ALIGN = MAGIC_ALIGN or include("autorun/magic_align.lua")

local M = MAGIC_ALIGN
local client = M.Client or {}
M.Client = client

local TARGET_TOOL = "magic_align"
local TARGET_KEY = "tool.magic_align.name"
local TARGET_TEXT = "Magic Align"
local TARGET_COMMAND = "gmod_tool " .. TARGET_TOOL
local TARGET_CATEGORY = (TOOL and type(TOOL.Category) == "string" and TOOL.Category ~= "" and TOOL.Category)
    or "Construction"
local ENABLE_CVAR = "magic_align_highlight_context_menu"
local SCAN_ID = "MagicAlignMenuEntryLetterOverlay"
local TOGGLE_CALLBACK_ID = SCAN_ID .. "Toggle"
local OVERLAY_VERSION = 5
local LETTERS = {
    { prefix = "", letter = "M", color = Color(240, 167, 68), disabled = Color(240, 167, 68, 120) },
    { prefix = "Magic ", letter = "A", color = Color(82, 158, 238), disabled = Color(82, 158, 238, 120) }
}

local function resolvedText(value)
    local raw = tostring(value or "")
    if raw == "" then return "", raw end

    local key = raw == TARGET_KEY and raw or string.sub(raw, 1, 1) == "#" and string.sub(raw, 2)
    return key and language.GetPhrase(key) or raw, raw
end

local function panelText(panel)
    return resolvedText((IsValid(panel) and panel.GetText and panel:GetText()) or "")
end

local function overlayEnabled()
    local cvar = GetConVar(ENABLE_CVAR)
    return not cvar or cvar:GetBool()
end

local function categoryLabel(category)
    local label = category.GetLabel and category:GetLabel()
    if type(label) == "string" and label ~= "" then return label end

    label = IsValid(category.Header) and category.Header.GetText and category.Header:GetText()
    return type(label) == "string" and label ~= "" and label or nil
end

local function isTargetCategory(panel)
    if not IsValid(panel) then return false end

    local className = panel.GetClassName and panel:GetClassName()
    local isCategory = className == "DCollapsibleCategory"
        or (panel.SetExpanded and panel.GetExpanded and IsValid(panel.Header))
    if not isCategory then return false end

    local suffix = "." .. TARGET_CATEGORY
    local cookieName = panel.GetCookieName and panel:GetCookieName()
    if type(cookieName) == "string" and string.sub(cookieName, -#suffix) == suffix then return true end

    local label = categoryLabel(panel)
    if not label then return false end

    local labelText, labelRaw = resolvedText(label)
    local categoryText, categoryRaw = resolvedText(TARGET_CATEGORY)
    return labelRaw == categoryRaw or labelText == categoryText
end

local function isTargetEntry(panel)
    if not IsValid(panel) or panel.MagicAlignMenuEntryOverlayPart then return false end
    if panel.Name == TARGET_TOOL or panel.Command == TARGET_COMMAND then return true end

    local text, raw = panelText(panel)
    return raw == "#" .. TARGET_KEY or raw == TARGET_KEY or text == TARGET_TEXT
end

local function textInset(panel)
    if not panel.GetTextInset then return 0, 0 end

    local x, y = panel:GetTextInset()
    return tonumber(x) or 0, tonumber(y) or 0
end

local function textStartX(panel, text, font, width)
    surface.SetFont(font)

    local textWidth = surface.GetTextSize(text)
    local inset = textInset(panel)
    local align = panel.GetContentAlignment and panel:GetContentAlignment() or 4

    if align == 2 or align == 5 or align == 8 then
        return math.floor((width - textWidth) * 0.5 + inset + 0.5)
    elseif align == 3 or align == 6 or align == 9 then
        return math.floor(width - textWidth - inset + 0.5)
    end

    return math.floor(inset + 0.5)
end

local function removeOverlay(panel)
    if not IsValid(panel) then return end

    if panel.MagicAlignMenuEntryOverlay or panel.MagicAlignMenuEntryOverlayVersion then
        panel.PaintOver = panel.MagicAlignMenuEntryOldPaintOver
        panel.PerformLayout = panel.MagicAlignMenuEntryOldPerformLayout
    end

    local clips = panel.MagicAlignMenuEntryClips
    for i = 1, clips and #clips or 0 do
        if IsValid(clips[i]) then clips[i]:Remove() end
    end

    panel.MagicAlignMenuEntryClips = nil
    panel.MagicAlignMenuEntryOldPaintOver = nil
    panel.MagicAlignMenuEntryOldPerformLayout = nil
    panel.MagicAlignMenuEntryOverlay = nil
    panel.MagicAlignMenuEntryOverlayVersion = nil
end

local function createClips(panel)
    local clips = {}
    for i = 1, #LETTERS do
        local clip = vgui.Create("DPanel", panel)
        clip:SetMouseInputEnabled(false)
        clip:SetKeyboardInputEnabled(false)
        clip:SetPaintBackground(false)
        clip.Paint = function() end
        clip.MagicAlignMenuEntryOverlayPart = true

        if clip.SetPaintedManually and clip.PaintManual then
            clip:SetPaintedManually(true)
            clip.MagicAlignPaintedManually = true
        end

        local label = vgui.Create("DLabel", clip)
        label:SetMouseInputEnabled(false)
        label:SetKeyboardInputEnabled(false)
        label:SetPaintBackground(false)
        label:SetText(TARGET_TEXT)
        label.MagicAlignMenuEntryOverlayPart = true
        clip.Label = label
        clips[i] = clip
    end

    panel.MagicAlignMenuEntryClips = clips
end

local function updateClip(panel, clip, spec, text, font, textX, width, height, enabled)
    if not IsValid(clip) or not IsValid(clip.Label) then return end

    surface.SetFont(font)
    local x1 = math.floor(textX + surface.GetTextSize(spec.prefix) + 0.5)
    local x2 = math.floor(x1 + surface.GetTextSize(spec.letter) + 0.5)

    if x1 < 0 then x1 = 0 end
    if x2 > width then x2 = width end
    if x2 <= x1 then
        clip:SetVisible(false)
        return
    end

    local insetX, insetY = textInset(panel)
    local label = clip.Label

    clip:SetVisible(true)
    clip:SetPos(x1, 0)
    clip:SetSize(x2 - x1, height)
    clip:SetZPos(32767)

    label:SetText(text)
    label:SetFont(font)
    label:SetTextColor(enabled and spec.color or spec.disabled)
    label:SetContentAlignment(panel.GetContentAlignment and panel:GetContentAlignment() or 4)
    label:SetTextInset(insetX, insetY)
    label:SetPos(-x1, 0)
    label:SetSize(width, height)
end

local function syncOverlay(panel, width, height)
    local text = panelText(panel)
    local clips = panel.MagicAlignMenuEntryClips

    if text ~= TARGET_TEXT or not clips then
        for i = 1, clips and #clips or 0 do
            if IsValid(clips[i]) then clips[i]:SetVisible(false) end
        end
        return
    end

    width = width or panel:GetWide()
    height = height or panel:GetTall()

    local font = panel.GetFont and panel:GetFont() or "DermaDefault"
    local textX = textStartX(panel, text, font, width)
    local enabled = not panel.IsEnabled or panel:IsEnabled()

    for i = 1, #LETTERS do
        updateClip(panel, clips[i], LETTERS[i], text, font, textX, width, height, enabled)
    end
end

local function installOverlay(panel)
    if not overlayEnabled() then
        removeOverlay(panel)
        return
    end

    if not isTargetEntry(panel) or panel.MagicAlignMenuEntryOverlayVersion == OVERLAY_VERSION then return end

    removeOverlay(panel)
    createClips(panel)

    panel.MagicAlignMenuEntryOverlay = true
    panel.MagicAlignMenuEntryOverlayVersion = OVERLAY_VERSION
    panel.MagicAlignMenuEntryOldPaintOver = panel.PaintOver
    panel.MagicAlignMenuEntryOldPerformLayout = panel.PerformLayout

    panel.PaintOver = function(self, width, height)
        if self.MagicAlignMenuEntryOldPaintOver then
            self.MagicAlignMenuEntryOldPaintOver(self, width, height)
        end

        syncOverlay(self, width, height)

        local clips = self.MagicAlignMenuEntryClips
        for i = 1, clips and #clips or 0 do
            local clip = clips[i]
            if IsValid(clip) and clip:IsVisible() and clip.MagicAlignPaintedManually and clip.PaintManual then
                clip:PaintManual()
            end
        end
    end

    panel.PerformLayout = function(self, width, height)
        if self.MagicAlignMenuEntryOldPerformLayout then
            self.MagicAlignMenuEntryOldPerformLayout(self, width, height)
        end

        syncOverlay(self, width, height)
    end
end

local function clearPanel(panel)
    if not IsValid(panel) then return end

    removeOverlay(panel)

    local children = panel:GetChildren()
    for i = 1, #children do
        clearPanel(children[i])
    end
end

local function scanPanel(panel, inTargetCategory)
    if not IsValid(panel) then return end

    inTargetCategory = inTargetCategory or isTargetCategory(panel)
    if inTargetCategory then installOverlay(panel) end

    local children = panel:GetChildren()
    for i = 1, #children do
        scanPanel(children[i], inTargetCategory)
    end
end

local function scanKnownMenus()
    local root = IsValid(g_SpawnMenu) and g_SpawnMenu.GetToolMenu and g_SpawnMenu:GetToolMenu()
    if not IsValid(root) then return end

    if overlayEnabled() then
        scanPanel(root, false)
    else
        clearPanel(root)
    end
end

client.InstallMenuEntryLetterOverlay = scanKnownMenus

for _, hookName in ipairs({ "SpawnMenuCreated", "PostReloadToolsMenu", "OnSpawnMenuOpen" }) do
    hook.Add(hookName, SCAN_ID, function()
        timer.Simple(0, scanKnownMenus)
    end)
end

if cvars and cvars.AddChangeCallback then
    if cvars.RemoveChangeCallback then
        cvars.RemoveChangeCallback(ENABLE_CVAR, TOGGLE_CALLBACK_ID)
    end

    cvars.AddChangeCallback(ENABLE_CVAR, function()
        timer.Simple(0, scanKnownMenus)
    end, TOGGLE_CALLBACK_ID)
end

timer.Create(SCAN_ID, 1, 0, function()
    if IsValid(g_SpawnMenu) and g_SpawnMenu:IsVisible() then
        scanKnownMenus()
    end
end)
