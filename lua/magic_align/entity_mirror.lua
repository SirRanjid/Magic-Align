local M = MAGIC_ALIGN
if not M then return end

local isvector = M.IsVectorLike
local isangle = M.IsAngleLike
local VectorP = M.VectorP
local ZERO_VEC = VectorP(0, 0, 0)

M.ENTITY_MIRROR_NONE = 0
M.ENTITY_MIRROR_X = 1
M.ENTITY_MIRROR_Y = 2
M.ENTITY_MIRROR_Z = 3

M.ENTITY_MIRROR_VISUAL = 1
M.ENTITY_MIRROR_PHYSICS = 2
M.ENTITY_MIRROR_PRIMITIVE_AWARE = 4
M.ENTITY_MIRROR_DEFAULT_FLAGS = bit.bor(
    M.ENTITY_MIRROR_VISUAL,
    M.ENTITY_MIRROR_PHYSICS,
    M.ENTITY_MIRROR_PRIMITIVE_AWARE
)

M.ENTITY_MIRROR_MODIFIER_ID = "magic_align_entity_mirror"

local EntityMirror = M.EntityMirror or {}
M.EntityMirror = EntityMirror

local NW_AXIS = "magic_align_mirror_axis"
local NW_FLAGS = "magic_align_mirror_flags"
local NW_REVISION = "magic_align_mirror_revision"
local DEBUG_CVAR = "magic_align_mirror_debug"
local DEBUG_CLIENT_CVAR = "magic_align_mirror_debug_client"
local MIRROR_COLOR = Color(176, 112, 235)
local EDITOR_FADED_COLOR = Color(120, 120, 120)
local EDITOR_HEADER_FALLBACK = Color(122, 189, 254)
local EDITOR_BACKGROUND_FALLBACK = Color(245, 245, 245)

if SERVER then
    CreateConVar(
        DEBUG_CVAR,
        "0",
        FCVAR_ARCHIVE + FCVAR_NOTIFY + FCVAR_REPLICATED,
        "Print Magic Align mirror pose, visual, and physics debug data."
    )
elseif CLIENT then
    CreateClientConVar(
        DEBUG_CLIENT_CVAR,
        "0",
        true,
        false,
        "Print clientside Magic Align mirror visual and physics debug data."
    )
end

local function validAxis(axis)
    axis = tonumber(axis) or M.ENTITY_MIRROR_NONE
    axis = math.floor(axis)
    if axis < M.ENTITY_MIRROR_NONE or axis > M.ENTITY_MIRROR_Z then
        return M.ENTITY_MIRROR_NONE
    end

    return axis
end

local function validFlags(flags)
    flags = tonumber(flags)
    if not flags then return M.ENTITY_MIRROR_DEFAULT_FLAGS end

    return math.max(0, math.floor(flags))
end

function EntityMirror.IsMirrored(ent)
    return EntityMirror.GetAxis(ent) ~= M.ENTITY_MIRROR_NONE
end

function EntityMirror.AxisLabel(axis)
    axis = validAxis(axis)
    if axis == M.ENTITY_MIRROR_X then return "X" end
    if axis == M.ENTITY_MIRROR_Y then return "Y" end
    if axis == M.ENTITY_MIRROR_Z then return "Z" end
    return "Off"
end

function EntityMirror.Sanitize(data)
    if not istable(data) then return end

    local axis = validAxis(data.axis)
    if axis == M.ENTITY_MIRROR_NONE then return end

    return {
        schema = 1,
        axis = axis,
        flags = validFlags(data.flags),
        revision = math.max(0, math.floor(tonumber(data.revision) or 0))
    }
end

function EntityMirror.AxisForMirrorReference(reference)
    if not istable(reference) then return M.ENTITY_MIRROR_NONE end

    -- MirrorPose repairs point and plane reflections by preserving reflected
    -- forward/up hints. The remaining handedness flip is local right/Y.
    if reference.kind == M.MIRROR_POINT or reference.kind == M.MIRROR_PLANE then
        return M.ENTITY_MIRROR_Y
    end

    return M.ENTITY_MIRROR_NONE
end

function EntityMirror.ComposeAxis(currentAxis, deltaAxis)
    currentAxis = validAxis(currentAxis)
    deltaAxis = validAxis(deltaAxis)

    if deltaAxis == M.ENTITY_MIRROR_NONE then return currentAxis end
    if currentAxis == M.ENTITY_MIRROR_NONE then return deltaAxis end
    if currentAxis == deltaAxis then return M.ENTITY_MIRROR_NONE end

    -- Different local flips compose to a right-handed rotation. The caller is
    -- responsible for the pose solve; we clear the stored flip rather than stack.
    return M.ENTITY_MIRROR_NONE
end

function EntityMirror.ComposeState(state, deltaAxis, flags)
    state = istable(state) and state or {}

    return {
        axis = EntityMirror.ComposeAxis(state.axis, deltaAxis),
        flags = flags ~= nil and validFlags(flags) or validFlags(state.flags)
    }
end

function EntityMirror.StateAxis(state)
    if not istable(state) then return M.ENTITY_MIRROR_NONE end
    return validAxis(state.axis)
end

local function rawStoredState(ent)
    if not IsValid(ent) then return end

    local mods = istable(ent.EntityMods) and ent.EntityMods or nil
    return mods and mods[M.ENTITY_MIRROR_MODIFIER_ID] or nil
end

local function storedState(ent)
    return EntityMirror.Sanitize(rawStoredState(ent))
end

local function axisSigns(axis)
    if axis == M.ENTITY_MIRROR_X then return -1, 1, 1 end
    if axis == M.ENTITY_MIRROR_Y then return 1, -1, 1 end
    if axis == M.ENTITY_MIRROR_Z then return 1, 1, -1 end
    return 1, 1, 1
end

local function setVector(out, value)
    if not isvector(value) then return end

    if not isvector(out) then
        return VectorP(value.x, value.y, value.z)
    end

    out.x, out.y, out.z = value.x, value.y, value.z
    return out
end

function EntityMirror.AxisSigns(axis)
    return axisSigns(validAxis(axis))
end

function EntityMirror.ApplyAxisToVector(out, value, axis)
    if not isvector(value) then return end
    out = isvector(out) and out or Vector()

    local sx, sy, sz = axisSigns(validAxis(axis))
    out.x = value.x * sx
    out.y = value.y * sy
    out.z = value.z * sz

    return out
end

function EntityMirror.ApplyAxisToPoint(point, axis)
    if not isvector(point) then return false end

    EntityMirror.ApplyAxisToVector(point, point, axis)
    if isvector(point.normal) then
        EntityMirror.ApplyAxisToVector(point.normal, point.normal, axis)
    end

    return true
end

function EntityMirror.ScaleForAxis(axis, out)
    out = isvector(out) and out or Vector()
    out.x, out.y, out.z = axisSigns(validAxis(axis))
    return out
end

function EntityMirror.AxisForEntity(ent)
    if not IsValid(ent) then return M.ENTITY_MIRROR_NONE end
    return EntityMirror.GetAxis(ent)
end

function EntityMirror.LocalPointToWorldForAxis(localPos, originPos, originAng, axis, out)
    if not isvector(localPos) or not isvector(originPos) or not isangle(originAng) then return end

    local sx, sy, sz = axisSigns(validAxis(axis))
    local transformedLocal = VectorP(localPos.x * sx, localPos.y * sy, localPos.z * sz)
    return setVector(out, M.LocalToWorldPosPrecise(transformedLocal, originPos, originAng))
end

function EntityMirror.WorldPointToLocalForAxis(worldPos, originPos, originAng, axis, out)
    if not isvector(worldPos) or not isvector(originPos) or not isangle(originAng) then return end

    local rawLocal = M.WorldToLocalPosPrecise(worldPos, originPos, originAng)
    if not isvector(rawLocal) then return end

    local sx, sy, sz = axisSigns(validAxis(axis))
    return setVector(out, VectorP(rawLocal.x * sx, rawLocal.y * sy, rawLocal.z * sz))
end

function EntityMirror.LocalVectorToWorldForAxis(localVec, originAng, axis, out)
    if not isvector(localVec) or not isangle(originAng) then return end

    local sx, sy, sz = axisSigns(validAxis(axis))
    local transformedLocal = VectorP(localVec.x * sx, localVec.y * sy, localVec.z * sz)
    return setVector(out, M.LocalToWorldPosPrecise(transformedLocal, ZERO_VEC, originAng))
end

function EntityMirror.WorldVectorToLocalForAxis(worldVec, originAng, axis, out)
    if not isvector(worldVec) or not isangle(originAng) then return end

    local rawLocal = M.WorldToLocalPosPrecise(worldVec, ZERO_VEC, originAng)
    if not isvector(rawLocal) then return end

    local sx, sy, sz = axisSigns(validAxis(axis))
    return setVector(out, VectorP(rawLocal.x * sx, rawLocal.y * sy, rawLocal.z * sz))
end

function EntityMirror.LocalPointToWorld(ent, localPos, out)
    if not IsValid(ent) then return end
    return EntityMirror.LocalPointToWorldForAxis(localPos, ent:GetPos(), ent:GetAngles(), EntityMirror.AxisForEntity(ent), out)
end

function EntityMirror.WorldPointToLocal(ent, worldPos, out)
    if not IsValid(ent) then return end
    return EntityMirror.WorldPointToLocalForAxis(worldPos, ent:GetPos(), ent:GetAngles(), EntityMirror.AxisForEntity(ent), out)
end

function EntityMirror.LocalVectorToWorld(ent, localVec, out)
    if not IsValid(ent) then return end
    return EntityMirror.LocalVectorToWorldForAxis(localVec, ent:GetAngles(), EntityMirror.AxisForEntity(ent), out)
end

function EntityMirror.WorldVectorToLocal(ent, worldVec, out)
    if not IsValid(ent) then return end
    return EntityMirror.WorldVectorToLocalForAxis(worldVec, ent:GetAngles(), EntityMirror.AxisForEntity(ent), out)
end

local function scaleIsIdentity(scale)
    if not isvector(scale) then return true end

    local epsilon = tonumber(M.UI_COMPARE_EPSILON) or 0.0001
    return math.abs(scale.x - 1) <= epsilon
        and math.abs(scale.y - 1) <= epsilon
        and math.abs(scale.z - 1) <= epsilon
end

local function scaleIsZero(scale)
    if not isvector(scale) then return true end

    local epsilon = tonumber(M.UI_COMPARE_EPSILON) or 0.0001
    return math.abs(scale.x) <= epsilon
        and math.abs(scale.y) <= epsilon
        and math.abs(scale.z) <= epsilon
end

local function scaleApprox(a, b)
    if not isvector(a) or not isvector(b) then return false end

    local epsilon = tonumber(M.UI_COMPARE_EPSILON) or 0.0001
    return math.abs(a.x - b.x) <= epsilon
        and math.abs(a.y - b.y) <= epsilon
        and math.abs(a.z - b.z) <= epsilon
end

local function copyScale(scale, out)
    out = isvector(out) and out or Vector()

    if isvector(scale) and not scaleIsZero(scale) then
        out.x = scale.x
        out.y = scale.y
        out.z = scale.z
    else
        out.x = 1
        out.y = 1
        out.z = 1
    end

    return out
end

local function stripAxisSign(scale, axis, out)
    out = copyScale(scale, out)

    axis = validAxis(axis)
    local epsilon = tonumber(M.UI_COMPARE_EPSILON) or 0.0001
    if axis == M.ENTITY_MIRROR_X and out.x < -epsilon then
        out.x = -out.x
    elseif axis == M.ENTITY_MIRROR_Y and out.y < -epsilon then
        out.y = -out.y
    elseif axis == M.ENTITY_MIRROR_Z and out.z < -epsilon then
        out.z = -out.z
    end

    return out
end

local function applyAxisSign(scale, axis, out)
    out = copyScale(scale, out)

    local sx, sy, sz = axisSigns(validAxis(axis))
    out.x = out.x * sx
    out.y = out.y * sy
    out.z = out.z * sz
    return out
end

local function liveSizeHandlerScale(ent, getterName)
    local handler = M.FindSizeHandler(ent)
    local getter = IsValid(handler) and handler[getterName] or nil
    if not isfunction(getter) then return end

    local scale = M.ParseScaleVector(getter(handler))
    if not isvector(scale) or scaleIsZero(scale) then return end

    return scale
end

local function preferLiveResizeScale(stored, live)
    if not isvector(live) then return stored end
    if isvector(stored) and not scaleIsIdentity(stored) and scaleIsIdentity(live) then
        return stored
    end

    return live
end

local function optionResizeScale(options, key)
    local scale = istable(options) and options[key] or nil
    if isvector(scale) and not scaleIsZero(scale) then
        return scale
    end
end

local function captureResizeScales(ent, currentAxis, options)
    local physical = optionResizeScale(options, "resizePhysicalScale")
    local visual = optionResizeScale(options, "resizeVisualScale")

    if not isvector(physical) or not isvector(visual) then
        local storedPhysical, storedVisual = M.GetAdvResizerScales(ent)

        if not isvector(physical) then
            physical = preferLiveResizeScale(storedPhysical, liveSizeHandlerScale(ent, "GetActualPhysicsScale"))
        end

        if not isvector(visual) then
            visual = preferLiveResizeScale(storedVisual, liveSizeHandlerScale(ent, "GetVisualScale"))
        end
    end

    return stripAxisSign(physical, currentAxis), stripAxisSign(visual, currentAxis)
end

local function syncLiveSizeHandlerScales(ent, physical, visual)
    if not SERVER or not IsValid(ent) then return end

    local handler = M.FindSizeHandler(ent)
    if not IsValid(handler) then return end

    if isvector(physical) and isfunction(handler.SetActualPhysicsScale) then
        handler:SetActualPhysicsScale(tostring(physical))
    end

    if isvector(visual) and isfunction(handler.SetVisualScale) then
        handler:SetVisualScale(tostring(visual))
    end
end

local function ensureStoredResizeScales(ent, physical, visual)
    if not SERVER or not IsValid(ent) then return end
    if scaleIsIdentity(physical) and scaleIsIdentity(visual) then return end

    ent.EntityMods = istable(ent.EntityMods) and ent.EntityMods or {}
    local data = istable(ent.EntityMods.advr) and table.Copy(ent.EntityMods.advr) or {}
    data[1] = physical.x
    data[2] = physical.y
    data[3] = physical.z
    data[4] = visual.x
    data[5] = visual.y
    data[6] = visual.z
    if data[7] == nil then
        data[7] = false
    end

    duplicator.StoreEntityModifier(ent, "advr", data)

    syncLiveSizeHandlerScales(ent, physical, visual)
end

local function physicsScaleFor(ent, axis, out, physicalScale, currentAxis)
    if not isvector(physicalScale) then
        local physical = M.GetAdvResizerScales(ent)
        physicalScale = preferLiveResizeScale(physical, liveSizeHandlerScale(ent, "GetActualPhysicsScale"))
    end

    local base = stripAxisSign(physicalScale, currentAxis, out)
    return applyAxisSign(base, axis, out)
end

local function liveSizeHandlerVisualScale(ent)
    return liveSizeHandlerScale(ent, "GetVisualScale")
end

local function resizeVisualScaleFor(ent, currentAxis)
    local visual = liveSizeHandlerVisualScale(ent)
        or M.GetAdvResizerVisualScale(ent)

    if isvector(visual) then
        local base = stripAxisSign(
            visual,
            currentAxis,
            ent._magicAlignEntityMirrorResizeVisualScale
        )
        ent._magicAlignEntityMirrorResizeVisualScale = base
        return base
    end

    return ent._magicAlignEntityMirrorResizeVisualScale
end

local function visualScaleFor(ent, axis, out, currentAxis)
    local base = resizeVisualScaleFor(ent, currentAxis)
    return applyAxisSign(base, axis, out)
end

local function scaleKey(scale)
    if not isvector(scale) then return "" end
    return string.format("%.6f:%.6f:%.6f", scale.x, scale.y, scale.z)
end

local function captureCollisionBounds(ent)
    if not IsValid(ent) then return end

    if isfunction(ent.GetCollisionBounds) then
        local mins, maxs = ent:GetCollisionBounds()
        if isvector(mins) and isvector(maxs) then
            return mins, maxs
        end
    end

    if isfunction(ent.OBBMins) and isfunction(ent.OBBMaxs) then
        local mins, maxs = ent:OBBMins(), ent:OBBMaxs()
        if isvector(mins) and isvector(maxs) then
            return mins, maxs
        end
    end
end

local function captureRenderBounds(ent)
    if not IsValid(ent) then return end

    if isfunction(ent.GetRenderBounds) then
        local mins, maxs = ent:GetRenderBounds()
        if isvector(mins) and isvector(maxs) then
            return mins, maxs
        end
    end

    return captureCollisionBounds(ent)
end

local function boundsCenter(mins, maxs, out)
    if not isvector(mins) or not isvector(maxs) then return end
    out = isvector(out) and out or Vector()
    out.x = (mins.x + maxs.x) * 0.5
    out.y = (mins.y + maxs.y) * 0.5
    out.z = (mins.z + maxs.z) * 0.5
    return out
end

local function captureLocalBounds(ent)
    if not IsValid(ent) then return end

    local mins, maxs = M.GetLocalBounds(ent)
    if isvector(mins) and isvector(maxs) then
        return mins, maxs
    end

    return captureCollisionBounds(ent)
end

local function localBoundsCenter(ent, out)
    local mins, maxs = captureLocalBounds(ent)
    return boundsCenter(mins, maxs, out)
end

local function axisPoint(value, axis, out)
    if not isvector(value) then return end
    out = isvector(out) and out or Vector()

    local sx, sy, sz = axisSigns(validAxis(axis))
    out.x = value.x * sx
    out.y = value.y * sy
    out.z = value.z * sz
    return out
end

function EntityMirror.LocalBoundsCenter(ent, out)
    return localBoundsCenter(ent, out)
end

function EntityMirror.BaseMirrorPivot(ent, currentAxis, out)
    local center = localBoundsCenter(ent)
    if not isvector(center) then return end

    local boundsAxis = EntityMirror.BoundsAxisForEntity(ent) or currentAxis
    return axisPoint(center, boundsAxis, out)
end

function EntityMirror.LocalPivotForAxis(basePivot, axis, out)
    return axisPoint(basePivot, axis, out)
end

function EntityMirror.PositionForLocalPivot(ent, targetAng, targetAxis, targetPivotWorld, basePivot, out)
    if not IsValid(ent) or not isangle(targetAng) or not isvector(targetPivotWorld) then return end
    basePivot = isvector(basePivot) and basePivot or EntityMirror.BaseMirrorPivot(ent, EntityMirror.GetAxis(ent))
    if not isvector(basePivot) then return end

    local targetLocalPivot = axisPoint(basePivot, targetAxis)
    if not isvector(targetLocalPivot) then return end

    local targetOffset = M.LocalToWorldPosPrecise(targetLocalPivot, ZERO_VEC, targetAng)
    if not isvector(targetOffset) then return end

    return setVector(out, M.SubtractVectorsPrecise(targetPivotWorld, targetOffset))
end

function EntityMirror.PositionForInPlaceAxisChange(ent, targetAng, currentAxis, targetAxis, out)
    if not IsValid(ent) or not isangle(targetAng) then return end

    currentAxis = validAxis(currentAxis)
    targetAxis = validAxis(targetAxis)

    local basePivot = EntityMirror.BaseMirrorPivot(ent, currentAxis)
    if not isvector(basePivot) then
        return setVector(out, ent:GetPos())
    end

    local currentLocalPivot = axisPoint(basePivot, currentAxis)
    local currentPivotWorld = currentLocalPivot
        and M.LocalToWorldPosPrecise(currentLocalPivot, ent:GetPos(), ent:GetAngles())
        or nil
    if not isvector(currentPivotWorld) then
        return setVector(out, ent:GetPos())
    end

    return EntityMirror.PositionForLocalPivot(ent, targetAng, targetAxis, currentPivotWorld, basePivot, out)
end

local function scaledBounds(mins, maxs, scale)
    if not isvector(mins) or not isvector(maxs) or not isvector(scale) then return end

    return Vector(
        math.min(mins.x * scale.x, maxs.x * scale.x),
        math.min(mins.y * scale.y, maxs.y * scale.y),
        math.min(mins.z * scale.z, maxs.z * scale.z)
    ), Vector(
        math.max(mins.x * scale.x, maxs.x * scale.x),
        math.max(mins.y * scale.y, maxs.y * scale.y),
        math.max(mins.z * scale.z, maxs.z * scale.z)
    )
end

function EntityMirror.BoundsForAxis(mins, maxs, axis)
    if not isvector(mins) or not isvector(maxs) then return end

    local scale = EntityMirror.ScaleForAxis(axis, Vector())
    return scaledBounds(mins, maxs, scale)
end

function EntityMirror.BoundsAxisForEntity(ent)
    if not IsValid(ent) then return M.ENTITY_MIRROR_NONE end

    if EntityMirror.PhysicsAxisForEntity then
        return validAxis(EntityMirror.PhysicsAxisForEntity(ent))
    end

    local flags = EntityMirror.GetFlags(ent)
    if bit.band(flags, M.ENTITY_MIRROR_PHYSICS) == 0 then
        return M.ENTITY_MIRROR_NONE
    end

    if M.IsPrimitive(ent)
        and bit.band(flags, M.ENTITY_MIRROR_PRIMITIVE_AWARE) == 0 then
        return M.ENTITY_MIRROR_NONE
    end

    return EntityMirror.GetAxis(ent)
end

function EntityMirror.BoundsInBaseSpace(ent, mins, maxs, boundsAxis)
    boundsAxis = validAxis(boundsAxis ~= nil and boundsAxis or EntityMirror.BoundsAxisForEntity(ent))
    return EntityMirror.BoundsForAxis(mins, maxs, boundsAxis)
end

function EntityMirror.RevisionForEntity(ent)
    if not IsValid(ent) or not ent.GetNWInt then return -1 end
    return tonumber(ent:GetNWInt(NW_REVISION, -1)) or -1
end

function EntityMirror.BoundsRevisionForEntity(ent)
    if not IsValid(ent) then return "invalid" end

    local axis = EntityMirror.GetAxis(ent)
    local flags = EntityMirror.GetFlags(ent)

    return table.concat({
        tostring(axis),
        tostring(flags),
        tostring(EntityMirror.BoundsAxisForEntity(ent)),
        tostring(EntityMirror.RevisionForEntity(ent))
    }, "|")
end

local function convexBounds(convexes)
    if not istable(convexes) or not istable(convexes[1]) then return end

    local mins, maxs
    for i = 1, #convexes do
        local convex = convexes[i]
        for j = 1, #convex do
            local item = convex[j]
            local pos = istable(item) and item.pos or item
            if isvector(pos) then
                if not mins then
                    mins = Vector(pos.x, pos.y, pos.z)
                    maxs = Vector(pos.x, pos.y, pos.z)
                else
                    mins.x = math.min(mins.x, pos.x)
                    mins.y = math.min(mins.y, pos.y)
                    mins.z = math.min(mins.z, pos.z)
                    maxs.x = math.max(maxs.x, pos.x)
                    maxs.y = math.max(maxs.y, pos.y)
                    maxs.z = math.max(maxs.z, pos.z)
                end
            end
        end
    end

    return mins, maxs
end

local function setLocalBounds(ent, mins, maxs, collision, render)
    if not IsValid(ent) or not isvector(mins) or not isvector(maxs) then return end

    if collision ~= false and isfunction(ent.SetCollisionBounds) then
        ent:SetCollisionBounds(mins, maxs)
    end

    if render ~= false and isfunction(ent.SetRenderBounds) then
        ent:SetRenderBounds(mins, maxs)
    end

    if render ~= false and isfunction(ent.DestroyShadow) then
        ent:DestroyShadow()
    end
end

local function setCollisionBounds(ent, mins, maxs)
    setLocalBounds(ent, mins, maxs, true, false)
end

local function setRenderBounds(ent, mins, maxs)
    setLocalBounds(ent, mins, maxs, false, true)
end

local function setPhysicsRenderBounds(ent, mins, maxs)
    setLocalBounds(ent, mins, maxs, true, true)
end

local function physicsConvexes(phys)
    if not IsValid(phys) or not phys.GetMeshConvexes then return end

    local convexes = phys:GetMeshConvexes()
    if istable(convexes) and istable(convexes[1]) then
        return convexes
    end
end

local function scaledConvexes(convexes, scratch, scale)
    if not istable(convexes) or not istable(convexes[1]) or not istable(scratch) or not isvector(scale) then
        return
    end

    for i = 1, #convexes do
        local src = convexes[i]
        local dst = scratch[i]
        if not istable(dst) then
            dst = {}
            scratch[i] = dst
        end

        local count = 0
        for j = 1, #src do
            local item = src[j]
            local pos = istable(item) and item.pos or item
            if isvector(pos) then
                count = count + 1
                local out = dst[count]
                if not isvector(out) then
                    out = Vector()
                    dst[count] = out
                end

                out.x = pos.x * scale.x
                out.y = pos.y * scale.y
                out.z = pos.z * scale.z
            end
        end

        for j = count + 1, #dst do
            dst[j] = nil
        end
    end

    for i = #convexes + 1, #scratch do
        scratch[i] = nil
    end

    return scratch
end

local DEBUG_SIGNATURES = setmetatable({}, { __mode = "k" })

function EntityMirror.DebugEnabled()
    local cvar = GetConVar(DEBUG_CVAR)
    if cvar and cvar:GetBool() then return true end

    if CLIENT then
        local clientCvar = GetConVar(DEBUG_CLIENT_CVAR)
        return clientCvar and clientCvar:GetBool() or false
    end

    return false
end

local function debugVector(value)
    if not isvector(value) then return tostring(value) end

    return ("%.3f %.3f %.3f"):format(value.x, value.y, value.z)
end

local function debugAngle(value)
    if not isangle(value) then return tostring(value) end

    return ("%.3f %.3f %.3f"):format(value.p, value.y, value.r)
end

local function debugBounds(mins, maxs)
    if not isvector(mins) or not isvector(maxs) then return "nil" end

    return ("%s -> %s"):format(debugVector(mins), debugVector(maxs))
end

local function debugValue(value)
    if isvector(value) then return debugVector(value) end
    if isangle(value) then return debugAngle(value) end
    if istable(value) and (value.mins ~= nil or value.maxs ~= nil) then
        return debugBounds(value.mins, value.maxs)
    end

    return tostring(value)
end

local function primitiveDebugResult(ent)
    local primitive = IsValid(ent) and ent.primitive or nil
    local result = istable(primitive) and primitive.result or nil
    if istable(result) and istable(result.convexes) and istable(result.convexes[1]) then
        return result, "cached"
    end

    if not IsValid(ent) or not isfunction(ent.PrimitiveGetConstruct) then return nil, "none" end

    local ok, valid, constructed = pcall(ent.PrimitiveGetConstruct, ent)
    if ok and valid and istable(constructed) then
        return constructed, "constructed"
    end

    return nil, ok and "invalid" or "error"
end

local function debugPrimitiveBounds(ent)
    if not M.IsPrimitive(ent) then return "non-primitive" end

    local result, source = primitiveDebugResult(ent)
    if not result then return source or "none" end

    local mins, maxs = convexBounds(result.convexes)
    if not mins or not maxs then
        mins, maxs = result.mins, result.maxs
    end

    return ("%s %s"):format(source or "unknown", debugBounds(mins, maxs))
end

function EntityMirror.DebugEntity(label, ent, extra, force)
    if not force and not EntityMirror.DebugEnabled() then return end
    if not IsValid(ent) then return end

    local axis = EntityMirror.GetAxis(ent)
    local flags = EntityMirror.GetFlags(ent)
    local nwAxis = ent.GetNWInt and ent:GetNWInt(NW_AXIS, M.ENTITY_MIRROR_NONE) or M.ENTITY_MIRROR_NONE
    local nwFlags = ent.GetNWInt and ent:GetNWInt(NW_FLAGS, M.ENTITY_MIRROR_DEFAULT_FLAGS) or M.ENTITY_MIRROR_DEFAULT_FLAGS
    local nwRevision = ent.GetNWInt and ent:GetNWInt(NW_REVISION, -1) or -1
    local clientAxis = CLIENT and ent._magicAlignEntityMirrorAxis or nil
    local previewAxis = CLIENT and ent._magicAlignEntityMirrorPreviewAxis or nil
    local phys = ent:GetPhysicsObject()
    local cmins, cmaxs = captureCollisionBounds(ent)
    local rmins, rmaxs = captureRenderBounds(ent)
    local parts = {
        ("[%s]"):format(CLIENT and "CL" or "SV"),
        tostring(label or "mirror"),
        ("ent=%s#%s"):format(ent:GetClass(), ent:EntIndex()),
        ("primitive=%s"):format(M.IsPrimitive(ent) and "true" or "false"),
        ("axis=%s"):format(EntityMirror.AxisLabel(axis)),
        ("nwAxis=%s"):format(EntityMirror.AxisLabel(nwAxis)),
        ("nwFlags=%s"):format(nwFlags),
        ("nwRevision=%s"):format(nwRevision),
        ("clientAxis=%s"):format(clientAxis ~= nil and EntityMirror.AxisLabel(clientAxis) or "nil"),
        ("previewAxis=%s"):format(previewAxis ~= nil and EntityMirror.AxisLabel(previewAxis) or "nil"),
        ("renderOverrideActive=%s"):format(CLIENT and tostring(
            ent._magicAlignEntityMirrorRenderOverride ~= nil
                and ent.RenderOverride == ent._magicAlignEntityMirrorRenderOverride
        ) or "nil"),
        ("hasRenderMatrix=%s"):format(CLIENT and tostring(ent._magicAlignEntityMirrorMatrix ~= nil) or "nil"),
        ("flags=%s"):format(flags),
        ("pos=%s"):format(debugVector(ent:GetPos())),
        ("ang=%s"):format(debugAngle(ent:GetAngles())),
        ("physPos=%s"):format(IsValid(phys) and debugVector(phys:GetPos()) or "nil"),
        ("physAng=%s"):format(IsValid(phys) and debugAngle(phys:GetAngles()) or "nil"),
        ("collision=%s"):format(debugBounds(cmins, cmaxs)),
        ("render=%s"):format(debugBounds(rmins, rmaxs)),
        ("primitiveBounds=%s"):format(debugPrimitiveBounds(ent))
    }

    if istable(extra) then
        local keys = {}
        for key in pairs(extra) do
            keys[#keys + 1] = key
        end
        table.sort(keys)

        for i = 1, #keys do
            local key = keys[i]
            parts[#parts + 1] = ("%s=%s"):format(tostring(key), debugValue(extra[key]))
        end
    end

    local line = "[Magic Align mirror debug] " .. table.concat(parts, " | ")
    if not force then
        local signatures = DEBUG_SIGNATURES[ent]
        if not signatures then
            signatures = {}
            DEBUG_SIGNATURES[ent] = signatures
        end

        if signatures[label] == line then return end
        signatures[label] = line
    end

    print(line)
end

function EntityMirror.DebugConvexes(label, ent, axis, scale, source, transformed)
    if not EntityMirror.DebugEnabled() then return end

    local smins, smaxs = convexBounds(source)
    local tmins, tmaxs = convexBounds(transformed)
    EntityMirror.DebugEntity(label, ent, {
        requestedAxis = EntityMirror.AxisLabel(axis),
        scale = scale,
        sourceConvex = { mins = smins, maxs = smaxs },
        transformedConvex = { mins = tmins, maxs = tmaxs }
    })
end

if CLIENT then
    concommand.Remove("magic_align_mirror_debug_target")
    concommand.Add("magic_align_mirror_debug_target", function()
        local ply = LocalPlayer()
        local trace = IsValid(ply) and ply:GetEyeTrace() or nil
        local ent = trace and trace.Entity or nil
        if not IsValid(ent) then
            print("[Magic Align mirror debug] no valid entity under crosshair")
            return
        end

        EntityMirror.DebugEntity("client-target-dump", ent, nil, true)
    end)

    concommand.Remove("magic_align_mirror_debug_state")
    concommand.Add("magic_align_mirror_debug_state", function()
        local client = M.Client
        local state = M.ClientState
        if not istable(state) or not IsValid(state.prop1) then
            print("[Magic Align mirror debug] no active Magic Align prop1 state")
            return
        end

        local mirrorState = client
            and client.Mirror
            and client.Mirror.resolve
            and client.Mirror.resolve(state)
            or nil
        local reference = mirrorState and mirrorState.reference or nil
        if not istable(reference) then
            print("[Magic Align mirror debug] no active mirror reference")
            return
        end

        local transformed = M.ApplyTransformModeToPropSet
            and M.ApplyTransformModeToPropSet(M.TRANSFORM_MODE_MIRROR, state.prop1, state.linked, reference, {})
            or nil
        local preview = state.preview
        local deltaAxis = EntityMirror.AxisForMirrorReference(reference)
        local previewAxis = EntityMirror.ComposeAxis(EntityMirror.GetAxis(state.prop1), deltaAxis)

        EntityMirror.DebugEntity("client-state-prop1", state.prop1, {
            referenceKind = reference.kind,
            referencePoint = reference.point,
            referenceAxis = reference.axis,
            referenceNormal = reference.normal,
            deltaAxis = EntityMirror.AxisLabel(deltaAxis),
            previewAxis = EntityMirror.AxisLabel(previewAxis),
            transformedPos = transformed and transformed.pos or nil,
            transformedAng = transformed and transformed.ang or nil,
            previewPos = preview and preview.pos or nil,
            previewAng = preview and preview.ang or nil,
            previewTransformMode = preview and preview.transformMode or nil,
            solveAnchorId = preview and preview.solve and preview.solve.sourceAnchorId or nil,
            solveAnchorLocal = preview and preview.solve and preview.solve.sourceAnchorLocal or nil,
            solveAnchorWorld = preview and preview.solve and preview.solve.sourceAnchorWorld or nil,
            solveAnchorWorldFromLocal = preview
                and preview.solve
                and isvector(preview.solve.sourceAnchorLocal)
                and isvector(preview.pos)
                and isangle(preview.ang)
                and M.LocalToWorldPosPrecise(preview.solve.sourceAnchorLocal, preview.pos, preview.ang)
                or nil
        }, true)

        if preview and IsValid(state.ghost) then
            EntityMirror.DebugEntity("client-state-ghost", state.ghost, {
                previewPos = preview.pos,
                previewAng = preview.ang,
                previewAxis = EntityMirror.AxisLabel(preview.entityMirrorPreviewAxis or M.ENTITY_MIRROR_NONE)
            }, true)
        end
    end)
end

function EntityMirror.GetAxis(ent)
    if not IsValid(ent) then return M.ENTITY_MIRROR_NONE end

    if SERVER then
        local stored = storedState(ent)
        if stored then return stored.axis end
    end

    if ent.GetNWInt then
        return validAxis(ent:GetNWInt(NW_AXIS, M.ENTITY_MIRROR_NONE))
    end

    return M.ENTITY_MIRROR_NONE
end

function EntityMirror.GetFlags(ent)
    if not IsValid(ent) then return M.ENTITY_MIRROR_DEFAULT_FLAGS end

    if SERVER then
        local stored = storedState(ent)
        if stored then return stored.flags end
    end

    if ent.GetNWInt then
        return validFlags(ent:GetNWInt(NW_FLAGS, M.ENTITY_MIRROR_DEFAULT_FLAGS))
    end

    return M.ENTITY_MIRROR_DEFAULT_FLAGS
end

if SERVER then
    local PHYS_SCRATCH = setmetatable({}, { __mode = "k" })

    local function actualPhysicsAxis(ent)
        return validAxis(IsValid(ent) and ent._magicAlignEntityMirrorPhysicsAxis or M.ENTITY_MIRROR_NONE)
    end

    function EntityMirror.PhysicsAxisForEntity(ent)
        return actualPhysicsAxis(ent)
    end

    local function setActualPhysicsAxis(ent, axis)
        if IsValid(ent) then
            ent._magicAlignEntityMirrorPhysicsAxis = validAxis(axis)
        end
    end

    local function offStateAlreadyApplied(ent, current, currentFlags, actual, flags)
        if rawStoredState(ent) ~= nil then return false end

        return current == M.ENTITY_MIRROR_NONE
            and actual == M.ENTITY_MIRROR_NONE
            and currentFlags == flags
    end

    local function physicsState(ent)
        local phys = IsValid(ent) and ent:GetPhysicsObject() or nil
        if not IsValid(phys) then return end

        local state = {}
        if phys.GetMass then state.mass = phys:GetMass() end
        if phys.GetMaterial then state.material = phys:GetMaterial() end
        if phys.IsCollisionEnabled then state.collision = phys:IsCollisionEnabled() end
        if phys.IsDragEnabled then state.drag = phys:IsDragEnabled() end
        if phys.GetVelocity then state.velocity = phys:GetVelocity() end
        if phys.GetAngleVelocity then state.angleVelocity = phys:GetAngleVelocity() end
        if phys.IsGravityEnabled then state.gravity = phys:IsGravityEnabled() end
        if phys.IsMotionEnabled then state.motion = phys:IsMotionEnabled() end
        if phys.IsAsleep then state.asleep = phys:IsAsleep() end

        return state
    end

    local function applyPhysicsState(ent, state)
        if not istable(state) then return end

        local phys = IsValid(ent) and ent:GetPhysicsObject() or nil
        if not IsValid(phys) then return end

        if isnumber(state.mass) and phys.SetMass then phys:SetMass(state.mass) end
        if isstring(state.material) and phys.SetMaterial then phys:SetMaterial(state.material) end
        if isbool(state.collision) and phys.EnableCollisions then phys:EnableCollisions(state.collision) end
        if isbool(state.drag) and phys.EnableDrag then phys:EnableDrag(state.drag) end
        if isvector(state.velocity) and phys.SetVelocity then phys:SetVelocity(state.velocity) end
        if isvector(state.angleVelocity) and phys.AddAngleVelocity and phys.GetAngleVelocity then
            phys:AddAngleVelocity(state.angleVelocity - phys:GetAngleVelocity())
        end
        if isbool(state.gravity) and phys.EnableGravity then phys:EnableGravity(state.gravity) end
        if isbool(state.motion) and phys.EnableMotion then phys:EnableMotion(state.motion) end
        if state.asleep == true then
            if phys.Sleep then phys:Sleep() end
        elseif phys.Wake then
            phys:Wake()
        end
    end

    local function finishPhysics(ent, customCollisions, state, keepPhysicsTransform)
        if not IsValid(ent) then return end

        ent:EnableCustomCollisions(customCollisions == true)
        ent:SetMoveType(MOVETYPE_VPHYSICS)
        ent:SetSolid(SOLID_VPHYSICS)

        local phys = ent:GetPhysicsObject()
        if IsValid(phys) and keepPhysicsTransform ~= true then
            phys:SetPos(ent:GetPos())
            phys:SetAngles(ent:GetAngles())
        end

        applyPhysicsState(ent, state)
        if isfunction(ent.Activate) then
            ent:Activate()
        end
    end

    local function scratchFor(ent)
        local scratch = PHYS_SCRATCH[ent]
        if not scratch then
            scratch = {}
            PHYS_SCRATCH[ent] = scratch
        end

        return scratch
    end

    local function primitiveConstruct(ent)
        if not IsValid(ent) or not isfunction(ent.PrimitiveGetConstruct) then return end

        local valid, result = ent:PrimitiveGetConstruct()
        if not valid or not istable(result) then return end
        if not istable(result.convexes) or not istable(result.convexes[1]) then return end

        return result
    end

    local function rebuildPrimitiveBase(ent, result, options)
        if not IsValid(ent) or not istable(result) then return false end

        local previousSuppress = ent._magicAlignEntityMirrorSuppressPrimitiveHook
        ent._magicAlignEntityMirrorSuppressPrimitiveHook = true

        if isfunction(ent.PrimitiveRebuildPhysics) then
            ent:PrimitiveRebuildPhysics(result)
        elseif isfunction(ent.PrimitiveReconstruct) then
            ent:PrimitiveReconstruct()
        else
            ent._magicAlignEntityMirrorSuppressPrimitiveHook = previousSuppress
            return false
        end

        ent._magicAlignEntityMirrorSuppressPrimitiveHook = previousSuppress
        if istable(ent.primitive) and type(ent.primitive.thread) == "thread" then
            return false
        end

        return true
    end

    local function initStockModelPhysics(ent)
        if not IsValid(ent) or not isfunction(ent.PhysicsInit) then return false end

        ent:EnableCustomCollisions(false)
        local ok = ent:PhysicsInit(SOLID_VPHYSICS)
        if ok == false then return false end

        local collisionMins, collisionMaxs = captureCollisionBounds(ent)
        local renderMins, renderMaxs = captureRenderBounds(ent)
        return ent:GetPhysicsObject(), collisionMins, collisionMaxs, renderMins, renderMaxs
    end

    local function rebuildModelPhysics(ent, axis, state, options)
        local currentAxis = actualPhysicsAxis(ent)
        local physicalScale, visualScale = captureResizeScales(ent, currentAxis, options)
        ensureStoredResizeScales(ent, physicalScale, visualScale)

        local phys, stockMins, stockMaxs, renderMins, renderMaxs = initStockModelPhysics(ent)
        if phys == false then return false end

        local scale = physicsScaleFor(ent, axis, ent._magicAlignEntityMirrorPhysicsScale, physicalScale, M.ENTITY_MIRROR_NONE)
        ent._magicAlignEntityMirrorPhysicsScale = scale
        local needsCustom = axis ~= M.ENTITY_MIRROR_NONE or not scaleIsIdentity(scale)
        if not needsCustom then
            setCollisionBounds(ent, stockMins, stockMaxs)
            setRenderBounds(ent, renderMins or stockMins, renderMaxs or stockMaxs)
            finishPhysics(ent, false, state)
            setActualPhysicsAxis(ent, axis)
            return true
        end

        local source = physicsConvexes(phys)
        if not istable(source) or not istable(source[1]) then
            finishPhysics(ent, false, state)
            setActualPhysicsAxis(ent, M.ENTITY_MIRROR_NONE)
            return false
        end

        local convexes = scaledConvexes(source, scratchFor(ent), scale)
        if not convexes or not ent:PhysicsInitMultiConvex(convexes) then
            initStockModelPhysics(ent)
            finishPhysics(ent, false, state)
            setActualPhysicsAxis(ent, M.ENTITY_MIRROR_NONE)
            return false
        end

        local mins, maxs = convexBounds(convexes)
        if not mins or not maxs then
            mins, maxs = scaledBounds(stockMins, stockMaxs, scale)
        end
        setPhysicsRenderBounds(ent, mins, maxs)
        finishPhysics(ent, true, state)
        setActualPhysicsAxis(ent, axis)
        return true
    end

    local function rebuildPrimitivePhysics(ent, axis, state, options)
        if not isfunction(ent.PrimitiveReconstruct) then return false end

        local currentAxis = actualPhysicsAxis(ent)
        local physicalScale, visualScale = captureResizeScales(ent, currentAxis, options)
        ensureStoredResizeScales(ent, physicalScale, visualScale)

        local result = primitiveConstruct(ent)
        if not result then return false end

        if options.baseAlreadyFresh ~= true and not rebuildPrimitiveBase(ent, result, options) then
            return false
        end

        local source = result.convexes
        if axis == M.ENTITY_MIRROR_NONE then
            local mins, maxs = convexBounds(source)
            setPhysicsRenderBounds(ent, mins, maxs)
            finishPhysics(ent, true, state)
            setActualPhysicsAxis(ent, M.ENTITY_MIRROR_NONE)
            return true
        end

        local scale = physicsScaleFor(ent, axis, nil, physicalScale, M.ENTITY_MIRROR_NONE)
        local convexes = scaledConvexes(source, scratchFor(ent), scale)
        EntityMirror.DebugConvexes("server-primitive-physics-build", ent, axis, scale, source, convexes)
        if not convexes or not ent:PhysicsInitMultiConvex(convexes) then
            rebuildPrimitiveBase(ent, result, options)
            finishPhysics(ent, true, state)
            setActualPhysicsAxis(ent, M.ENTITY_MIRROR_NONE)
            return false
        end

        local mins, maxs = convexBounds(convexes)
        setPhysicsRenderBounds(ent, mins, maxs)
        finishPhysics(ent, true, state)
        setActualPhysicsAxis(ent, axis)
        EntityMirror.DebugEntity("server-primitive-physics-final", ent, {
            requestedAxis = EntityMirror.AxisLabel(axis),
            scale = scale
        })
        return true
    end

    local function rebuildPhysics(ent, axis, options)
        if not IsValid(ent) then return false end

        axis = validAxis(axis)
        options = istable(options) and options or {}
        local state = physicsState(ent)

        if M.IsPrimitive(ent) then
            return rebuildPrimitivePhysics(ent, axis, state, options)
        end

        return rebuildModelPhysics(ent, axis, state, options)
    end

    function EntityMirror.ApplyPhysics(ent, axis, options)
        axis = validAxis(axis)
        if axis == M.ENTITY_MIRROR_NONE or not IsValid(ent) then return false end

        options = istable(options) and options or {}
        local actual = actualPhysicsAxis(ent)
        if actual == axis and options.force ~= true and options.baseAlreadyFresh ~= true then
            return true
        end

        return rebuildPhysics(ent, axis, options)
    end

    function EntityMirror.RestorePhysics(ent, options)
        if not IsValid(ent) then return end

        options = istable(options) and options or {}
        return rebuildPhysics(ent, M.ENTITY_MIRROR_NONE, options)
    end

    local function networkState(ent, axis, flags)
        if not IsValid(ent) then return end

        axis = validAxis(axis)
        flags = validFlags(flags)

        ent:SetNWInt(NW_AXIS, axis)
        ent:SetNWInt(NW_FLAGS, flags)
        ent:SetNWInt(NW_REVISION, (ent:GetNWInt(NW_REVISION, 0) + 1) % 65536)
        EntityMirror.DebugEntity("server-network-state", ent, {
            networkAxis = EntityMirror.AxisLabel(axis),
            networkFlags = flags,
            networkRevision = ent:GetNWInt(NW_REVISION, -1)
        })
    end

    local function storeState(ent, data)
        if not IsValid(ent) then return end

        ent.EntityMods = istable(ent.EntityMods) and ent.EntityMods or {}
        if data then
            duplicator.StoreEntityModifier(ent, M.ENTITY_MIRROR_MODIFIER_ID, data)
        else
            duplicator.ClearEntityModifier(ent, M.ENTITY_MIRROR_MODIFIER_ID)
        end
    end

    function EntityMirror.SetState(ent, axis, flags, options)
        if not IsValid(ent) then return false end

        axis = validAxis(axis)
        flags = validFlags(flags)
        options = istable(options) and options or {}

        local current = EntityMirror.GetAxis(ent)
        local currentFlags = EntityMirror.GetFlags(ent)
        local actual = actualPhysicsAxis(ent)
        local changed = current ~= axis or currentFlags ~= flags
        local forced = options.force == true
        local capturedPhysicalScale
        local capturedVisualScale

        local function physicsOptions(extra)
            local out = {}
            if istable(extra) then
                for key, value in pairs(extra) do
                    out[key] = value
                end
            end

            if not isvector(capturedPhysicalScale) or not isvector(capturedVisualScale) then
                capturedPhysicalScale, capturedVisualScale = captureResizeScales(ent, actual, options)
            end

            out.resizePhysicalScale = capturedPhysicalScale
            out.resizeVisualScale = capturedVisualScale
            return out
        end

        if axis == M.ENTITY_MIRROR_NONE then
            if offStateAlreadyApplied(ent, current, currentFlags, actual, flags) then
                return true
            end

            local restoreAfterNetwork = M.IsPrimitive(ent)
            if not restoreAfterNetwork
                and (forced or actual ~= M.ENTITY_MIRROR_NONE or current ~= M.ENTITY_MIRROR_NONE or changed) then
                EntityMirror.RestorePhysics(ent, physicsOptions())
            end

            storeState(ent)
            networkState(ent, M.ENTITY_MIRROR_NONE, flags)

            if restoreAfterNetwork
                and (forced or actual ~= M.ENTITY_MIRROR_NONE or current ~= M.ENTITY_MIRROR_NONE or changed) then
                EntityMirror.RestorePhysics(ent, physicsOptions())
            end
            return true
        end

        local data = {
            schema = 1,
            axis = axis,
            flags = flags,
            revision = (ent:GetNWInt(NW_REVISION, 0) + 1) % 65536
        }

        storeState(ent, data)
        networkState(ent, axis, flags)

        if changed or forced then
            local hadPhysics = bit.band(currentFlags, M.ENTITY_MIRROR_PHYSICS) ~= 0
            local wantsPhysics = bit.band(flags, M.ENTITY_MIRROR_PHYSICS) ~= 0
            local forcePhysicsRebuild = forced and actual ~= M.ENTITY_MIRROR_NONE and wantsPhysics
            local restored = true
            if actual ~= M.ENTITY_MIRROR_NONE
                and (actual ~= axis or (hadPhysics and not wantsPhysics) or forcePhysicsRebuild) then
                restored = EntityMirror.RestorePhysics(ent, physicsOptions({ suppressPrimitiveHook = true })) ~= false
            end
            if restored and wantsPhysics and (actual ~= axis or forced) then
                EntityMirror.ApplyPhysics(ent, axis, physicsOptions({ force = forced }))
            end
        end

        return true
    end

    function EntityMirror.ApplyDelta(ent, deltaAxis, flags)
        if not IsValid(ent) then return false end

        local axis = EntityMirror.ComposeAxis(EntityMirror.GetAxis(ent), deltaAxis)
        return EntityMirror.SetState(ent, axis, flags)
    end

    function EntityMirror.Capture(ent)
        if not IsValid(ent) then return end

        return {
            axis = EntityMirror.GetAxis(ent),
            flags = EntityMirror.GetFlags(ent)
        }
    end

    function EntityMirror.Restore(ent, state)
        if not IsValid(ent) then return end
        state = istable(state) and state or {}

        return EntityMirror.SetState(
            ent,
            validAxis(state.axis),
            validFlags(state.flags),
            { force = true }
        )
    end

    function EntityMirror.ApplyFromBaseState(ent, baseState, deltaAxis, flags, options)
        if not IsValid(ent) then return false end

        options = istable(options) and options or {}
        deltaAxis = validAxis(deltaAxis)
        local baseAxis = EntityMirror.StateAxis(baseState)
        if deltaAxis == M.ENTITY_MIRROR_NONE
            and options.includeBaseState ~= true
            and baseAxis == M.ENTITY_MIRROR_NONE then
            return false
        end

        local targetFlags = deltaAxis ~= M.ENTITY_MIRROR_NONE
            and validFlags(flags)
            or validFlags(istable(baseState) and baseState.flags or nil)
        local targetState = EntityMirror.ComposeState(baseState, deltaAxis, targetFlags)

        if options.normalizeInherited == true then
            -- Cloned entities may have already received mirrored EntityMods from
            -- the duplicator. Normalize through the same unmirrored base before
            -- applying the final state so copy and move use identical mirror physics.
            EntityMirror.SetState(ent, M.ENTITY_MIRROR_NONE, targetFlags, { force = true })
        end

        if targetState.axis == M.ENTITY_MIRROR_NONE then
            return EntityMirror.SetState(ent, M.ENTITY_MIRROR_NONE, targetState.flags, { force = true })
        end

        return EntityMirror.SetState(ent, targetState.axis, targetState.flags, { force = true })
    end

    local function scheduleModifierStateReapply(ent, state)
        state = EntityMirror.Sanitize(state)
        if not state then return end

        timer.Simple(0, function()
            if not IsValid(ent) then return end
            if EntityMirror.GetAxis(ent) ~= state.axis then return end

            EntityMirror.SetState(ent, state.axis, state.flags, { force = true })
        end)
    end

    duplicator.RegisterEntityModifier(M.ENTITY_MIRROR_MODIFIER_ID, function(_, ent, data)
        local stored = EntityMirror.Sanitize(data)
        if stored then
            EntityMirror.SetState(ent, stored.axis, stored.flags, { force = true })
            scheduleModifierStateReapply(ent, stored)
        else
            EntityMirror.SetState(ent, M.ENTITY_MIRROR_NONE, M.ENTITY_MIRROR_DEFAULT_FLAGS, { force = true })
        end
    end)

    hook.Add("Primitive_PostRebuildPhysics", "MagicAlignEntityMirrorPrimitivePhysics", function(ent)
        if not IsValid(ent) then return end
        if ent._magicAlignEntityMirrorSuppressPrimitiveHook then return end
        local axis = EntityMirror.GetAxis(ent)
        if axis == M.ENTITY_MIRROR_NONE then return end
        local flags = EntityMirror.GetFlags(ent)
        if bit.band(flags, M.ENTITY_MIRROR_PHYSICS) == 0 then return end
        if bit.band(flags, M.ENTITY_MIRROR_PRIMITIVE_AWARE) == 0 then return end

        EntityMirror.ApplyPhysics(ent, axis, { baseAlreadyFresh = true })
    end)
end

if CLIENT then
    local ACTIVE_VISUALS = setmetatable({}, { __mode = "k" })
    local CLIENT_ENTITY_STATE = setmetatable({}, { __mode = "k" })
    local ACTIVE_CLIENT_PHYSICS = setmetatable({}, { __mode = "k" })
    local CLIENT_PHYS_SCRATCH = setmetatable({}, { __mode = "k" })
    local VISUAL_PREDICTIONS = setmetatable({}, { __mode = "k" })
    local VISUAL_PREDICTIONS_BY_COMMIT = {}
    local VISUAL_PREDICTION_TIMEOUT = 8
    local VISUAL_PREDICTION_TOKEN = 0
    local INITIAL_RECONCILE_DELAYS = { 0, 0.05, 0.25, 1 }
    local INITIAL_RECONCILE_ATTEMPTS = setmetatable({}, { __mode = "k" })
    local SIZE_HANDLER_REFRESH_ATTEMPTS = setmetatable({}, { __mode = "k" })
    local reconcileEntity
    local scheduleVisualPredictionExpiry
    local releaseOwnedClientPhysics

    local function stateFor(ent)
        local state = CLIENT_ENTITY_STATE[ent]
        if not state then
            state = {
                desiredVisualAxis = M.ENTITY_MIRROR_NONE,
                desiredPhysicsAxis = M.ENTITY_MIRROR_NONE,
                ownsPhysics = false,
                ownedPhysicsKind = nil,
                ownedPhysicsAxis = M.ENTITY_MIRROR_NONE,
                ownedPhysicsScaleKey = nil,
                primitiveResult = nil,
                pendingPhysicsAxis = nil,
                lastRevision = nil
            }
            CLIENT_ENTITY_STATE[ent] = state
        end

        return state
    end

    local function desiredAxes(ent)
        local axis = EntityMirror.GetAxis(ent)
        local flags = EntityMirror.GetFlags(ent)
        local desiredVisualAxis = bit.band(flags, M.ENTITY_MIRROR_VISUAL) ~= 0
            and axis
            or M.ENTITY_MIRROR_NONE
        local desiredPhysicsAxis = M.ENTITY_MIRROR_NONE

        if bit.band(flags, M.ENTITY_MIRROR_PHYSICS) ~= 0 then
            if M.IsPrimitive(ent) then
                if bit.band(flags, M.ENTITY_MIRROR_PRIMITIVE_AWARE) ~= 0 then
                    desiredPhysicsAxis = axis
                end
            else
                desiredPhysicsAxis = axis
            end
        end

        return validAxis(desiredVisualAxis), validAxis(desiredPhysicsAxis), axis, flags
    end

    function EntityMirror.PhysicsAxisForEntity(ent)
        if not IsValid(ent) then return M.ENTITY_MIRROR_NONE end

        local state = CLIENT_ENTITY_STATE[ent]
        if state then
            if state.ownsPhysics == true then
                return validAxis(state.ownedPhysicsAxis)
            end

            return M.ENTITY_MIRROR_NONE
        end

        local _, desiredPhysicsAxis = desiredAxes(ent)
        return validAxis(desiredPhysicsAxis)
    end

    local function truthy(value)
        if value == true then return true end
        if value == false or value == nil then return false end

        local numeric = tonumber(value)
        if numeric ~= nil then return numeric ~= 0 end

        if isstring(value) then
            local text = string.lower(value)
            return text == "true" or text == "yes" or text == "on"
        end

        return false
    end

    local function advResizerClientPhysicsDisabled(ent)
        local entityMods = IsValid(ent) and ent.EntityMods or nil
        local modifierData = istable(entityMods) and entityMods.advr or nil
        if not istable(modifierData) then return false end

        return truthy(modifierData[7])
    end

    local function clientStateExtra(ent, state, extra)
        local data = {}
        if istable(extra) then
            for key, value in pairs(extra) do
                data[key] = value
            end
        end

        state = state or CLIENT_ENTITY_STATE[ent]
        if istable(state) then
            data.desiredVisualAxis = EntityMirror.AxisLabel(state.desiredVisualAxis)
            data.desiredPhysicsAxis = EntityMirror.AxisLabel(state.desiredPhysicsAxis)
            data.ownsPhysics = state.ownsPhysics == true
            data.ownedPhysicsKind = state.ownedPhysicsKind
            data.ownedPhysicsAxis = EntityMirror.AxisLabel(state.ownedPhysicsAxis)
            data.ownedPhysicsScaleKey = state.ownedPhysicsScaleKey
            data.pendingPhysicsAxis = state.pendingPhysicsAxis ~= nil
                and EntityMirror.AxisLabel(state.pendingPhysicsAxis)
                or "nil"
            data.lastRevision = state.lastRevision
        else
            data.clientState = "none"
        end

        local phys = IsValid(ent) and ent:GetPhysicsObject() or nil
        data.physValid = IsValid(phys)
        data.solid = IsValid(ent) and isfunction(ent.GetSolid) and ent:GetSolid() or nil
        data.moveType = IsValid(ent) and isfunction(ent.GetMoveType) and ent:GetMoveType() or nil
        data.collisionGroup = IsValid(ent) and isfunction(ent.GetCollisionGroup) and ent:GetCollisionGroup() or nil
        data.advrDcp = advResizerClientPhysicsDisabled(ent)

        local physical, visual = M.GetAdvResizerScales(ent)
        data.advrPhysical = physical
        data.advrVisual = visual

        local handler = M.FindSizeHandler(ent)
        data.sizeHandler = IsValid(handler)
        if IsValid(handler) then
            data.handlerActualPhysics = isfunction(handler.GetActualPhysicsScale)
                and tostring(handler:GetActualPhysicsScale())
                or "nil"
            data.handlerVisual = isfunction(handler.GetVisualScale)
                and tostring(handler:GetVisualScale())
                or "nil"
        end

        return data
    end

    local function debugClientEntity(label, ent, state, extra, force)
        if not force and not EntityMirror.DebugEnabled() then return end
        if not IsValid(ent) then return end

        EntityMirror.DebugEntity(label, ent, clientStateExtra(ent, state, extra), force)
    end

    local function hasBootstrapNetworkState(ent)
        if not IsValid(ent) or not ent.GetNWInt then return false end

        return ent:GetNWInt(NW_REVISION, -1) >= 0
            or ent:GetNWInt(NW_AXIS, M.ENTITY_MIRROR_NONE) ~= M.ENTITY_MIRROR_NONE
            or ent:GetNWInt(NW_FLAGS, M.ENTITY_MIRROR_DEFAULT_FLAGS) ~= M.ENTITY_MIRROR_DEFAULT_FLAGS
    end

    local function scheduleInitialReconcile(ent, reason, attempt)
        if not IsValid(ent) then return end

        attempt = math.floor(tonumber(attempt) or 1)
        if attempt < 1 or attempt > #INITIAL_RECONCILE_DELAYS then return end

        local queuedAttempt = INITIAL_RECONCILE_ATTEMPTS[ent]
        if queuedAttempt and queuedAttempt >= attempt then return end

        INITIAL_RECONCILE_ATTEMPTS[ent] = attempt
        timer.Simple(INITIAL_RECONCILE_DELAYS[attempt] or 0, function()
            if not IsValid(ent) then return end
            if INITIAL_RECONCILE_ATTEMPTS[ent] ~= attempt then return end

            debugClientEntity("client-init-reconcile", ent, CLIENT_ENTITY_STATE[ent], {
                reason = reason,
                attempt = attempt,
                bootstrapNetworkState = hasBootstrapNetworkState(ent)
            })
            reconcileEntity(ent, reason)
            if hasBootstrapNetworkState(ent)
                or CLIENT_ENTITY_STATE[ent] ~= nil
                or attempt >= #INITIAL_RECONCILE_DELAYS then
                INITIAL_RECONCILE_ATTEMPTS[ent] = nil
                return
            end

            INITIAL_RECONCILE_ATTEMPTS[ent] = nil
            scheduleInitialReconcile(ent, reason, attempt + 1)
        end)
    end

    local function clientPhysicsScratch(ent)
        local scratch = CLIENT_PHYS_SCRATCH[ent]
        if not scratch then
            scratch = {}
            CLIENT_PHYS_SCRATCH[ent] = scratch
        end

        return scratch
    end

    local function primitiveResult(ent)
        local primitive = IsValid(ent) and ent.primitive or nil
        return istable(primitive) and primitive.result or nil
    end

    local function primitiveConvexes(ent)
        local result = primitiveResult(ent)
        if istable(result) and istable(result.convexes) and istable(result.convexes[1]) then
            return result.convexes
        end

        return physicsConvexes(IsValid(ent) and ent:GetPhysicsObject() or nil)
    end

    local function mirroredClientConvexes(ent, axis, scale)
        local convexes = primitiveConvexes(ent)
        if not convexes then return end

        scale = isvector(scale) and scale or physicsScaleFor(ent, axis)
        return scaledConvexes(convexes, clientPhysicsScratch(ent), scale)
    end

    local function pinClientPhysicsTransform(ent, phys)
        if not IsValid(ent) then return false end

        phys = phys or ent:GetPhysicsObject()
        if IsValid(phys) then
            phys:SetPos(ent:GetPos())
            phys:SetAngles(ent:GetAngles())
            phys:EnableMotion(false)
            if phys.Sleep then
                phys:Sleep()
            end
            return true
        end

        return false
    end

    local function refreshActiveClientPhysics(ent, state)
        if state and (state.ownsPhysics == true or state.pendingPhysicsAxis ~= nil) then
            ACTIVE_CLIENT_PHYSICS[ent] = true
        else
            ACTIVE_CLIENT_PHYSICS[ent] = nil
        end
    end

    local function markPhysicsPending(ent, state, axis)
        state.pendingPhysicsAxis = validAxis(axis)
        refreshActiveClientPhysics(ent, state)
    end

    local function clearPhysicsPending(ent, state)
        state.pendingPhysicsAxis = nil
        refreshActiveClientPhysics(ent, state)
    end

    local function claimOwnedClientPhysics(ent, state, kind, axis, scaleKeyValue, primitiveResultValue)
        state.ownsPhysics = true
        state.ownedPhysicsKind = kind
        state.ownedPhysicsAxis = validAxis(axis)
        state.ownedPhysicsScaleKey = scaleKeyValue
        state.primitiveResult = primitiveResultValue
        refreshActiveClientPhysics(ent, state)
    end

    local function markOwnedClientPhysics(ent, state, kind, axis, scaleKeyValue, primitiveResultValue)
        claimOwnedClientPhysics(ent, state, kind, axis, scaleKeyValue, primitiveResultValue)
        clearPhysicsPending(ent, state)
    end

    local function clearOwnedClientPhysics(ent, state)
        state.ownsPhysics = false
        state.ownedPhysicsKind = nil
        state.ownedPhysicsAxis = M.ENTITY_MIRROR_NONE
        state.ownedPhysicsScaleKey = nil
        state.primitiveResult = primitiveResult(ent)
        refreshActiveClientPhysics(ent, state)
    end

    local function finishClientPhysics(ent, customCollisions, keepPhysicsTransform)
        ent:EnableCustomCollisions(customCollisions == true)
        ent:SetMoveType(MOVETYPE_VPHYSICS)
        ent:SetSolid(SOLID_VPHYSICS)

        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then
            if keepPhysicsTransform ~= true then
                pinClientPhysicsTransform(ent, phys)
            else
                phys:EnableMotion(false)
                if phys.Sleep then
                    phys:Sleep()
                end
            end
        end
    end

    local function initClientStockPhysics(ent)
        if not IsValid(ent) or not isfunction(ent.PhysicsInit) then return false end

        ent:EnableCustomCollisions(false)
        local ok = ent:PhysicsInit(SOLID_VPHYSICS)
        if ok == false then return false end

        local collisionMins, collisionMaxs = captureCollisionBounds(ent)
        local renderMins, renderMaxs = captureRenderBounds(ent)
        return ent:GetPhysicsObject(), collisionMins, collisionMaxs, renderMins, renderMaxs
    end

    local function buildClientModelPhysics(ent, axis, scale, state)
        scale = isvector(scale) and scale or physicsScaleFor(ent, axis)

        local phys, stockMins, stockMaxs, renderMins, renderMaxs = initClientStockPhysics(ent)
        if phys == false then
            debugClientEntity("client-model-physics-stock-init-failed", ent, state, {
                requestedAxis = EntityMirror.AxisLabel(axis),
                desiredScale = scale
            })
            return false
        end
        if state then
            claimOwnedClientPhysics(ent, state, "model_mirror", M.ENTITY_MIRROR_NONE, nil, nil)
        end
        debugClientEntity("client-model-physics-stock-owned", ent, state, {
            requestedAxis = EntityMirror.AxisLabel(axis),
            desiredScale = scale,
            desiredScaleKey = scaleKey(scale)
        })

        local source = physicsConvexes(phys)
        if not istable(source) or not istable(source[1]) then
            debugClientEntity("client-model-physics-source-missing", ent, state, {
                requestedAxis = EntityMirror.AxisLabel(axis),
                desiredScale = scale
            })
            return false
        end

        local convexes = scaledConvexes(source, clientPhysicsScratch(ent), scale)
        if not convexes or not ent:PhysicsInitMultiConvex(convexes) then
            debugClientEntity("client-model-physics-multiconvex-failed", ent, state, {
                requestedAxis = EntityMirror.AxisLabel(axis),
                desiredScale = scale
            })
            return false
        end

        local mins, maxs = convexBounds(convexes)
        if not mins or not maxs then
            mins, maxs = scaledBounds(stockMins, stockMaxs, scale)
        end
        setPhysicsRenderBounds(ent, mins, maxs)
        finishClientPhysics(ent, true)

        return true
    end

    local function rebuildClientModelBaselinePhysics(ent, scale)
        scale = isvector(scale) and scale or physicsScaleFor(ent, M.ENTITY_MIRROR_NONE)

        local phys, stockMins, stockMaxs, renderMins, renderMaxs = initClientStockPhysics(ent)
        if phys == false then return false end

        if scaleIsIdentity(scale) then
            if isvector(stockMins) and isvector(stockMaxs) then
                setCollisionBounds(ent, stockMins, stockMaxs)
            end
            if isvector(renderMins) and isvector(renderMaxs) then
                setRenderBounds(ent, renderMins, renderMaxs)
            end
            finishClientPhysics(ent, false)
            return true
        end

        local source = physicsConvexes(phys)
        if not istable(source) or not istable(source[1]) then return false end

        local convexes = scaledConvexes(source, clientPhysicsScratch(ent), scale)
        if not convexes or not ent:PhysicsInitMultiConvex(convexes) then
            return false
        end

        local mins, maxs = convexBounds(convexes)
        if not mins or not maxs then
            mins, maxs = scaledBounds(stockMins, stockMaxs, scale)
        end
        setPhysicsRenderBounds(ent, mins, maxs)
        finishClientPhysics(ent, true)
        return true
    end

    local function shouldEnsureClientBaselinePhysics(ent)
        if not IsValid(ent) then return false end
        if not M.IsProp(ent) then return false end
        if M.IsPrimitive(ent) then return false end
        if advResizerClientPhysicsDisabled(ent) then return false end
        if not isfunction(ent.PhysicsInit) then return false end
        if isfunction(ent.GetSolid) and ent:GetSolid() ~= SOLID_VPHYSICS then return false end

        return true
    end

    local function hasExplicitMirrorNetworkState(state)
        local revision = tonumber(state and state.currentRevision)
        if revision and revision >= 0 then return true end

        revision = tonumber(state and state.lastRevision)
        return revision ~= nil and revision >= 0
    end

    local function ensureClientBaselinePhysics(ent, state, reason)
        if not IsValid(ent) then return false end

        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then
            if state.ownsPhysics == true and state.ownedPhysicsKind == "model_baseline" then
                pinClientPhysicsTransform(ent, phys)
            end
            return true
        end

        if not shouldEnsureClientBaselinePhysics(ent) then
            debugClientEntity("client-baseline-skipped", ent, state, {
                baselineReason = reason
            })
            return true
        end

        markPhysicsPending(ent, state, M.ENTITY_MIRROR_NONE)

        local scale = physicsScaleFor(ent, M.ENTITY_MIRROR_NONE, state.desiredPhysicsScale)
        local rebuilt = rebuildClientModelBaselinePhysics(ent, scale)
        debugClientEntity(rebuilt and "client-baseline-restored" or "client-baseline-failed", ent, state, {
            baselineReason = reason,
            baselineScale = scale,
            baselineScaleKey = scaleKey(scale)
        })

        if rebuilt then
            markOwnedClientPhysics(ent, state, "model_baseline", M.ENTITY_MIRROR_NONE, scaleKey(scale), nil)
            return true
        end

        refreshActiveClientPhysics(ent, state)
        return false
    end

    local function restoreOwnedPrimitiveBaseline(ent)
        local result = primitiveResult(ent)
        if istable(result) and istable(result.convexes) and istable(result.convexes[1]) then
            if ent:PhysicsInitMultiConvex(result.convexes) then
                local mins, maxs = convexBounds(result.convexes)
                setPhysicsRenderBounds(ent, mins, maxs)
                finishClientPhysics(ent, true)
                return true
            end
        end

        if isfunction(ent.PrimitiveReconstruct) then
            ent:PrimitiveReconstruct()
            if istable(ent.primitive) and type(ent.primitive.thread) == "thread" then
                return false
            end

            local mins, maxs = convexBounds(primitiveConvexes(ent))
            setPhysicsRenderBounds(ent, mins, maxs)
            finishClientPhysics(ent, true)

            return true
        end

        return false
    end

    releaseOwnedClientPhysics = function(ent, state)
        if not IsValid(ent) then return false end

        if state.ownsPhysics ~= true then
            debugClientEntity("client-release-unowned", ent, state, {
                releaseAxis = EntityMirror.AxisLabel(M.ENTITY_MIRROR_NONE)
            })
            if hasExplicitMirrorNetworkState(state) then
                return ensureClientBaselinePhysics(ent, state, "unowned-off-networked")
            end

            clearOwnedClientPhysics(ent, state)
            clearPhysicsPending(ent, state)
            return true
        end

        if state.ownedPhysicsKind == "model_baseline" then
            return ensureClientBaselinePhysics(ent, state, "owned-baseline")
        end

        markPhysicsPending(ent, state, M.ENTITY_MIRROR_NONE)
        debugClientEntity("client-release-owned", ent, state, {
            releaseKind = state.ownedPhysicsKind,
            releaseAxis = EntityMirror.AxisLabel(state.ownedPhysicsAxis)
        })

        local restored = false
        if state.ownedPhysicsKind == "primitive_mirror" then
            restored = restoreOwnedPrimitiveBaseline(ent)
        else
            if isfunction(ent.PhysicsDestroy) then
                ent:EnableCustomCollisions(false)
                ent:PhysicsDestroy()
                restored = true
            end

            local scale = physicsScaleFor(ent, M.ENTITY_MIRROR_NONE, state.desiredPhysicsScale)
            if not advResizerClientPhysicsDisabled(ent) then
                restored = rebuildClientModelBaselinePhysics(ent, scale)
                if restored then
                    markOwnedClientPhysics(ent, state, "model_baseline", M.ENTITY_MIRROR_NONE, scaleKey(scale), nil)
                    return true
                else
                    debugClientEntity("client-release-baseline-failed", ent, state, {
                        baselineScale = scale,
                        baselineScaleKey = scaleKey(scale)
                    })
                end
            else
                debugClientEntity("client-release-baseline-skipped-dcp", ent, state, {
                    baselineScale = scale,
                    baselineScaleKey = scaleKey(scale)
                })
            end
        end

        if not restored then
            refreshActiveClientPhysics(ent, state)
            return false
        end

        clearOwnedClientPhysics(ent, state)
        clearPhysicsPending(ent, state)
        return true
    end

    local function applyOwnedModelPhysics(ent, axis, state)
        axis = validAxis(axis)
        if axis == M.ENTITY_MIRROR_NONE then return releaseOwnedClientPhysics(ent, state) end

        if state.ownsPhysics == true and state.ownedPhysicsKind ~= "model_mirror" then
            if not releaseOwnedClientPhysics(ent, state) then return false end
        end

        local scale = physicsScaleFor(ent, axis, state.desiredPhysicsScale)
        state.desiredPhysicsScale = scale
        local desiredScaleKey = scaleKey(scale)
        if state.ownsPhysics == true
            and state.ownedPhysicsKind == "model_mirror"
            and state.ownedPhysicsAxis == axis
            and state.ownedPhysicsScaleKey == desiredScaleKey then
            clearPhysicsPending(ent, state)
            return true
        end

        markPhysicsPending(ent, state, axis)
        if not buildClientModelPhysics(ent, axis, scale, state) then
            return false
        end

        markOwnedClientPhysics(ent, state, "model_mirror", axis, desiredScaleKey, nil)
        return true
    end

    local function applyOwnedPrimitivePhysics(ent, axis, state)
        axis = validAxis(axis)
        if axis == M.ENTITY_MIRROR_NONE then return releaseOwnedClientPhysics(ent, state) end

        if state.ownsPhysics == true and state.ownedPhysicsKind ~= "primitive_mirror" then
            if not releaseOwnedClientPhysics(ent, state) then return false end
        end

        local result = primitiveResult(ent)
        local resultChanged = state.primitiveResult ~= result
        local scale = physicsScaleFor(ent, axis, state.desiredPhysicsScale)
        state.desiredPhysicsScale = scale
        local desiredScaleKey = scaleKey(scale)

        if state.ownsPhysics == true
            and state.ownedPhysicsKind == "primitive_mirror"
            and state.ownedPhysicsAxis == axis
            and state.ownedPhysicsScaleKey == desiredScaleKey
            and not resultChanged then
            clearPhysicsPending(ent, state)
            return true
        end

        markPhysicsPending(ent, state, axis)
        if istable(ent.primitive) and type(ent.primitive.thread) == "thread" then
            return false
        end

        if state.ownsPhysics == true
            and state.ownedPhysicsKind == "primitive_mirror"
            and not restoreOwnedPrimitiveBaseline(ent) then
            return false
        end

        local convexes = mirroredClientConvexes(ent, axis, scale)
        EntityMirror.DebugConvexes("client-primitive-physics-build", ent, axis, scale, primitiveConvexes(ent), convexes)
        if not convexes or not ent:PhysicsInitMultiConvex(convexes) then
            return false
        end

        local mins, maxs = convexBounds(convexes)
        setPhysicsRenderBounds(ent, mins, maxs)
        finishClientPhysics(ent, true)
        markOwnedClientPhysics(ent, state, "primitive_mirror", axis, desiredScaleKey, primitiveResult(ent))
        EntityMirror.DebugEntity("client-primitive-physics-final", ent, {
            requestedAxis = EntityMirror.AxisLabel(axis),
            scale = scale
        })
        return true
    end

    local function applyOwnedClientPhysics(ent, desiredPhysicsAxis, state)
        desiredPhysicsAxis = validAxis(desiredPhysicsAxis)
        if desiredPhysicsAxis == M.ENTITY_MIRROR_NONE then
            return releaseOwnedClientPhysics(ent, state)
        end

        if M.IsPrimitive(ent) then
            return applyOwnedPrimitivePhysics(ent, desiredPhysicsAxis, state)
        end

        return applyOwnedModelPhysics(ent, desiredPhysicsAxis, state)
    end

    local function reconcileClientPhysics(ent, desiredPhysicsAxis, state)
        state.desiredPhysicsAxis = validAxis(desiredPhysicsAxis)

        if not IsValid(ent) then return false end
        if not M.IsProp(ent) then
            if state.desiredPhysicsAxis == M.ENTITY_MIRROR_NONE then
                return releaseOwnedClientPhysics(ent, state)
            end

            clearPhysicsPending(ent, state)
            return false
        end

        return applyOwnedClientPhysics(ent, state.desiredPhysicsAxis, state)
    end

    local function setRenderMatrix(ent, axis, currentAxis)
        axis = validAxis(axis)
        currentAxis = validAxis(currentAxis)

        if axis == M.ENTITY_MIRROR_NONE and not ent._magicAlignEntityMirrorMatrix then
            ent._magicAlignEntityMirrorScale = nil
            ent._magicAlignEntityMirrorExpectedScale = nil
            return
        end

        local scale = visualScaleFor(ent, axis, ent._magicAlignEntityMirrorScale, currentAxis)
        ent._magicAlignEntityMirrorScale = scale

        if axis == M.ENTITY_MIRROR_NONE and scaleIsIdentity(scale) then
            ent:DisableMatrix("RenderMultiply")
            ent._magicAlignEntityMirrorMatrix = nil
            ent._magicAlignEntityMirrorScale = nil
            ent._magicAlignEntityMirrorExpectedScale = nil
            return
        end

        local matrix = ent._magicAlignEntityMirrorMatrix or Matrix()
        matrix:Identity()
        matrix:Scale(scale)
        ent:EnableMatrix("RenderMultiply", matrix)

        if axis == M.ENTITY_MIRROR_NONE then
            ent._magicAlignEntityMirrorMatrix = nil
            ent._magicAlignEntityMirrorScale = nil
            ent._magicAlignEntityMirrorExpectedScale = nil
        else
            ent._magicAlignEntityMirrorMatrix = matrix
        end

        EntityMirror.DebugEntity("client-visual-matrix", ent, {
            requestedAxis = EntityMirror.AxisLabel(axis),
            visualScale = scale
        })
    end

    local function mirrorRenderOverride(ent, ...)
        render.CullMode(MATERIAL_CULLMODE_CW)

        local old = ent._magicAlignEntityMirrorOldRenderOverride
        if isfunction(old) then
            old(ent, ...)
        else
            ent:DrawModel(...)
        end

        render.CullMode(MATERIAL_CULLMODE_CCW)
    end

    local function enableRenderOverride(ent)
        if ent.RenderOverride == mirrorRenderOverride then
            ent._magicAlignEntityMirrorRenderOverride = mirrorRenderOverride
            return
        end

        ent._magicAlignEntityMirrorOldRenderOverride = ent.RenderOverride
        ent._magicAlignEntityMirrorRenderOverride = mirrorRenderOverride
        ent.RenderOverride = mirrorRenderOverride
    end

    local function disableRenderOverride(ent)
        if ent.RenderOverride ~= mirrorRenderOverride then return end

        ent.RenderOverride = ent._magicAlignEntityMirrorOldRenderOverride
        ent._magicAlignEntityMirrorOldRenderOverride = nil
        ent._magicAlignEntityMirrorRenderOverride = nil
    end

    local function renderMatrixNeedsSync(ent, axis, currentAxis)
        axis = validAxis(axis)
        currentAxis = validAxis(currentAxis)

        local scale = visualScaleFor(ent, axis, ent._magicAlignEntityMirrorExpectedScale, currentAxis)
        ent._magicAlignEntityMirrorExpectedScale = scale

        local needsMatrix = axis ~= M.ENTITY_MIRROR_NONE or not scaleIsIdentity(scale)
        if not needsMatrix then
            return ent._magicAlignEntityMirrorMatrix ~= nil
        end

        return ent._magicAlignEntityMirrorMatrix == nil
            or not scaleApprox(ent._magicAlignEntityMirrorScale, scale)
    end

    local function visualNeedsSync(ent, axis)
        axis = validAxis(axis)
        local currentAxis = validAxis(ent._magicAlignEntityMirrorAxis)
        if currentAxis ~= axis then return true end

        if axis == M.ENTITY_MIRROR_NONE then
            return ent.RenderOverride == mirrorRenderOverride
                or (ent._magicAlignEntityMirrorMatrix ~= nil and renderMatrixNeedsSync(ent, axis, currentAxis))
        end

        return ent.RenderOverride ~= mirrorRenderOverride
            or renderMatrixNeedsSync(ent, axis, currentAxis)
    end

    local function restoreVisualRenderBounds(ent)
        local mins = ent._magicAlignEntityMirrorBaseRenderMins
        local maxs = ent._magicAlignEntityMirrorBaseRenderMaxs
        if isvector(mins) and isvector(maxs) then
            setRenderBounds(ent, mins, maxs)
        end

        ent._magicAlignEntityMirrorBaseRenderMins = nil
        ent._magicAlignEntityMirrorBaseRenderMaxs = nil
    end

    local function applyVisualRenderBounds(ent, axis)
        if not IsValid(ent) then return end

        local baseMins = ent._magicAlignEntityMirrorBaseRenderMins
        local baseMaxs = ent._magicAlignEntityMirrorBaseRenderMaxs
        if not isvector(baseMins) or not isvector(baseMaxs) then
            baseMins, baseMaxs = captureRenderBounds(ent)
            if not isvector(baseMins) or not isvector(baseMaxs) then return end

            ent._magicAlignEntityMirrorBaseRenderMins = Vector(baseMins.x, baseMins.y, baseMins.z)
            ent._magicAlignEntityMirrorBaseRenderMaxs = Vector(baseMaxs.x, baseMaxs.y, baseMaxs.z)
        end

        local scale = EntityMirror.ScaleForAxis(axis, ent._magicAlignEntityMirrorRenderBoundsScale)
        ent._magicAlignEntityMirrorRenderBoundsScale = scale
        local mins, maxs = scaledBounds(baseMins, baseMaxs, scale)
        setRenderBounds(ent, mins, maxs)
    end

    function EntityMirror.ApplyVisual(ent, axis)
        if not IsValid(ent) then return end

        axis = validAxis(axis)
        local currentAxis = validAxis(ent._magicAlignEntityMirrorAxis)
        if axis == M.ENTITY_MIRROR_NONE then
            setRenderMatrix(ent, M.ENTITY_MIRROR_NONE, currentAxis)
            disableRenderOverride(ent)
            restoreVisualRenderBounds(ent)
            ACTIVE_VISUALS[ent] = nil
            ent._magicAlignEntityMirrorAxis = M.ENTITY_MIRROR_NONE
            ent._magicAlignEntityMirrorCullPreviewAxis = M.ENTITY_MIRROR_NONE
            return
        end

        setRenderMatrix(ent, axis, currentAxis)
        enableRenderOverride(ent)
        applyVisualRenderBounds(ent, axis)
        ACTIVE_VISUALS[ent] = true
        ent._magicAlignEntityMirrorAxis = axis
    end

    local function applyVisualState(ent, desiredVisualAxis, state)
        state.desiredVisualAxis = validAxis(desiredVisualAxis)
        local needsSync = visualNeedsSync(ent, state.desiredVisualAxis)
        debugClientEntity(needsSync and "client-visual-sync" or "client-visual-stable", ent, state, {
            desiredVisualAxisNow = EntityMirror.AxisLabel(state.desiredVisualAxis),
            currentClientAxis = EntityMirror.AxisLabel(ent._magicAlignEntityMirrorAxis),
            hasRenderMatrix = ent._magicAlignEntityMirrorMatrix ~= nil,
            renderOverrideActive = ent.RenderOverride == mirrorRenderOverride
        })
        if needsSync then
            EntityMirror.ApplyVisual(ent, state.desiredVisualAxis)
        end
    end

    local function predictionVisualAxis(ent)
        local prediction = VISUAL_PREDICTIONS[ent]
        if not istable(prediction) then return end
        if RealTime() > (tonumber(prediction.expiresAt) or 0) then return end

        return validAxis(prediction.axis)
    end

    local function sizeHandlerParent(handler)
        if not IsValid(handler) or handler:GetClass() ~= "sizehandler" then return end
        if not isfunction(handler.GetParent) then return end

        local parent = handler:GetParent()
        if IsValid(parent) then return parent end
    end

    local function scheduleSizeHandlerVisualRefresh(handler, reason, attempt)
        attempt = math.floor(tonumber(attempt) or 1)
        if attempt < 1 then attempt = 1 end

        local parent = sizeHandlerParent(handler)
        if not IsValid(parent) then
            local nextAttempt = attempt + 1
            if nextAttempt > #INITIAL_RECONCILE_DELAYS then return end

            local queuedAttempt = SIZE_HANDLER_REFRESH_ATTEMPTS[handler]
            if queuedAttempt and queuedAttempt >= nextAttempt then return end

            SIZE_HANDLER_REFRESH_ATTEMPTS[handler] = nextAttempt
            timer.Simple(INITIAL_RECONCILE_DELAYS[nextAttempt] or 0, function()
                if not IsValid(handler) then return end
                if SIZE_HANDLER_REFRESH_ATTEMPTS[handler] ~= nextAttempt then return end

                SIZE_HANDLER_REFRESH_ATTEMPTS[handler] = nil
                scheduleSizeHandlerVisualRefresh(handler, reason, nextAttempt)
            end)
            return
        end

        SIZE_HANDLER_REFRESH_ATTEMPTS[handler] = nil
        if parent._magicAlignEntityMirrorVisualRefreshQueued then return end

        local desiredVisualAxis, desiredPhysicsAxis = desiredAxes(parent)
        local predictedAxis = predictionVisualAxis(parent)
        local state = CLIENT_ENTITY_STATE[parent]
        if validAxis(desiredVisualAxis) == M.ENTITY_MIRROR_NONE
            and validAxis(desiredPhysicsAxis) == M.ENTITY_MIRROR_NONE
            and validAxis(predictedAxis) == M.ENTITY_MIRROR_NONE
            and validAxis(parent._magicAlignEntityMirrorAxis) == M.ENTITY_MIRROR_NONE
            and not (state and (
                state.ownsPhysics == true
                or state.pendingPhysicsAxis ~= nil
                or validAxis(state.desiredPhysicsAxis) ~= M.ENTITY_MIRROR_NONE
            )) then
            return
        end

        parent._magicAlignEntityMirrorVisualRefreshQueued = true
        timer.Simple(0, function()
            if not IsValid(parent) then return end

            parent._magicAlignEntityMirrorVisualRefreshQueued = nil
            reconcileEntity(parent, reason)
        end)
    end

    local function normalizedCommitId(commitId)
        commitId = tonumber(commitId)
        if not commitId then return end

        commitId = math.floor(commitId)
        if commitId < 0 then return end

        return commitId
    end

    local function unlinkVisualPrediction(ent, prediction)
        prediction = prediction or VISUAL_PREDICTIONS[ent]
        local commitId = prediction and normalizedCommitId(prediction.commitId) or nil
        if not commitId then return end

        local byCommit = VISUAL_PREDICTIONS_BY_COMMIT[commitId]
        if not byCommit then return end

        byCommit[ent] = nil
        if next(byCommit) == nil then
            VISUAL_PREDICTIONS_BY_COMMIT[commitId] = nil
        end
    end

    local function clearVisualPrediction(ent)
        if not VISUAL_PREDICTIONS[ent] then return end

        unlinkVisualPrediction(ent)
        VISUAL_PREDICTIONS[ent] = nil
    end

    scheduleVisualPredictionExpiry = function(ent, prediction)
        if not IsValid(ent) or not istable(prediction) then return end

        VISUAL_PREDICTION_TOKEN = VISUAL_PREDICTION_TOKEN + 1
        local token = VISUAL_PREDICTION_TOKEN
        prediction.expiryToken = token

        local delay = math.max((tonumber(prediction.expiresAt) or RealTime()) - RealTime(), 0)
        timer.Simple(delay, function()
            if VISUAL_PREDICTIONS[ent] ~= prediction or prediction.expiryToken ~= token then return end
            if not IsValid(ent) then
                clearVisualPrediction(ent)
                return
            end

            reconcileEntity(ent, "prediction_expired")
        end)
    end

    function EntityMirror.PredictVisual(ent, axis, timeout, commitId)
        if not IsValid(ent) then return false end

        axis = validAxis(axis)
        commitId = normalizedCommitId(commitId)
        clearVisualPrediction(ent)

        local prediction = {
            axis = axis,
            commitId = commitId,
            revision = ent.GetNWInt and ent:GetNWInt(NW_REVISION, -1) or -1,
            expiresAt = RealTime() + math.max(tonumber(timeout) or VISUAL_PREDICTION_TIMEOUT, 0.1)
        }
        VISUAL_PREDICTIONS[ent] = prediction

        if commitId then
            local byCommit = VISUAL_PREDICTIONS_BY_COMMIT[commitId]
            if not byCommit then
                byCommit = setmetatable({}, { __mode = "k" })
                VISUAL_PREDICTIONS_BY_COMMIT[commitId] = byCommit
            end
            byCommit[ent] = true
        end

        scheduleVisualPredictionExpiry(ent, prediction)
        EntityMirror.ApplyVisual(ent, axis)

        return true
    end

    function EntityMirror.ResolveVisualPrediction(commitId, accepted)
        commitId = normalizedCommitId(commitId)
        if not commitId then return false end

        local byCommit = VISUAL_PREDICTIONS_BY_COMMIT[commitId]
        if not byCommit then return false end

        local touched = false
        local now = RealTime()
        for ent in pairs(byCommit) do
            local prediction = VISUAL_PREDICTIONS[ent]
            if istable(prediction) and normalizedCommitId(prediction.commitId) == commitId then
                touched = true
                if accepted then
                    prediction.acknowledged = true
                    prediction.expiresAt = math.max(tonumber(prediction.expiresAt) or 0, now + 1)
                    scheduleVisualPredictionExpiry(ent, prediction)
                else
                    clearVisualPrediction(ent)
                    if reconcileEntity then
                        reconcileEntity(ent, "prediction")
                    end
                end
            end
        end

        if not accepted then
            VISUAL_PREDICTIONS_BY_COMMIT[commitId] = nil
        end

        return touched
    end

    function EntityMirror.ApplyVisualPreview(ent, axis)
        if not IsValid(ent) then return end

        axis = validAxis(axis)
        local currentAxis = validAxis(ent._magicAlignEntityMirrorPreviewAxis)
        if axis == M.ENTITY_MIRROR_NONE then
            if validAxis(ent._magicAlignEntityMirrorPreviewAxis) == M.ENTITY_MIRROR_NONE
                and ent.RenderOverride ~= mirrorRenderOverride
                and ent._magicAlignEntityMirrorMatrix == nil then
                return
            end

            setRenderMatrix(ent, M.ENTITY_MIRROR_NONE, currentAxis)
            disableRenderOverride(ent)
            restoreVisualRenderBounds(ent)
            ACTIVE_VISUALS[ent] = nil
            ent._magicAlignEntityMirrorPreviewAxis = M.ENTITY_MIRROR_NONE
            return
        end

        if validAxis(ent._magicAlignEntityMirrorPreviewAxis) == axis
            and ent.RenderOverride == mirrorRenderOverride
            and not renderMatrixNeedsSync(ent, axis, currentAxis) then
            return
        end

        setRenderMatrix(ent, axis, currentAxis)
        enableRenderOverride(ent)
        applyVisualRenderBounds(ent, axis)
        ACTIVE_VISUALS[ent] = nil
        ent._magicAlignEntityMirrorPreviewAxis = axis
    end

    function EntityMirror.ApplyVisualCullPreview(ent, axis)
        if not IsValid(ent) then return end

        axis = validAxis(axis)
        if axis == M.ENTITY_MIRROR_NONE then
            if validAxis(ent._magicAlignEntityMirrorCullPreviewAxis) == M.ENTITY_MIRROR_NONE
                and ent.RenderOverride ~= mirrorRenderOverride then
                return
            end

            disableRenderOverride(ent)
            ent._magicAlignEntityMirrorCullPreviewAxis = M.ENTITY_MIRROR_NONE
            return
        end

        if validAxis(ent._magicAlignEntityMirrorCullPreviewAxis) == axis
            and ent.RenderOverride == mirrorRenderOverride then
            return
        end

        enableRenderOverride(ent)
        ent._magicAlignEntityMirrorCullPreviewAxis = axis
    end

    reconcileEntity = function(ent, reason)
        if not IsValid(ent) then return end

        local desiredVisualAxis, desiredPhysicsAxis = desiredAxes(ent)
        local revision = ent.GetNWInt and ent:GetNWInt(NW_REVISION, -1) or -1
        local state = CLIENT_ENTITY_STATE[ent]
        if not state
            and revision < 0
            and desiredVisualAxis == M.ENTITY_MIRROR_NONE
            and desiredPhysicsAxis == M.ENTITY_MIRROR_NONE
            and not VISUAL_PREDICTIONS[ent] then
            return
        end

        state = state or stateFor(ent)
        state.currentRevision = revision
        local visualAxis = desiredVisualAxis
        local prediction = VISUAL_PREDICTIONS[ent]

        if istable(prediction) then
            local expired = RealTime() > (tonumber(prediction.expiresAt) or 0)
            local predictionRevision = tonumber(prediction.revision) or -1
            local serverAdvanced = revision >= 0
                and predictionRevision >= 0
                and revision ~= predictionRevision
            local predictedAxis = validAxis(prediction.axis)

            if expired then
                clearVisualPrediction(ent)
            elseif serverAdvanced and visualAxis == predictedAxis then
                clearVisualPrediction(ent)
            elseif serverAdvanced then
                prediction.expiresAt = math.min(tonumber(prediction.expiresAt) or 0, RealTime() + 0.25)
                scheduleVisualPredictionExpiry(ent, prediction)
                visualAxis = predictedAxis
            else
                visualAxis = predictedAxis
            end
        end

        applyVisualState(ent, visualAxis, state)
        reconcileClientPhysics(ent, desiredPhysicsAxis, state)
        if revision >= 0 then
            state.lastRevision = revision
        end
        debugClientEntity("client-reconcile", ent, state, {
            reason = reason,
            visualAxis = EntityMirror.AxisLabel(visualAxis),
            desiredVisualAxisNow = EntityMirror.AxisLabel(desiredVisualAxis),
            desiredPhysicsAxisNow = EntityMirror.AxisLabel(desiredPhysicsAxis),
            revision = revision
        })
    end

    local function maintainActiveVisual(ent)
        if not IsValid(ent) then
            ACTIVE_VISUALS[ent] = nil
            return
        end

        local desiredVisualAxis = predictionVisualAxis(ent) or desiredAxes(ent)
        local currentClientAxis = validAxis(ent._magicAlignEntityMirrorAxis)
        if desiredVisualAxis == M.ENTITY_MIRROR_NONE
            and currentClientAxis == M.ENTITY_MIRROR_NONE
            and not VISUAL_PREDICTIONS[ent] then
            ACTIVE_VISUALS[ent] = nil
            return
        end

        if not visualNeedsSync(ent, desiredVisualAxis) then return end

        debugClientEntity("client-active-visual-resync", ent, CLIENT_ENTITY_STATE[ent], {
            desiredVisualAxisNow = EntityMirror.AxisLabel(desiredVisualAxis),
            currentClientAxis = EntityMirror.AxisLabel(currentClientAxis),
            hasRenderMatrix = ent._magicAlignEntityMirrorMatrix ~= nil,
            renderOverrideActive = ent.RenderOverride == mirrorRenderOverride
        })
        EntityMirror.ApplyVisual(ent, desiredVisualAxis)
    end

    local function queueEntityNetworkInit(ent, reason)
        if not IsValid(ent) then return end

        if ent:GetClass() == "sizehandler" then
            scheduleSizeHandlerVisualRefresh(ent, reason)
            return
        end

        debugClientEntity("client-init-queued", ent, CLIENT_ENTITY_STATE[ent], {
            reason = reason,
            bootstrapNetworkState = hasBootstrapNetworkState(ent)
        })
        scheduleInitialReconcile(ent, reason, 1)
    end

    local function bootstrapKnownEntities(reason)
        for _, ent in ipairs(ents.GetAll()) do
            queueEntityNetworkInit(ent, reason)
        end
    end

    hook.Add("EntityNetworkedVarChanged", "MagicAlignEntityMirrorNetworked", function(ent, name)
        if IsValid(ent) and ent:GetClass() == "sizehandler" then
            scheduleSizeHandlerVisualRefresh(ent, "sizehandler_var")
            return
        end

        if name ~= NW_AXIS and name ~= NW_FLAGS and name ~= NW_REVISION then return end
        debugClientEntity("client-network-var", ent, CLIENT_ENTITY_STATE[ent], {
            networkVar = name,
            bootstrapNetworkState = hasBootstrapNetworkState(ent)
        })
        reconcileEntity(ent, "network_var")
        if hasBootstrapNetworkState(ent) or CLIENT_ENTITY_STATE[ent] ~= nil then
            INITIAL_RECONCILE_ATTEMPTS[ent] = nil
        end
    end)

    hook.Add("NetworkEntityCreated", "MagicAlignEntityMirrorCreated", function(ent)
        queueEntityNetworkInit(ent, "created")
    end)

    hook.Add("NotifyShouldTransmit", "MagicAlignEntityMirrorTransmit", function(ent, shouldTransmit)
        if shouldTransmit then
            queueEntityNetworkInit(ent, "transmit")
        end
    end)

    hook.Add("InitPostEntity", "MagicAlignEntityMirrorInitialState", function()
        bootstrapKnownEntities("init_post_entity")
    end)

    timer.Simple(0, function()
        bootstrapKnownEntities("load")
    end)

    hook.Add("EntityRemoved", "MagicAlignEntityMirrorRemoved", function(ent)
        INITIAL_RECONCILE_ATTEMPTS[ent] = nil
        SIZE_HANDLER_REFRESH_ATTEMPTS[ent] = nil
        ACTIVE_VISUALS[ent] = nil
        ACTIVE_CLIENT_PHYSICS[ent] = nil
        CLIENT_ENTITY_STATE[ent] = nil
        CLIENT_PHYS_SCRATCH[ent] = nil
        clearVisualPrediction(ent)
    end)

    hook.Add("Primitive_PostRebuildPhysics", "MagicAlignEntityMirrorClientPrimitivePhysics", function(ent)
        timer.Simple(0, function()
            if not IsValid(ent) then return end

            local state = CLIENT_ENTITY_STATE[ent]
            if not state then return end
            if state.ownsPhysics ~= true and state.pendingPhysicsAxis == nil then return end

            markPhysicsPending(ent, state, state.desiredPhysicsAxis)
            reconcileEntity(ent, "primitive_rebuild")
        end)
    end)

    hook.Remove("Think", "MagicAlignEntityMirrorVisuals")
    hook.Remove("Think", "MagicAlignEntityMirrorActivePhysics")
    hook.Add("Think", "MagicAlignEntityMirrorActiveState", function()
        for ent in pairs(ACTIVE_VISUALS) do
            maintainActiveVisual(ent)
        end

        for ent in pairs(ACTIVE_CLIENT_PHYSICS) do
            local state = CLIENT_ENTITY_STATE[ent]
            if not IsValid(ent) or not state then
                ACTIVE_CLIENT_PHYSICS[ent] = nil
            else
                if state.ownsPhysics == true and not pinClientPhysicsTransform(ent) then
                    markPhysicsPending(ent, state, state.desiredPhysicsAxis)
                end

                if state.ownsPhysics == true
                    and M.IsPrimitive(ent)
                    and state.primitiveResult ~= primitiveResult(ent) then
                    markPhysicsPending(ent, state, state.desiredPhysicsAxis)
                end

                if state.pendingPhysicsAxis ~= nil then
                    reconcileEntity(ent, "active_physics")
                end
            end
        end
    end)

    local function rayMetrics(startPos, direction, ent)
        if not IsValid(ent) then return end

        local center = isfunction(ent.WorldSpaceCenter) and ent:WorldSpaceCenter() or ent:GetPos()
        if not isvector(center) then return end

        local offset = center - startPos
        local along = offset:Dot(direction)
        local closest = startPos + direction * along
        return along, center:Distance(closest), center
    end

    local function traceCandidateRadius(ent, fallback)
        local mins, maxs = captureCollisionBounds(ent)
        if isvector(mins) and isvector(maxs) then
            return math.max((maxs - mins):Length() * 0.5, tonumber(fallback) or 0)
        end

        return tonumber(fallback) or 96
    end

    local function addTraceCandidate(list, seen, ent, startPos, direction, maxDistance, radius)
        if not IsValid(ent) or seen[ent] or not M.IsProp(ent) then return end

        local along, perpendicular, center = rayMetrics(startPos, direction, ent)
        if not along or along < 0 or along > maxDistance then return end

        local acceptedRadius = traceCandidateRadius(ent, radius)
        if perpendicular > acceptedRadius then return end

        seen[ent] = true
        list[#list + 1] = {
            ent = ent,
            along = along,
            perpendicular = perpendicular,
            center = center,
            acceptedRadius = acceptedRadius
        }
    end

    local function collectTraceCandidates(startPos, endPos, direction, maxDistance, radius)
        local list = {}
        local seen = {}
        local mins = Vector(-radius, -radius, -radius)
        local maxs = Vector(radius, radius, radius)

        for _, ent in ipairs(ents.FindAlongRay(startPos, endPos, mins, maxs)) do
            addTraceCandidate(list, seen, ent, startPos, direction, maxDistance, radius)
        end

        for _, ent in ipairs(ents.GetAll()) do
            addTraceCandidate(list, seen, ent, startPos, direction, maxDistance, radius)
        end

        table.sort(list, function(a, b)
            return a.along < b.along
        end)

        return list
    end

    local function debugTrace(args)
        local ply = LocalPlayer()
        if not IsValid(ply) then return end

        local startPos = ply:EyePos()
        local direction = ply:EyeAngles():Forward()
        local maxDistance = math.Clamp(tonumber(args and args[1]) or 32768, 256, 65536)
        local radius = math.Clamp(tonumber(args and args[2]) or 96, 1, 1024)
        local endPos = startPos + direction * maxDistance
        local trace = util.TraceLine({
            start = startPos,
            endpos = endPos,
            filter = ply
        })
        local traceEnt = trace and trace.Entity or nil

        print(("[Magic Align mirror debug] trace start=%s end=%s hit=%s hitWorld=%s hitPos=%s fraction=%s"):format(
            debugVector(startPos),
            debugVector(endPos),
            IsValid(traceEnt) and ("%s#%s"):format(traceEnt:GetClass(), traceEnt:EntIndex()) or tostring(traceEnt),
            tostring(trace and trace.HitWorld or false),
            debugVector(trace and trace.HitPos or nil),
            tostring(trace and trace.Fraction or nil)
        ))

        if IsValid(traceEnt) then
            debugClientEntity("client-trace-hit", traceEnt, CLIENT_ENTITY_STATE[traceEnt], nil, true)
        end

        local candidates = collectTraceCandidates(startPos, endPos, direction, maxDistance, radius)
        if #candidates < 1 then
            print("[Magic Align mirror debug] no prop bounds candidates along eye ray")
            return
        end

        local limit = math.min(#candidates, 16)
        print(("[Magic Align mirror debug] prop bounds candidates=%d showing=%d radius=%.1f"):format(#candidates, limit, radius))
        for i = 1, limit do
            local item = candidates[i]
            local ent = item.ent
            debugClientEntity("client-trace-candidate-" .. i, ent, CLIENT_ENTITY_STATE[ent], {
                traceHit = ent == traceEnt,
                rayAlong = item.along,
                rayPerpendicular = item.perpendicular,
                rayAcceptedRadius = item.acceptedRadius,
                rayCenter = item.center
            }, true)
        end
    end

    concommand.Remove("magic_align_mirror_debug_trace")
    concommand.Add("magic_align_mirror_debug_trace", function(_, _, args)
        debugTrace(args)
    end)

    local function debugCommandEntity(args)
        local entIndex = math.floor(tonumber(args and args[1]) or -1)
        if entIndex >= 0 then
            local ent = Entity(entIndex)
            if IsValid(ent) then return ent end
        end

        local ply = LocalPlayer()
        local trace = IsValid(ply) and ply:GetEyeTrace() or nil
        local ent = trace and trace.Entity or nil
        if IsValid(ent) then return ent end
    end

    concommand.Remove("magic_align_mirror_debug_ent")
    concommand.Add("magic_align_mirror_debug_ent", function(_, _, args)
        local ent = debugCommandEntity(args)
        if not IsValid(ent) then
            print("[Magic Align mirror debug] look at an entity or use: magic_align_mirror_debug_ent <entindex>")
            return
        end

        debugClientEntity("client-ent-dump", ent, CLIENT_ENTITY_STATE[ent], nil, true)
    end)

    concommand.Remove("magic_align_mirror_debug_refresh_ent")
    concommand.Add("magic_align_mirror_debug_refresh_ent", function(_, _, args)
        local ent = debugCommandEntity(args)
        if not IsValid(ent) then
            print("[Magic Align mirror debug] look at an entity or use: magic_align_mirror_debug_refresh_ent <entindex>")
            return
        end

        reconcileEntity(ent, "debug_refresh")
        debugClientEntity("client-debug-refresh", ent, CLIENT_ENTITY_STATE[ent], nil, true)
    end)

    local function mirroredEditor(panel)
        return IsValid(panel)
            and IsValid(panel.m_Entity)
            and EntityMirror.GetAxis(panel.m_Entity) ~= M.ENTITY_MIRROR_NONE
    end

    local function updatePrimitiveEditorWindow(panel)
        if not IsValid(panel) then return end

        local window = panel:GetParent()
        if not IsValid(window) then return end

        local mirrored = mirroredEditor(panel)
        local ent = panel.m_Entity
        local title = IsValid(ent) and tostring(ent) or ""
        if mirrored then
            title = title .. " [mirrored]"
        end

        local currentTitle = isfunction(window.GetTitle) and window:GetTitle() or nil
        if currentTitle ~= title then
            window:SetTitle(title)
        end

        local footer = mirrored and 24 or 12
        if window._magicAlignMirrorFooter ~= footer then
            window:DockPadding(4, 24, 4, footer)
            window._magicAlignMirrorFooter = footer
        end
    end

    local function drawEditorBox(bevel, x, y, w, h, color, tl, tr, bl, br)
        draw.RoundedBoxEx(bevel, x, y, w, h, EDITOR_FADED_COLOR, tl, tr, bl, br)
        draw.RoundedBoxEx(bevel, x + 1, y + 1, w - 2, h - 2, color, tl, tr, bl, br)
    end

    local function patchPrimitiveEditor()
        local panel = vgui.GetControlTable("DTreeEditorBase")
        if not istable(panel) or panel._magicAlignMirrorPatched then return false end

        panel._magicAlignMirrorPatched = true
        local oldSetupWindow = panel.SetupWindow
        local oldSetEntity = panel.SetEntity

        panel.SetupWindow = function(self, ...)
            if isfunction(oldSetupWindow) then
                oldSetupWindow(self, ...)
            end

            local window = self:GetParent()
            if not IsValid(window) then return end

            window.Paint = function(pnl, w, h)
                local sk = pnl.GetEditorSkin and pnl:GetEditorSkin() or {}
                local mirrored = mirroredEditor(self)
                local header = 24
                local footer = mirrored and 24 or 12
                local headerColor = mirrored and MIRROR_COLOR or (sk.colorHeader or EDITOR_HEADER_FALLBACK)
                local background = sk.colorBackground or EDITOR_BACKGROUND_FALLBACK

                drawEditorBox(4, 0, 0, w, header, headerColor, true, true, false, false)
                drawEditorBox(4, 0, h - footer, w, footer, headerColor, false, false, true, true)
                surface.SetDrawColor(background)
                surface.DrawRect(0, header - 1, w, h - footer - header + 2)

                if mirrored then
                    draw.SimpleText(
                        "Mirrored primitive: some shape controls may act reversed.",
                        "DTreeEditorBaseSmall",
                        8,
                        h - footer + 5,
                        color_white,
                        TEXT_ALIGN_LEFT,
                        TEXT_ALIGN_TOP
                    )
                end
            end

            local oldThink = window.Think
            window.Think = function(pnl, ...)
                if isfunction(oldThink) then oldThink(pnl, ...) end
                updatePrimitiveEditorWindow(self)
            end

            updatePrimitiveEditorWindow(self)
        end

        panel.SetEntity = function(self, ent, ...)
            if isfunction(oldSetEntity) then
                oldSetEntity(self, ent, ...)
            end
            updatePrimitiveEditorWindow(self)
        end

        return true
    end

    hook.Add("Think", "MagicAlignEntityMirrorPrimitiveEditorPatch", function()
        if patchPrimitiveEditor() then
            hook.Remove("Think", "MagicAlignEntityMirrorPrimitiveEditorPatch")
        end
    end)
end

return M
