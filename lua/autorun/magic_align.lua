if SERVER then
    AddCSLuaFile()
    AddCSLuaFile("magic_align/precision.lua")
    AddCSLuaFile("magic_align/rounding.lua")
    AddCSLuaFile("magic_align/anchor.lua")
    AddCSLuaFile("magic_align/compat/primitive_sh.lua")
    AddCSLuaFile("magic_align/compat/primitive_cl.lua")
end

MAGIC_ALIGN = MAGIC_ALIGN or {}

local M = MAGIC_ALIGN

include("magic_align/precision.lua")
include("magic_align/rounding.lua")
include("magic_align/anchor.lua")
include("magic_align/compat/primitive_sh.lua")

local VectorP = M.VectorP
local AngleP = M.AngleP
local isvector = M.IsVectorLike
local isangle = M.IsAngleLike

if SERVER then
    include("magic_align/compat/primitive_sv.lua")
else
    include("magic_align/compat/primitive_cl.lua")
end

M.NET = "magic_align_commit"
M.NET_COMMIT_LINKED_PART = "magic_align_commit_linked_part"
M.NET_COMMIT_FINISH = "magic_align_commit_finish"
M.NET_BOUNDS_REQUEST = "magic_align_bounds_request"
M.NET_BOUNDS_REPLY = "magic_align_bounds_reply"
M.NET_CLIENT_ACTION = "magic_align_client_action"
M.NET_VIEW_ANGLES = "magic_align_view_angles"
M.AABB_REQUEST_COOLDOWN = 0.25
M.MAX_POINTS = 3
M.MAX_COMMIT_PROPS = 255
M.DEFAULT_MAX_LINKED_PROPS = 32
M.DEFAULT_COMMIT_LINKED_PART_SIZE = 62
M.COMMIT_LINKED_PART_SIZE = M.DEFAULT_COMMIT_LINKED_PART_SIZE
M.DEFAULT_COMMIT_BUDGET_MS = 0.2
M.LINE_PLANE_EPSILON = M.PICKING_EPSILON
M.ZERO = VectorP(0, 0, 0)
M.ZERO_ANGLE = AngleP(0, 0, 0)
M.COMMIT_MOVE = 0
M.COMMIT_COPY = 1
M.COMMIT_COPY_MOVE = 2
M.CLIENT_ACTION_RIGHTCLICK = 0
M.CLIENT_ACTION_RESET = 1

local MAX_LINKED_PROPS_CVAR = "magic_align_max_linked_props"
local COMMIT_LINKED_PART_SIZE_CVAR = "magic_align_commit_linked_part_size"
local COMMIT_BUDGET_CVAR = "magic_align_commit_budget_ms"

if SERVER then
    CreateConVar(
        MAX_LINKED_PROPS_CVAR,
        tostring(M.DEFAULT_MAX_LINKED_PROPS),
        FCVAR_ARCHIVE + FCVAR_NOTIFY + FCVAR_REPLICATED,
        "Maximum number of linked props per Magic Align commit.",
        0,
        M.MAX_COMMIT_PROPS
    )
    CreateConVar(
        COMMIT_LINKED_PART_SIZE_CVAR,
        tostring(M.DEFAULT_COMMIT_LINKED_PART_SIZE),
        FCVAR_ARCHIVE + FCVAR_NOTIFY + FCVAR_REPLICATED,
        "Maximum number of linked props per Magic Align commit upload part.",
        1,
        M.MAX_COMMIT_PROPS
    )
    CreateConVar(
        COMMIT_BUDGET_CVAR,
        tostring(M.DEFAULT_COMMIT_BUDGET_MS),
        FCVAR_ARCHIVE + FCVAR_NOTIFY,
        "Maximum CPU time in milliseconds per Magic Align commit slice.",
        0.01
    )
end

local function readConVarNumber(name, fallback, integer)
    local cvar = GetConVar(name)
    if not cvar then return fallback end

    local value = integer and cvar:GetInt() or cvar:GetFloat()
    value = tonumber(value)

    return value or fallback
end

function M.GetMaxLinkedProps()
    local limit = readConVarNumber(MAX_LINKED_PROPS_CVAR, M.DEFAULT_MAX_LINKED_PROPS, true)
    return math.Clamp(math.floor(limit or 0), 0, M.MAX_COMMIT_PROPS)
end

function M.GetCommitLinkedPartSize()
    local size = readConVarNumber(COMMIT_LINKED_PART_SIZE_CVAR, M.DEFAULT_COMMIT_LINKED_PART_SIZE, true)
    return math.Clamp(math.floor(size or M.DEFAULT_COMMIT_LINKED_PART_SIZE), 1, M.MAX_COMMIT_PROPS)
end

function M.GetCommitBudgetMs()
    local budget = readConVarNumber(COMMIT_BUDGET_CVAR, M.DEFAULT_COMMIT_BUDGET_MS, false)
    return math.max(tonumber(budget) or M.DEFAULT_COMMIT_BUDGET_MS, 0.1)
end

function M.GetCommitBudgetSeconds()
    return M.GetCommitBudgetMs() * 0.001
end
-- "Referenz" meint hier genau die vier Tabs im Tool.
-- Jeder Tab beschreibt einen eigenen lokalen Referenzraum:
-- prop1 = lokaler Raum von Prop 1
-- prop2 = lokaler Raum von Prop 2
-- points = lokaler Raum der gewaehlten Point-Axis
-- world = Weltachsen ohne lokale Rotation
M.SPACES = { "prop1", "prop2", "points", "world" }
M.WORLD_TARGET = M.WORLD_TARGET or setmetatable({
    __magic_align_world = true
}, {
    __tostring = function()
        return "magic_align_world"
    end
})

function M.IsWorldTarget(ent)
    if ent == M.WORLD_TARGET then
        return true
    end

    if IsValid(ent) and ent.IsWorld then
        return ent:IsWorld()
    end

    local world = game and game.GetWorld and game.GetWorld() or nil
    return world ~= nil and ent == world
end

function M.HasTargetEntity(ent)
    return M.IsWorldTarget(ent) or IsValid(ent)
end

function M.NextSessionId()
    M._nextSessionId = (tonumber(M._nextSessionId) or 0) + 1
    return M._nextSessionId
end

function M.NewSession()
    return {
        sessionId = M.NextSessionId(),
        state = "source_prop",
        prop1 = nil,
        prop2 = nil,
        selectedWorldPointIndex = nil,
        linked = {},
        anchorSelection = {},
        source = {},
        target = {},
        bounds = {},
        preview = nil,
        pending = nil,
        compatGhosts = { linked = {} },
        hover = nil,
        press = nil,
        ghost = nil,
        linkedGhosts = {},
        attackDown = false,
        useDown = false
    }
end

function M.CopyPoints(points)
    points = istable(points) and points or {}

    local out = {}

    for i = 1, #points do
        local p = points[i]
        if isvector(p) then
            out[i] = VectorP(p.x, p.y, p.z)

            if isvector(p.normal) then
                out[i].normal = VectorP(p.normal.x, p.normal.y, p.normal.z)
            end

            if p.world == true then
                out[i].world = true
            end
        end
    end

    return out
end

local function hasUsableModel(ent)
    if not IsValid(ent) or not isfunction(ent.GetModel) then return false end

    local model = ent:GetModel()
    return isstring(model) and model ~= ""
end

local function isStoredScriptedEntity(class)
    if not isstring(class) or class == "" then return false end
    if not scripted_ents or not isfunction(scripted_ents.GetStored) then return false end

    local stored = scripted_ents.GetStored(class)
    return istable(stored) and stored.t ~= nil
end

function M.IsProp(ent)
    if not IsValid(ent) then return false end
    if ent:IsWorld() or ent:IsPlayer() or ent:IsNPC() or ent:IsWeapon() then return false end
    if M.IsPrimitive and M.IsPrimitive(ent) then return true end

    local class = ent:GetClass()
    if string.StartWith(class, "prop_") then return true end

    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then return true end

    return hasUsableModel(ent) and isStoredScriptedEntity(class)
end

function M.GetActiveMagicAlignTool(ply)
    if not IsValid(ply) then return end

    local weapon = ply:GetActiveWeapon()
    if not IsValid(weapon) or weapon:GetClass() ~= "gmod_tool" then return end

    local tool = ply:GetTool()
    if not tool or tool.Mode ~= "magic_align" then return end

    return tool, weapon
end

local function sanitizeBounds(mins, maxs)
    if not isvector(mins) or not isvector(maxs) then return end

    mins = VectorP(mins.x, mins.y, mins.z)
    maxs = VectorP(maxs.x, maxs.y, maxs.z)

    local size = M.SubtractVectorsPrecise(maxs, mins)
    if not isvector(size) then return end
    if size.x < -M.VALIDATION_EPSILON or size.y < -M.VALIDATION_EPSILON or size.z < -M.VALIDATION_EPSILON then return end

    return mins, maxs
end

local function expandBounds(mins, maxs, point)
    if not isvector(point) then
        return mins, maxs
    end

    if not isvector(mins) or not isvector(maxs) then
        return VectorP(point.x, point.y, point.z), VectorP(point.x, point.y, point.z)
    end

    mins.x = math.min(mins.x, point.x)
    mins.y = math.min(mins.y, point.y)
    mins.z = math.min(mins.z, point.z)
    maxs.x = math.max(maxs.x, point.x)
    maxs.y = math.max(maxs.y, point.y)
    maxs.z = math.max(maxs.z, point.z)

    return mins, maxs
end

local function physAABBToLocalBounds(ent, phys)
    if not IsValid(ent) or not IsValid(phys) then return end
    if not phys.GetAABB or not phys.GetPos or not phys.GetAngles then return end

    local mins, maxs = sanitizeBounds(phys:GetAABB())
    if not mins or not maxs then return end

    local localMins, localMaxs
    local physPos = phys:GetPos()
    local physAng = phys:GetAngles()
    local entPos = ent:GetPos()
    local entAng = ent:GetAngles()
    if not isvector(physPos) or not isangle(physAng) or not isvector(entPos) or not isangle(entAng) then return end

    local corners = {
        VectorP(mins.x, mins.y, mins.z),
        VectorP(mins.x, mins.y, maxs.z),
        VectorP(mins.x, maxs.y, mins.z),
        VectorP(mins.x, maxs.y, maxs.z),
        VectorP(maxs.x, mins.y, mins.z),
        VectorP(maxs.x, mins.y, maxs.z),
        VectorP(maxs.x, maxs.y, mins.z),
        VectorP(maxs.x, maxs.y, maxs.z)
    }

    for i = 1, #corners do
        local worldPos = LocalToWorldPrecise(corners[i], AngleP(0, 0, 0), physPos, physAng)
        local localPos = isvector(worldPos) and WorldToLocalPrecise(worldPos, AngleP(0, 0, 0), entPos, entAng) or nil
        localMins, localMaxs = expandBounds(localMins, localMaxs, localPos)
    end

    return sanitizeBounds(localMins, localMaxs)
end

local SCALE_IDENTITY = VectorP(1, 1, 1)
local SCALE_ZERO = VectorP(0, 0, 0)

local function vectorApprox(a, b, eps)
    if not isvector(a) or not isvector(b) then return false end

    eps = eps or M.UI_COMPARE_EPSILON

    return math.abs(a.x - b.x) <= eps
        and math.abs(a.y - b.y) <= eps
        and math.abs(a.z - b.z) <= eps
end

local function parseScaleVector(value)
    local vec = value

    if isstring(value) then
        if value == "" then return end
        vec = VectorP(value)
    end

    if not isvector(vec) then return end

    return VectorP(vec.x, vec.y, vec.z)
end

local function modifierScale(data, firstIndex)
    if not istable(data) then return end

    local x = tonumber(data[firstIndex])
    local y = tonumber(data[firstIndex + 1])
    local z = tonumber(data[firstIndex + 2])
    if not x or not y or not z then return end

    return VectorP(x, y, z)
end

local function findSizeHandler(ent)
    if not IsValid(ent) or not isfunction(ent.GetChildren) then return end

    local children = ent:GetChildren()
    for i = 1, #children do
        local child = children[i]
        if IsValid(child) and child:GetClass() == "sizehandler" then
            return child
        end
    end
end

local function advResizerBoundsScale(ent)
    if not IsValid(ent) then return end

    local modifierData = istable(ent.EntityMods) and ent.EntityMods.advr or nil
    local physical = modifierScale(modifierData, 1)
    local visual = modifierScale(modifierData, 4)
    local handler = (physical and visual) and nil or findSizeHandler(ent)

    if not isvector(physical) then
        physical = IsValid(handler) and isfunction(handler.GetActualPhysicsScale)
            and parseScaleVector(handler:GetActualPhysicsScale())
            or nil
    end

    if not isvector(visual) then
        visual = IsValid(handler) and isfunction(handler.GetVisualScale)
            and parseScaleVector(handler:GetVisualScale())
            or nil
    end

    if not isvector(physical) or vectorApprox(physical, SCALE_ZERO) then
        physical = VectorP(1, 1, 1)
    end

    if not isvector(visual) or vectorApprox(visual, SCALE_ZERO) then
        visual = VectorP(1, 1, 1)
    end

    local ratio = VectorP(
        visual.x / math.max(physical.x, M.MODEL_SCALE_EPSILON),
        visual.y / math.max(physical.y, M.MODEL_SCALE_EPSILON),
        visual.z / math.max(physical.z, M.MODEL_SCALE_EPSILON)
    )

    if vectorApprox(ratio, SCALE_IDENTITY) then return end

    return ratio
end

local function scaleBounds(mins, maxs, scale)
    if not isvector(mins) or not isvector(maxs) or not isvector(scale) then
        return mins, maxs
    end

    return sanitizeBounds(
        VectorP(mins.x * scale.x, mins.y * scale.y, mins.z * scale.z),
        VectorP(maxs.x * scale.x, maxs.y * scale.y, maxs.z * scale.z)
    )
end

function M.GetLocalBounds(ent)
    if not M.IsProp(ent) then return end

    local visualScale = advResizerBoundsScale(ent)

    local phys = ent:GetPhysicsObject()
    local mins, maxs = physAABBToLocalBounds(ent, phys)
    if mins and maxs then
        return scaleBounds(mins, maxs, visualScale)
    end

    if ent.GetCollisionBounds then
        mins, maxs = sanitizeBounds(ent:GetCollisionBounds())
        if mins and maxs then
            return scaleBounds(mins, maxs, visualScale)
        end
    end

    mins, maxs = sanitizeBounds(ent:OBBMins(), ent:OBBMaxs())
    if mins and maxs then
        return scaleBounds(mins, maxs, visualScale)
    end

    if ent.GetRenderBounds then
        mins, maxs = sanitizeBounds(ent:GetRenderBounds())
        if mins and maxs then
            return scaleBounds(mins, maxs, visualScale)
        end
    end
end

function M.RefreshState(session)
    if not IsValid(session.prop1) then
        session.state = "source_prop"
    elseif #session.source == 0 then
        session.state = "source_points"
    elseif not M.HasTargetEntity(session.prop2) then
        session.state = "target_prop"
    elseif #session.target == 0 then
        session.state = "target_points"
    else
        session.state = "ready"
    end
end

function M.ModeName(sourceCount, targetCount, hasTarget)
    if not hasTarget then
        return "local"
    end

    return ("%dx%d"):format(sourceCount, targetCount)
end

local function copyVec(v)
    return M.CopyVectorPrecise(v)
end

local function copyAng(a)
    return M.CopyAnglePrecise(a)
end

local function localToWorldSafe(localPos, localAng, originPos, originAng)
    return LocalToWorldPrecise(
        copyVec(localPos),
        copyAng(localAng),
        copyVec(originPos),
        copyAng(originAng)
    )
end

local function worldToLocalSafe(worldPos, worldAng, originPos, originAng)
    return WorldToLocalPrecise(
        copyVec(worldPos),
        copyAng(worldAng),
        copyVec(originPos),
        copyAng(originAng)
    )
end

local function normalized(v)
    return M.NormalizeVectorPrecise(v, M.COMPUTE_VECTOR_EPSILON_SQR)
end

local function projected(v, axis)
    return M.ProjectVectorPrecise(v, axis, M.COMPUTE_VECTOR_EPSILON_SQR)
end

local function chooseUp(axis)
    return projected(VectorP(0, 0, 1), axis) or projected(VectorP(0, 1, 0), axis) or VectorP(0, 1, 0)
end

local function singlePointNormalContext(points)
    local point = istable(points) and points[1] or nil
    if not isvector(point) or not isvector(point.normal) then return end

    local normal = normalized(point.normal)
    if not normal then return end

    return {
        pos = point,
        primary = normal,
        secondary = nil,
        ang = M.AngleFromForwardUpPrecise(normal, chooseUp(normal))
    }
end

local function pointContext(points, anchorOptions)
    local count = #points
    if count < 1 then return end

    -- Die Point-Axis ist ein lokaler Referenzraum, der nur aus den markierten
    -- Punkten aufgebaut wird:
    -- origin    = Bezugspunkt des Punktsatzes
    -- primary   = Hauptachse P1 -> P2
    -- secondary = zweite Achse aus P3, orthogonal auf primary projiziert
    -- ang       = vollstaendige Winkelbasis dieses Referenzraums
    local originId, origin = M.ResolveAnchor(points, M.ANCHOR_CENTER_ID, { "mid12", "p1" }, anchorOptions)
    origin = origin or points[1]
    local primary = count >= 2 and normalized(M.SubtractVectorsPrecise(points[2], points[1])) or nil
    local secondary = count >= 3 and projected(M.SubtractVectorsPrecise(points[3], origin), primary) or nil
    local up = primary and (secondary or chooseUp(primary)) or nil

    return {
        anchorId = originId,
        pos = origin,
        primary = primary,
        secondary = secondary,
        ang = primary and M.AngleFromForwardUpPrecise(primary, up) or nil
    }
end

local function rotateToAxis(ang, localAxis, targetAxis)
    if not localAxis or not targetAxis then return ang end

    localAxis = normalized(localAxis)
    targetAxis = normalized(targetAxis)
    if not localAxis or not targetAxis then return ang end

    local current = normalized(localToWorldSafe(localAxis, nil, nil, ang))
    if not current then return ang end

    local dot = math.Clamp(M.DotVectorsPrecise(current, targetAxis), -1, 1)

    if dot > 1 - M.DIRECTION_DOT_EPSILON then
        return ang
    end

    ang = copyAng(ang)

    if dot < -1 + M.DIRECTION_DOT_EPSILON then
        local fallback = projected(M.AngleUpPrecise(ang), targetAxis) or projected(M.AngleRightPrecise(ang), targetAxis) or chooseUp(targetAxis)
        return M.RotateAngleAroundAxisPrecise(ang, fallback, 180)
    end

    local axis = normalized(M.CrossVectorsPrecise(current, targetAxis))
    if not axis then
        return ang
    end

    return M.RotateAngleAroundAxisPrecise(ang, axis, math.deg(math.acos(dot)))
end

local function signedAngle(axis, fromVec, toVec)
    fromVec = projected(fromVec, axis)
    toVec = projected(toVec, axis)
    if not fromVec or not toVec then return 0 end

    return math.deg(math.atan2(
        M.DotVectorsPrecise(axis, M.CrossVectorsPrecise(fromVec, toVec)),
        M.DotVectorsPrecise(fromVec, toVec)
    ))
end

function M.Solve(prop1, sourcePoints, prop2, targetPoints, sourceSelected, sourcePriority, targetSelected, targetPriority, sourceAnchorOptions, targetAnchorOptions)
    local sourceCount = #sourcePoints
    local targetIsWorld = M.IsWorldTarget(prop2)
    local hasTarget = (targetIsWorld or IsValid(prop2)) and #targetPoints > 0

    if not IsValid(prop1) or sourceCount < 1 then return end

    local sourceAnchorId, sourceAnchorLocal = M.ResolveAnchor(sourcePoints, sourceSelected, sourcePriority, sourceAnchorOptions)
    if not isvector(sourceAnchorLocal) then return end

    local targetAnchorId, targetAnchorLocal
    if hasTarget then
        targetAnchorId, targetAnchorLocal = M.ResolveAnchor(targetPoints, targetSelected, targetPriority, targetAnchorOptions)
        if not isvector(targetAnchorLocal) then return end
    end

    local sourceContext = pointContext(sourcePoints, sourceAnchorOptions) or { pos = sourceAnchorLocal, anchorId = sourceAnchorId }
    local targetContext = hasTarget and (pointContext(targetPoints, targetAnchorOptions) or { pos = targetAnchorLocal, anchorId = targetAnchorId }) or nil
    local targetSinglePointContext = hasTarget and #targetPoints == 1 and singlePointNormalContext(targetPoints) or nil
    local targetBasePos = targetIsWorld and VectorP(0, 0, 0) or (IsValid(prop2) and copyVec(prop2:GetPos()) or nil)
    local targetBaseAng = targetIsWorld and AngleP(0, 0, 0) or (IsValid(prop2) and copyAng(prop2:GetAngles()) or nil)

    if sourceCount >= 2 and not sourceContext.primary then return end
    if hasTarget and #targetPoints >= 2 and (not targetContext or not targetContext.primary) then return end

    local solveSourceAnchorId, solveSourceAnchorLocal = sourceAnchorId, sourceAnchorLocal
    local solveTargetAnchorId, solveTargetAnchorLocal = targetAnchorId, targetAnchorLocal

    local ang = AngleP(prop1:GetAngles().p, prop1:GetAngles().y, prop1:GetAngles().r)
    local partial = false
    local pointsLocalAng
    local pointsWorldAng

    -- Solve baut zuerst die Grundpose von Prop 1 im Weltspace:
    -- 1. lokale Source-Infos aus Prop 1 lesen
    -- 2. falls vorhanden auf den Ziel-Referenzraum von Prop 2 ausrichten
    -- 3. den geloesten Anchor von Prop 1 auf den Ziel-Anchor im Weltspace setzen
    if not hasTarget then
        partial = sourceCount < 3
        pointsLocalAng = sourceContext.ang
    elseif sourceCount == 1 and #targetPoints == 1 then
        partial = false
    elseif sourceCount >= 2 and #targetPoints >= 2 then
        -- Hier passiert die eigentliche Rotation von Prop 1 auf den
        -- Referenzraum von Prop 2:
        -- primary richtet die Hauptachse aus, secondary loest den verbleibenden Twist.
        local targetAxisWorld = localToWorldSafe(targetContext.primary, nil, nil, targetBaseAng)
        ang = rotateToAxis(ang, sourceContext.primary, targetAxisWorld)
        partial = true
        pointsLocalAng = sourceContext.ang

        local sourceHintWorld = sourceContext.secondary and localToWorldSafe(sourceContext.secondary, nil, nil, ang)
            or projected(M.AngleUpPrecise(ang), targetAxisWorld)
        local targetHintWorld = targetContext.secondary and localToWorldSafe(targetContext.secondary, nil, nil, targetBaseAng) or nil

        if sourceHintWorld and targetHintWorld then
            ang = M.RotateAngleAroundAxisPrecise(ang, targetAxisWorld, signedAngle(targetAxisWorld, sourceHintWorld, targetHintWorld))
            partial = sourceCount < 3 or #targetPoints < 3
        end
    elseif sourceCount == 1 and #targetPoints >= 2 then
        partial = true
        pointsWorldAng = targetContext.ang and select(2, localToWorldSafe(nil, targetContext.ang, nil, targetBaseAng)) or nil
    else
        partial = true
        pointsLocalAng = sourceContext.ang
    end

    if targetSinglePointContext and targetSinglePointContext.ang then
        pointsLocalAng = nil
        pointsWorldAng = targetIsWorld
            and copyAng(targetSinglePointContext.ang)
            or select(2, localToWorldSafe(nil, targetSinglePointContext.ang, nil, targetBaseAng))
    end

    local targetAnchorWorld = hasTarget
        and localToWorldSafe(solveTargetAnchorLocal, nil, targetBasePos, targetBaseAng)
        or localToWorldSafe(solveSourceAnchorLocal, nil, prop1:GetPos(), prop1:GetAngles())
    local rotatedAnchor = localToWorldSafe(solveSourceAnchorLocal, nil, nil, ang)
    local pos = M.SubtractVectorsPrecise(targetAnchorWorld, rotatedAnchor)
    local axisAng = pointsWorldAng or ang
    if pointsLocalAng then
        local _, worldAng = localToWorldSafe(nil, pointsLocalAng, nil, ang)
        axisAng = worldAng or axisAng
    end

    return {
        mode = M.ModeName(sourceCount, #targetPoints, hasTarget),
        partial = partial,
        pos = pos,
        ang = ang,
        axisAng = axisAng,
        pointsLocalAng = pointsLocalAng,
        pointsWorldAng = pointsWorldAng,
        sourceAnchorId = solveSourceAnchorId,
        sourceAnchorLocal = solveSourceAnchorLocal,
        sourceContextLocal = sourceContext,
        targetAnchorId = solveTargetAnchorId,
        targetAnchorLocal = solveTargetAnchorLocal,
        targetAnchorWorld = targetAnchorWorld,
        sourceCount = sourceCount,
        targetCount = #targetPoints,
        hasTarget = hasTarget
    }
end

local function lPI(viewVec, viewOri, norm, ori, ang)
    if not isvector(viewVec) or not isvector(viewOri) or not isvector(norm) or not isvector(ori) or not isangle(ang) then
        return nil, nil
    end

    -- Der DragContext ist eine virtuelle Ebene im Weltspace.
    -- `ori` + `ang` beschreiben ihren lokalen Raum, damit derselbe Schnittpunkt
    -- direkt auch als lokale Gizmo-/Referenz-Koordinate verfuegbar ist.
    local denominator = M.DotVectorsPrecise(norm, viewVec)
    if math.abs(denominator) <= M.LINE_PLANE_EPSILON then
        return nil, nil
    end

    local distance = (M.DotVectorsPrecise(norm, ori) - M.DotVectorsPrecise(norm, viewOri)) / denominator
    local worldPos = M.AddVectorsPrecise(viewOri, M.ScaleVectorPrecise(viewVec, distance))
    local localPos = worldToLocalSafe(worldPos, nil, ori, ang)

    return worldPos, localPos
end

function M.LinePlaneIntersection(viewVec, viewOri, norm, ori, ang)
    local worldPos, localPos = lPI(viewVec, viewOri, norm, ori, ang)

    if not isvector(worldPos) or not isvector(localPos) then
        return nil, nil
    end

    return worldPos, localPos
end

function M.LocalToLocal(localPos, localAng, fromOrigin, fromAng, toOrigin, toAng)
    -- Offizielle Zwiebelschicht-Umrechnung:
    -- erst aus dem lokalen "from"-Raum in den Weltspace,
    -- dann aus dem Weltspace wieder in den lokalen "to"-Raum.
    -- Wichtig: Beide Bezugssysteme muessen dabei im selben Parent-Raum
    -- beschrieben sein. In diesem Tool ist dieser Parent-Raum der Weltspace.
    local worldPos, worldAng = localToWorldSafe(localPos, localAng, fromOrigin, fromAng)
    return worldToLocalSafe(worldPos, worldAng, toOrigin, toAng)
end

local function rotateAngle(ang, basisAng, rot)
    -- Die lokale Tab-Rotation wird offiziell in den Referenzraum eingeklinkt:
    -- Welt -> Referenz (WorldToLocal), lokale Delta-Rotation davorlegen,
    -- dann wieder Referenz -> Welt (LocalToWorld).
    local _, localAng = worldToLocalSafe(nil, ang, nil, basisAng)
    local _, composedLocalAng = localToWorldSafe(nil, localAng, nil, rot)
    local _, worldAng = localToWorldSafe(nil, composedLocalAng, nil, basisAng)
    return worldAng
end

function M.RotateAroundAnchor(pos, ang, anchorLocal, basisAng, rot)
    local anchorWorld = localToWorldSafe(anchorLocal, nil, pos, ang)
    ang = rotateAngle(ang, basisAng, rot)

    pos = M.SubtractVectorsPrecise(anchorWorld, localToWorldSafe(anchorLocal, nil, nil, ang))

    return pos, ang
end

local function rotatedBasis(basisAng, rot)
    local _, worldAng = localToWorldSafe(nil, rot, nil, basisAng)
    return worldAng
end

function M.ComposePose(solve, offsets, prop2)
    local pos = copyVec(solve.pos)
    local ang = copyAng(solve.ang)
    local prop2Ang = M.IsWorldTarget(prop2) and AngleP(0, 0, 0) or (IsValid(prop2) and prop2:GetAngles() or nil)
    local spaceBasis = {}
    local referenceBasis = {}
    local function rotateStoredBases(rotationBasis, rotationDelta)
        for _, storedName in ipairs(M.SPACES) do
            if referenceBasis[storedName] then
                referenceBasis[storedName] = rotateAngle(referenceBasis[storedName], rotationBasis, rotationDelta)
            end

            if spaceBasis[storedName] then
                spaceBasis[storedName] = rotateAngle(spaceBasis[storedName], rotationBasis, rotationDelta)
            end
        end
    end

    for _, name in ipairs(M.SPACES) do
        local item = offsets and offsets[name]
        local basis = AngleP(0, 0, 0)

        if name == "prop1" then
            basis = copyAng(ang)
        elseif name == "prop2" then
            basis = copyAng(prop2Ang or ang)
        elseif name == "points" then
            if solve.pointsLocalAng then
                local _, worldAng = localToWorldSafe(nil, solve.pointsLocalAng, nil, ang)
                basis = worldAng or ang
            else
                basis = copyAng(solve.pointsWorldAng or ang)
            end
        end

        local moveBasis = copyAng(basis)

        if item then
            local anchorWorld = localToWorldSafe(solve.sourceAnchorLocal, nil, pos, ang)

            if item.pos then
                anchorWorld = localToWorldSafe(item.pos, nil, anchorWorld, basis)
            end

            if item.rot then
                -- Eine aeussere Zwiebelschicht dreht auch alle bereits
                -- existierenden inneren Referenzraeume/Gizmos im Weltspace mit.
                if item.rot.p ~= 0 or item.rot.y ~= 0 or item.rot.r ~= 0 then
                    rotateStoredBases(basis, item.rot)
                end

                moveBasis = rotatedBasis(basis, item.rot)
                ang = rotateAngle(ang, basis, item.rot)
            end

            pos = M.SubtractVectorsPrecise(anchorWorld, localToWorldSafe(solve.sourceAnchorLocal, nil, nil, ang))
        end

        -- Diese beiden Basen werden so gespeichert, wie sie nach allen bisher
        -- verarbeiteten aeusseren Schichten im Weltspace sichtbar waeren.
        -- "moveBasis" ist der eigentliche Gizmo-Raum dieses Tabs:
        -- Referenzraum plus die lokalen Rotations-Slider des Tabs.
        referenceBasis[name] = copyAng(basis)
        spaceBasis[name] = copyAng(moveBasis)
    end

    return pos, ang, spaceBasis, referenceBasis
end

function M.PointInsideAABB(localPos, mins, maxs)
    local eps = M.AABB_PICKING_PADDING

    return localPos.x >= mins.x - eps and localPos.x <= maxs.x + eps
        and localPos.y >= mins.y - eps and localPos.y <= maxs.y + eps
        and localPos.z >= mins.z - eps and localPos.z <= maxs.z + eps
end

return M
