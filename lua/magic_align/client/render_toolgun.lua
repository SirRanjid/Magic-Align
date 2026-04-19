MAGIC_ALIGN = MAGIC_ALIGN or include("autorun/magic_align.lua")

local M = MAGIC_ALIGN
local VectorP = M.VectorP
local isvector = M.IsVectorLike
local client = M.Client or {}
local FormulaManager = M.FormulaManager or include("magic_align/client/formula_manager.lua")
local colors = client.colors or {}
local menuColors = client.menuColors or {}
local activeTool = client.activeTool
local isWorldTarget = M.IsWorldTarget
local spaceLabels = client.spaceLabels or {}

local MICRO_UNIT = "\194\181"
local DEGREE_UNIT = "\194\176"
local VALUE_FONT_PREFIX = "MagicAlignToolgunValue"
local VALUE_FONT_SIZES = { 64, 58, 52, 46, 40, 34, 30, 26, 22, 18, 16 }
local fontsReady = false

local palette = {
    bg = menuColors.panelSoft or Color(243, 243, 243),
    shell = menuColors.panel or Color(232, 232, 232),
    card = menuColors.inputFocus or Color(255, 255, 255),
    cardSoft = menuColors.input or Color(247, 247, 247),
    border = menuColors.border or Color(138, 138, 138),
    text = menuColors.text or Color(18, 18, 18),
    textMuted = menuColors.textMuted or Color(118, 118, 118),
    idle = colors.preview or Color(80, 240, 255),
    sheen = Color(255, 255, 255, 55),
    shadow = Color(0, 0, 0, 18)
}

local function solid(color, fallback)
    color = color or fallback
    return Color(color.r, color.g, color.b, 255)
end

local handleAccent = {
    x = solid(colors.x, Color(255, 100, 100)),
    y = solid(colors.y, Color(120, 255, 120)),
    z = solid(colors.z, Color(120, 160, 255)),
    xy = solid(colors.xy, Color(255, 210, 80)),
    xz = solid(colors.xz, Color(255, 130, 210)),
    yz = solid(colors.yz, Color(110, 240, 255)),
    pitch = solid(colors.y, Color(120, 255, 120)),
    yaw = solid(colors.z, Color(120, 160, 255)),
    roll = solid(colors.x, Color(255, 100, 100))
}

local handleNames = {
    x = "X",
    y = "Y",
    z = "Z",
    xy = "XY",
    xz = "XZ",
    yz = "YZ",
    pitch = "Pitch",
    yaw = "Yaw",
    roll = "Roll"
}

local panelAccent = {
    prop1 = solid(colors.source, Color(255, 190, 80)),
    prop2 = solid(colors.target, Color(80, 220, 255))
}
local footerTabAccent = {
    prop1 = panelAccent.prop1,
    prop2 = panelAccent.prop2,
    points = solid(colors.preview, Color(80, 240, 255)),
    world = solid(menuColors.tabActiveLine, Color(94, 94, 94))
}
local pointCountColor = Color(46, 148, 84)
local missingPropColor = Color(150, 150, 150)

local sliderColors = {
    px = handleAccent.x,
    py = handleAccent.y,
    pz = handleAccent.z,
    pitch = handleAccent.pitch,
    yaw = handleAccent.yaw,
    roll = handleAccent.roll
}

local sliderLabels = {
    px = "Pos X",
    py = "Pos Y",
    pz = "Pos Z",
    pitch = "Pitch",
    yaw = "Yaw",
    roll = "Roll"
}

local translationFallback = {
    x = { "px" },
    y = { "py" },
    z = { "pz" },
    xy = { "px", "py" },
    xz = { "px", "pz" },
    yz = { "py", "pz" }
}

local gizmoFormulaKeys = {
    move = {
        x = { "px" },
        y = { "py" },
        z = { "pz" }
    },
    plane = {
        xy = { "px", "py" },
        xz = { "px", "pz" },
        yz = { "py", "pz" }
    },
    rot = {
        roll = { "roll" },
        pitch = { "pitch" },
        yaw = { "yaw" }
    }
}

local function colorAlpha(color, alpha)
    return Color(color.r, color.g, color.b, alpha)
end

local function commitUploadProgress()
    local upload = M.CommitUpload
    if not istable(upload) or upload.finishedAt then return end

    return math.Clamp(tonumber(upload.progress) or 0, 0, 1)
end

local function luminance(color)
    return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
end

local function accentTextColor(color)
    if luminance(color) >= 170 then
        return palette.text
    end

    return Color(252, 252, 252)
end

local function clampDisplayValue(value)
    value = tonumber(value) or 0
    if math.abs(value) < 0.005 then
        return 0
    end

    return value
end

local function formatUnits(value)
    return ("%+.2f %s"):format(clampDisplayValue(value), MICRO_UNIT)
end

local function formatAngle(value)
    return ("%+.2f%s"):format(clampDisplayValue(value), DEGREE_UNIT)
end

local function ensureFonts()
    if fontsReady then return end

    surface.CreateFont("MagicAlignToolgunBrand", {
        font = "Roboto",
        size = 25,
        weight = 900,
        antialias = true,
        extended = true
    })

    surface.CreateFont("MagicAlignToolgunTitle", {
        font = "Roboto",
        size = 21,
        weight = 700,
        antialias = true,
        extended = true
    })

    surface.CreateFont("MagicAlignToolgunTitleSoft", {
        font = "Roboto",
        size = 21,
        weight = 500,
        antialias = true,
        extended = true
    })

    surface.CreateFont("MagicAlignToolgunBody", {
        font = "Roboto",
        size = 18,
        weight = 550,
        antialias = true,
        extended = true
    })

    surface.CreateFont("MagicAlignToolgunChip", {
        font = "Roboto",
        size = 18,
        weight = 700,
        antialias = true,
        extended = true
    })

    surface.CreateFont("MagicAlignToolgunCaption", {
        font = "Roboto",
        size = 18,
        weight = 600,
        antialias = true,
        extended = true
    })

    surface.CreateFont("MagicAlignToolgunStatus", {
        font = "Roboto",
        size = 18,
        weight = 600,
        antialias = true,
        extended = true
    })

    surface.CreateFont("MagicAlignToolgunTab", {
        font = "Roboto",
        size = 14,
        weight = 700,
        antialias = true,
        extended = true
    })

    for _, size in ipairs(VALUE_FONT_SIZES) do
        surface.CreateFont(VALUE_FONT_PREFIX .. size, {
            font = "Roboto",
            size = size,
            weight = size >= 42 and 800 or 700,
            antialias = true,
            extended = true
        })
    end

    fontsReady = true
end

local function widestText(font, texts)
    surface.SetFont(font)

    local widest = 0
    for i = 1, #texts do
        local width = select(1, surface.GetTextSize(texts[i]))
        widest = math.max(widest, width)
    end

    return widest
end

local function pickValueFont(texts, maxWidth, maxHeight)
    ensureFonts()
    maxHeight = maxHeight or VALUE_FONT_SIZES[1]

    for _, size in ipairs(VALUE_FONT_SIZES) do
        local font = VALUE_FONT_PREFIX .. size
        if size <= maxHeight and widestText(font, texts) <= maxWidth then
            return font
        end
    end

    return VALUE_FONT_PREFIX .. VALUE_FONT_SIZES[#VALUE_FONT_SIZES]
end

local function drawChip(x, y, text, accent)
    surface.SetFont("MagicAlignToolgunChip")
    local textWidth, textHeight = surface.GetTextSize(text)
    local width = textWidth + 20
    local height = textHeight + 10

    draw.RoundedBox(8, x, y, width, height, accent)
    draw.SimpleText(text, "MagicAlignToolgunChip", x + width * 0.5, y + height * 0.5, accentTextColor(accent), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    return width, height
end

local function chipWidth(text)
    surface.SetFont("MagicAlignToolgunChip")
    local textWidth = select(1, surface.GetTextSize(text))
    return textWidth + 20
end

local function footerRect(width, height)
    local footerHeight = 20
    return 20, height - footerHeight - 14, width - 40, footerHeight
end

local function contentRect(width, height)
    local footerX, footerY, footerW = footerRect(width, height)
    return footerX, 80, footerW, math.max(footerY - 92, 40)
end

local function drawBackdrop(width, height, accent)
    accent = accent or palette.idle

    surface.SetDrawColor(palette.bg)
    surface.DrawRect(0, 0, width, height)

    draw.RoundedBox(18, 8, 8, width - 16, height - 16, palette.shell)
    draw.RoundedBox(14, 16, 16, width - 32, height - 32, palette.cardSoft)

    local topBarX = 16
    local topBarY = 16
    local topBarW = width - 32
    local topBarH = 6

    surface.SetDrawColor(colorAlpha(accent, 165))
    surface.DrawRect(topBarX, topBarY, topBarW, topBarH)

    local uploadProgress = commitUploadProgress()
    if uploadProgress then
        local covered = math.floor(topBarW * (1 - uploadProgress))
        if covered > 0 then
            surface.SetDrawColor(colorAlpha(panelAccent.prop1, 178))
            surface.DrawRect(topBarX + topBarW - covered, topBarY, covered, topBarH)
        end
    end

    surface.SetDrawColor(palette.border)
    surface.DrawOutlinedRect(8, 8, width - 16, height - 16, 1)
    surface.DrawOutlinedRect(16, 16, width - 32, height - 32, 1)

    for index = 0, 4 do
        local x = 26 + index * 34
        surface.SetDrawColor(colorAlpha(palette.sheen, 22))
        surface.DrawLine(x, 22, x + 46, height - 22)
    end
end

local function drawValueCards(width, height, items)
    local margin = 24
    local gap = 8
    local top = 86
    local _, footerY = footerRect(width, height)
    local availableHeight = math.max(footerY - top - 8, 56)
    local cardWidth = width - margin * 2
    local count = math.max(#items, 1)
    local cardHeight = math.floor((availableHeight - gap * (count - 1)) / count)
    local valueFont = pickValueFont((function()
        local texts = {}
        for i = 1, #items do
            texts[i] = items[i].value
        end
        return texts
    end)(), cardWidth - 30, math.max(cardHeight * 0.52, VALUE_FONT_SIZES[#VALUE_FONT_SIZES]))

    for index = 1, #items do
        local item = items[index]
        local y = top + (index - 1) * (cardHeight + gap)
        local itemValueFont = item.valueFont or valueFont

        draw.RoundedBox(12, margin, y, cardWidth, cardHeight, palette.card)
        draw.RoundedBox(12, margin, y, 8, cardHeight, item.accent or palette.idle)
        surface.SetDrawColor(colorAlpha(palette.shadow, 10))
        surface.DrawOutlinedRect(margin, y, cardWidth, cardHeight, 1)

        draw.SimpleText(item.label, "MagicAlignToolgunCaption", margin + 18, y + 14, palette.textMuted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText(item.value, itemValueFont, margin + cardWidth * 0.5, y + cardHeight * 0.62, item.valueColor or palette.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end

local function drawCompass(cx, cy, radius, angle, accent)
    draw.NoTexture()
    surface.SetDrawColor(colorAlpha(palette.border, 160))
    for step = 0, 35 do
        local a0 = math.rad(step * 10)
        local a1 = math.rad((step + 1) * 10)
        surface.DrawLine(
            cx + math.cos(a0) * radius,
            cy + math.sin(a0) * radius,
            cx + math.cos(a1) * radius,
            cy + math.sin(a1) * radius
        )
    end

    surface.SetDrawColor(colorAlpha(palette.textMuted, 120))
    surface.DrawLine(cx, cy - radius, cx, cy - radius + 5)
    surface.DrawLine(cx, cy + radius - 5, cx, cy + radius)
    surface.DrawLine(cx - radius, cy, cx - radius + 5, cy)
    surface.DrawLine(cx + radius - 5, cy, cx + radius, cy)

    local dirX = math.sin(angle)
    local dirY = -math.cos(angle)
    local tipX = cx + dirX * (radius - 1)
    local tipY = cy + dirY * (radius - 1)
    local backX = cx - dirX * 3
    local backY = cy - dirY * 3
    local sideX = -dirY * 4
    local sideY = dirX * 4

    surface.SetDrawColor(accent)
    surface.DrawPoly({
        { x = tipX, y = tipY },
        { x = backX + sideX, y = backY + sideY },
        { x = backX - sideX, y = backY - sideY }
    })

    draw.NoTexture()
    surface.SetDrawColor(palette.card)
    surface.DrawRect(cx - 1, cy - 1, 2, 2)
end

local function compassAngle(ent)
    if not IsValid(ent) then return end

    local player = LocalPlayer()
    if not IsValid(player) then return end

    local yaw = (player:GetPos() - ent:GetPos()):Angle().y - player:EyeAngles().y

    if not isnumber(yaw) then
        return 0
    end

    return math.rad(-(yaw + 180))
end

local function currentSpace(tool, state, data)
    local space = data and data.space or tool:GetClientInfo("space")
    if not space or space == "" then
        space = state and state.press and state.press.space or "points"
    end

    return space
end

local function drawFooter(width, height, tool, state, data)
    local spaces = M.SPACES or { "prop1", "prop2", "points", "world" }
    if not istable(spaces) or #spaces == 0 then return end

    local activeSpace = currentSpace(tool, state, data)
    local x, y, w, h = footerRect(width, height)
    local gap = 3
    local tabWidth = math.floor((w - gap * (#spaces - 1)) / #spaces)
    local remainder = w - tabWidth * #spaces - gap * (#spaces - 1)
    local tabX = x
    local stripColor = menuColors.tabStrip or palette.shell
    local borderColor = menuColors.border or palette.border

    draw.RoundedBoxEx(6, x, y, w, h, stripColor, true, true, false, false)
    surface.SetDrawColor(colorAlpha(borderColor, 180))
    surface.DrawOutlinedRect(x, y, w, h, 1)

    for i = 1, #spaces do
        local space = spaces[i]
        local tabW = tabWidth + (i == #spaces and remainder or 0)
        local active = space == activeSpace
        local bg = active and (menuColors.tabActive or palette.card) or (menuColors.tabIdle or palette.shell)
        local textColor = active and palette.text or palette.textMuted

        draw.RoundedBoxEx(6, tabX, y, tabW, h, bg, true, true, false, false)
        surface.SetDrawColor(colorAlpha(borderColor, active and 170 or 130))
        surface.DrawOutlinedRect(tabX, y, tabW, h - 1, 1)

        if active then
            surface.SetDrawColor(footerTabAccent[space] or menuColors.tabActiveLine or palette.text)
            surface.DrawRect(tabX + 1, y + h - 3, math.max(tabW - 2, 0), 3)
        end

        draw.SimpleText(spaceLabels[space] or tostring(space), "MagicAlignToolgunTab", tabX + tabW * 0.5, y + h * 0.48, textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        tabX = tabX + tabW + gap
    end
end

local function pointCountText(count)
    count = math.max(math.floor(tonumber(count) or 0), 0)
    if count <= 0 then
        return "0 Points"
    end
    if count == 1 then
        return "1 Point"
    end
    if count == 2 then
        return "2-Point Axis"
    end

    return "3-Point Plane"
end

local function linkedCountText(count, maxCount)
    count = math.max(math.floor(tonumber(count) or 0), 0)
    maxCount = math.max(math.floor(tonumber(maxCount) or M.DEFAULT_MAX_LINKED_PROPS or 0), 0)
    return ("[%d/%d]"):format(count, maxCount)
end

local function blendColor(fromColor, toColor, t)
    t = math.Clamp(tonumber(t) or 0, 0, 1)

    return Color(
        math.Round(Lerp(t, fromColor.r, toColor.r)),
        math.Round(Lerp(t, fromColor.g, toColor.g)),
        math.Round(Lerp(t, fromColor.b, toColor.b)),
        math.Round(Lerp(t, fromColor.a or 255, toColor.a or 255))
    )
end

local function linkedCountColor(count, maxCount)
    local ratio = 0
    maxCount = math.max(tonumber(maxCount) or 0, 0)
    if maxCount > 0 then
        ratio = math.Clamp((tonumber(count) or 0) / maxCount, 0, 1)
    end

    local alpha = math.Round(Lerp(ratio, 255 * 0.10, 255 * 0.62))
    local dark = Color(22, 22, 22, alpha)
    local warn = Color(156, 142, 88, alpha)
    local hot = Color(166, 92, 86, alpha)

    if ratio <= 0.5 then
        return blendColor(dark, warn, ratio / 0.5)
    end

    return blendColor(warn, hot, (ratio - 0.5) / 0.5)
end

local function drawLinkedCountInline(x, y, h, label, count, maxCount)
    local text = linkedCountText(count, maxCount)
    local color = linkedCountColor(count, maxCount)

    surface.SetFont("MagicAlignToolgunTitleSoft")

    local labelWidth = select(1, surface.GetTextSize(label))
    local textX = x + 18 + labelWidth + 8
    local lineY = y + h * 0.34

    draw.SimpleText(text, "MagicAlignToolgunTitleSoft", textX, lineY, color, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

local function drawCompassPanel(x, y, w, h, label, ent, accent, pointCount)
    draw.RoundedBox(12, x, y, w, h, palette.card)
    draw.RoundedBox(12, x, y, 8, h, colorAlpha(accent, 220))
    surface.SetDrawColor(colorAlpha(palette.border, 105))
    surface.DrawOutlinedRect(x, y, w, h, 1)

    local compassX = x + w - 28
    draw.SimpleText(label, "MagicAlignToolgunTitle", x + 18, y + h * 0.34, palette.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

    if IsValid(ent) then
        draw.SimpleText(pointCountText(pointCount), "MagicAlignToolgunStatus", x + 18, y + h * 0.68, pointCountColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    elseif isWorldTarget and isWorldTarget(ent) then
        draw.SimpleText(pointCountText(pointCount), "MagicAlignToolgunStatus", x + 18, y + h * 0.68, pointCountColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    else
        draw.SimpleText("No Prop Selected", "MagicAlignToolgunCaption", x + 18, y + h * 0.68, missingPropColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local angle = isWorldTarget and isWorldTarget(ent) and 0 or compassAngle(ent)
    if angle then
        drawCompass(compassX, y + h * 0.5, 14, angle, accent)
    end
end

local function drawIdleCompasses(width, height, state)
    local x, y, w, h = contentRect(width, height)
    local gap = 10
    local panelHeight = 56
    local totalHeight = panelHeight * 2 + gap
    local startY = y + math.max((h - totalHeight) * 0.5, 0)

    drawCompassPanel(
        x,
        startY,
        w,
        panelHeight,
        spaceLabels.prop1 or "Prop 1",
        state and state.prop1 or nil,
        panelAccent.prop1 or palette.idle,
        state and istable(state.source) and #state.source or 0
    )
    drawLinkedCountInline(
        x,
        startY,
        panelHeight,
        spaceLabels.prop1 or "Prop 1",
        state and istable(state.linked) and #state.linked or 0,
        M.GetMaxLinkedProps()
    )
    drawCompassPanel(
        x,
        startY + panelHeight + gap,
        w,
        panelHeight,
        spaceLabels.prop2 or "Prop 2",
        state and state.prop2 or nil,
        panelAccent.prop2 or palette.idle,
        state and istable(state.target) and #state.target or 0
    )
end

local function formulaSnapshotFor(cvarName)
    if not FormulaManager or not cvarName or cvarName == "" then
        return nil
    end

    FormulaManager:RegisterConVar(cvarName)

    local snapshot = FormulaManager:GetSnapshot(cvarName)
    if snapshot and snapshot.rawMode == "formula" then
        return snapshot
    end

    return nil
end

local function lockedFormulaKeysForPress(press)
    if not press or press.kind ~= "gizmo" or not press.gizmo or not press.space then
        return nil
    end

    local byKind = gizmoFormulaKeys[press.gizmo.kind]
    local keys = byKind and byKind[press.gizmo.key]
    if press.gizmo.kind ~= "rot" and isvector(press.referenceDelta) then
        keys = {}
        if math.abs(press.referenceDelta.x) > 1e-6 then keys[#keys + 1] = "px" end
        if math.abs(press.referenceDelta.y) > 1e-6 then keys[#keys + 1] = "py" end
        if math.abs(press.referenceDelta.z) > 1e-6 then keys[#keys + 1] = "pz" end
        if #keys == 0 then
            keys = byKind and byKind[press.gizmo.key]
        end
    end
    if not istable(keys) then
        return nil
    end

    local locked = {}
    for index = 1, #keys do
        local key = keys[index]
        local cvarName = ("magic_align_%s_%s"):format(press.space, key)
        if formulaSnapshotFor(cvarName) then
            locked[key] = true
        end
    end

    return next(locked) and locked or nil
end

local function collectSliderItems(keys, values, formatter, lockedKeys)
    local items = {}

    for i = 1, #keys do
        local key = keys[i]
        local value = clampDisplayValue(values[key])
        local locked = istable(lockedKeys) and lockedKeys[key] == true
        if locked or math.abs(value) >= 0.005 then
            items[#items + 1] = {
                key = key,
                label = sliderLabels[key] or string.upper(key),
                value = locked and "FORMULA" or formatter(value),
                accent = sliderColors[key] or palette.idle,
                valueColor = locked and palette.textMuted or palette.text,
                valueFont = locked and "MagicAlignToolgunTab" or nil
            }
        end
    end

    return items
end

local function buildTranslationItems(press, lockedKeys)
    local delta = press.referenceDelta or VectorP(0, 0, 0)
    local values = {
        px = delta.x,
        py = delta.y,
        pz = delta.z
    }
    local items = collectSliderItems({ "px", "py", "pz" }, values, formatUnits, lockedKeys)

    if #items > 0 then
        return items
    end

    local fallback = translationFallback[press.gizmo.key] or { "px" }
    local fallbackItems = {}

    for i = 1, #fallback do
        local key = fallback[i]
        local locked = istable(lockedKeys) and lockedKeys[key] == true
        fallbackItems[#fallbackItems + 1] = {
            key = key,
            label = sliderLabels[key] or string.upper(key),
            value = locked and "formula" or formatUnits(0),
            accent = sliderColors[key] or palette.idle,
            valueColor = locked and palette.textMuted or palette.text,
            valueFont = locked and "MagicAlignToolgunTab" or nil
        }
    end

    return fallbackItems
end

local function buildRotationItems(_, press, lockedKeys)
    local key = press.gizmo and press.gizmo.key or "roll"
    local value = press.rotationDelta or 0
    local locked = istable(lockedKeys) and lockedKeys[key] == true

    return {
        {
            key = key,
            label = sliderLabels[key] or string.upper(key),
            value = locked and "formula" or formatAngle(value),
            accent = sliderColors[key] or palette.idle,
            valueColor = locked and palette.textMuted or palette.text,
            valueFont = locked and "MagicAlignToolgunTab" or nil
        }
    }
end

local function buildDisplayData(tool, state)
    local press = state and state.press
    if not press or press.kind ~= "gizmo" or not press.gizmo then
        return
    end

    local accent = handleAccent[press.gizmo.key] or palette.idle
    local lockedKeys = lockedFormulaKeysForPress(press)
    local items = press.gizmo.kind == "rot"
        and buildRotationItems(tool, press, lockedKeys)
        or buildTranslationItems(press, lockedKeys)

    return {
        accent = accent,
        title = "Reference Delta",
        handle = handleNames[press.gizmo.key] or string.upper(tostring(press.gizmo.key or "Gizmo")),
        space = press.space,
        items = items
    }
end

local function activeState(tool)
    if activeTool then
        local active, state = activeTool()
        if active == tool and state then
            return state
        end
    end

    return M.ClientState
end

function TOOL:DrawToolScreen(width, height)
    ensureFonts()

    local state = activeState(self)
    local data = buildDisplayData(self, state)
    local accent = data and data.accent or palette.idle

    drawBackdrop(width, height, accent)

    draw.SimpleText("MAGIC ALIGN", "MagicAlignToolgunBrand", 24, 30, palette.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

    if not data then
        drawIdleCompasses(width, height, state)
        drawFooter(width, height, self, state, data)
        return
    end

    draw.SimpleText(data.title, "MagicAlignToolgunTitle", 24, 58, palette.textMuted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

    local chipX = width - chipWidth(data.handle) - 24
    drawChip(chipX, 28, data.handle, data.accent)

    drawValueCards(width, height, data.items)
    drawFooter(width, height, self, state, data)
end
