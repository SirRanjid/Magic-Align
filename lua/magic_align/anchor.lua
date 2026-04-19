MAGIC_ALIGN = MAGIC_ALIGN or {}

local M = MAGIC_ALIGN
local isvector = M.IsVectorLike

M.ANCHOR_CENTER_ID = "mid123"
M.ANCHOR_PERCENT_MIN = 0
M.ANCHOR_PERCENT_MAX = 100
M.ANCHOR_PERCENT_STEP = 5
M.ANCHOR_PERCENT_DEFAULT = 50
M.ANCHOR_PERCENT_KEYS = { "mid12", "mid23", "mid13" }
M.ANCHORS = {
    { id = "p1", label = "P1" },
    { id = "p2", label = "P2" },
    { id = "p3", label = "P3" },
    { id = "mid12", label = "Mid P1-P2" },
    { id = "mid23", label = "Mid P2-P3" },
    { id = "mid13", label = "Mid P1-P3" },
    { id = M.ANCHOR_CENTER_ID, label = "General Mid" }
}
M.DEFAULT_PRIORITY = { "p1", "mid12", "p2", "p3", "mid23", "mid13", M.ANCHOR_CENTER_ID }

function M.ParsePriority(text)
    if istable(text) then return text end

    local out = {}
    text = string.lower(tostring(text or ""))

    for token in string.gmatch(text, "[^,%s]+") do
        out[#out + 1] = token
    end

    return out
end

function M.ClampAnchorPercent(value)
    return math.Clamp(
        tonumber(value) or M.ANCHOR_PERCENT_DEFAULT,
        M.ANCHOR_PERCENT_MIN,
        M.ANCHOR_PERCENT_MAX
    )
end

function M.SnapAnchorPercent(value)
    local clamped = M.ClampAnchorPercent(value)
    local step = math.max(tonumber(M.ANCHOR_PERCENT_STEP) or 1, 1)
    local snapped = M.ANCHOR_PERCENT_MIN + math.Round((clamped - M.ANCHOR_PERCENT_MIN) / step) * step

    return math.Clamp(snapped, M.ANCHOR_PERCENT_MIN, M.ANCHOR_PERCENT_MAX)
end

function M.NormalizeAnchorOptions(options)
    options = istable(options) and options or {}

    return {
        mid12_pct = M.ClampAnchorPercent(options.mid12_pct or options.mid12),
        mid23_pct = M.ClampAnchorPercent(options.mid23_pct or options.mid23),
        mid13_pct = M.ClampAnchorPercent(options.mid13_pct or options.mid13)
    }
end

function M.AnchorOptionsFromReader(readValue, prefix)
    if type(readValue) ~= "function" then
        return M.NormalizeAnchorOptions()
    end

    prefix = tostring(prefix or "")
    if prefix ~= "" and not string.EndsWith(prefix, "_") then
        prefix = prefix .. "_"
    end

    return M.NormalizeAnchorOptions({
        mid12_pct = readValue(prefix .. "mid12_pct"),
        mid23_pct = readValue(prefix .. "mid23_pct"),
        mid13_pct = readValue(prefix .. "mid13_pct")
    })
end

local function interpolation(options, key)
    return (options[key .. "_pct"] or M.ANCHOR_PERCENT_DEFAULT) * 0.01
end

local function lerpPoint(a, b, t)
    return M.AddVectorsPrecise(
        M.ScaleVectorPrecise(a, 1 - t),
        M.ScaleVectorPrecise(b, t)
    )
end

local function anchorPoint(points, id, options)
    points = istable(points) and points or {}

    local p1, p2, p3 = points[1], points[2], points[3]

    if id == "p1" then return p1 end
    if id == "p2" then return p2 end
    if id == "p3" then return p3 end
    if id == "mid12" and p1 and p2 then return lerpPoint(p1, p2, interpolation(options, "mid12")) end
    if id == "mid23" and p2 and p3 then return lerpPoint(p2, p3, interpolation(options, "mid23")) end
    if id == "mid13" and p1 and p3 then return lerpPoint(p1, p3, interpolation(options, "mid13")) end

    if id == M.ANCHOR_CENTER_ID and p1 and p2 and p3 then
        local m12 = anchorPoint(points, "mid12", options)
        local m23 = anchorPoint(points, "mid23", options)
        local m13 = anchorPoint(points, "mid13", options)

        if m12 and m23 and m13 then
            return M.ScaleVectorPrecise(M.AddVectorsPrecise(M.AddVectorsPrecise(m12, m23), m13), 1 / 3)
        end
    end
end

function M.AnchorPoint(points, id, options)
    return anchorPoint(points, string.lower(tostring(id or "")), M.NormalizeAnchorOptions(options))
end

function M.AnchorAvailable(id, count)
    id = string.lower(tostring(id or ""))

    if id == "p1" then return count >= 1 end
    if id == "p2" or id == "mid12" then return count >= 2 end
    if id == "p3" or id == "mid23" or id == "mid13" or id == M.ANCHOR_CENTER_ID then return count >= 3 end

    return false
end

function M.ResolveAnchor(points, selected, priority, options)
    local seen = {}
    local normalized = M.NormalizeAnchorOptions(options)

    local function try(id)
        id = string.lower(tostring(id or ""))
        if id == "" or seen[id] then return end
        seen[id] = true

        local pos = anchorPoint(points, id, normalized)
        if isvector(pos) then
            return id, pos
        end
    end

    local id, pos = try(selected)
    if pos then return id, pos end

    for _, name in ipairs(M.ParsePriority(priority)) do
        id, pos = try(name)
        if pos then return id, pos end
    end

    for _, name in ipairs(M.DEFAULT_PRIORITY) do
        id, pos = try(name)
        if pos then return id, pos end
    end
end

return M
