MAGIC_ALIGN = MAGIC_ALIGN or include("autorun/magic_align.lua")

local M = MAGIC_ALIGN
local client = M.Client or {}
M.Client = client

local worldPoints = client.WorldPoints or {}
client.WorldPoints = worldPoints

local VectorP = M.VectorP
local AngleP = M.AngleP
local isvector = M.IsVectorLike
local isWorldTarget = M.IsWorldTarget
local LocalToWorldPosPrecise = M.LocalToWorldPosPrecise
local snapGizmoPosition = client.snapGizmoPosition
local gizmoShared = client.gizmoShared or {}

local WORLD_POINT_DRAG_DEADZONE = 1
local WORLD_POINT_GIZMO_SPACE = "world_point"

local copyVec = M.CopyVectorPrecise
local copyAng = M.CopyAnglePrecise
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

local function normalizedVec(value)
    return M.NormalizeVectorPrecise(value, M.COMPUTE_VECTOR_EPSILON_SQR)
end

local function targetPoints(state)
    return istable(state) and istable(state.target) and state.target or {}
end

local function selectedIndex(state)
    local index = tonumber(state and state.selectedWorldPointIndex)
    if index == nil then return end

    index = math.floor(index)
    if index < 1 or not isWorldTarget(state and state.prop2) then return end

    local points = targetPoints(state)
    if index > #points or not isvector(points[index]) then return end

    return index
end

local function setSelectedIndex(state, index)
    if not istable(state) then return end

    if index == nil then
        state.selectedWorldPointIndex = nil
        return
    end

    index = math.floor(tonumber(index) or 0)
    if index < 1 or not isWorldTarget(state.prop2) then
        state.selectedWorldPointIndex = nil
        return
    end

    local points = targetPoints(state)
    if index > #points or not isvector(points[index]) then
        state.selectedWorldPointIndex = nil
        return
    end

    state.selectedWorldPointIndex = index
end

local function clearWorldPointPress(state)
    if not istable(state) or not istable(state.press) then return end

    if state.press.kind == "world_point_press" or state.press.worldPoint == true then
        state.press = nil
    end
end

local function adjustPressIndex(press, removedIndex)
    if not istable(press) then return end

    local key
    if press.kind == "world_point_press" then
        key = "index"
    elseif press.worldPoint == true then
        key = "worldPointIndex"
    end

    if not key then return end

    local index = math.floor(tonumber(press[key]) or 0)
    if index < 1 then return end

    if removedIndex == index then
        return false
    elseif removedIndex < index then
        index = index - 1
        press[key] = index
        if press.index ~= nil then
            press.index = index
        end
    end

    return true
end

local function selectedPoint(state)
    local index = selectedIndex(state)
    return index, index and state.target[index] or nil
end

local function makeWorldPoint(worldPos, worldNormal, fallbackPoint)
    local point = isvector(worldPos) and copyVec(worldPos) or nil
    if not isvector(point) then return end

    point.world = true

    local normal = normalizedVec(worldNormal)
    if normal then
        point.normal = copyVec(normal)
    elseif isvector(fallbackPoint and fallbackPoint.normal) then
        point.normal = copyVec(fallbackPoint.normal)
    end

    return point
end

local function updateTargetPoint(state, index, worldPos, worldNormal)
    local points = targetPoints(state)
    local currentPoint = points[index]
    if not isvector(currentPoint) or not isvector(worldPos) then return false end

    local point = makeWorldPoint(worldPos, worldNormal, currentPoint)
    if not point then return false end

    points[index] = point
    setSelectedIndex(state, index)
    M.RefreshState(state)
    return true
end

local function updateTargetPointFromCandidate(state, index, candidate)
    if not istable(candidate) or not isvector(candidate.worldPos) then return false end

    local worldNormal = isvector(candidate.localNormal) and candidate.localNormal or candidate.normal
    return updateTargetPoint(state, index, candidate.worldPos, worldNormal)
end

local function gizmoSize(state)
    if isfunction(gizmoShared.sizeForProp) then
        return gizmoShared.sizeForProp(state and state.prop1)
    end

    return math.Clamp(IsValid(state and state.prop1) and state.prop1:BoundingRadius() * 0.42 or 32, 18, 72)
end

local function worldBasis()
    return AngleP(0, 0, 0)
end

local function modifierState()
    return input.IsKeyDown(KEY_LALT) or input.IsKeyDown(KEY_RALT)
end

local function buildGizmo(state)
    local index, point = selectedPoint(state)
    if not index or not isvector(point) then return end

    local press = state.press
    if press and (press.kind == "world_point_press" or (press.kind == "drag_point" and press.worldPoint == true)) then
        return
    end

    local origin = copyVec(point)
    local basis = worldBasis()
    local referenceBasis = copyAng(basis)

    if press
        and press.kind == "gizmo"
        and press.worldPoint == true
        and press.worldPointIndex == index
        and press.space == WORLD_POINT_GIZMO_SPACE then
        local currentOrigin = isvector(press.currentGizmoPos)
            and LocalToWorldPosPrecise(press.currentGizmoPos, press.origin, press.basis)
            or press.origin
        origin = copyVec(currentOrigin)
        basis = copyAng(press.basis)
        referenceBasis = copyAng(press.referenceBasis or basis)
    end

    local size = gizmoSize(state)
    local handles, metrics
    if isfunction(gizmoShared.linearHandles) then
        handles, _, _, _, metrics = gizmoShared.linearHandles(origin, basis, size)
    end

    local best
    if handles and metrics and isfunction(gizmoShared.pickHoveredHandle) then
        best = gizmoShared.pickHoveredHandle(handles, metrics.pickRadius, metrics.ringRadius, metrics.ringPadding, origin, basis)
    end

    return {
        origin = origin,
        basis = basis,
        referenceBasis = referenceBasis,
        size = size,
        planeOffset = metrics and metrics.planeOffset or size * 0.2,
        ringRadius = metrics and metrics.ringRadius or size * 0.82,
        ringPadding = metrics and metrics.ringPadding or 0.5,
        hover = press
            and press.kind == "gizmo"
            and press.worldPoint == true
            and press.worldPointIndex == index
            and press.space == WORLD_POINT_GIZMO_SPACE
            and press.gizmo
            or best,
        space = WORLD_POINT_GIZMO_SPACE,
        disableRotation = true,
        worldPoint = true,
        worldPointIndex = index
    }
end

local function beginWorldPointPress(state, hover)
    if not istable(state) or not istable(hover) then return false end

    local hoverPoint = hover.point
    if not istable(hoverPoint) then return false end

    local index = math.floor(tonumber(hoverPoint.index) or 0)
    local points = targetPoints(state)
    if index < 1 or index > #points or not isvector(points[index]) then return false end

    local startWorldPos = hover.candidate and hover.candidate.worldPos
        or hover.trace and hover.trace.HitPos
        or hoverPoint.worldPos
    if not isvector(startWorldPos) then
        startWorldPos = points[index]
    end

    state.press = {
        kind = "world_point_press",
        side = "target",
        index = index,
        startWorldPos = copyVec(startWorldPos)
    }

    return true
end

local function beginWorldPointGizmoDrag(state, handle)
    if not istable(state) or not istable(handle) or not istable(handle.hover) then return false end

    local index = math.floor(tonumber(handle.worldPointIndex) or 0)
    local points = targetPoints(state)
    if index < 1 or index > #points or not isvector(points[index]) then return false end

    local ply = LocalPlayer()
    if not IsValid(ply) then return false end

    local eye = ply:GetShootPos()
    local dir = ply:GetAimVector()
    local origin = copyVec(handle.origin)
    local basis = copyAng(handle.basis or worldBasis())
    local item = handle.hover
    if item.kind ~= "move" and item.kind ~= "plane" then
        return false
    end

    local normal = isfunction(gizmoShared.linearDragNormal)
        and gizmoShared.linearDragNormal(origin, basis, item, eye)
        or nil
    if not normal then return false end

    local worldPos, localPos = M.LinePlaneIntersection(dir, eye, normal, origin, basis)
    if not isvector(worldPos) or not isvector(localPos) then return false end

    state.press = {
        kind = "gizmo",
        worldPoint = true,
        worldPointIndex = index,
        gizmo = item,
        origin = copyVec(origin),
        basis = copyAng(basis),
        referenceBasis = copyAng(handle.referenceBasis or basis),
        normal = copyVec(normal),
        startWorld = copyVec(worldPos),
        startLocal = copyVec(localPos),
        dragStartLocal = VectorP(0, 0, 0),
        currentGizmoPos = VectorP(0, 0, 0),
        referenceDelta = VectorP(0, 0, 0),
        rotationDelta = 0,
        space = WORLD_POINT_GIZMO_SPACE
    }

    setSelectedIndex(state, index)
    return true
end

local function traceSnapNormal(press)
    local trace = press and press.lastTraceSnapHit and press.lastTraceSnapHit.trace or nil
    if not trace or not isvector(trace.HitNormal) then return end

    return trace.HitNormal
end

local function updateWorldPointGizmoDrag(state)
    local press = state.press
    if not istable(press) or press.kind ~= "gizmo" or press.worldPoint ~= true then return false end

    local ply = LocalPlayer()
    if not IsValid(ply) then return true end

    local eye = ply:GetShootPos()
    local dir = ply:GetAimVector()
    local _, localPos = M.LinePlaneIntersection(dir, eye, press.normal, press.origin, press.basis)
    if not isvector(localPos) then return true end

    local dragStartLocal = press.dragStartLocal or press.startLocal or ZERO_VEC
    local currentGizmoPos = isfunction(gizmoShared.translationLocalPos)
        and gizmoShared.translationLocalPos(press.gizmo, dragStartLocal, localPos, press.currentGizmoPos)
        or nil
    if not isvector(currentGizmoPos) then
        return true
    end

    if isfunction(snapGizmoPosition) then
        currentGizmoPos = snapGizmoPosition(state, press, currentGizmoPos) or currentGizmoPos
    end

    press.currentGizmoPos = setVec(press.currentGizmoPos, currentGizmoPos)
    press.referenceDelta = setVec(press.referenceDelta, currentGizmoPos - dragStartLocal)
    press.rotationDelta = 0

    local worldPos = LocalToWorldPosPrecise(currentGizmoPos, press.origin, press.basis)
    if isvector(worldPos) then
        updateTargetPoint(state, press.worldPointIndex, worldPos, traceSnapNormal(press))
    end

    return true
end

function worldPoints.clearSelection(state)
    setSelectedIndex(state, nil)
end

function worldPoints.getSelectedIndex(state)
    return selectedIndex(state)
end

function worldPoints.isSelected(state, index)
    return selectedIndex(state) == math.floor(tonumber(index) or 0)
end

function worldPoints.toggleSelection(state, index)
    index = math.floor(tonumber(index) or 0)
    if index < 1 then
        setSelectedIndex(state, nil)
        return
    end

    if selectedIndex(state) == index then
        setSelectedIndex(state, nil)
    else
        setSelectedIndex(state, index)
    end
end

function worldPoints.hasToggleHint(state)
    return istable(state) and isWorldTarget(state.prop2) and #targetPoints(state) > 0
end

function worldPoints.handleModifierToggle(state, blocked)
    if not istable(state) then return false end

    local altDown = modifierState()
    local altPressed = altDown and not state.worldPointAltDown

    state.worldPointAltDown = altDown

    if blocked or not worldPoints.hasToggleHint(state) or istable(state.press) then
        return false
    end

    local hover = state.hover
    if not istable(hover) or hover.side ~= "target" or not hover.point or not isWorldTarget(hover.ent) then
        return false
    end

    if not altPressed then
        return false
    end

    worldPoints.toggleSelection(state, hover.point.index)
    return true
end

function worldPoints.sanitizeState(state)
    if not istable(state) then return end

    if not isWorldTarget(state.prop2) then
        setSelectedIndex(state, nil)
        clearWorldPointPress(state)
        return
    end

    local index = selectedIndex(state)
    state.selectedWorldPointIndex = index

    local press = state.press
    if not istable(press) then return end

    if press.kind == "world_point_press" then
        local points = targetPoints(state)
        local pointIndex = math.floor(tonumber(press.index) or 0)
        if pointIndex < 1 or pointIndex > #points or not isvector(points[pointIndex]) then
            state.press = nil
        end
    elseif press.worldPoint == true then
        local points = targetPoints(state)
        local pointIndex = math.floor(tonumber(press.worldPointIndex) or 0)
        if pointIndex < 1 or pointIndex > #points or not isvector(points[pointIndex]) then
            state.press = nil
        end
    end
end

function worldPoints.onTargetPointRemoved(state, removedIndex)
    if not istable(state) then return end

    removedIndex = math.floor(tonumber(removedIndex) or 0)
    if removedIndex < 1 then return end

    local index = math.floor(tonumber(state.selectedWorldPointIndex) or 0)
    if index >= 1 then
        if removedIndex == index then
            setSelectedIndex(state, nil)
        elseif removedIndex < index then
            setSelectedIndex(state, index - 1)
        end
    end

    if adjustPressIndex(state.press, removedIndex) == false then
        state.press = nil
    end
end

function worldPoints.getGizmo(_, state)
    if not istable(state) then return end
    if not isWorldTarget(state.prop2) then return end

    return buildGizmo(state)
end

function worldPoints.shouldSuppressDefaultGizmo(state)
    if not istable(state) or not isWorldTarget(state.prop2) then return false end

    local press = state.press
    if not istable(press) then return false end

    return press.kind == "world_point_press"
        or (press.kind == "drag_point" and press.worldPoint == true)
end

function worldPoints.beginMousePress(_, state)
    if not istable(state) or not isWorldTarget(state.prop2) then return false end

    local hover = state.hover
    if not istable(hover) then return false end

    if hover.gizmo and hover.gizmo.worldPoint and hover.gizmo.hover then
        return beginWorldPointGizmoDrag(state, hover.gizmo)
    end

    if hover.side == "target" and hover.point and isWorldTarget(hover.ent) then
        return beginWorldPointPress(state, hover)
    end

    return false
end

function worldPoints.updateActivePress(_, state)
    if not istable(state) or not istable(state.press) then return false end

    local press = state.press
    if press.kind == "world_point_press" then
        state.corner = nil

        local hover = state.hover
        local candidate = hover and hover.candidate or nil
        if hover
            and hover.side == "target"
            and isWorldTarget(state.prop2)
            and istable(candidate)
            and isvector(candidate.worldPos)
            and isvector(press.startWorldPos)
            and press.startWorldPos:Distance(candidate.worldPos) >= WORLD_POINT_DRAG_DEADZONE then
            setSelectedIndex(state, press.index)
            state.press = {
                kind = "drag_point",
                side = "target",
                index = press.index,
                worldPoint = true,
                worldPointIndex = press.index
            }
            updateTargetPointFromCandidate(state, press.index, candidate)
        end

        return true
    end

    if press.kind == "gizmo" and press.worldPoint == true then
        state.corner = nil
        updateWorldPointGizmoDrag(state)
        return true
    end

    return false
end

function worldPoints.handleMouseRelease(_, state, press)
    if not istable(state) or not istable(press) or press.kind ~= "world_point_press" then
        return false
    end

    worldPoints.toggleSelection(state, press.index)
    return true
end
