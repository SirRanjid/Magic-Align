MAGIC_ALIGN = MAGIC_ALIGN or include("autorun/magic_align.lua")

local M = MAGIC_ALIGN
local VectorP = M.VectorP
local AngleP = M.AngleP
local isvector = M.IsVectorLike
local isangle = M.IsAngleLike
local toVector = M.ToVector
local toAngle = M.ToAngle
local LocalToWorldPosPrecise = M.LocalToWorldPosPrecise
local client = M.Client or {}
M.Client = client
local colors = client.colors or {}
local RENDER_CONFIG = {
    billboardScale = 0.035,
    billboardPush = 0.15,
    circleSegments = 40,
    ringQualityCvar = "magic_align_ring_quality",
    gridLabelPercentCvar = "magic_align_grid_label_percent",
    gridLabelReduceFractionCvar = "magic_align_grid_label_reduce_fraction",
    gridAlphaCvar = "magic_align_grid_alpha",
    previewOccludedCvar = "magic_align_preview_occluded",
    previewOccludedDefaultColor = Color(255, 179, 48, 222),
    wireframeMaterial = Material("models/wireframe")
}
local SHAPE_CONFIG = {
    cacheName = "magic_align_shape",
    rebuildHook = "magic_align_shape_rebuild",
    rebuildCallback = "magic_align_shape_quality",
    materialFlags = bit.bor(16, 32, 128, 2048, 2097152),
    rtPaddingRatio = 1 / 32,
    rtMinPadding = 8,
    ratioQuantization = 256,
    ringThicknessCompensationMax = 0.008,
    ringThicknessCompensationScale = 0.2
}
local STRIPE_CONFIG = {
    rtSize = 64,
    fillAlpha = 100,
    stripeAlpha = 200,
    stripeRatio = 0.5,
    worldTile = 5.5,
    triangleAlphaScale = 0.45,
    occludedReferenceDistance = 100,
    occludedMinScreenScale = 0.01,
    occludedMaxScreenScale = 100,
    occludedScreenParallax = 0.12,
    patternName = "magic_align_stripe_pattern",
    materialFlags = bit.bor(16, 32, 128, 2048, 2097152),
    rebuildHook = "magic_align_stripe_pattern_rebuild"
}
local GRID_CONFIG = {
    alphaPrimary = 64,
    alphaSecondary = 64,
    snapLineAlpha = 255,
    snapLabelAlpha = 235,
    snapLabelInset = 1.6
}
local TRANSLATION_CONFIG = {
    axisTickCount = 21,
    gridHalfCells = 5
}
local ROTATION_CONFIG = {
    ringDefaultSegments = 32,
    ringMinSegments = 8,
    ringMaxSegments = 360,
    ringFillAlpha = 40,
    ringEdgeAlpha = 220,
    ringMinHalfWidth = 0.05,
    deltaSectorAlpha = 76,
    deltaSectorEdgeAlpha = 170
}
client.activeTool = client.activeTool or function()
    return nil
end
client.validateState = client.validateState or function()
    return true
end
client.gizmo = client.gizmo or function()
    return nil
end
client.rotationSnapDivisions = client.rotationSnapDivisions or function()
    return 24
end
client.rotationSnapStep = client.rotationSnapStep or function(tool)
    return 360 / math.max(client.rotationSnapDivisions(tool), 1)
end
client.translationSnapStep = client.translationSnapStep or function()
    return 0
end
client.rotationSnapMaxVisibleTicks = client.rotationSnapMaxVisibleTicks or 20
client.isMajorRotationTick = client.isMajorRotationTick or function()
    return false
end
client.sampleWorldPos = client.sampleWorldPos or function(_, sample)
    return sample and sample.pos or nil
end
client.ringQualityPresets = client.ringQualityPresets or {}
client.defaultRingQualityIndex = client.defaultRingQualityIndex or 2
local circlePointCache = {}
local unitCircle
local stripePatternTexture
local stripeTrianglePatternTexture
local stripePatternMaterial
local stripeTrianglePatternMaterial
local stripePatternScreenMaterial
local stripePatternReady = false
local shapeCache = {}
local shapeMetricCache = {}
local shapeWhiteMaterial
local reusableCirclePolyCache = {}
local reusableRingQuad = {
    { x = 0, y = 0, u = 0, v = 0 },
    { x = 0, y = 0, u = 0, v = 0 },
    { x = 0, y = 0, u = 0, v = 0 },
    { x = 0, y = 0, u = 0, v = 0 }
}
local ensureStripePatternMaterial

local function setStripePatternCopyBlend(enabled)
    if render.OverrideAlphaWriteEnable then
        render.OverrideAlphaWriteEnable(enabled, true)
    end

    if render.OverrideBlend and BLEND_ONE and BLEND_ZERO and BLENDFUNC_ADD then
        if enabled then
            render.OverrideBlend(true, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD, BLEND_ONE, BLEND_ZERO, BLENDFUNC_ADD)
        else
            render.OverrideBlend(false)
        end
    end
end

local function drawStripePatternRect(intensity, x, y, width, height)
    intensity = math.Clamp(math.floor(tonumber(intensity) or 0), 0, 255)
    surface.SetDrawColor(intensity, intensity, intensity, intensity)
    surface.DrawRect(x, y, width, height)
end

local function stripePatternStripeSize()
    return math.Clamp(math.floor(STRIPE_CONFIG.rtSize * STRIPE_CONFIG.stripeRatio + 0.5), 1, STRIPE_CONFIG.rtSize)
end

local function drawStripePatternDiagonal(intensity)
    intensity = math.Clamp(math.floor(tonumber(intensity) or 0), 0, 255)
    surface.SetDrawColor(intensity, intensity, intensity, intensity)

    local size = STRIPE_CONFIG.rtSize
    local stripeSize = stripePatternStripeSize()
    for y = 0, size - 1 do
        local startX = (y - stripeSize + 1) % size
        local firstWidth = math.min(stripeSize, size - startX)
        surface.DrawRect(startX, y, firstWidth, 1)

        local wrappedWidth = stripeSize - firstWidth
        if wrappedWidth > 0 then
            surface.DrawRect(0, y, wrappedWidth, 1)
        end
    end
end

local function drawLine(startPos, endPos, color, writeZ)
    startPos = toVector(startPos)
    endPos = toVector(endPos)
    if not startPos or not endPos then return end

    render.DrawLine(startPos, endPos, color, writeZ)
end

local function drawQuad(a, b, c, d, color)
    a = toVector(a)
    b = toVector(b)
    c = toVector(c)
    d = toVector(d)
    if not a or not b or not c or not d then return end

    render.DrawQuad(a, b, c, d, color)
end

local function meshPosition(position)
    position = toVector(position)
    if not position then return end

    mesh.Position(position)
end

local renderAnchorOptionCache = {}

local function anchorOptions(tool, side)
    if not tool then return nil end

    local cache = renderAnchorOptionCache[side]
    if not cache then
        cache = { options = {} }
        renderAnchorOptionCache[side] = cache
    end

    local prefix = side
    if prefix ~= "" and not string.EndsWith(prefix, "_") then
        prefix = prefix .. "_"
    end

    local mid12 = M.ClampAnchorPercent(tool:GetClientInfo(prefix .. "mid12_pct"))
    local mid23 = M.ClampAnchorPercent(tool:GetClientInfo(prefix .. "mid23_pct"))
    local mid13 = M.ClampAnchorPercent(tool:GetClientInfo(prefix .. "mid13_pct"))

    if cache.tool ~= tool
        or cache.options.mid12_pct ~= mid12
        or cache.options.mid23_pct ~= mid23
        or cache.options.mid13_pct ~= mid13 then
        cache.tool = tool
        cache.options.mid12_pct = mid12
        cache.options.mid23_pct = mid23
        cache.options.mid13_pct = mid13
    end

    return cache.options
end

local function circlePointsForSegments(segments)
    segments = math.max(math.Round(tonumber(segments) or RENDER_CONFIG.circleSegments), 3)

    local points = circlePointCache[segments]
    if points then
        return points
    end

    points = {}
    for i = 0, segments do
        local rad = math.rad((i / segments) * 360)
        points[i + 1] = { x = math.cos(rad), y = math.sin(rad) }
    end

    circlePointCache[segments] = points
    return points
end

unitCircle = circlePointsForSegments(RENDER_CONFIG.circleSegments)

local ZERO_VEC = VectorP(0, 0, 0)
local ZERO_ANG = AngleP(0, 0, 0)

local function setVec(out, value)
    if not isvector(value) then return end

    if not isvector(out) then
        return VectorP(value.x, value.y, value.z)
    end

    out.x, out.y, out.z = value.x, value.y, value.z
    return out
end

local cachedColors = {}

local function cachedColor(r, g, b, a)
    r = math.Clamp(math.floor(tonumber(r) or 0), 0, 255)
    g = math.Clamp(math.floor(tonumber(g) or 0), 0, 255)
    b = math.Clamp(math.floor(tonumber(b) or 0), 0, 255)
    a = math.Clamp(math.floor(tonumber(a) or 255), 0, 255)

    local key = (((r * 256) + g) * 256 + b) * 256 + a
    local cached = cachedColors[key]
    if cached then
        return cached
    end

    cached = Color(r, g, b, a)
    cachedColors[key] = cached
    return cached
end

local function colorAlpha(color, alpha)
    return cachedColor(color.r, color.g, color.b, alpha == nil and color.a or alpha)
end

local function cappedAlpha(color, alpha)
    local baseAlpha = color.a == nil and 255 or color.a
    return cachedColor(color.r, color.g, color.b, math.min(baseAlpha, alpha))
end

local function scaledAlphaColor(color, scale)
    local baseAlpha = color.a == nil and 255 or color.a
    return cachedColor(color.r, color.g, color.b, math.Clamp(math.floor(baseAlpha * scale + 0.5), 0, 255))
end

local function clampUnitInterval(value)
    return math.Clamp(tonumber(value) or 0, 0, 1)
end

local function readClampedConVarInt(name, fallback, minValue, maxValue)
    local cvar = name and GetConVar(name) or nil
    local value = cvar and cvar:GetFloat() or fallback

    return math.Clamp(math.floor((tonumber(value) or fallback or 0) + 0.5), minValue or 0, maxValue or 255)
end

local function ringQualityIndex(tool)
    local raw = tool and tool.GetClientNumber and tool:GetClientNumber("ring_quality") or client.defaultRingQualityIndex
    return math.Clamp(math.Round(tonumber(raw) or client.defaultRingQualityIndex), 1, math.max(#client.ringQualityPresets, 1))
end

local function ringRenderSettingsForTool(tool)
    return client.ringQualityPresets[ringQualityIndex(tool)]
        or client.ringQualityPresets[client.defaultRingQualityIndex]
        or client.ringQualityPresets[1]
end

local function activeRingRenderSettings()
    local tool = select(1, client.activeTool())
    return ringRenderSettingsForTool(tool)
end

local function ringRtSize(settings)
    return settings and (settings.ringRtSize or settings.rtSize) or nil
end

local function scaleCircleResolutionValue(value, minValue)
    value = tonumber(value)
    if value == nil then return end

    return math.max(math.floor(value * 0.25 + 0.5), minValue or 1)
end

local function circleSpriteRtSize(settings)
    if not settings then return end

    local raw = settings.circleRtSize
    if raw ~= nil then
        return math.max(math.Round(tonumber(raw) or 0), 1)
    end

    return scaleCircleResolutionValue(settings.ringRtSize or settings.rtSize, 1)
end

local function ringRenderSegments(settings)
    local raw = settings and (settings.ringSegments or settings.segments) or ROTATION_CONFIG.ringDefaultSegments
    return math.Clamp(math.Round(tonumber(raw) or ROTATION_CONFIG.ringDefaultSegments), ROTATION_CONFIG.ringMinSegments, ROTATION_CONFIG.ringMaxSegments)
end

local function circleSpriteSegments(settings)
    if settings and settings.circleSegments ~= nil then
        return math.max(math.Round(tonumber(settings.circleSegments) or RENDER_CONFIG.circleSegments), 3)
    end

    local derived = settings and scaleCircleResolutionValue(settings.ringSegments or settings.segments, 3) or nil
    if derived then
        return derived
    end

    return math.max(math.Round(RENDER_CONFIG.circleSegments), 3)
end

local function rotationRingTickLimit(settings, divisions)
    local raw = settings and settings.tickCount or client.rotationSnapMaxVisibleTicks
    return math.Clamp(math.Round(tonumber(raw) or client.rotationSnapMaxVisibleTicks), 1, math.max(math.Round(tonumber(divisions) or 0), 1))
end

local function quantizeShapeRatio(value)
    value = clampUnitInterval(value)
    return math.Clamp(math.Round(value * SHAPE_CONFIG.ratioQuantization) / SHAPE_CONFIG.ratioQuantization, 0, 1)
end

local function compensatedInnerRatio(innerRatio)
    innerRatio = clampUnitInterval(innerRatio)
    if innerRatio <= 0 then
        return 0
    end

    local thicknessRatio = math.Clamp(1 - innerRatio, 0, 1)
    thicknessRatio = math.Clamp(
        thicknessRatio + math.min(SHAPE_CONFIG.ringThicknessCompensationMax, thicknessRatio * SHAPE_CONFIG.ringThicknessCompensationScale),
        0,
        1
    )

    return math.Clamp(1 - thicknessRatio, 0, 1)
end

local function resolvedRingInnerRadius(innerRadius, outerRadius)
    outerRadius = math.max(tonumber(outerRadius) or 0, 0)
    if outerRadius <= 0 then
        return 0
    end

    innerRadius = math.Clamp(tonumber(innerRadius) or 0, 0, outerRadius)
    local innerRatio = quantizeShapeRatio(compensatedInnerRatio(innerRadius / outerRadius))
    return outerRadius * innerRatio
end

local function shapeMetricsForRtSize(rtSize)
    rtSize = math.max(math.Round(tonumber(rtSize) or 0), 1)

    local metrics = shapeMetricCache[rtSize]
    if metrics then
        return metrics
    end

    local halfSize = rtSize * 0.5
    local padding = math.max(math.floor(rtSize * SHAPE_CONFIG.rtPaddingRatio + 0.5), SHAPE_CONFIG.rtMinPadding)
    local outerRadius = math.max(halfSize - padding, 1)

    metrics = {
        rtSize = rtSize,
        halfSize = halfSize,
        padding = padding,
        outerRadius = outerRadius,
        worldScale = halfSize / outerRadius,
        segments = math.max(math.floor(rtSize / 32 + 0.5), RENDER_CONFIG.circleSegments)
    }

    shapeMetricCache[rtSize] = metrics
    return metrics
end

local function reusableCirclePoly(points)
    local key = #points
    local poly = reusableCirclePolyCache[key]
    if poly then
        return poly
    end

    poly = {}
    for i = 1, key + 1 do
        poly[i] = { x = 0, y = 0, u = 0, v = 0 }
    end

    reusableCirclePolyCache[key] = poly
    return poly
end

local function drawCircle2DAt(centerX, centerY, radius, color, points)
    radius = tonumber(radius) or 0
    if radius <= 0 then return end

    points = points or unitCircle
    centerX = tonumber(centerX) or 0
    centerY = tonumber(centerY) or 0

    local poly = reusableCirclePoly(points)
    poly[1].x = centerX
    poly[1].y = centerY
    poly[1].u = 0.5
    poly[1].v = 0.5

    for i = 1, #points do
        local point = points[i]
        local vertex = poly[i + 1]
        vertex.x = centerX + point.x * radius
        vertex.y = centerY + point.y * radius
        vertex.u = 0.5 + point.x * 0.5
        vertex.v = 0.5 + point.y * 0.5
    end

    surface.SetDrawColor(color)
    surface.DrawPoly(poly)
end

local function drawRing2DByRadiiAt(centerX, centerY, outerRadius, innerRadius, color, points)
    outerRadius = tonumber(outerRadius) or 0
    innerRadius = math.Clamp(tonumber(innerRadius) or 0, 0, outerRadius)
    if outerRadius <= 0 or innerRadius >= outerRadius then return end

    points = points or unitCircle
    centerX = tonumber(centerX) or 0
    centerY = tonumber(centerY) or 0

    surface.SetDrawColor(color)

    for i = 1, #points - 1 do
        local a = points[i]
        local b = points[i + 1]

        reusableRingQuad[1].x = centerX + a.x * outerRadius
        reusableRingQuad[1].y = centerY + a.y * outerRadius
        reusableRingQuad[1].u = 0.5 + a.x * 0.5
        reusableRingQuad[1].v = 0.5 + a.y * 0.5
        reusableRingQuad[2].x = centerX + b.x * outerRadius
        reusableRingQuad[2].y = centerY + b.y * outerRadius
        reusableRingQuad[2].u = 0.5 + b.x * 0.5
        reusableRingQuad[2].v = 0.5 + b.y * 0.5
        reusableRingQuad[3].x = centerX + b.x * innerRadius
        reusableRingQuad[3].y = centerY + b.y * innerRadius
        reusableRingQuad[3].u = 0.5 + b.x * 0.5
        reusableRingQuad[3].v = 0.5 + b.y * 0.5
        reusableRingQuad[4].x = centerX + a.x * innerRadius
        reusableRingQuad[4].y = centerY + a.y * innerRadius
        reusableRingQuad[4].u = 0.5 + a.x * 0.5
        reusableRingQuad[4].v = 0.5 + a.y * 0.5
        surface.DrawPoly(reusableRingQuad)
    end
end

local function ensureShapeWhiteMaterial()
    if not shapeWhiteMaterial then
    shapeWhiteMaterial = CreateMaterial(SHAPE_CONFIG.cacheName .. "_white_mat", "UnlitGeneric", {
            ["$basetexture"] = "vgui/white",
            ["$translucent"] = "1",
            ["$additive"] = "1",
            ["$vertexalpha"] = "1",
            ["$vertexcolor"] = "1",
            ["$nocull"] = "1",
            ["$model"] = "1"
        })
    end

    local materialFlags = shapeWhiteMaterial:GetInt("$flags") or 0
    local requiredFlags = bit.bor(materialFlags, SHAPE_CONFIG.materialFlags)
    if materialFlags ~= requiredFlags then
        shapeWhiteMaterial:SetInt("$flags", requiredFlags)
    end

    return shapeWhiteMaterial
end

local function buildShapeCacheKey(shapeKind, rtSize, innerRatio, segments)
    segments = math.max(math.Round(tonumber(segments) or 0), 0)

    if innerRatio == nil then
        return ("%s_%d_%d"):format(shapeKind, rtSize, segments)
    end

    return ("%s_%d_%d_%d"):format(shapeKind, rtSize, math.Round(innerRatio * SHAPE_CONFIG.ratioQuantization), segments)
end

local function rebuildShapeCacheEntry(entry)
    if not entry or not entry.texture or not entry.metrics then return end

    local metrics = entry.metrics
    local center = metrics.halfSize
    local outerRadius = metrics.outerRadius
    local points = circlePointsForSegments(entry.segments or metrics.segments)

    render.PushRenderTarget(entry.texture)
    render.Clear(0, 0, 0, 0, true, true)
    cam.Start2D()
        draw.NoTexture()

        if entry.shapeKind == "disc" then
            drawCircle2DAt(center, center, outerRadius, color_white, points)
        elseif entry.shapeKind == "ring" then
            drawRing2DByRadiiAt(center, center, outerRadius, outerRadius * (entry.innerRatio or 0), color_white, points)
        elseif entry.shapeKind == "ring_band" then
            local innerRadius = outerRadius * (entry.innerRatio or 0)
            local bandThickness = math.max(outerRadius - innerRadius, 1)
            local edgeThickness = math.min(math.max(math.floor(metrics.rtSize / 512 + 0.5), 1), bandThickness * 0.5)

        drawRing2DByRadiiAt(center, center, outerRadius, innerRadius, Color(255, 255, 255, ROTATION_CONFIG.ringFillAlpha), points)
        drawRing2DByRadiiAt(center, center, outerRadius, math.max(innerRadius, outerRadius - edgeThickness), Color(255, 255, 255, ROTATION_CONFIG.ringEdgeAlpha), points)
        drawRing2DByRadiiAt(center, center, math.min(outerRadius, innerRadius + edgeThickness), innerRadius, Color(255, 255, 255, ROTATION_CONFIG.ringEdgeAlpha), points)
        end
    cam.End2D()
    render.PopRenderTarget()

    entry.ready = true
end

local function ensureCachedShape(shapeKind, rtSize, innerRatio, segments)
    rtSize = math.max(math.Round(tonumber(rtSize) or 0), 1)
    if rtSize <= 0 then return end

    if innerRatio ~= nil then
        innerRatio = quantizeShapeRatio(innerRatio)
    end

    local metrics = shapeMetricsForRtSize(rtSize)
    segments = math.max(math.Round(tonumber(segments) or metrics.segments), 3)

    local cacheKey = buildShapeCacheKey(shapeKind, rtSize, innerRatio, segments)
    local entry = shapeCache[cacheKey]
    if not entry then
        local texture = GetRenderTargetEx(
        SHAPE_CONFIG.cacheName .. "_" .. cacheKey .. "_rt",
            rtSize,
            rtSize,
            RT_SIZE_NO_CHANGE,
            MATERIAL_RT_DEPTH_NONE,
            0,
            0,
            IMAGE_FORMAT_RGBA8888
        )
    local material = CreateMaterial(SHAPE_CONFIG.cacheName .. "_" .. cacheKey .. "_mat", "UnlitGeneric", {
            ["$basetexture"] = texture:GetName(),
            ["$translucent"] = "1",
            ["$additive"] = "1",
            ["$vertexalpha"] = "1",
            ["$vertexcolor"] = "1",
            ["$nocull"] = "1",
            ["$model"] = "1"
        })

        entry = {
            cacheKey = cacheKey,
            shapeKind = shapeKind,
            innerRatio = innerRatio,
            metrics = metrics,
            segments = segments,
            texture = texture,
            material = material,
            ready = false
        }

        shapeCache[cacheKey] = entry
    end

    entry.material:SetTexture("$basetexture", entry.texture)
    local materialFlags = entry.material:GetInt("$flags") or 0
    local requiredFlags = bit.bor(materialFlags, SHAPE_CONFIG.materialFlags)
    if materialFlags ~= requiredFlags then
        entry.material:SetInt("$flags", requiredFlags)
    end

    if not entry.ready then
        rebuildShapeCacheEntry(entry)
    end

    return entry
end

local function drawCachedShapeRect2D(outerRadius, entry, color)
    if not entry or not entry.material or not entry.metrics then return false end

    outerRadius = tonumber(outerRadius) or 0
    if outerRadius <= 0 then return false end

    local rectHalfSize = outerRadius * entry.metrics.worldScale
    local rectSize = rectHalfSize * 2

    surface.SetMaterial(entry.material)
    surface.SetDrawColor(color)
    surface.DrawTexturedRect(-rectHalfSize, -rectHalfSize, rectSize, rectSize)
    return true
end

local function ensureCachedCircleSprite(settings, outerRadius, innerRadius, rtSizeOverride, segmentsOverride)
    local rtSize = rtSizeOverride or circleSpriteRtSize(settings)
    if not settings or settings.realtime or not rtSize then return end

    outerRadius = tonumber(outerRadius) or 0
    if outerRadius <= 0 then return end

    local segments = segmentsOverride or circleSpriteSegments(settings)
    return {
        fill = ensureCachedShape("disc", rtSize, nil, segments),
        outline = ensureCachedShape("ring", rtSize, innerRadius / math.max(outerRadius, 1e-6), segments)
    }
end

local function drawCachedCircleSpriteRect2D(outerRadius, spriteCache, color)
    if not spriteCache or not spriteCache.fill or not spriteCache.outline then return false end

    drawCachedShapeRect2D(outerRadius, spriteCache.fill, cappedAlpha(color, 220))
    drawCachedShapeRect2D(outerRadius, spriteCache.outline, cappedAlpha(color, 255))
    return true
end

local function pushTexturedWorldVertex(position, u, v, color)
    meshPosition(position)
    mesh.TexCoord(0, u, v)
    mesh.Color(color.r, color.g, color.b, color.a)
    mesh.AdvanceVertex()
end

local function drawTexturedWorldQuad(a, b, c, d, color, material, doubleSided)
    if not material then return false end

    render.SetMaterial(material)
    mesh.Begin(MATERIAL_TRIANGLES, doubleSided and 4 or 2)
        pushTexturedWorldVertex(a, 0, 0, color)
        pushTexturedWorldVertex(b, 1, 0, color)
        pushTexturedWorldVertex(c, 1, 1, color)

        pushTexturedWorldVertex(a, 0, 0, color)
        pushTexturedWorldVertex(c, 1, 1, color)
        pushTexturedWorldVertex(d, 0, 1, color)

        if doubleSided then
            pushTexturedWorldVertex(c, 1, 1, color)
            pushTexturedWorldVertex(b, 1, 0, color)
            pushTexturedWorldVertex(a, 0, 0, color)

            pushTexturedWorldVertex(d, 0, 1, color)
            pushTexturedWorldVertex(c, 1, 1, color)
            pushTexturedWorldVertex(a, 0, 0, color)
        end
    mesh.End()

    return true
end

local function drawCachedShapePlane(origin, axisA, axisB, outerRadius, entry, color, doubleSided)
    if not isvector(origin) or not isvector(axisA) or not isvector(axisB) then return false end
    if axisA:LengthSqr() < 1e-8 or axisB:LengthSqr() < 1e-8 then return false end
    if not entry or not entry.metrics then return false end

    outerRadius = tonumber(outerRadius) or 0
    if outerRadius <= 0 then return false end

    local halfSize = outerRadius * entry.metrics.worldScale
    local axisX = axisA:GetNormalized() * halfSize
    local axisY = axisB:GetNormalized() * halfSize

    return drawTexturedWorldQuad(
        origin - axisX - axisY,
        origin + axisX - axisY,
        origin + axisX + axisY,
        origin - axisX + axisY,
        color,
        entry.material,
        doubleSided
    )
end

local function queueShapeCacheWarmup(tool)
    hook.Remove("PostRender", SHAPE_CONFIG.rebuildHook)

    local settings = tool and ringRenderSettingsForTool(tool) or activeRingRenderSettings()
    if not settings or settings.realtime then
        return
    end

    hook.Add("PostRender", SHAPE_CONFIG.rebuildHook, function()
        local ringSize = ringRtSize(settings)
        local circleSize = circleSpriteRtSize(settings)
        local ringSegments = ringRenderSegments(settings)
        local circleSegments = circleSpriteSegments(settings)

        if ringSize then
            ensureCachedShape("disc", ringSize, nil, ringSegments)
        end
        if circleSize then
            ensureCachedShape("disc", circleSize, nil, circleSegments)
        end
        hook.Remove("PostRender", SHAPE_CONFIG.rebuildHook)
    end)
end

local function selectionColor(state)
    return cachedColor(colors.source.r, colors.source.g, colors.source.b, 255)
end

shapeMetricCache.renderPerf = shapeMetricCache.renderPerf or {}

function shapeMetricCache.renderPerf.drawWireMarkerBatch(entries, ignoreZ)
    if not istable(entries) or #entries == 0 then return end

    render.MaterialOverride(RENDER_CONFIG.wireframeMaterial)
    render.SuppressEngineLighting(true)
    if ignoreZ then
        cam.IgnoreZ(true)
    end

    for i = 1, #entries do
        local entry = entries[i]
        local ent = entry and entry.ent
        local color = entry and entry.color
        if IsValid(ent) and color then
            render.SetColorModulation(color.r / 255, color.g / 255, color.b / 255)
            render.SetBlend(math.Clamp((tonumber(entry.alpha) or 0) / 255, 0.02, 1))
            ent:DrawModel()
        end
    end

    if ignoreZ then
        cam.IgnoreZ(false)
    end
    render.SuppressEngineLighting(false)
    render.SetBlend(1)
    render.SetColorModulation(1, 1, 1)
    render.MaterialOverride()
end

function shapeMetricCache.renderPerf.addGhostRenderEntry(entries, ghost, minBlend, maxBlend)
    if not istable(entries) or not IsValid(ghost) then return end
    if ghost.GetNoDraw and ghost:GetNoDraw() then return end

    local ghostColor = ghost:GetColor()
    local index = (tonumber(entries._magicAlignCount) or 0) + 1
    entries._magicAlignCount = index
    local entry = entries[index]
    if not istable(entry) then
        entry = {}
        entries[index] = entry
    end

    entry.ghost = ghost
    entry.alpha = ghostColor.a or 255
    entry.minBlend = minBlend
    entry.maxBlend = maxBlend
end

function shapeMetricCache.renderPerf.drawGhostRenderEntries(entries)
    if not istable(entries) or #entries == 0 then return end

    for i = 1, #entries do
        local entry = entries[i]
        if IsValid(entry.ghost) and not (entry.ghost.GetNoDraw and entry.ghost:GetNoDraw()) then
            render.SetBlend(math.Clamp(entry.alpha / 255, entry.minBlend, entry.maxBlend))
            entry.ghost:DrawModel()
        end
    end

    render.SetBlend(1)
end

local function clampColorByte(value, fallback)
    return math.Clamp(math.floor(tonumber(value) or fallback or 0), 0, 255)
end

local function previewOccludedEnabled(tool)
    if tool and tool.GetClientNumber then
        return (tonumber(tool:GetClientNumber("preview_occluded")) or 0) ~= 0
    end

    local cvar = GetConVar(RENDER_CONFIG.previewOccludedCvar)
    return cvar and cvar:GetBool() or false
end

local function previewOccludedPickerColor(tool)
    if tool and tool.GetClientNumber then
        return cachedColor(
            clampColorByte(tool:GetClientNumber("preview_occluded_r"), RENDER_CONFIG.previewOccludedDefaultColor.r),
            clampColorByte(tool:GetClientNumber("preview_occluded_g"), RENDER_CONFIG.previewOccludedDefaultColor.g),
            clampColorByte(tool:GetClientNumber("preview_occluded_b"), RENDER_CONFIG.previewOccludedDefaultColor.b),
            clampColorByte(tool:GetClientNumber("preview_occluded_a"), RENDER_CONFIG.previewOccludedDefaultColor.a)
        )
    end

    local function cvarByte(suffix, fallback)
        local cvar = GetConVar("magic_align_preview_occluded_" .. suffix)
        return clampColorByte(cvar and cvar:GetInt() or fallback, fallback)
    end

    return cachedColor(
        cvarByte("r", RENDER_CONFIG.previewOccludedDefaultColor.r),
        cvarByte("g", RENDER_CONFIG.previewOccludedDefaultColor.g),
        cvarByte("b", RENDER_CONFIG.previewOccludedDefaultColor.b),
        cvarByte("a", RENDER_CONFIG.previewOccludedDefaultColor.a)
    )
end

local function scaledOccludedPreviewColor(tool, holoAlpha)
    local picker = previewOccludedPickerColor(tool)
    local alpha = math.Clamp(math.floor((picker.a / 255) * clampColorByte(holoAlpha, 0) + 0.5), 0, 255)
    if alpha <= 0 then return end

    return cachedColor(picker.r, picker.g, picker.b, alpha)
end

local function stencilAvailable()
    return isfunction(render.ClearStencil)
        and isfunction(render.SetStencilEnable)
        and isfunction(render.SetStencilWriteMask)
        and isfunction(render.SetStencilTestMask)
        and isfunction(render.SetStencilReferenceValue)
        and isfunction(render.SetStencilCompareFunction)
        and isfunction(render.SetStencilPassOperation)
        and isfunction(render.SetStencilFailOperation)
        and isfunction(render.SetStencilZFailOperation)
        and STENCILCOMPARISONFUNCTION_ALWAYS ~= nil
        and STENCILCOMPARISONFUNCTION_EQUAL ~= nil
        and STENCILOPERATION_KEEP ~= nil
        and STENCILOPERATION_REPLACE ~= nil
end

local function stripeDistanceScale(distance)
    distance = math.max(tonumber(distance) or 1, 1)
    return math.Clamp(
        STRIPE_CONFIG.occludedReferenceDistance / distance,
        STRIPE_CONFIG.occludedMinScreenScale,
        STRIPE_CONFIG.occludedMaxScreenScale
    )
end

local function occludedStripeTileSize(ghost)
    if not IsValid(ghost) then return STRIPE_CONFIG.rtSize end

    local center = ghost.WorldSpaceCenter and ghost:WorldSpaceCenter() or ghost:GetPos()
    if not isvector(center) then return STRIPE_CONFIG.rtSize end

    return math.max(1, STRIPE_CONFIG.rtSize * stripeDistanceScale(EyePos():Distance(center)))
end

local function occludedStripeScreenCenter(ghost)
    if not IsValid(ghost) then return ScrW() * 0.5, ScrH() * 0.5 end

    local mins, maxs
    if isfunction(ghost.GetRenderBounds) then
        mins, maxs = ghost:GetRenderBounds()
    end
    if (not isvector(mins) or not isvector(maxs)) and isfunction(ghost.OBBMins) and isfunction(ghost.OBBMaxs) then
        mins, maxs = ghost:OBBMins(), ghost:OBBMaxs()
    end

    if not isvector(mins) or not isvector(maxs) then
        local center = ghost.WorldSpaceCenter and ghost:WorldSpaceCenter() or ghost:GetPos()
        if isvector(center) then
            local screen = center:ToScreen()
            return screen.x, screen.y
        end

        return ScrW() * 0.5, ScrH() * 0.5
    end

    local pos = ghost:GetPos()
    local ang = ghost:GetAngles()
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge

    for xIndex = 0, 1 do
        for yIndex = 0, 1 do
            for zIndex = 0, 1 do
                local localPos = VectorP(
                    xIndex == 0 and mins.x or maxs.x,
                    yIndex == 0 and mins.y or maxs.y,
                    zIndex == 0 and mins.z or maxs.z
                )
                local world = LocalToWorldPosPrecise(localPos, pos, ang)
                local screen = world:ToScreen()
                minX = math.min(minX, screen.x)
                minY = math.min(minY, screen.y)
                maxX = math.max(maxX, screen.x)
                maxY = math.max(maxY, screen.y)
            end
        end
    end

    if minX == math.huge or minY == math.huge then
        return ScrW() * 0.5, ScrH() * 0.5
    end

    return (minX + maxX) * 0.5, (minY + maxY) * 0.5
end

local function occludedStripeParallaxCenter(centerX, centerY)
    local amount = math.Clamp(tonumber(STRIPE_CONFIG.occludedScreenParallax) or 0, 0, 1)
    if amount <= 0 then return centerX, centerY end

    local screenCenterX = ScrW() * 0.5
    local screenCenterY = ScrH() * 0.5
    return centerX + (screenCenterX - centerX) * amount, centerY + (screenCenterY - centerY) * amount
end

local function screenPointDistance(a, b)
    if not a or not b then return 0 end

    local dx = (tonumber(a.x) or 0) - (tonumber(b.x) or 0)
    local dy = (tonumber(a.y) or 0) - (tonumber(b.y) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function drawScreenStripePattern(color, tileSize, centerX, centerY)
    if ensureStripePatternMaterial then
        ensureStripePatternMaterial()
    end

    local stripeMaterial = stripePatternScreenMaterial or stripePatternMaterial
    if not stripeMaterial then return false end

    tileSize = math.max(1, tonumber(tileSize) or STRIPE_CONFIG.rtSize)
    local screenWidth = ScrW()
    local screenHeight = ScrH()
    centerX = tonumber(centerX) or screenWidth * 0.5
    centerY = tonumber(centerY) or screenHeight * 0.5
    local angle = math.rad(45)
    local cosAngle = math.cos(angle)
    local sinAngle = math.sin(angle)

    local function pushScreenVertex(x, y)
        local centeredX = x - centerX
        local centeredY = y - centerY
        meshPosition(VectorP(x, y, 0))
        mesh.TexCoord(
            0,
            0.5 + (centeredX * cosAngle + centeredY * sinAngle) / tileSize,
            0.5 + (-centeredX * sinAngle + centeredY * cosAngle) / tileSize
        )
        mesh.Color(color.r, color.g, color.b, color.a)
        mesh.AdvanceVertex()
    end

    cam.Start2D()
        render.SetMaterial(stripeMaterial)
        mesh.Begin(MATERIAL_TRIANGLES, 2)
            pushScreenVertex(0, 0)
            pushScreenVertex(screenWidth, 0)
            pushScreenVertex(screenWidth, screenHeight)

            pushScreenVertex(0, 0)
            pushScreenVertex(screenWidth, screenHeight)
            pushScreenVertex(0, screenHeight)
        mesh.End()
    cam.End2D()

    return true
end

local function drawPreviewOccludedGhost(tool, ghost, baseAlpha)
    if not IsValid(ghost) or (ghost.GetNoDraw and ghost:GetNoDraw()) then return end
    if not stencilAvailable() then return end

    local ghostColor = ghost:GetColor()
    local overlayColor = scaledOccludedPreviewColor(tool, baseAlpha or ghostColor.a or 255)
    if not overlayColor then return end

    render.ClearStencil()
    render.SetStencilEnable(true)
    render.SetStencilWriteMask(255)
    render.SetStencilTestMask(255)
    render.SetStencilReferenceValue(1)
    render.SetStencilCompareFunction(STENCILCOMPARISONFUNCTION_ALWAYS)
    render.SetStencilFailOperation(STENCILOPERATION_KEEP)
    render.SetStencilPassOperation(STENCILOPERATION_KEEP)
    render.SetStencilZFailOperation(STENCILOPERATION_REPLACE)

    if render.OverrideColorWriteEnable then
        render.OverrideColorWriteEnable(true, false)
    end
    render.SetBlend(0)
    ghost:DrawModel()
    render.SetBlend(1)
    if render.OverrideColorWriteEnable then
        render.OverrideColorWriteEnable(false, true)
    end

    render.SetStencilCompareFunction(STENCILCOMPARISONFUNCTION_EQUAL)
    render.SetStencilFailOperation(STENCILOPERATION_KEEP)
    render.SetStencilPassOperation(STENCILOPERATION_KEEP)
    render.SetStencilZFailOperation(STENCILOPERATION_KEEP)

    local centerX, centerY = occludedStripeParallaxCenter(occludedStripeScreenCenter(ghost))
    drawScreenStripePattern(overlayColor, occludedStripeTileSize(ghost), centerX, centerY)

    render.SetStencilEnable(false)
end

local function drawPreviewOccludedCompatEntry(tool, entry)
    if not istable(entry) or not IsValid(entry.ghost) then return end

    local color = entry.color or entry.ghost:GetColor()
    drawPreviewOccludedGhost(tool, entry.ghost, color and color.a or nil)
end

local function drawPreviewOccludedCompatGhosts(tool, state)
    local ghosts = state and state.compatGhosts
    if not istable(ghosts) then return end

    drawPreviewOccludedCompatEntry(tool, ghosts.main)

    for _, entry in pairs(ghosts.linked or {}) do
        drawPreviewOccludedCompatEntry(tool, entry)
    end
end

local function drawCircle2D(radius, color, segments)
    local material = ensureShapeWhiteMaterial()
    if material then
        surface.SetMaterial(material)
    else
        draw.NoTexture()
    end

    drawCircle2DAt(0, 0, radius, color, circlePointsForSegments(segments or RENDER_CONFIG.circleSegments))
end

local function drawRing2DByRadii(outerRadius, innerRadius, color, segments)
    local material = ensureShapeWhiteMaterial()
    if material then
        surface.SetMaterial(material)
    else
        draw.NoTexture()
    end

    drawRing2DByRadiiAt(0, 0, outerRadius, innerRadius, color, circlePointsForSegments(segments or RENDER_CONFIG.circleSegments))
end

local function drawBillboard(worldPos, painter, viewerPos)
    if not isvector(worldPos) then return end

    viewerPos = isvector(viewerPos)
        and viewerPos
        or (IsValid(LocalPlayer()) and LocalPlayer():GetShootPos() or EyePos())
    local toViewer = viewerPos - worldPos
    if toViewer:LengthSqr() < 1e-8 then
        toViewer = VectorP(0, 0, 1)
    else
        toViewer:Normalize()
    end

    local ang = toViewer:Angle()
    ang = M.RotateAngleAroundAxisPrecise(ang, M.AngleRightPrecise(ang), -90)
    local pos = worldPos + toViewer * RENDER_CONFIG.billboardPush

    local drawPos = toVector(pos)
    local drawAng = toAngle(ang)
    if not drawPos or not drawAng then return end

    -- Eine einzelne, zum Viewport gedrehte 3D2D-Flaeche reicht hier aus.
    cam.Start3D2D(drawPos, drawAng, RENDER_CONFIG.billboardScale)
        painter()
    cam.End3D2D()
end

local function drawCircleSprite(worldPos, radius, color, settings, viewerPos)
    settings = settings or activeRingRenderSettings()

    local pixelRadius = radius / RENDER_CONFIG.billboardScale
    local primaryInnerRadius = resolvedRingInnerRadius(math.max(pixelRadius - math.max(pixelRadius * 0.18, 4), 0), pixelRadius)
    local circleSegments = circleSpriteSegments(settings)
    local cachedCircleRtSize = circleSpriteRtSize(settings)

    drawBillboard(worldPos, function()
        if settings and not settings.realtime and cachedCircleRtSize then
            local spriteCache = ensureCachedCircleSprite(settings, pixelRadius, primaryInnerRadius, cachedCircleRtSize, circleSegments)
            if drawCachedCircleSpriteRect2D(pixelRadius, spriteCache, color) then
                return
            end
        end

        drawCircle2D(pixelRadius, cappedAlpha(color, 220), circleSegments)
        drawRing2DByRadii(pixelRadius, primaryInnerRadius, cappedAlpha(color, 255), circleSegments)
    end, viewerPos)
end

local function drawRingSprite(worldPos, radius, thickness, color, settings, viewerPos, matchCircleQuality)
    settings = settings or activeRingRenderSettings()

    local pixelRadius = radius / RENDER_CONFIG.billboardScale
    local pixelThickness = math.max(thickness / RENDER_CONFIG.billboardScale, 4)
    local mainInnerRadius = resolvedRingInnerRadius(math.max(pixelRadius - pixelThickness, 0), pixelRadius)
    local accentOuterRadius = math.max(pixelRadius - pixelThickness * 0.7, 0)
    local accentInnerRadius = resolvedRingInnerRadius(
        math.max(accentOuterRadius - math.max(pixelThickness * 0.22, 2), 0),
        accentOuterRadius
    )
    local ringSegments = matchCircleQuality and circleSpriteSegments(settings) or ringRenderSegments(settings)
    local cachedRingRtSize = matchCircleQuality and circleSpriteRtSize(settings) or ringRtSize(settings)

    drawBillboard(worldPos, function()
        if settings and not settings.realtime and cachedRingRtSize then
            local mainEntry = ensureCachedShape("ring", cachedRingRtSize, mainInnerRadius / math.max(pixelRadius, 1e-6), ringSegments)
            local accentEntry = accentOuterRadius > 0
                and ensureCachedShape("ring", cachedRingRtSize, accentInnerRadius / math.max(accentOuterRadius, 1e-6), ringSegments)
                or nil

            if mainEntry and (accentOuterRadius <= 0 or accentEntry) then
                drawCachedShapeRect2D(pixelRadius, mainEntry, cappedAlpha(color, 255))
                if accentEntry then
                    drawCachedShapeRect2D(accentOuterRadius, accentEntry, cappedAlpha(color, 150))
                end
                return
            end
        end

        drawRing2DByRadii(pixelRadius, mainInnerRadius, cappedAlpha(color, 255), ringSegments)
        if accentOuterRadius > 0 then
            drawRing2DByRadii(accentOuterRadius, accentInnerRadius, cappedAlpha(color, 150), ringSegments)
        end
    end, viewerPos)
end

local function normalizeDegrees(angle)
    angle = tonumber(angle) or 0
    angle = angle % 360
    if angle < 0 then
        angle = angle + 360
    end

    return angle
end

local function snapRotationDisplayAngle(angle, step)
    step = tonumber(step) or 0
    if step <= 1e-8 then
        return normalizeDegrees(angle)
    end

    return normalizeDegrees(math.Round(normalizeDegrees(angle) / step) * step)
end

local function isAngleMultiple(angle, interval)
    local remainder = normalizeDegrees(angle) % interval
    return remainder <= 1e-4 or math.abs(remainder - interval) <= 1e-4
end

local function isMajorTick(angle)
    if client.isMajorRotationTick(angle) then
        return true
    end

    return isAngleMultiple(angle, 30) or isAngleMultiple(angle, 45)
end

local function isFortyFiveTick(angle)
    return isAngleMultiple(angle, 45)
end

local function visibleRotationTicks(divisions, step, cursorAngle, settings)
    local cachedRotationTicks = shapeMetricCache.rotationTicks
    if not cachedRotationTicks then
        cachedRotationTicks = {}
        shapeMetricCache.rotationTicks = cachedRotationTicks
    end

    local tickLimit = rotationRingTickLimit(settings, divisions)
    if cachedRotationTicks.ticks
        and cachedRotationTicks.divisions == divisions
        and math.abs((cachedRotationTicks.step or 0) - step) <= 1e-8
        and math.abs((cachedRotationTicks.cursorAngle or 0) - cursorAngle) <= 1e-8
        and cachedRotationTicks.tickLimit == tickLimit then
        return cachedRotationTicks.ticks
    end

    local ticks = {}
    for index = 0, math.max(divisions - 1, 0) do
        local angle = index * step
        ticks[#ticks + 1] = {
            angle = angle,
            dist = math.abs(math.AngleDifference(angle, cursorAngle)),
            major = isMajorTick(angle)
        }
    end

    table.sort(ticks, function(a, b)
        if math.abs(a.dist - b.dist) <= 1e-4 then
            return a.angle < b.angle
        end

        return a.dist < b.dist
    end)

    local selected = {}
    for i = 1, math.min(tickLimit, #ticks) do
        selected[#selected + 1] = ticks[i]
    end

    table.sort(selected, function(a, b)
        return a.angle < b.angle
    end)

    cachedRotationTicks.cursorAngle = cursorAngle
    cachedRotationTicks.divisions = divisions
    cachedRotationTicks.step = step
    cachedRotationTicks.tickLimit = tickLimit
    cachedRotationTicks.ticks = selected

    return selected
end

local function drawRotationRingTicks(origin, a, b, radius, size, ticks, color)
    if not istable(ticks) or #ticks == 0 then return end

    local minorInner = math.max(size * 0.022, 0.65)
    local majorInner = math.max(size * 0.048, 1.4)
    local major45Inner = math.max(size * 0.062, 1.9)

    for i = 1, #ticks do
        local tick = ticks[i]
        local angle = math.rad(tick.angle)
        local direction = a * math.cos(angle) + b * math.sin(angle)
        local inner = isFortyFiveTick(tick.angle) and major45Inner or tick.major and majorInner or minorInner

        drawLine(origin + direction * (radius - inner), origin + direction * radius, color, true)
    end
end

local function formatPercentLabel(percent)
    if percent == nil or percent <= 0.05 or percent >= 99.95 then return end

    local rounded = math.Round(percent, math.abs(percent - math.Round(percent)) < 0.05 and 0 or 1)
    if math.abs(rounded - math.Round(rounded)) < 0.05 then
        return ("%d%%"):format(math.Round(rounded))
    end

    return ("%.1f%%"):format(rounded)
end

local function gcd(a, b)
    a = math.abs(math.floor(tonumber(a) or 0))
    b = math.abs(math.floor(tonumber(b) or 0))

    while b ~= 0 do
        a, b = b, a % b
    end

    return math.max(a, 1)
end

local function lcm(a, b)
    a = math.max(math.floor(tonumber(a) or 0), 1)
    b = math.max(math.floor(tonumber(b) or 0), 1)

    return math.floor((a / gcd(a, b)) * b)
end

local function gridAxisDivisions(grid, axisKey)
    if not grid then return 0 end

    return math.max(math.Round(axisKey == "u" and (grid.divU or 0) or (grid.divV or 0)), 0)
end

local function commonGridDivisions(face, axisKey)
    local common = 1
    local found = false
    local gridSets = {}
    local seen = {}

    local function addGrid(grid)
        if not grid or seen[grid] then return end
        seen[grid] = true
        gridSets[#gridSets + 1] = grid
    end

    addGrid(face and face.gridA)
    addGrid(face and face.gridB)
    addGrid(face and face.snapGridU)
    addGrid(face and face.snapGridV)

    for _, grid in ipairs(gridSets) do
        local divisions = gridAxisDivisions(grid, axisKey)
        if divisions > 0 then
            common = lcm(common, divisions)
            found = true
        end
    end

    return found and common or 0
end

local function formatFractionLabel(index, divisions, commonDivisions, reduce)
    index = math.Round(tonumber(index) or 0)
    divisions = math.max(math.Round(tonumber(divisions) or 0), 0)
    commonDivisions = math.max(math.Round(tonumber(commonDivisions) or divisions), divisions)

    if divisions <= 0 or index <= 0 or index >= divisions then return end

    local numerator = index
    local denominator = divisions

    if reduce ~= false then
        numerator = math.Round(index * commonDivisions / divisions)
        denominator = commonDivisions
        local divisor = gcd(numerator, denominator)

        numerator = math.floor(numerator / divisor)
        denominator = math.floor(denominator / divisor)
    end

    if denominator <= 1 then return tostring(numerator) end

    return ("%d/%d"):format(numerator, denominator)
end

local function shouldUsePercentGridLabels()
    local cvar = GetConVar(RENDER_CONFIG.gridLabelPercentCvar)

    return cvar and cvar:GetBool() or false
end

local function shouldReduceFractionGridLabels()
    local cvar = GetConVar(RENDER_CONFIG.gridLabelReduceFractionCvar)

    return cvar == nil or cvar:GetBool()
end

local function currentGridLineAlpha(isPrimary)
    local fallback = isPrimary and GRID_CONFIG.alphaPrimary or GRID_CONFIG.alphaSecondary
    return readClampedConVarInt(RENDER_CONFIG.gridAlphaCvar, fallback, 0, 255)
end

local function formatGridLineLabel(face, axisKey)
    if shouldUsePercentGridLabels() then
        return formatPercentLabel(axisKey == "u" and face.snapPercentU or face.snapPercentV)
    end

    local grid = axisKey == "u" and face.snapGridU or face.snapGridV
    local index = axisKey == "u" and face.snapIndexU or face.snapIndexV
    local divisions = gridAxisDivisions(grid, axisKey)

    return formatFractionLabel(index, divisions, commonGridDivisions(face, axisKey), shouldReduceFractionGridLabels())
end

local function insetLineEnds(a, b, inset)
    local dir = b - a
    local length = dir:Length()
    if length <= 1e-6 then
        return a, b
    end

    dir:Normalize()
    local padding = math.min(inset, length * 0.25)

    return a + dir * padding, b - dir * padding
end

local function faceLineLocalPoints(face, grid, axisKey, value)
    if axisKey == "u" then
        if face.axis == 1 then
            return VectorP(face.fixed, value, grid.vMin), VectorP(face.fixed, value, grid.vMax)
        elseif face.axis == 2 then
            return VectorP(value, face.fixed, grid.vMin), VectorP(value, face.fixed, grid.vMax)
        end

        return VectorP(value, grid.vMin, face.fixed), VectorP(value, grid.vMax, face.fixed)
    end

    if face.axis == 1 then
        return VectorP(face.fixed, grid.uMin, value), VectorP(face.fixed, grid.uMax, value)
    elseif face.axis == 2 then
        return VectorP(grid.uMin, face.fixed, value), VectorP(grid.uMax, face.fixed, value)
    end

    return VectorP(grid.uMin, value, face.fixed), VectorP(grid.uMax, value, face.fixed)
end

local function faceLineWorldPoints(ent, face, grid, axisKey, value)
    local a, b = faceLineLocalPoints(face, grid, axisKey, value)
    if not a or not b then return end
    if not IsValid(ent) then return end

    local pos = ent:GetPos()
    local ang = ent:GetAngles()

    return LocalToWorldPosPrecise(a, pos, ang), LocalToWorldPosPrecise(b, pos, ang)
end

local function drawSnapLineLabels2D(a, b, label, color)
    if not label then return end

    local startPos, endPos = insetLineEnds(a, b, GRID_CONFIG.snapLabelInset)
    local startScreen = startPos:ToScreen()
    local endScreen = endPos:ToScreen()

    if startScreen.visible then
        draw.SimpleTextOutlined(label, "DermaDefaultBold", startScreen.x, startScreen.y, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
    end

    if endScreen.visible then
        draw.SimpleTextOutlined(label, "DermaDefaultBold", endScreen.x, endScreen.y, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
    end
end

local function drawPlaneSquare(worldPos, axisA, axisB, halfSize, color, outline, flipNormal, flipFace)
    if not isvector(worldPos) or not isvector(axisA) or not isvector(axisB) then return end
    if axisA:LengthSqr() < 1e-8 or axisB:LengthSqr() < 1e-8 then return end

    local a = axisA:GetNormalized() * halfSize
    local b = axisB:GetNormalized() * halfSize
    local normal = a:Cross(b)
    if normal:LengthSqr() < 1e-8 then return end
    normal:Normalize()
    if flipNormal then
        normal = -normal
    end

    local push = normal * 0.12
    local p1 = worldPos - a - b + push
    local p2 = worldPos + a - b + push
    local p3 = worldPos + a + b + push
    local p4 = worldPos - a + b + push
    local edge = outline or colorAlpha(color, 255)

    if flipFace then
        p2, p4 = p4, p2
    end

    render.SetColorMaterial()
    if render.DrawQuad then
        drawQuad(p1, p2, p3, p4, colorAlpha(color, color.a or 160))
    end
    drawLine(p1, p2, edge, true)
    drawLine(p2, p3, edge, true)
    drawLine(p3, p4, edge, true)
    drawLine(p4, p1, edge, true)
end

local function pushTriangle(a, b, c, color)
    meshPosition(a)
    mesh.Color(color.r, color.g, color.b, color.a)
    mesh.AdvanceVertex()

    meshPosition(b)
    mesh.Color(color.r, color.g, color.b, color.a)
    mesh.AdvanceVertex()

    meshPosition(c)
    mesh.Color(color.r, color.g, color.b, color.a)
    mesh.AdvanceVertex()
end

local function drawFilledQuad(a, b, c, d, color)
    render.SetColorMaterial()
    mesh.Begin(MATERIAL_TRIANGLES, 4)
        pushTriangle(a, b, c, color)
        pushTriangle(a, c, d, color)
        pushTriangle(c, b, a, color)
        pushTriangle(d, c, a, color)
    mesh.End()
end

local function rotationRingBandRadii(radius, padding)
    radius = tonumber(radius) or 0
    if radius <= 0 then return end

    local halfWidth = math.max((tonumber(padding) or 0) * 0.5, ROTATION_CONFIG.ringMinHalfWidth)
    local outerRadius = radius + halfWidth
    local innerRadius = resolvedRingInnerRadius(math.max(radius - halfWidth, 0.01), outerRadius)
    if innerRadius >= outerRadius then return end

    return innerRadius, outerRadius
end

local function ringPlanePoint(origin, axisA, axisB, angleDegrees, pointRadius)
    local angle = math.rad(angleDegrees)
    local dir = axisA * math.cos(angle) + axisB * math.sin(angle)
    return origin + dir * pointRadius
end

local function drawRotationRingBandRealtime(origin, axisA, axisB, innerRadius, outerRadius, fill, edge, segments)
    local material = ensureShapeWhiteMaterial()
    if material then
        render.SetMaterial(material)
        mesh.Begin(MATERIAL_TRIANGLES, segments * 2)
            for step = 0, segments - 1 do
                local angle1 = (step / segments) * 360
                local angle2 = ((step + 1) / segments) * 360
                local outer1 = ringPlanePoint(origin, axisA, axisB, angle1, outerRadius)
                local outer2 = ringPlanePoint(origin, axisA, axisB, angle2, outerRadius)
                local inner1 = ringPlanePoint(origin, axisA, axisB, angle1, innerRadius)
                local inner2 = ringPlanePoint(origin, axisA, axisB, angle2, innerRadius)

                pushTexturedWorldVertex(outer1, 0, 0, fill)
                pushTexturedWorldVertex(outer2, 0, 0, fill)
                pushTexturedWorldVertex(inner2, 0, 0, fill)

                pushTexturedWorldVertex(outer1, 0, 0, fill)
                pushTexturedWorldVertex(inner2, 0, 0, fill)
                pushTexturedWorldVertex(inner1, 0, 0, fill)
            end
        mesh.End()
    end

    for step = 0, segments - 1 do
        local angle1 = (step / segments) * 360
        local angle2 = ((step + 1) / segments) * 360

        drawLine(ringPlanePoint(origin, axisA, axisB, angle1, outerRadius), ringPlanePoint(origin, axisA, axisB, angle2, outerRadius), edge, true)
        drawLine(ringPlanePoint(origin, axisA, axisB, angle1, innerRadius), ringPlanePoint(origin, axisA, axisB, angle2, innerRadius), edge, true)
    end
end

local function drawRotationSectorMask(origin, axisA, axisB, radius, startAngle, delta, segments)
    render.SetColorMaterial()
    mesh.Begin(MATERIAL_TRIANGLES, segments * 2)
        for step = 0, segments - 1 do
            local angle1 = startAngle + delta * (step / segments)
            local angle2 = startAngle + delta * ((step + 1) / segments)
            local point1 = ringPlanePoint(origin, axisA, axisB, angle1, radius)
            local point2 = ringPlanePoint(origin, axisA, axisB, angle2, radius)

            pushTriangle(origin, point1, point2, color_white)
            pushTriangle(origin, point2, point1, color_white)
        end
    mesh.End()
end

local function drawRotationDeltaSectorRealtime(origin, axisA, axisB, radius, startAngle, delta, fill, edge, segments)
    local material = ensureShapeWhiteMaterial()
    if material then
        render.SetMaterial(material)
        mesh.Begin(MATERIAL_TRIANGLES, segments * 2)
            for step = 0, segments - 1 do
                local angle1 = startAngle + delta * (step / segments)
                local angle2 = startAngle + delta * ((step + 1) / segments)
                local point1 = ringPlanePoint(origin, axisA, axisB, angle1, radius)
                local point2 = ringPlanePoint(origin, axisA, axisB, angle2, radius)

                pushTexturedWorldVertex(origin, 0, 0, fill)
                pushTexturedWorldVertex(point1, 0, 0, fill)
                pushTexturedWorldVertex(point2, 0, 0, fill)

                pushTexturedWorldVertex(origin, 0, 0, fill)
                pushTexturedWorldVertex(point2, 0, 0, fill)
                pushTexturedWorldVertex(point1, 0, 0, fill)
            end
        mesh.End()
    end

    for step = 0, segments - 1 do
        local angle1 = startAngle + delta * (step / segments)
        local angle2 = startAngle + delta * ((step + 1) / segments)
        drawLine(ringPlanePoint(origin, axisA, axisB, angle1, radius), ringPlanePoint(origin, axisA, axisB, angle2, radius), edge, true)
    end

    drawLine(origin, ringPlanePoint(origin, axisA, axisB, startAngle, radius), edge, true)
    drawLine(origin, ringPlanePoint(origin, axisA, axisB, startAngle + delta, radius), edge, true)
end

local function drawRotationRingBand(origin, a, b, radius, padding, color, edgeColor, settings)
    if not isvector(origin) or not isvector(a) or not isvector(b) then return end
    if a:LengthSqr() < 1e-8 or b:LengthSqr() < 1e-8 then return end

    settings = settings or activeRingRenderSettings()

    local innerRadius, outerRadius = rotationRingBandRadii(radius, padding)
    if not innerRadius or not outerRadius then return end

    local axisA = a:GetNormalized()
    local axisB = b:GetNormalized()
    local baseColor = color or color_white
    local fill = cappedAlpha(baseColor, ROTATION_CONFIG.ringFillAlpha)
    local edge = edgeColor or cappedAlpha(baseColor, ROTATION_CONFIG.ringEdgeAlpha)
    local segments = ringRenderSegments(settings)
    local cachedRingRtSize = ringRtSize(settings)

    if not settings.realtime and cachedRingRtSize then
        local entry = ensureCachedShape("ring_band", cachedRingRtSize, innerRadius / outerRadius, segments)
        if drawCachedShapePlane(origin, axisA, axisB, outerRadius, entry, baseColor) then
            return
        end
    end

    drawRotationRingBandRealtime(origin, axisA, axisB, innerRadius, outerRadius, fill, edge, segments)
end

local function drawRotationDeltaSector(origin, a, b, radius, padding, startAngle, currentAngle, color, settings)
    if not isvector(origin) or not isvector(a) or not isvector(b) then return end
    if a:LengthSqr() < 1e-8 or b:LengthSqr() < 1e-8 then return end

    settings = settings or activeRingRenderSettings()

    radius = tonumber(radius) or 0
    startAngle = tonumber(startAngle)
    currentAngle = tonumber(currentAngle)
    if radius <= 0 or not startAngle or not currentAngle then return end

    local delta = math.AngleDifference(currentAngle, startAngle)
    if math.abs(delta) <= 0.05 then return end

    local ringPadding = tonumber(padding) or 0
    local bandHalfWidth = math.max(ringPadding * 0.5, ROTATION_CONFIG.ringMinHalfWidth)
    local gap = math.max(ringPadding * 0.16, 0.03)
    local discRadius = math.max(radius - bandHalfWidth - gap, 0.01)
    local axisA = a:GetNormalized()
    local axisB = b:GetNormalized()
    local fill = cappedAlpha(color or color_white, ROTATION_CONFIG.deltaSectorAlpha)
    local edge = cappedAlpha(color or color_white, ROTATION_CONFIG.deltaSectorEdgeAlpha)
    local segmentsPerCircle = ringRenderSegments(settings)
    local segments = math.Clamp(math.ceil(math.abs(delta) / 360 * segmentsPerCircle), 1, segmentsPerCircle)
    local cachedRingRtSize = ringRtSize(settings)

    if not settings.realtime and cachedRingRtSize and stencilAvailable() then
        local entry = ensureCachedShape("disc", cachedRingRtSize, nil, segmentsPerCircle)
        if entry then
            render.ClearStencil()
            render.SetStencilEnable(true)
            render.SetStencilWriteMask(255)
            render.SetStencilTestMask(255)
            render.SetStencilReferenceValue(1)
            render.SetStencilCompareFunction(STENCILCOMPARISONFUNCTION_ALWAYS)
            render.SetStencilFailOperation(STENCILOPERATION_KEEP)
            render.SetStencilPassOperation(STENCILOPERATION_REPLACE)
            render.SetStencilZFailOperation(STENCILOPERATION_REPLACE)

            if render.OverrideColorWriteEnable then
                render.OverrideColorWriteEnable(true, false)
            end
            render.SetBlend(0)
            drawRotationSectorMask(origin, axisA, axisB, discRadius, startAngle, delta, segments)
            render.SetBlend(1)
            if render.OverrideColorWriteEnable then
                render.OverrideColorWriteEnable(false, true)
            end

            render.SetStencilCompareFunction(STENCILCOMPARISONFUNCTION_EQUAL)
            render.SetStencilFailOperation(STENCILOPERATION_KEEP)
            render.SetStencilPassOperation(STENCILOPERATION_KEEP)
            render.SetStencilZFailOperation(STENCILOPERATION_KEEP)

            drawCachedShapePlane(origin, axisA, axisB, discRadius, entry, fill, true)

            render.SetStencilEnable(false)

            drawLine(origin, ringPlanePoint(origin, axisA, axisB, startAngle, discRadius), edge, true)
            drawLine(origin, ringPlanePoint(origin, axisA, axisB, startAngle + delta, discRadius), edge, true)
            return
        end
    end

    drawRotationDeltaSectorRealtime(origin, axisA, axisB, discRadius, startAngle, delta, fill, edge, segments)
end

local function componentForAxisKey(v, key)
    return key == "x" and v.x or key == "y" and v.y or v.z
end

local function handleUsesAxis(item, key)
    if not item or not key then return false end

    if item.kind == "move" then
        return item.key == key
    elseif item.kind == "plane" then
        return item.key:find(key, 1, true) ~= nil
    end

    return false
end

local function axisVectorsForKey(basis, key)
    if not isangle(basis) then return end

    local forward, right, up = M.AngleAxesPrecise(basis)
    if key == "x" then
        return forward, right, up
    elseif key == "y" then
        return right, forward, up
    end

    return up, forward, right
end

local function translationDisplayDistance(key, distance)
    local sign = key == "y" and -1 or 1
    return (tonumber(distance) or 0) * sign
end

local function activeTranslationSnapStep(tool, state)
    local fallback = tool and tool.GetClientInfo and tonumber(tool:GetClientInfo("translation_snap")) or nil
    local step = client.translationSnapStep(tool) or math.Clamp(tonumber(fallback) or 0, 0, 62)
    if step <= 0 then return 0 end

    local settings = state and state.hover and state.hover.settings
    if settings and settings.shift then
        return 0
    end

    if input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT) then
        return 0
    end

    return step
end

local function currentTranslationLocalPos(press)
    if press and isvector(press.currentGizmoPos) then
        return press.currentGizmoPos
    end

    if press and isvector(press.dragStartLocal) then
        return press.dragStartLocal
    end

    return ZERO_VEC
end

local function translationSnapOverlayColor(press)
    local gizmoColor = press and press.gizmo and press.gizmo.color or nil
    if istable(gizmoColor) and gizmoColor.r ~= nil and gizmoColor.g ~= nil and gizmoColor.b ~= nil then
        return gizmoColor
    end

    if press and press.gizmo and colors[press.gizmo.key] then
        return colors[press.gizmo.key]
    end

    return color_white
end

local function drawTranslationAxisTicks(press, size, step, spriteSettings, viewerPos)
    if not press or not press.gizmo or press.gizmo.kind ~= "move" then return end
    if not isvector(press.origin) or not isangle(press.basis) then return end

    local axisDir = select(1, axisVectorsForKey(press.basis, press.gizmo.key))
    if not isvector(axisDir) then return end

    local currentLocal = currentTranslationLocalPos(press)
    local currentIndex = math.Round(componentForAxisKey(currentLocal, press.gizmo.key) / step)
    local halfWindow = math.floor(TRANSLATION_CONFIG.axisTickCount * 0.5)
    local minIndex = currentIndex - halfWindow
    local maxIndex = currentIndex + halfWindow
    local baseColor = translationSnapOverlayColor(press)

    for index = minIndex, maxIndex do
        local worldPos = press.origin + axisDir * translationDisplayDistance(press.gizmo.key, index * step)
        local isCurrent = index == currentIndex
        local isMajor = index == 0 or math.abs(index) % 5 == 0

        local pointRadius = math.Min(step * 0.25, 2.5)
        local pointColor = isCurrent and colorAlpha(color_white, 228) or colorAlpha(baseColor, isMajor and 128 or 82)
        drawCircleSprite(worldPos, pointRadius, pointColor, spriteSettings, viewerPos)
    end

    local currentWorldPos = press.origin + axisDir * translationDisplayDistance(press.gizmo.key, currentIndex * step)
    drawRingSprite(currentWorldPos, math.Clamp(size * 0.042, 0.65, 1.4), math.Clamp(size * 0.012, 0.18, 0.42), color_white, spriteSettings, viewerPos)
end

local function drawTranslationPlaneGrid(press, size, step, spriteSettings, viewerPos)
    if not press or not press.gizmo or press.gizmo.kind ~= "plane" then return end
    if not isvector(press.origin) or not isangle(press.basis) then return end

    local first = press.gizmo.key:sub(1, 1)
    local second = press.gizmo.key:sub(2, 2)
    local axisA = select(1, axisVectorsForKey(press.basis, first))
    local axisB = select(1, axisVectorsForKey(press.basis, second))
    if not isvector(axisA) or not isvector(axisB) then return end

    local currentLocal = currentTranslationLocalPos(press)
    local currentIndexA = math.Round(componentForAxisKey(currentLocal, first) / step)
    local currentIndexB = math.Round(componentForAxisKey(currentLocal, second) / step)
    local minA = currentIndexA - TRANSLATION_CONFIG.gridHalfCells
    local maxA = currentIndexA + TRANSLATION_CONFIG.gridHalfCells
    local minB = currentIndexB - TRANSLATION_CONFIG.gridHalfCells
    local maxB = currentIndexB + TRANSLATION_CONFIG.gridHalfCells
    local baseColor = translationSnapOverlayColor(press)

    for index = minA, maxA do
        local lineStart = press.origin
            + axisA * translationDisplayDistance(first, index * step)
            + axisB * translationDisplayDistance(second, minB * step)
        local lineEnd = press.origin
            + axisA * translationDisplayDistance(first, index * step)
            + axisB * translationDisplayDistance(second, maxB * step)
        local isCurrent = index == currentIndexA
        --local isMajor = index == 0 or math.abs(index) % 5 == 0
        local lineColor = isCurrent and colorAlpha(color_white, 200) or colorAlpha(baseColor, 120)
        drawLine(lineStart, lineEnd, lineColor, false)
    end

    for index = minB, maxB do
        local lineStart = press.origin
            + axisA * translationDisplayDistance(first, minA * step)
            + axisB * translationDisplayDistance(second, index * step)
        local lineEnd = press.origin
            + axisA * translationDisplayDistance(first, maxA * step)
            + axisB * translationDisplayDistance(second, index * step)
        local isCurrent = index == currentIndexB
        --local isMajor = index == 0 or math.abs(index) % 5 == 0
        local lineColor = isCurrent and colorAlpha(color_white, 200) or colorAlpha(baseColor, 120)
        drawLine(lineStart, lineEnd, lineColor, false)
    end

    local currentWorldPos = press.origin
        + axisA * translationDisplayDistance(first, currentIndexA * step)
        + axisB * translationDisplayDistance(second, currentIndexB * step)
    drawRingSprite(currentWorldPos, math.Clamp(size * 0.045, 0.7, 1.5), math.Clamp(size * 0.012, 0.18, 0.42), color_white, spriteSettings, viewerPos)
end

local function drawTranslationSnapOverlay(tool, state, g, spriteSettings, viewerPos)
    local press = state and state.press
    if not press or press.kind ~= "gizmo" or not press.gizmo then return end

    local step = activeTranslationSnapStep(tool, state)
    if step <= 0 then return end

    local size = g and g.size or 32
    if press.gizmo.kind == "move" then
        drawTranslationAxisTicks(press, size, step, spriteSettings, viewerPos)
    elseif press.gizmo.kind == "plane" then
        drawTranslationPlaneGrid(press, size, step, spriteSettings, viewerPos)
    end
end

local reusablePointWorldPositions = {}

local function drawDoubleSidedPlaneSquare(worldPos, axisA, axisB, halfSize, outline, preferredNormal)
    if not isvector(worldPos) or not isvector(axisA) or not isvector(axisB) then return end
    if axisA:LengthSqr() < 1e-8 or axisB:LengthSqr() < 1e-8 then return end

    local a = axisA:GetNormalized() * halfSize
    local b = axisB:GetNormalized() * halfSize
    local normal = a:Cross(b)
    if normal:LengthSqr() < 1e-8 then return end
    normal:Normalize()
    if isvector(preferredNormal) and preferredNormal:LengthSqr() >= 1e-8 and normal:Dot(preferredNormal) < 0 then
        normal = -normal
    end

    local push = normal * 0.12
    local p1 = worldPos - a - b + push
    local p2 = worldPos + a - b + push
    local p3 = worldPos + a + b + push
    local p4 = worldPos - a + b + push
    local edge = outline or color_white

    drawLine(p1, p2, edge, true)
    drawLine(p2, p3, edge, true)
    drawLine(p3, p4, edge, true)
    drawLine(p4, p1, edge, true)
end

local function activeTraceMarkerDirection(state, g, key)
    local press = state.press
    if not press or press.kind ~= "gizmo" or not press.gizmo then return end
    if press.gizmo.kind ~= "move" and press.gizmo.kind ~= "plane" then return end
    if not handleUsesAxis(press.gizmo, key) then return end

    local entry = istable(press.traceSnapAxes) and press.traceSnapAxes[key] or nil
    local direction = entry and entry.direction or nil
    if not isvector(direction) or direction:LengthSqr() < 1e-8 then return end

    return direction:GetNormalized(), entry
end

local function drawFilledTraceSnapSquare(worldPos, axisA, axisB, halfSize, color)
    if not isvector(worldPos) or not isvector(axisA) or not isvector(axisB) then return end
    if axisA:LengthSqr() < 1e-8 or axisB:LengthSqr() < 1e-8 then return end

    local a = axisA:GetNormalized() * halfSize
    local b = axisB:GetNormalized() * halfSize
    local normal = a:Cross(b)
    if normal:LengthSqr() < 1e-8 then return end
    normal:Normalize()

    local push = normal * 0.12
    local p1 = worldPos - a - b + push
    local p2 = worldPos + a - b + push
    local p3 = worldPos + a + b + push
    local p4 = worldPos - a + b + push
    local outline = colorAlpha(color, 255)
    local fill = colorAlpha(color, 76)

    drawFilledQuad(p1, p2, p3, p4, fill)
    drawLine(p1, p2, outline, true)
    drawLine(p2, p3, outline, true)
    drawLine(p3, p4, outline, true)
    drawLine(p4, p1, outline, true)
end

local function drawOutlineTraceSnapSquare(worldPos, axisA, axisB, halfSize, color, preferredNormal)
    drawDoubleSidedPlaneSquare(worldPos, axisA, axisB, halfSize, colorAlpha(color, 244), preferredNormal)
end

local function drawTraceSnapHitCluster(center, outwardDir, axisA, axisB, halfSize, color, traceLength)
    if not isvector(center) or not isvector(outwardDir) or outwardDir:LengthSqr() < 1e-8 then return end

    local dir = outwardDir:GetNormalized()
    local mainHalfSize = halfSize * 2.36
    local copyOffset = math.max((tonumber(traceLength) or 0) * 0.191, 0.01)

    drawFilledTraceSnapSquare(center, axisA, axisB, mainHalfSize, color)
    drawOutlineTraceSnapSquare(center - dir * copyOffset, axisA, axisB, mainHalfSize, color, -dir)
    drawOutlineTraceSnapSquare(center - dir * (copyOffset * 2), axisA, axisB, mainHalfSize, color, -dir)
end

local function drawTraceSnapAxisMarker(origin, direction, axisA, axisB, distance, halfSize, color, traceEntry)
    if distance <= 0 or halfSize <= 0 then return end
    if not isvector(origin) or not isvector(direction) or direction:LengthSqr() < 1e-8 then return end

    local dir = direction:GetNormalized()
    local positiveCenter = origin + dir * distance
    local negativeCenter = origin - dir * distance

    if not istable(traceEntry) then
        drawOutlineTraceSnapSquare(positiveCenter, axisA, axisB, halfSize, color, dir)
        drawOutlineTraceSnapSquare(negativeCenter, axisA, axisB, halfSize, color, -dir)
        return
    end

    if traceEntry.positiveHit then
        drawTraceSnapHitCluster(positiveCenter, dir, axisA, axisB, halfSize, color, distance)
    else
        drawOutlineTraceSnapSquare(positiveCenter, axisA, axisB, halfSize, color, dir)
    end

    if traceEntry.negativeHit then
        drawTraceSnapHitCluster(negativeCenter, -dir, axisA, axisB, halfSize, color, distance)
    else
        drawOutlineTraceSnapSquare(negativeCenter, axisA, axisB, halfSize, color, -dir)
    end
end

local function drawFilledTriangle(a, b, c, color)
    render.SetColorMaterial()
    mesh.Begin(MATERIAL_TRIANGLES, 2)
        pushTriangle(a, b, c, color)
        pushTriangle(c, b, a, color)
    mesh.End()
end

local function pushTexturedVertex(position, u, v, color)
    meshPosition(position)
    mesh.TexCoord(0, u, v)
    mesh.Color(color.r, color.g, color.b, color.a)
    mesh.AdvanceVertex()
end

local function drawTexturedTriangle(a, b, c, uvA, uvB, uvC, color, material)
    if not material then return end

    render.SetMaterial(material)
    mesh.Begin(MATERIAL_TRIANGLES, 2)
        pushTexturedVertex(a, uvA.u, uvA.v, color)
        pushTexturedVertex(b, uvB.u, uvB.v, color)
        pushTexturedVertex(c, uvC.u, uvC.v, color)

        pushTexturedVertex(c, uvC.u, uvC.v, color)
        pushTexturedVertex(b, uvB.u, uvB.v, color)
        pushTexturedVertex(a, uvA.u, uvA.v, color)
    mesh.End()
end

local reusableTriangleUV = { {}, {}, {} }

ensureStripePatternMaterial = function()
    if not stripePatternTexture then
        stripePatternTexture = GetRenderTargetEx(
        STRIPE_CONFIG.patternName .. "_rt",
        STRIPE_CONFIG.rtSize,
        STRIPE_CONFIG.rtSize,
            RT_SIZE_NO_CHANGE,
            MATERIAL_RT_DEPTH_NONE,
            0,
            0,
            IMAGE_FORMAT_RGBA8888
        )
    end

    if not stripeTrianglePatternTexture then
        stripeTrianglePatternTexture = GetRenderTargetEx(
        STRIPE_CONFIG.patternName .. "_triangle_rt",
        STRIPE_CONFIG.rtSize,
        STRIPE_CONFIG.rtSize,
            RT_SIZE_NO_CHANGE,
            MATERIAL_RT_DEPTH_NONE,
            0,
            0,
            IMAGE_FORMAT_RGBA8888
        )
    end

    if not stripePatternMaterial then
    stripePatternMaterial = CreateMaterial(STRIPE_CONFIG.patternName .. "_mat", "UnlitGeneric", {
            ["$basetexture"] = stripePatternTexture:GetName(),
            ["$translucent"] = "1",
            ["$additive"] = "1",
            ["$vertexalpha"] = "1",
            ["$vertexcolor"] = "1",
            ["$model"] = "1"
        })
    end

    if not stripeTrianglePatternMaterial then
    stripeTrianglePatternMaterial = CreateMaterial(STRIPE_CONFIG.patternName .. "_triangle_mat", "UnlitGeneric", {
            ["$basetexture"] = stripeTrianglePatternTexture:GetName(),
            ["$translucent"] = "1",
            ["$additive"] = "1",
            ["$vertexalpha"] = "1",
            ["$vertexcolor"] = "1",
            ["$model"] = "1"
        })
    end

    if not stripePatternScreenMaterial then
    stripePatternScreenMaterial = CreateMaterial(STRIPE_CONFIG.patternName .. "_screen_mat", "UnlitGeneric", {
            ["$basetexture"] = stripePatternTexture:GetName(),
            ["$translucent"] = "1",
            ["$additive"] = "1",
            ["$vertexalpha"] = "1",
            ["$vertexcolor"] = "1"
        })
    end

    stripePatternMaterial:SetTexture("$basetexture", stripePatternTexture)
    stripeTrianglePatternMaterial:SetTexture("$basetexture", stripeTrianglePatternTexture)
    stripePatternScreenMaterial:SetTexture("$basetexture", stripePatternTexture)
    local materialFlags = stripePatternMaterial:GetInt("$flags") or 0
    local requiredFlags = bit.bor(materialFlags, STRIPE_CONFIG.materialFlags)
    if materialFlags ~= requiredFlags then
        stripePatternMaterial:SetInt("$flags", requiredFlags)
    end
    materialFlags = stripeTrianglePatternMaterial:GetInt("$flags") or 0
    requiredFlags = bit.bor(materialFlags, STRIPE_CONFIG.materialFlags)
    if materialFlags ~= requiredFlags then
        stripeTrianglePatternMaterial:SetInt("$flags", requiredFlags)
    end

    if not stripePatternReady then
        local stripeSize = stripePatternStripeSize()

        render.PushRenderTarget(stripePatternTexture)
        render.Clear(0, 0, 0, 0, true, true)
        cam.Start2D()
            -- Named render targets survive Lua refreshes; copy exact intensity values into the RT.
            setStripePatternCopyBlend(true)
        drawStripePatternRect(0, 0, 0, STRIPE_CONFIG.rtSize, STRIPE_CONFIG.rtSize)
        drawStripePatternRect(STRIPE_CONFIG.fillAlpha, 0, 0, STRIPE_CONFIG.rtSize, STRIPE_CONFIG.rtSize)
        drawStripePatternRect(STRIPE_CONFIG.stripeAlpha, 0, 0, STRIPE_CONFIG.rtSize, stripeSize)
            setStripePatternCopyBlend(false)
        cam.End2D()
        render.PopRenderTarget()

        render.PushRenderTarget(stripeTrianglePatternTexture)
        render.Clear(0, 0, 0, 0, true, true)
        cam.Start2D()
            setStripePatternCopyBlend(true)
        drawStripePatternRect(0, 0, 0, STRIPE_CONFIG.rtSize, STRIPE_CONFIG.rtSize)
        drawStripePatternRect(STRIPE_CONFIG.fillAlpha, 0, 0, STRIPE_CONFIG.rtSize, STRIPE_CONFIG.rtSize)
        drawStripePatternDiagonal(STRIPE_CONFIG.stripeAlpha)
            setStripePatternCopyBlend(false)
        cam.End2D()
        render.PopRenderTarget()

        stripePatternReady = true
    end

    return stripeTrianglePatternMaterial
end

local function queueStripePatternRebuild()
    stripePatternReady = false

    hook.Remove("PostRender", STRIPE_CONFIG.rebuildHook)
    hook.Add("PostRender", STRIPE_CONFIG.rebuildHook, function()
        ensureStripePatternMaterial()
        hook.Remove("PostRender", STRIPE_CONFIG.rebuildHook)
    end)
end

queueStripePatternRebuild()

if cvars and cvars.AddChangeCallback then
    if cvars.RemoveChangeCallback then
    cvars.RemoveChangeCallback(RENDER_CONFIG.ringQualityCvar, SHAPE_CONFIG.rebuildCallback)
    end

    cvars.AddChangeCallback(RENDER_CONFIG.ringQualityCvar, function()
        queueShapeCacheWarmup()
    end, SHAPE_CONFIG.rebuildCallback)
end

queueShapeCacheWarmup()

local function drawStripedTriangle(a, b, c, frontColor, stripePhase, viewerPos)
    if not isvector(a) or not isvector(b) or not isvector(c) then return end

    local ab = b - a
    local ac = c - a
    local normal = ab:Cross(ac)
    if normal:LengthSqr() < 1e-8 then return end
    normal:Normalize()

    viewerPos = isvector(viewerPos)
        and viewerPos
        or setVec(shapeMetricCache.renderPerf.fallbackViewerPos, IsValid(LocalPlayer()) and LocalPlayer():GetShootPos() or EyePos())
    shapeMetricCache.renderPerf.fallbackViewerPos = viewerPos
    local center = (a + b + c) / 3
    local frontFacing = normal:Dot(viewerPos - center) >= 0
    local visibleNormal = frontFacing and normal or -normal
    local push = visibleNormal * 0.08
    local tintColor = frontFacing
        and cachedColor(frontColor.r, frontColor.g, frontColor.b, 220)
        or cachedColor(155, 155, 155, 255)
    local edgeColor = frontFacing and cappedAlpha(frontColor, 36) or cachedColor(165, 165, 165, 32)

    local pa = a + push
    local pb = b + push
    local pc = c + push

    local u = ab:GetNormalized()
    local v = ac - u * ac:Dot(u)
    if v:LengthSqr() < 1e-8 then return end
    local vLen = v:Length()
    v:Normalize()

    local bx = ab:Length()
    local cx = ac:Dot(u)
    local cy = vLen
    local distance = math.max(viewerPos:Distance(center), 1)
    local tileSize = math.max(1, STRIPE_CONFIG.rtSize * stripeDistanceScale(distance))
    local centerScreen = center:ToScreen()
    local pixelsPerWorld = 0
    if centerScreen then
        pixelsPerWorld = (
            screenPointDistance(centerScreen, (center + u):ToScreen())
            + screenPointDistance(centerScreen, (center + v):ToScreen())
        ) * 0.5
    end

    local stripePeriod = STRIPE_CONFIG.worldTile * math.sqrt(2)
    if pixelsPerWorld > 1e-4 then
        stripePeriod = math.max(0.01, tileSize / pixelsPerWorld)
    end
    local phase = ((tonumber(stripePhase) or 0) % 1)
    local stripeMaterial = ensureStripePatternMaterial()

    if stripeMaterial then
        reusableTriangleUV[1].u = 0
        reusableTriangleUV[1].v = -phase
        reusableTriangleUV[2].u = bx / stripePeriod
        reusableTriangleUV[2].v = -phase
        reusableTriangleUV[3].u = cx / stripePeriod
        reusableTriangleUV[3].v = cy / stripePeriod - phase

        drawTexturedTriangle(
            pa,
            pb,
            pc,
            reusableTriangleUV[1],
            reusableTriangleUV[2],
            reusableTriangleUV[3],
            scaledAlphaColor(tintColor, STRIPE_CONFIG.triangleAlphaScale),
            stripeMaterial
        )
    else
        drawFilledTriangle(pa, pb, pc, frontFacing and cappedAlpha(frontColor, STRIPE_CONFIG.fillAlpha) or Color(105, 105, 105, STRIPE_CONFIG.fillAlpha))
    end

    drawLine(pa, pb, edgeColor, false)
    drawLine(pb, pc, edgeColor, false)
    drawLine(pc, pa, edgeColor, false)
end

local function drawAxisArrow(startPos, endPos, color, viewerPos)
    if not isvector(startPos) or not isvector(endPos) then return end

    local axis = endPos - startPos
    local length = axis:Length()
    if length < 0.01 then return end

    axis:Normalize()

    local center = (startPos + endPos) * 0.5
    viewerPos = isvector(viewerPos)
        and viewerPos
        or setVec(shapeMetricCache.renderPerf.fallbackViewerPos, IsValid(LocalPlayer()) and LocalPlayer():GetShootPos() or EyePos())
    shapeMetricCache.renderPerf.fallbackViewerPos = viewerPos
    local toViewer = viewerPos - center
    local width = axis:Cross(toViewer)
    if width:LengthSqr() < 1e-8 then
        width = axis:Cross(math.abs(axis.z) < 0.99 and VectorP(0, 0, 1) or VectorP(0, 1, 0))
    end
    if width:LengthSqr() < 1e-8 then return end
    width:Normalize()

    local normal = width:Cross(axis)
    if normal:LengthSqr() > 1e-8 then
        normal:Normalize()
    else
        normal = VectorP(0, 0, 1)
    end

    local push = normal * 0.08
    local shaftHalf = math.Clamp(length * 0.006, 0.06, 0.22)
    local headHalf = shaftHalf * 3.8
    local headLength = math.Clamp(length * 0.16, shaftHalf * 4.2, length * 0.28)
    local headBase = endPos - axis * headLength

    local tailLeft = startPos - width * shaftHalf + push
    local tailRight = startPos + width * shaftHalf + push
    local baseLeft = headBase - width * shaftHalf + push
    local baseRight = headBase + width * shaftHalf + push
    local headLeft = headBase - width * headHalf + push
    local headRight = headBase + width * headHalf + push
    local tip = endPos + push
    local fill = cappedAlpha(color, 225)
    local outline = cachedColor(
        math.min(color.r + 55, 255),
        math.min(color.g + 55, 255),
        math.min(color.b + 55, 255),
        math.min((color.a or 255) + 26, 110)
    )

    drawFilledQuad(tailLeft, baseLeft, baseRight, tailRight, fill)
    drawFilledTriangle(headLeft, tip, headRight, fill)

    drawLine(tailLeft, baseLeft, outline, true)
    drawLine(tailRight, baseRight, outline, true)
    drawLine(headLeft, tip, outline, true)
    drawLine(tip, headRight, outline, true)
    drawLine(tailLeft, tailRight, outline, true)
    drawLine(headLeft, headRight, outline, true)
end

local function drawFrame(pos, ang, size, alpha)
    render.DrawLine(toVector(pos), toVector(pos + ang:Forward() * size), cachedColor(colors.x.r, colors.x.g, colors.x.b, alpha), true)
    render.DrawLine(toVector(pos), toVector(pos + ang:Right() * size), cachedColor(colors.y.r, colors.y.g, colors.y.b, alpha), true)
    render.DrawLine(toVector(pos), toVector(pos + ang:Up() * size), cachedColor(colors.z.r, colors.z.g, colors.z.b, alpha), true)
end

local function shouldDrawPointTriangle(spriteSettings)
    return not (spriteSettings and spriteSettings.hidePointTriangles == true)
end

local function anchorPercent(options, key)
    return ((options and options[key .. "_pct"]) or M.ANCHOR_PERCENT_DEFAULT) * 0.01
end

local function lerpPointFast(a, b, t)
    return VectorP(
        a.x + (b.x - a.x) * t,
        a.y + (b.y - a.y) * t,
        a.z + (b.z - a.z) * t
    )
end

local function anchorPointFast(points, id, options)
    local p1, p2, p3 = points[1], points[2], points[3]

    if id == "p1" then return p1 end
    if id == "p2" then return p2 end
    if id == "p3" then return p3 end
    if id == "mid12" and p1 and p2 then return lerpPointFast(p1, p2, anchorPercent(options, "mid12")) end
    if id == "mid23" and p2 and p3 then return lerpPointFast(p2, p3, anchorPercent(options, "mid23")) end
    if id == "mid13" and p1 and p3 then return lerpPointFast(p1, p3, anchorPercent(options, "mid13")) end

    if id == M.ANCHOR_CENTER_ID and p1 and p2 and p3 then
        local m12 = lerpPointFast(p1, p2, anchorPercent(options, "mid12"))
        local m23 = lerpPointFast(p2, p3, anchorPercent(options, "mid23"))
        local m13 = lerpPointFast(p1, p3, anchorPercent(options, "mid13"))

        return VectorP(
            (m12.x + m23.x + m13.x) / 3,
            (m12.y + m23.y + m13.y) / 3,
            (m12.z + m23.z + m13.z) / 3
        )
    end
end

local function drawPointSet(ent, points, color, posOverride, angOverride, stripePhase, triangleColor, anchorConfig, spriteSettings, viewerPos)
    if #points < 1 then return end

    local basePos, baseAng
    if isvector(posOverride) and isangle(angOverride) then
        basePos, baseAng = posOverride, angOverride
    elseif M.IsWorldTarget and M.IsWorldTarget(ent) then
        basePos, baseAng = ZERO_VEC, ZERO_ANG
    elseif IsValid(ent) then
        basePos, baseAng = ent:GetPos(), ent:GetAngles()
    else
        return
    end

    local worldPoints = reusablePointWorldPositions
    for i = 1, #points do
        worldPoints[i] = LocalToWorldPosPrecise(points[i], basePos, baseAng)
    end
    for i = #points + 1, #worldPoints do
        worldPoints[i] = nil
    end

    if shouldDrawPointTriangle(spriteSettings) and worldPoints[1] and worldPoints[2] and worldPoints[3] then
        drawStripedTriangle(worldPoints[1], worldPoints[2], worldPoints[3], triangleColor or color, stripePhase, viewerPos)
    end

    local mainRadius = 1.35
    local midRadius = mainRadius * 0.5
    local function anchorWorldPos(id)
        local localPos = anchorPointFast(points, id, anchorConfig)
        if not isvector(localPos) then return end

        return LocalToWorldPosPrecise(localPos, basePos, baseAng)
    end

    local mid12World = anchorWorldPos("mid12")
    local mid23World = anchorWorldPos("mid23")
    local mid13World = anchorWorldPos("mid13")

    if worldPoints[2] and worldPoints[3] then
        drawLine(worldPoints[2], worldPoints[3], cappedAlpha(color, 170), true)
    end
    if worldPoints[1] and worldPoints[3] then
        drawLine(worldPoints[1], worldPoints[3], cappedAlpha(color, 170), true)
    end

    if mid12World then
        drawCircleSprite(mid12World, midRadius, cappedAlpha(color, 185), spriteSettings, viewerPos)
    end
    if mid23World then
        drawCircleSprite(mid23World, midRadius, cappedAlpha(color, 185), spriteSettings, viewerPos)
    end
    if mid13World then
        drawCircleSprite(mid13World, midRadius, cappedAlpha(color, 185), spriteSettings, viewerPos)
    end

    local centerWorld = anchorWorldPos(M.ANCHOR_CENTER_ID)
    if centerWorld then
        drawCircleSprite(centerWorld, midRadius * 0.9, cappedAlpha(color, 165), spriteSettings, viewerPos)
    end

    for i = 1, #worldPoints do
        drawCircleSprite(worldPoints[i], mainRadius, color, spriteSettings, viewerPos)
    end

    if worldPoints[1] and worldPoints[2] then
        drawAxisArrow(worldPoints[2], worldPoints[1], color, viewerPos)
    end
end

local function drawPoints(ent, points, color, anchorId, anchorConfig)
    local basePos, baseAng
    if M.IsWorldTarget and M.IsWorldTarget(ent) then
        basePos, baseAng = ZERO_VEC, ZERO_ANG
    elseif IsValid(ent) then
        basePos, baseAng = ent:GetPos(), ent:GetAngles()
    else
        return
    end

    for i = 1, #points do
        local world = LocalToWorldPosPrecise(points[i], basePos, baseAng)
        local screen = world:ToScreen()
        if screen.visible then
            draw.SimpleTextOutlined("P" .. i, "DermaDefault", screen.x + 8, screen.y - 8, color, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM, 1, color_black)
        end
    end

    if not anchorId then return end

    local anchor = anchorPointFast(points, anchorId, anchorConfig)
    if not anchor then return end

    local world = LocalToWorldPosPrecise(anchor, basePos, baseAng)
    local screen = world:ToScreen()
    if screen.visible then
        draw.SimpleTextOutlined("A", "DermaDefault", screen.x, screen.y, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
    end
end

local function isDrawingPickPress(state)
    local press = state and state.press
    if not press then return false end

    if press.drawActive ~= true then
        return false
    end

    return press.kind == "pick"
        or press.kind == "select_source_pick"
        or press.kind == "select_target_pick"
end

local function shouldRenderHoverGrid(state, hoverCandidate)
    if not hoverCandidate or not hoverCandidate.face or not IsValid(hoverCandidate.ent) then return false end

    local settings = state and state.hover and state.hover.settings
    if isDrawingPickPress(state) then return false end

    if settings and settings.shift then return false end

    return true
end

local function shouldRenderHoverFace(state, hoverCandidate)
    if not hoverCandidate or not hoverCandidate.face or not IsValid(hoverCandidate.ent) then return false end
    if isDrawingPickPress(state) then return false end

    return true
end

local function sideAccentColor(side)
    if side == "source" then
        return colors.source
    elseif side == "target" then
        return colors.target
    end

    return colors.pending
end

local function activePickAccentColor(state)
    local press = state and state.press
    if not press or not isDrawingPickPress(state) then
        return colors.pending
    end

    return sideAccentColor(press.side)
end

local hoverRender = {}

function hoverRender.drawGridLabels(state, candidate)
    if not shouldRenderHoverGrid(state, candidate) then return end

    local face = candidate.face
    local labelColor = cachedColor(255, 255, 255, GRID_CONFIG.snapLabelAlpha)

    if face.snapGridU and face.uSnap then
        local a, b = faceLineWorldPoints(candidate.ent, face, face.snapGridU, "u", face.uSnap)
        if a and b then
            drawSnapLineLabels2D(a, b, formatGridLineLabel(face, "u"), labelColor)
        end
    end

    if face.snapGridV and face.vSnap then
        local a, b = faceLineWorldPoints(candidate.ent, face, face.snapGridV, "v", face.vSnap)
        if a and b then
            drawSnapLineLabels2D(a, b, formatGridLineLabel(face, "v"), labelColor)
        end
    end
end

function hoverRender.drawFaceOutline(state, candidate)
    if not shouldRenderHoverFace(state, candidate) then return end

    local face = candidate.face
    local ent = candidate.ent
    local corners = face.corners
    local entPos = ent:GetPos()
    local entAng = ent:GetAngles()

    for i = 1, 4 do
        drawLine(
            LocalToWorldPosPrecise(corners[i], entPos, entAng),
            LocalToWorldPosPrecise(corners[i % 4 + 1], entPos, entAng),
            cachedColor(255, 255, 255, 70),
            true
        )
    end
end

function hoverRender.drawGrid(state, candidate)
    if not shouldRenderHoverGrid(state, candidate) then return end

    local face = candidate.face
    local ent = candidate.ent
    local renderPerf = shapeMetricCache.renderPerf
    local gridSets = renderPerf.reusableGridSets or {}
    local seen = renderPerf.reusableGridSeen or {}
    renderPerf.reusableGridSets = gridSets
    renderPerf.reusableGridSeen = seen
    for i = 1, #gridSets do
        gridSets[i] = nil
    end
    for grid in pairs(seen) do
        seen[grid] = nil
    end

    local function addGrid(grid)
        if not grid or seen[grid] then return end
        seen[grid] = true
        gridSets[#gridSets + 1] = grid
    end

    addGrid(face.gridA)
    addGrid(face.gridB)
    addGrid(face.snapGridU)
    addGrid(face.snapGridV)

    for _, grid in ipairs(gridSets) do
        local lineAlpha = currentGridLineAlpha(grid == face.gridA)

        for uIndex = 0, math.max(grid.divU or 0, 0) do
            local u = uIndex == (grid.divU or 0) and grid.uMax or (grid.uMin + grid.stepU * uIndex)
            local a, b = faceLineWorldPoints(ent, face, grid, "u", u)
            if a and b then
                drawLine(a, b, cachedColor(255, 255, 255, lineAlpha), false)
            end
        end

        for vIndex = 0, math.max(grid.divV or 0, 0) do
            local v = vIndex == (grid.divV or 0) and grid.vMax or (grid.vMin + grid.stepV * vIndex)
            local a, b = faceLineWorldPoints(ent, face, grid, "v", v)
            if a and b then
                drawLine(a, b, cachedColor(255, 255, 255, lineAlpha), false)
            end
        end
    end

    if face.snapGridU and face.uSnap then
        local a, b = faceLineWorldPoints(ent, face, face.snapGridU, "u", face.uSnap)
        if a and b then
            drawLine(a, b, cachedColor(255, 255, 255, GRID_CONFIG.snapLineAlpha), false)
        end
    end

    if face.snapGridV and face.vSnap then
        local a, b = faceLineWorldPoints(ent, face, face.snapGridV, "v", face.vSnap)
        if a and b then
            drawLine(a, b, cachedColor(255, 255, 255, GRID_CONFIG.snapLineAlpha), false)
        end
    end
end

local function clearReusableEntries(entries, lastUsed)
    if not istable(entries) then return end

    for i = (tonumber(lastUsed) or 0) + 1, #entries do
        entries[i] = nil
    end
end

local function reusableEntry(entries, index)
    local entry = entries[index]
    if not istable(entry) then
        entry = {}
        entries[index] = entry
    end

    return entry
end

function TOOL:DrawHUD()
    local tool, state = client.activeTool()
    if tool ~= self then return end
    if not client.validateState(self, state) then return end

    local hoverCandidate = state.hover and (state.hover.candidate or state.hover.overlay)
    local sourceAnchorOptions = anchorOptions(tool, "from")
    local targetAnchorOptions = anchorOptions(tool, "to")

    drawPoints(state.prop1, state.source, colors.source, state.preview and state.preview.solve and state.preview.solve.sourceAnchorId, sourceAnchorOptions)
    drawPoints(state.prop2, state.target, colors.target, state.preview and state.preview.solve and state.preview.solve.targetAnchorId, targetAnchorOptions)
    hoverRender.drawGridLabels(state, hoverCandidate)
end

hook.Add("PostDrawTranslucentRenderables", "magic_align_draw", function(bDrawingDepth, bDrawingSkybox)
    if bDrawingDepth or bDrawingSkybox then return end

    local tool, state = client.activeTool()
    if not tool then
        if M.ClientState and IsValid(M.ClientState.ghost) then
            M.ClientState.ghost:SetNoDraw(true)
        end
        if M.ClientState and istable(M.ClientState.linkedGhosts) then
            for _, ghost in pairs(M.ClientState.linkedGhosts) do
                if IsValid(ghost) then
                    ghost:SetNoDraw(true)
                end
            end
        end
        return
    end
    if not client.validateState(tool, state) then return end

    local markerColor = selectionColor(state)
    local wireMarkers = shapeMetricCache.renderPerf.reusableWireMarkers or {}
    shapeMetricCache.renderPerf.reusableWireMarkers = wireMarkers

    local wireMarkerCount = 0
    wireMarkerCount = wireMarkerCount + 1
    local sourceMarker = reusableEntry(wireMarkers, wireMarkerCount)
    sourceMarker.ent = state.prop1
    sourceMarker.color = markerColor
    sourceMarker.alpha = 72

    wireMarkerCount = wireMarkerCount + 1
    local targetMarker = reusableEntry(wireMarkers, wireMarkerCount)
    targetMarker.ent = state.prop2
    targetMarker.color = colors.target
    targetMarker.alpha = 72

    for i = 1, #(state.linked or {}) do
        wireMarkerCount = wireMarkerCount + 1
        local linkedMarker = reusableEntry(wireMarkers, wireMarkerCount)
        linkedMarker.ent = state.linked[i]
        linkedMarker.color = markerColor
        linkedMarker.alpha = 34
    end
    clearReusableEntries(wireMarkers, wireMarkerCount)
    shapeMetricCache.renderPerf.drawWireMarkerBatch(wireMarkers, true)

    local ghostEntries = shapeMetricCache.renderPerf.reusableGhostEntries or {}
    shapeMetricCache.renderPerf.reusableGhostEntries = ghostEntries
    ghostEntries._magicAlignCount = 0
    shapeMetricCache.renderPerf.addGhostRenderEntry(ghostEntries, state.ghost, 0.08, 0.65)
    if istable(state.linkedGhosts) then
        for _, ghost in pairs(state.linkedGhosts) do
            shapeMetricCache.renderPerf.addGhostRenderEntry(ghostEntries, ghost, 0.05, 0.38)
        end
    end
    clearReusableEntries(ghostEntries, ghostEntries._magicAlignCount)

    if previewOccludedEnabled(tool) then
        for i = 1, #ghostEntries do
            local entry = ghostEntries[i]
            drawPreviewOccludedGhost(tool, entry.ghost, entry.alpha)
        end
        drawPreviewOccludedCompatGhosts(tool, state)
    end

    shapeMetricCache.renderPerf.drawGhostRenderEntries(ghostEntries)

    local hoverCandidate = state.hover and (state.hover.candidate or state.hover.overlay)
    local sourceAnchorOptions = anchorOptions(tool, "from")
    local targetAnchorOptions = anchorOptions(tool, "to")
    local spriteSettings = ringRenderSettingsForTool(tool)
    local viewerPos = setVec(shapeMetricCache.renderPerf.viewerPos, IsValid(LocalPlayer()) and LocalPlayer():GetShootPos() or EyePos())
    shapeMetricCache.renderPerf.viewerPos = viewerPos
    cam.IgnoreZ(true)

    hoverRender.drawFaceOutline(state, hoverCandidate)
    hoverRender.drawGrid(state, hoverCandidate)

    drawPointSet(state.prop1, state.source, colors.source, nil, nil, 0, nil, sourceAnchorOptions, spriteSettings, viewerPos)
    drawPointSet(state.prop2, state.target, colors.target, nil, nil, 0.5, nil, targetAnchorOptions, spriteSettings, viewerPos)
    if state.preview and state.preview.pos and state.preview.ang and #state.source > 0 then
        drawPointSet(
            nil,
            state.source,
            cachedColor(120, 255, 150, 5),
            state.preview.pos,
            state.preview.ang,
            0,
            cachedColor(120, 255, 150, 128),
            sourceAnchorOptions,
            spriteSettings,
            viewerPos
        )
    end

    if state.press and isDrawingPickPress(state) and state.press.samples then
        local samples = state.press.samples
        local pathColor = activePickAccentColor(state)
        for i = 2, #samples do
            local a = client.sampleWorldPos(state.press.ent, samples[i - 1]) or samples[i - 1].pos
            local b = client.sampleWorldPos(state.press.ent, samples[i]) or samples[i].pos
            if isvector(a) and isvector(b) then
                drawLine(a, b, pathColor, true)
            end
        end

        if tool:GetClientNumber("show_trace_probes") == 1
            and IsValid(state.press.ent)
            and istable(state.press.aggregatedProbes) then
            for i = 1, #state.press.aggregatedProbes do
                local probe = state.press.aggregatedProbes[i]
                if isvector(probe.localPos) then
                    local worldPos = LocalToWorldPosPrecise(probe.localPos, state.press.ent:GetPos(), state.press.ent:GetAngles())
                    drawCircleSprite(worldPos, 0.22, colorAlpha(pathColor, 190), spriteSettings, viewerPos)
                end
            end
        end
    end

    if hoverCandidate and not isDrawingPickPress(state) then
            drawCircleSprite(hoverCandidate.worldPos, 1.2, colorAlpha(colors.preview, 210), spriteSettings, viewerPos)
    end

    if state.hover and state.hover.point then
        drawRingSprite(state.hover.point.worldPos, 1.7, 0.55, color_white, spriteSettings, viewerPos, true)
    end

    if state.corner and isDrawingPickPress(state) then
        local cornerColor = activePickAccentColor(state)
        drawCircleSprite(state.corner.worldPos, 1.05, colorAlpha(cornerColor, 215), spriteSettings, viewerPos)
        if isvector(state.corner.axisWorldDir) then
            local axisHalfLength = math.Clamp(IsValid(state.corner.ent) and state.corner.ent:BoundingRadius() * 0.18 or 12, 8, 28)
            drawLine(
                state.corner.worldPos - state.corner.axisWorldDir * axisHalfLength,
                state.corner.worldPos + state.corner.axisWorldDir * axisHalfLength,
                colorAlpha(cornerColor, 230),
                true
            )
        end
        drawLine(state.corner.worldPos, state.corner.worldPos + state.corner.normal * 10, cornerColor, true)
    end

    if state.pending then
        drawFrame(LocalToWorldPosPrecise(state.pending.solve.sourceAnchorLocal, state.pending.pos, state.pending.ang), state.pending.ang, 10, 120)
    end

    if state.preview and state.preview.solve then
        local solve = state.preview.solve
        local baseAnchor = LocalToWorldPosPrecise(solve.sourceAnchorLocal, solve.pos, solve.ang)
        local liveAnchor = LocalToWorldPosPrecise(solve.sourceAnchorLocal, state.preview.pos, state.preview.ang)
        local liveContext = LocalToWorldPosPrecise(solve.sourceContextLocal and solve.sourceContextLocal.pos or solve.sourceAnchorLocal, state.preview.pos, state.preview.ang)

        drawFrame(baseAnchor, solve.ang, 12, 80)
        drawFrame(liveAnchor, state.preview.ang, 16, 220)
        drawFrame(liveContext, solve.axisAng, 8, 110)

        local g = client.gizmo(tool, state)
        if g then
            local showRotation = g.disableRotation ~= true
            local axisHandleRadius = g.size * 0.09
            local traceSnapLength = tool and tool.GetClientInfo and tonumber(tool:GetClientInfo("trace_snap_length")) or 0
            local traceMarkerHalfSize = math.Clamp(math.min(g.size * 0.028, traceSnapLength * 0.14), 0.24, 0.95)
            local press = state.press
            local activeHandle = press and press.kind == "gizmo" and press.space == g.space and press.gizmo or nil
            local basisForward, basisRight, basisUp = M.AngleAxesPrecise(g.basis)
            local xHandle = M.AddVectorsPrecise(g.origin, M.ScaleVectorPrecise(basisForward, g.size))
            local yHandle = M.AddVectorsPrecise(g.origin, M.ScaleVectorPrecise(basisRight, g.size))
            local zHandle = M.AddVectorsPrecise(g.origin, M.ScaleVectorPrecise(basisUp, g.size))

            local function shouldDrawHandle(kind, key)
                if not activeHandle then return true end

                return activeHandle.kind == kind and activeHandle.key == key
            end

            if shouldDrawHandle("move", "x") then
                drawLine(g.origin, M.SubtractVectorsPrecise(xHandle, M.ScaleVectorPrecise(basisForward, axisHandleRadius)), colors.x, true)
                drawCircleSprite(xHandle, axisHandleRadius, colors.x, spriteSettings, viewerPos)
            end
            if shouldDrawHandle("move", "y") then
                drawLine(g.origin, M.SubtractVectorsPrecise(yHandle, M.ScaleVectorPrecise(basisRight, axisHandleRadius)), colors.y, true)
                drawCircleSprite(yHandle, axisHandleRadius, colors.y, spriteSettings, viewerPos)
            end
            if shouldDrawHandle("move", "z") then
                drawLine(g.origin, M.SubtractVectorsPrecise(zHandle, M.ScaleVectorPrecise(basisUp, axisHandleRadius)), colors.z, true)
                drawCircleSprite(zHandle, axisHandleRadius, colors.z, spriteSettings, viewerPos)
            end

            if shouldDrawHandle("plane", "xy") then
                drawPlaneSquare(M.AddVectorsPrecise(M.AddVectorsPrecise(g.origin, M.ScaleVectorPrecise(basisForward, g.planeOffset)), M.ScaleVectorPrecise(basisRight, g.planeOffset)), basisForward, basisRight, g.size * 0.11, colors.xy)
            end
            if shouldDrawHandle("plane", "xz") then
                drawPlaneSquare(M.AddVectorsPrecise(M.AddVectorsPrecise(g.origin, M.ScaleVectorPrecise(basisForward, g.planeOffset)), M.ScaleVectorPrecise(basisUp, g.planeOffset)), basisForward, basisUp, g.size * 0.11, colors.xz, nil, true, true)
            end
            if shouldDrawHandle("plane", "yz") then
                drawPlaneSquare(M.AddVectorsPrecise(M.AddVectorsPrecise(g.origin, M.ScaleVectorPrecise(basisRight, g.planeOffset)), M.ScaleVectorPrecise(basisUp, g.planeOffset)), basisRight, basisUp, g.size * 0.11, colors.yz)
            end

            if traceSnapLength > 0 then
                local xTraceDir, xTrace = activeTraceMarkerDirection(state, g, "x")
                local yTraceDir, yTrace = activeTraceMarkerDirection(state, g, "y")
                local zTraceDir, zTrace = activeTraceMarkerDirection(state, g, "z")

                if xTraceDir then
                    drawTraceSnapAxisMarker(g.origin, xTraceDir, basisRight, basisUp, traceSnapLength, traceMarkerHalfSize, colors.x, xTrace)
                end
                if yTraceDir then
                    drawTraceSnapAxisMarker(g.origin, yTraceDir, basisForward, basisUp, traceSnapLength, traceMarkerHalfSize, colors.y, yTrace)
                end
                if zTraceDir then
                    drawTraceSnapAxisMarker(g.origin, zTraceDir, basisForward, basisRight, traceSnapLength, traceMarkerHalfSize, colors.z, zTrace)
                end
            end

            drawTranslationSnapOverlay(tool, state, g, spriteSettings, viewerPos)

            local ringRenderSettings = showRotation and spriteSettings or nil
            if showRotation then
                local rotationRings = {
                    { key = "roll", axis = basisForward, a = basisRight, b = basisUp, c = colors.x },
                    { key = "pitch", axis = basisRight, a = basisForward, b = basisUp, c = colors.y },
                    { key = "yaw", axis = basisUp, a = basisForward, b = basisRight, c = colors.z }
                }
                local rotationSnapEnabled = not (input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT))
                local activeRotationKey = rotationSnapEnabled and g.hover and g.hover.kind == "rot" and g.hover.key or nil
                local rotationDivisions = client.rotationSnapDivisions(tool)
                local rotationStep = client.rotationSnapStep(tool) or (360 / math.max(rotationDivisions, 1))

                for _, item in ipairs(rotationRings) do
                    if shouldDrawHandle("rot", item.key) then
                        drawRotationRingBand(g.origin, item.a, item.b, g.ringRadius, g.ringPadding, item.c, nil, ringRenderSettings)

                        if press and press.kind == "gizmo"
                            and press.gizmo and press.gizmo.kind == "rot"
                            and press.gizmo.key == item.key
                            and press.startRingAngle and press.currentRingAngle then
                            local sectorStartAngle = math.deg(press.startRingAngle)
                            local sectorCurrentAngle = press.currentRingAngle
                            if rotationSnapEnabled then
                                sectorStartAngle = snapRotationDisplayAngle(sectorStartAngle, rotationStep)
                                sectorCurrentAngle = snapRotationDisplayAngle(sectorCurrentAngle, rotationStep)
                            end

                            drawRotationDeltaSector(
                                g.origin,
                                item.a,
                                item.b,
                                g.ringRadius,
                                g.ringPadding,
                                sectorStartAngle,
                                sectorCurrentAngle,
                                item.c,
                                ringRenderSettings
                            )
                        end

                        if activeRotationKey == item.key and rotationDivisions > 0 then
                            local fallbackAngle = press and press.kind == "gizmo"
                                and press.gizmo and press.gizmo.kind == "rot"
                                and press.gizmo.key == item.key
                                and math.deg(press.startRingAngle)
                                or 0
                            local cursorAngle = press and press.kind == "gizmo"
                                and press.gizmo and press.gizmo.kind == "rot"
                                and press.gizmo.key == item.key
                                and press.currentRingAngle
                                or g.hover and g.hover.kind == "rot"
                                and g.hover.key == item.key
                                and g.hover.cursorAngle
                                or fallbackAngle
                            cursorAngle = normalizeDegrees(cursorAngle)
                            local ticks = visibleRotationTicks(rotationDivisions, rotationStep, cursorAngle, ringRenderSettings)
                            drawRotationRingTicks(g.origin, item.a, item.b, g.ringRadius - g.ringPadding * 0.5, g.size, ticks, colorAlpha(color_white, 220))
                        end
                    end
                end
            end

            if g.hover and shouldDrawHandle(g.hover.kind, g.hover.key) then
                if g.hover.kind == "move" then
                    local axisDir = g.hover.key == "x" and basisForward
                        or g.hover.key == "y" and basisRight
                        or basisUp
                    drawLine(g.hover.a, g.hover.b - axisDir * axisHandleRadius, color_white, true)
                    drawRingSprite(g.hover.b, g.size * 0.09, g.size * 0.022, color_white, ringRenderSettings, viewerPos, true)
                elseif g.hover.kind == "plane" then
                    if g.hover.key == "xy" then
                        drawPlaneSquare(g.hover.center, basisForward, basisRight, g.size * 0.135, g.hover.color or colors.xy, color_white)
                    elseif g.hover.key == "xz" then
                        drawPlaneSquare(g.hover.center, basisForward, basisUp, g.size * 0.135, g.hover.color or colors.xz, color_white, true, true)
                    else
                        drawPlaneSquare(g.hover.center, basisRight, basisUp, g.size * 0.135, g.hover.color or colors.yz, color_white)
                    end
                elseif g.hover.key == "roll" then
                    drawRotationRingBand(g.origin, basisRight, basisUp, g.ringRadius, g.ringPadding, color_white, nil, ringRenderSettings)
                elseif g.hover.key == "pitch" then
                    drawRotationRingBand(g.origin, basisForward, basisUp, g.ringRadius, g.ringPadding, color_white, nil, ringRenderSettings)
                else
                    drawRotationRingBand(g.origin, basisForward, basisRight, g.ringRadius, g.ringPadding, color_white, nil, ringRenderSettings)
                end
            end
        end
    end

    cam.IgnoreZ(false)
end)
