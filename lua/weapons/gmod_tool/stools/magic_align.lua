TOOL.Category = "Construction"
TOOL.Name = "#tool.magic_align.name"
TOOL.Command = nil
TOOL.ConfigName = ""

MAGIC_ALIGN = MAGIC_ALIGN or include("autorun/magic_align.lua")

local M = MAGIC_ALIGN
local VectorP = M.VectorP
local AngleP = M.AngleP
local isvector = M.IsVectorLike
local isangle = M.IsAngleLike
local toVector = M.ToVector
local toAngle = M.ToAngle
local isWorldTarget
local hasTargetEntity
local traceHitsWorld
local traceMatchesEntity
local worldPosFromLocalPoint
local localPointFromWorldPos
local localNormalFromWorld
local worldNormalFromLocal
local pointFromCandidate
local traceCandidate

local function clearCompatGhost(state, ent)
    if M.Compat and isfunction(M.Compat.ClearGhost) then
        M.Compat.ClearGhost(state, ent)
    end
end

local function clearAllCompatGhosts(state)
    if M.Compat and isfunction(M.Compat.ClearGhosts) then
        M.Compat.ClearGhosts(state)
    end
end

local function setCompatGhost(state, ent, pos, ang, alphaFn, linked)
    if M.Compat and isfunction(M.Compat.SetGhost) then
        return M.Compat.SetGhost(state, ent, pos, ang, alphaFn, linked)
    end

    return false
end

local function worldPointsApi()
    return M.Client and M.Client.WorldPoints or nil
end

-- Die Tabs spiegeln die Referenzen aus dem Shared-Code wider.
-- Jeder Tab arbeitet mit seinem eigenen Referenzraum und zeigt denselben
-- Raum anschliessend als Gizmo im Weltspace an.
local SPACE_LABELS = {
    prop1 = "Prop 1",
    prop2 = "Prop 2",
    points = "Axis",
    world = "World"
}
local RING_QUALITY_PRESETS = {
    { label = "Low", ringRtSize = 512, circleRtSize = 64, ringSegments = 64, circleSegments = 64, tickCount = 9 },
    { label = "Medium", ringRtSize = 1024, circleRtSize = 128, ringSegments = 128, circleSegments = 128, tickCount = 17 },
    { label = "High", ringRtSize = 2048, circleRtSize = 512, ringSegments = 256, circleSegments = 256, tickCount = 33 },
    { label = "Ultra", ringRtSize = 4096, circleRtSize = 1024, ringSegments = 360, circleSegments = 360, tickCount = 65 },
    { label = "Low", realtime = true, ringSegments = 12, circleSegments = 6, tickCount = 9 },
    { label = "Medium", realtime = true, ringSegments = 24, circleSegments = 12, tickCount = 17 },
    { label = "High", realtime = true, ringSegments = 36, circleSegments = 18, tickCount = 33 },
    { label = "Ultra", realtime = true, ringSegments = 64, circleSegments = 32, tickCount = 65 }
}
local DEFAULT_RING_QUALITY_INDEX = 2

TOOL.ClientConVar = {
    grid_a = "12",
    grid_a_min = "3",
    grid_b_enable = "0",
    grid_b = "8",
    grid_b_min = "2",
    min_length = "4",
    trace_snap_length = "5",
    display_rounding = "5",
    show_trace_probes = "0",
    preview_occluded = "0",
    preview_occluded_r = "18",
    preview_occluded_g = "52",
    preview_occluded_b = "70",
    preview_occluded_a = "160",
    ring_quality = tostring(DEFAULT_RING_QUALITY_INDEX),
    rotation_snap = "12",
    translation_snap = "0",
    world_target = "1",
    weld = "0",
    nocollide = "0",
    parent = "0",
    from_anchor = "p1",
    from_priority = "mid12,p1,p2,p3,mid23,mid13,mid123",
    from_mid12_pct = "50",
    from_mid23_pct = "50",
    from_mid13_pct = "50",
    to_anchor = "p1",
    to_priority = "mid12,mid12,p2,p3,mid23,mid13,mid123",
    to_mid12_pct = "50",
    to_mid23_pct = "50",
    to_mid13_pct = "50",
    space = "prop1"
}

for _, space in ipairs(M.SPACES) do
    -- Positionswerte werden im Referenzraum des Tabs gespeichert.
    -- Die Winkelwerte beschreiben, wie der Gizmo innerhalb dieses
    -- Referenzraums gedreht ist.
    TOOL.ClientConVar[space .. "_px"] = "0"
    TOOL.ClientConVar[space .. "_py"] = "0"
    TOOL.ClientConVar[space .. "_pz"] = "0"
    TOOL.ClientConVar[space .. "_pitch"] = "0"
    TOOL.ClientConVar[space .. "_yaw"] = "0"
    TOOL.ClientConVar[space .. "_roll"] = "0"
end

local POINT_REMOVE_RADIUS = 12
local CORNER_TRACE_MIN_LENGTH = 6
local DRAW_SELECT_DEADZONE = 1
local FACE_TRACE_OUTSIDE_OFFSET = 1
local FACE_TRACE_END_OVERSHOOT = 1
local PRIMITIVE_AABB_FACE_EPSILON = 0.75
local TRACE_PROBE_NORMAL_DOT_MIN = 0.999999
local ROTATION_SNAP_DIVISORS = { 3, 4, 5, 6, 8, 9, 10, 12, 15, 18, 20, 24, 30, 36, 40, 45, 60, 72, 90, 120, 180, 360 }
local DEFAULT_ROTATION_SNAP_INDEX = 12
local MAX_VISIBLE_ROTATION_TICKS = 20
local SESSION_CONVAR_SUFFIXES = { "px", "py", "pz", "pitch", "yaw", "roll" }
local SMARTSNAP_ENABLED_CVAR = "snap_enabled"
local SMARTSNAP_DISABLE_CVAR = "magic_align_disable_smartsnap_active"
local TOOL_DEFAULT_DESCRIPTION = "Easily align props."
local TOOL_STATUS_DESCRIPTIONS = {
    source_prop = "Pick the source prop by placing a point on it.",
    source_points = "Place points on Prop 1.",
    target_prop = "Add Points, Link Props",
    target_points = "Place points on Prop 2.",
    ready = "Refine positioning, then commit it."
}
local TOOL_INFORMATION_IDLE = {
    { name = "left" },
    { name = "right" },
    { name = "reload", icon = "magic_align/keys/R.png" },
    { name = "tab", icon = "magic_align/keys/TAB.png", },
    { name = "alt_pick", icon = "magic_align/keys/ALT.png" },
    { name = "supress_snap", icon = "magic_align/keys/SHFT.png", icon2 = "magic_align/keys/EMP.png" }
}
local TOOL_INFORMATION_READY = {
    { name = "left" },
    { name = "right" },
    { name = "reload", icon = "magic_align/keys/R.png" },
    { name = "use", icon = "magic_align/keys/E.png" },
    { name = "tab", icon = "magic_align/keys/TAB.png" },
    { name = "alt_pick", icon = "magic_align/keys/ALT.png" },
    { name = "supress_snap", icon = "magic_align/keys/SHFT.png", icon2 = "magic_align/keys/EMP.png" }
}
local TOOL_INFORMATION_WORLD_POINT = { name = "world_point_gizmo", icon = "magic_align/keys/ALT.png" }
local TOOL_INFORMATION_IDLE_WORLD_POINT = {
    TOOL_INFORMATION_IDLE[1],
    TOOL_INFORMATION_IDLE[2],
    TOOL_INFORMATION_IDLE[3],
    TOOL_INFORMATION_IDLE[4],
    TOOL_INFORMATION_WORLD_POINT,
    TOOL_INFORMATION_IDLE[6]
}
local TOOL_INFORMATION_READY_WORLD_POINT = {
    TOOL_INFORMATION_READY[1],
    TOOL_INFORMATION_READY[2],
    TOOL_INFORMATION_READY[3],
    TOOL_INFORMATION_READY[4],
    TOOL_INFORMATION_READY[5],
    TOOL_INFORMATION_WORLD_POINT,
    TOOL_INFORMATION_READY[7]
}

TOOL.Information = TOOL_INFORMATION_IDLE

if CLIENT then
    CreateClientConVar(
        "magic_align_grid_label_percent",
        "1",
        true,
        false,
        "Show Magic Align gridline labels as percentages instead of reduced fractions.",
        0,
        1
    )

    CreateClientConVar(
        SMARTSNAP_DISABLE_CVAR,
        "1",
        true,
        false,
        "Disable SmartSnap while the Magic Align tool is active.",
        0,
        1
    )

    CreateClientConVar(
        "magic_align_highlight_context_menu",
        "1",
        true,
        false,
        "Highlight the Magic Align tool entry in the context menu.",
        0,
        1
    )

    language.Add("tool.magic_align.name", "Magic Align")
    language.Add("tool.magic_align.desc", TOOL_DEFAULT_DESCRIPTION)
    language.Add("tool.magic_align.left", "Place & Move Points | Manipulate Gizmo")
    language.Add("tool.magic_align.right", "Delete Points | Toggle Linked Props")
    language.Add("tool.magic_align.reload", "Reset Session")
    language.Add("tool.magic_align.use", "Commit | Shift: Keep Session | Ctrl: Copy | Ctrl+Shift: Copy&Move")
    language.Add("tool.magic_align.tab", "Cycles Reference Spaces")
    language.Add("tool.magic_align.world_point_gizmo", "Toggle Gizmoon hovered World-Point")
    language.Add("tool.magic_align.alt_pick", "Surface-Select")
    language.Add("tool.magic_align.supress_snap", "Suppress Snapping")
end

local function sendClientAction(ply, action, trace)
    if CLIENT or not IsValid(ply) then return end

    net.Start(M.NET_CLIENT_ACTION)
        net.WriteUInt(action, 2)

        if action == M.CLIENT_ACTION_RIGHTCLICK then
            local ent = trace and trace.Entity or NULL
            local hitPos = trace and trace.HitPos or nil
            local hitWorld = trace ~= nil and (trace.HitWorld == true or (IsValid(ent) and ent.IsWorld and ent:IsWorld())) or false

            net.WriteEntity(IsValid(ent) and ent or NULL)
            net.WriteBool(isvector(hitPos))
            if isvector(hitPos) then
                net.WritePreciseVector(hitPos)
            end
            net.WriteBool(hitWorld)
        end
    net.Send(ply)
end

local function editable(state, ent, tr)
    if IsValid(ent) then
        if ent == state.prop1 then
            return "source", state.prop1, state.source
        elseif ent == state.prop2 then
            return "target", state.prop2, state.target
        end
    end

    if isWorldTarget(state.prop2) and traceHitsWorld(tr) then
        return "target", state.prop2, state.target
    end

    if hasTargetEntity(state.prop2) then
        return "target", state.prop2, state.target
    end

    if IsValid(state.prop1) then
        return "source", state.prop1, state.source
    end
end

local function performClientRightClick(trace)
    local state = M.ClientState
    if not state then return true end

    state.linked = state.linked or {}
    state.linkedGhosts = state.linkedGhosts or {}

    if IsValid(state.prop1)
        and trace
        and M.IsProp(trace.Entity)
        and trace.Entity ~= state.prop1
        and trace.Entity ~= state.prop2 then
        local linked = state.linked
        local existing

        for i = 1, #linked do
            if linked[i] == trace.Entity then
                existing = i
                break
            end
        end

        if existing then
            table.remove(linked, existing)

            local ghost = state.linkedGhosts[trace.Entity]
            if IsValid(ghost) then
                ghost:Remove()
            end
            state.linkedGhosts[trace.Entity] = nil
            clearCompatGhost(state, trace.Entity)
        elseif #linked < M.GetMaxLinkedProps() then
            linked[#linked + 1] = trace.Entity
        end

        return true
    end

    local _, ent, points = editable(state, trace and trace.Entity or nil, trace)
    if not trace or not ent or not traceMatchesEntity(trace, ent) or not isvector(trace.HitPos) then return true end

    local best, bestDist
    for i = 1, #points do
        local world = worldPosFromLocalPoint(ent, points[i])
        if isvector(world) then
            local dist = world:DistToSqr(trace.HitPos)
            if not bestDist or dist < bestDist then
                best = i
                bestDist = dist
            end
        end
    end

    if best and bestDist <= POINT_REMOVE_RADIUS ^ 2 then
        table.remove(points, best)

        local worldPoints = worldPointsApi()
        if worldPoints
            and points == state.target
            and isWorldTarget(state.prop2)
            and isfunction(worldPoints.onTargetPointRemoved) then
            worldPoints.onTargetPointRemoved(state, best)
        end

        state.pending = nil
        M.RefreshState(state)
    end

    return true
end

local function resetSessionConVars()
    for _, space in ipairs(M.SPACES) do
        for _, suffix in ipairs(SESSION_CONVAR_SUFFIXES) do
            RunConsoleCommand("magic_align_" .. space .. "_" .. suffix, "0")
        end
    end

    if M.Client and M.Client.updateSessionTabTitles then
        M.Client.updateSessionTabTitles()
    end
end

local function performClientReload(tool)
    local state = M.ClientState
    if state and IsValid(state.ghost) then
        state.ghost:Remove()
    end
    if state and istable(state.linkedGhosts) then
        for _, ghost in pairs(state.linkedGhosts) do
            if IsValid(ghost) then
                ghost:Remove()
            end
        end
    end
    if state then
        clearAllCompatGhosts(state)
    end

    resetSessionConVars()

    if IsValid(M.ClientSheet) and M.ClientTabs and tool then
        local currentSpace = tool:GetClientInfo("space")
        local activeTab = M.ClientTabs[currentSpace]
        if IsValid(activeTab) then
            M.ClientSheet:SetActiveTab(activeTab)
        end
    end

    M.ClientState = M.NewSession()

    return true
end

local function resetClientSession(tool)
    return performClientReload(tool)
end

local function validateClientState(tool, state)
    if not state then return true end

    if state.prop1 ~= nil and (not IsValid(state.prop1) or not M.IsProp(state.prop1)) then
        resetClientSession(tool)
        return false
    end

    if state.prop2 ~= nil and not isWorldTarget(state.prop2) and (not IsValid(state.prop2) or not M.IsProp(state.prop2)) then
        resetClientSession(tool)
        return false
    end

    return true
end

local function setPlayerViewAngles(ply, ang)
    if not IsValid(ply) or not isangle(ang) then return end

    ply:SetEyeAngles(toAngle(ang))

    if game.SinglePlayer() then
        net.Start(M.NET_VIEW_ANGLES)
            net.WritePreciseAngle(ang)
        net.SendToServer()
    end
end

function TOOL:LeftClick()
    return true
end

function TOOL:RightClick(trace)
    if SERVER then
        if game.SinglePlayer() then
            sendClientAction(self:GetOwner(), M.CLIENT_ACTION_RIGHTCLICK, trace)
        end
        return true
    end

    if game.SinglePlayer() then
        return true
    end

    return performClientRightClick(trace)
end

function TOOL:Reload()
    if SERVER then
        if game.SinglePlayer() then
            sendClientAction(self:GetOwner(), M.CLIENT_ACTION_RESET)
        end
        return true
    end

    if game.SinglePlayer() then
        return true
    end

    return performClientReload(self)
end

if SERVER then
    hook.Add("AllowPlayerPickup", "MagicAlignBlockUsePickup", function(ply, ent)
        if not M.IsProp(ent) then return end
        if not M.GetActiveMagicAlignTool(ply) then return end

        return false
    end)

    AddCSLuaFile("magic_align/client/math_parser.lua")
    AddCSLuaFile("magic_align/client/formula_manager.lua")
    AddCSLuaFile("magic_align/client/dmagic_align_numslider.lua")
    AddCSLuaFile("magic_align/client/menu.lua")
    AddCSLuaFile("magic_align/client/menuentryhack.lua")
    AddCSLuaFile("magic_align/client/render.lua")
    AddCSLuaFile("magic_align/client/render_toolgun.lua")
    AddCSLuaFile("magic_align/client/world_points.lua")
    return
end

local colors = {
    source = Color(255, 190, 80),
    target = Color(80, 220, 255),
    preview = Color(80, 240, 255),
    pending = Color(120, 255, 120),
    corner = Color(255, 120, 255),
    x = Color(255, 100, 100),
    y = Color(120, 255, 120),
    z = Color(120, 160, 255),
    dim = Color(255, 255, 255, 80)
}

colors.xy = Color(255, 210, 80, 150)
colors.xz = Color(255, 130, 210, 150)
colors.yz = Color(110, 240, 255, 150)

local function ensureStateShape(state)
    state = state or M.NewSession()

    state.sessionId = tonumber(state.sessionId) or M.NextSessionId()
    state.linked = state.linked or {}
    state.anchorSelection = state.anchorSelection or {}
    state.source = state.source or {}
    state.target = state.target or {}
    state.bounds = state.bounds or {}
    state.compatGhosts = state.compatGhosts or { linked = {} }
    state.compatGhosts.linked = state.compatGhosts.linked or {}
    state.linkedGhosts = state.linkedGhosts or {}
    state.attackDown = state.attackDown == true
    state.useDown = state.useDown == true

    return state
end

local function state()
    if not M.ClientSessionConVarsInitialized then
        resetSessionConVars()
        M.ClientSessionConVarsInitialized = true
    end

    M.ClientState = ensureStateShape(M.ClientState)
    return M.ClientState
end

local function comp(v, key)
    return key == "x" and v.x or key == "y" and v.y or v.z
end

local function copyVec(v)
    return M.CopyVectorPrecise(v)
end

local function copyAng(a)
    return M.CopyAnglePrecise(a)
end

local function normalizedVec(v)
    return M.NormalizeVectorPrecise(v, M.COMPUTE_VECTOR_EPSILON_SQR)
end

function isWorldTarget(ent)
    return M.IsWorldTarget and M.IsWorldTarget(ent) or false
end

function hasTargetEntity(ent)
    return M.HasTargetEntity and M.HasTargetEntity(ent) or isWorldTarget(ent) or IsValid(ent)
end

local function worldIdentityPos()
    return VectorP(0, 0, 0)
end

local function worldIdentityAng()
    return AngleP(0, 0, 0)
end

function traceHitsWorld(tr)
    return tr ~= nil
        and tr.Hit ~= false
        and tr.HitSky ~= true
        and isvector(tr.HitPos)
        and (tr.HitWorld == true or isWorldTarget(tr.Entity))
end

function traceMatchesEntity(tr, ent)
    if not tr then return false end

    if isWorldTarget(ent) then
        return traceHitsWorld(tr)
    end

    return IsValid(ent) and tr.Hit ~= false and tr.Entity == ent and isvector(tr.HitPos)
end

local function entityBasePos(ent)
    if isWorldTarget(ent) then
        return worldIdentityPos()
    end

    return IsValid(ent) and ent:GetPos() or nil
end

local function entityBaseAng(ent)
    if isWorldTarget(ent) then
        return worldIdentityAng()
    end

    return IsValid(ent) and ent:GetAngles() or nil
end

function worldPosFromLocalPoint(ent, localPos)
    if not isvector(localPos) then return end

    if isWorldTarget(ent) then
        return copyVec(localPos)
    end

    local pos = entityBasePos(ent)
    local ang = entityBaseAng(ent)
    if not isvector(pos) or not isangle(ang) then return end

    return LocalToWorldPrecise(localPos, AngleP(0, 0, 0), pos, ang)
end

function localPointFromWorldPos(ent, worldPos)
    if not isvector(worldPos) then return end

    if isWorldTarget(ent) then
        return copyVec(worldPos)
    end

    local pos = entityBasePos(ent)
    local ang = entityBaseAng(ent)
    if not isvector(pos) or not isangle(ang) then return end

    return WorldToLocalPrecise(worldPos, AngleP(0, 0, 0), pos, ang)
end

function localNormalFromWorld(ent, worldPos, worldNormal)
    local worldPoint = copyVec(worldPos)
    local normal = normalizedVec(worldNormal)
    if not isvector(worldPoint) or not normal then return end

    if isWorldTarget(ent) then
        return copyVec(normal)
    end

    local localPos = localPointFromWorldPos(ent, worldPoint)
    local pos = entityBasePos(ent)
    local ang = entityBaseAng(ent)
    if not isvector(localPos) or not isvector(pos) or not isangle(ang) then return end

    local normalTip = WorldToLocalPrecise(worldPoint + normal, AngleP(0, 0, 0), pos, ang)
    if not isvector(normalTip) then return end

    return normalizedVec(normalTip - localPos)
end

function worldNormalFromLocal(ent, localPos, localNormal)
    local normal = normalizedVec(localNormal)
    if not normal then return end

    if isWorldTarget(ent) then
        return copyVec(normal)
    end

    local worldPos = worldPosFromLocalPoint(ent, localPos)
    local pos = entityBasePos(ent)
    local ang = entityBaseAng(ent)
    if not isvector(worldPos) or not isvector(pos) or not isangle(ang) then return end

    local worldTip = LocalToWorldPrecise(localPos + normal, AngleP(0, 0, 0), pos, ang)
    if not isvector(worldTip) then return end

    return normalizedVec(worldTip - worldPos)
end

function pointFromCandidate(candidate)
    if not istable(candidate) or not isvector(candidate.localPos) then return end

    local point = VectorP(candidate.localPos.x, candidate.localPos.y, candidate.localPos.z)
    local localNormal = normalizedVec(candidate.localNormal)

    if not localNormal and isvector(candidate.normal) then
        local worldPos = isvector(candidate.worldPos) and candidate.worldPos or worldPosFromLocalPoint(candidate.ent, candidate.localPos)
        localNormal = localNormalFromWorld(candidate.ent, worldPos, candidate.normal)
    end

    if localNormal then
        point.normal = copyVec(localNormal)
    end

    if isWorldTarget(candidate.ent) then
        point.world = true
    end

    return point
end

local function clientNumber(tool, name, fallback)
    local value

    if tool and isfunction(tool.GetClientInfo) then
        value = tonumber(tool:GetClientInfo(name))
    end

    if value == nil and tool and isfunction(tool.GetClientNumber) then
        value = tonumber(tool:GetClientNumber(name))
    end

    if not M.IsFiniteNumber(value) then
        value = tonumber(fallback) or 0
    end

    return value
end

local function exactNormalKey(v)
    local n = normalizedVec(v)
    if not n then return end

    return ("%.17g|%.17g|%.17g"):format(
        n.x,
        n.y,
        n.z
    )
end

local function buildTraceSample(ent, worldPos, worldNormal, tr)
    if not hasTargetEntity(ent) then return end

    if tr then
        if not traceMatchesEntity(tr, ent) then return end
        worldPos = copyVec(tr.HitPos)
        worldNormal = isvector(tr.HitNormal) and copyVec(tr.HitNormal) or tr.HitNormal
    end

    if not isvector(worldPos) then return end

    local localPos = localPointFromWorldPos(ent, worldPos)
    if not isvector(localPos) then return end
    localPos = copyVec(localPos)

    local localNormal
    local localNormalKey

    if isvector(worldNormal) then
        localNormal = localNormalFromWorld(ent, worldPos, worldNormal)
        if localNormal then
            localNormalKey = exactNormalKey(localNormal)
        else
            localNormal = nil
        end
    end

    return {
        localPos = localPos,
        localNormal = localNormal,
        localNormalKey = localNormalKey,
        surfaceHit = tr ~= nil
    }
end

local function sampleWorldPos(ent, sample)
    if not istable(sample) then return end

    if hasTargetEntity(ent) and isvector(sample.localPos) then
        return worldPosFromLocalPoint(ent, sample.localPos)
    end

    return isvector(sample.pos) and sample.pos or nil
end

local function sampleWorldNormal(ent, sample)
    if not istable(sample) then return end

    if hasTargetEntity(ent) and isvector(sample.localPos) and isvector(sample.localNormal) then
        local worldNormal = worldNormalFromLocal(ent, sample.localPos, sample.localNormal)
        if worldNormal then
            return worldNormal
        end
    end

    if isvector(sample.normal) then
        return normalizedVec(sample.normal)
    end
end

local function sampleLocalPos(sample)
    if not istable(sample) or not isvector(sample.localPos) then return end
    return copyVec(sample.localPos)
end

local function sampleLocalNormal(sample)
    return normalizedVec(sample and sample.localNormal)
end

local function aggregateTraceProbes(samples)
    local probes = {}

    for i = 1, #samples do
        local sample = samples[i]
        if istable(sample) and sample.surfaceHit == true then
            local localPos = sampleLocalPos(sample)
            local localNormal = sampleLocalNormal(sample)
            local normalKey = sample.localNormalKey

            if localPos and localNormal then
                normalKey = normalKey or exactNormalKey(localNormal)
            end

            if localPos and localNormal and isstring(normalKey) and normalKey ~= "" then
                local probe

                for j = 1, #probes do
                    local existing = probes[j]
            if isvector(existing.localNormal) and M.DotVectorsPrecise(existing.localNormal, localNormal) >= TRACE_PROBE_NORMAL_DOT_MIN then
                probe = existing
                break
            end
                end

                if not probe then
                    probe = {
                        normalKey = normalKey,
                        localNormal = localNormal,
                        normalSum = VectorP(0, 0, 0),
                        localPos = VectorP(0, 0, 0),
                        planeDistance = 0,
                        count = 0
                    }
                    probes[#probes + 1] = probe
                end

                probe.count = probe.count + 1
                probe.normalSum = probe.normalSum + localNormal
                probe.localNormal = normalizedVec(probe.normalSum) or probe.localNormal
                probe.localPos = probe.localPos + localPos
            end
        end
    end

    for i = 1, #probes do
        local probe = probes[i]
        probe.localPos = probe.localPos / probe.count
        probe.localNormal = normalizedVec(probe.normalSum) or normalizedVec(probe.localNormal)
        probe.planeDistance = probe.localNormal:Dot(probe.localPos)
        probe.normalSum = nil
        probe.normalKey = probe.normalKey or exactNormalKey(probe.localNormal)
    end

    table.sort(probes, function(a, b)
        if a.count == b.count then
            return a.normalKey < b.normalKey
        end

        return a.count > b.count
    end)

    return probes
end

local function worldVectorFromLocalDirection(ent, localDir)
    local localNormal = normalizedVec(localDir)
    if not IsValid(ent) or not localNormal then return end

    local worldOrigin = LocalToWorldPrecise(VectorP(0, 0, 0), AngleP(0, 0, 0), ent:GetPos(), ent:GetAngles())
    local worldTip = LocalToWorldPrecise(localNormal, AngleP(0, 0, 0), ent:GetPos(), ent:GetAngles())
    return normalizedVec(worldTip - worldOrigin)
end

local function buildTraceProbeCandidate(ent, localPos, localNormal, mode, probes, axisLocalDir)
    if not hasTargetEntity(ent) or not isvector(localPos) then return end

    local worldPos = worldPosFromLocalPoint(ent, localPos)
    if not isvector(worldPos) then return end

    local storedLocalNormal = normalizedVec(localNormal)
    local worldNormal = worldNormalFromLocal(ent, localPos, storedLocalNormal)
    local worldAxisDir = worldNormalFromLocal(ent, localPos, axisLocalDir)

    return {
        ent = ent,
        localPos = copyVec(localPos),
        worldPos = worldPos,
        localNormal = storedLocalNormal and copyVec(storedLocalNormal) or nil,
        normal = worldNormal or worldAxisDir or (isWorldTarget(ent) and VectorP(0, 0, 1) or ent:GetUp()),
        mode = mode,
        probes = probes,
        axisLocalDir = isvector(axisLocalDir) and copyVec(axisLocalDir) or nil,
        axisWorldDir = worldAxisDir
    }
end

local function ghostAlpha(alpha)
    return math.Clamp(math.floor((tonumber(alpha) or 255) * 0.42), 48, 140)
end

local function linkedGhostAlpha(alpha)
    return math.Clamp(math.floor(ghostAlpha(alpha) * 0.58), 28, 88)
end

local function modelScale(ent)
    return math.max(tonumber(IsValid(ent) and ent:GetModelScale() or 1) or 1, M.MODEL_SCALE_EPSILON)
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

local function visualScale(ent)
    local handler = findSizeHandler(ent)
    if not IsValid(handler) or not isfunction(handler.GetVisualScale) then return end

    local scale = parseScaleVector(handler:GetVisualScale())
    if not isvector(scale) or vectorApprox(scale, SCALE_ZERO) or vectorApprox(scale, SCALE_IDENTITY) then
        return
    end

    return scale
end

local function applyGhostScale(ghost, src)
    if not IsValid(ghost) or not IsValid(src) then return end

    ghost:SetModelScale(modelScale(src), 0)

    local scale = visualScale(src)
    if scale then
        local matrix = Matrix()
        matrix:Scale(toVector(scale))
        ghost:EnableMatrix("RenderMultiply", matrix)
    else
        ghost:DisableMatrix("RenderMultiply")
    end

    local mins, maxs = src:GetRenderBounds()
    if isvector(mins) and isvector(maxs) then
        ghost:SetRenderBounds(mins, maxs)
    end
end

local function revisionValue(value, depth)
    if isvector(value) or isangle(value) then
        return tostring(value)
    end

    if istable(value) and (tonumber(depth) or 0) < 2 then
        local keys = {}
        for key in pairs(value) do
            keys[#keys + 1] = key
        end

        table.sort(keys, function(a, b)
            return tostring(a) < tostring(b)
        end)

        local parts = {}
        for i = 1, #keys do
            local key = keys[i]
            parts[#parts + 1] = tostring(key) .. "=" .. revisionValue(value[key], (depth or 0) + 1)
        end

        return "{" .. table.concat(parts, ",") .. "}"
    end

    return tostring(value)
end

local function resizeRevision(ent)
    local parts = {}
    local modifierData = istable(ent.EntityMods) and ent.EntityMods.advr or nil

    if istable(modifierData) then
        for i = 1, 7 do
            parts[#parts + 1] = revisionValue(modifierData[i])
        end
    else
        parts[#parts + 1] = "noadvr"
    end

    local handler = findSizeHandler(ent)
    if IsValid(handler) then
        parts[#parts + 1] = isfunction(handler.GetActualPhysicsScale) and tostring(handler:GetActualPhysicsScale()) or "nophys"
        parts[#parts + 1] = isfunction(handler.GetVisualScale) and tostring(handler:GetVisualScale()) or "novis"
    else
        parts[#parts + 1] = "nohandler"
    end

    return table.concat(parts, "|")
end

local function primitiveRevision(ent)
    if not (M.IsPrimitive and M.IsPrimitive(ent)) then return "notprimitive" end

    local parts = { ent:GetClass() }

    if isfunction(ent.PrimitiveGetKeys) then
        local keys = ent:PrimitiveGetKeys()
        if istable(keys) then
            local names = {}
            for name in pairs(keys) do
                names[#names + 1] = name
            end

            table.sort(names)

            for i = 1, #names do
                local name = names[i]
                parts[#parts + 1] = tostring(name) .. "=" .. revisionValue(keys[name])
            end
        else
            parts[#parts + 1] = "nokeys"
        end
    else
        parts[#parts + 1] = "nogetter"
    end

    return table.concat(parts, "|")
end

local function boundsRevision(ent)
    if not IsValid(ent) then return "invalid" end

    local collisionMins, collisionMaxs = ent:GetCollisionBounds()
    local renderMins, renderMaxs = ent:GetRenderBounds()

    return table.concat({
        tostring(modelScale(ent)),
        isvector(collisionMins) and tostring(collisionMins) or "nil",
        isvector(collisionMaxs) and tostring(collisionMaxs) or "nil",
        isvector(renderMins) and tostring(renderMins) or "nil",
        isvector(renderMaxs) and tostring(renderMaxs) or "nil",
        resizeRevision(ent),
        primitiveRevision(ent)
    }, "|")
end

local function resetBoundsEntry(entry)
    if not istable(entry) then return end

    entry.pending = false
    entry.ready = false
    entry.size = nil
    entry.mins = nil
    entry.maxs = nil
    entry.center = nil
    entry.requestRevision = nil
end

local function refreshBoundsEntry(ent, entry)
    if not IsValid(ent) or not istable(entry) then return end

    local revision = boundsRevision(ent)
    if entry.revision == revision then
        return revision
    end

    resetBoundsEntry(entry)
    entry.requestedAt = 0
    entry.revision = revision

    return revision
end

local function linkedPropIndex(state, ent)
    if not IsValid(ent) then return end

    for i = 1, #(state.linked or {}) do
        if state.linked[i] == ent then
            return i
        end
    end
end

local function isLinkedProp(state, ent)
    return linkedPropIndex(state, ent) ~= nil
end

local function removeLinkedGhost(state, ent)
    local ghosts = state.linkedGhosts or {}
    local ghost = ghosts[ent]
    if IsValid(ghost) then
        ghost:Remove()
    end
    ghosts[ent] = nil
    clearCompatGhost(state, ent)
end

local function resetLinkedProps(state)
    if istable(state.linkedGhosts) then
        for ent, ghost in pairs(state.linkedGhosts) do
            if IsValid(ghost) then
                ghost:Remove()
            end
            state.linkedGhosts[ent] = nil
            clearCompatGhost(state, ent)
        end
    end

    local compatLinked = state.compatGhosts and state.compatGhosts.linked or nil
    if istable(compatLinked) then
        for ent in pairs(compatLinked) do
            clearCompatGhost(state, ent)
        end
    end

    state.linked = {}
end

local function removeLinkedProp(state, ent)
    local index = linkedPropIndex(state, ent)
    if not index then return false end

    table.remove(state.linked, index)
    removeLinkedGhost(state, ent)

    return true
end

local function cleanupLinkedProps(state)
    state.linked = state.linked or {}
    state.linkedGhosts = state.linkedGhosts or {}

    for i = #state.linked, 1, -1 do
        local ent = state.linked[i]
        if not IsValid(ent) or not M.IsProp(ent) or ent == state.prop1 or ent == state.prop2 then
            table.remove(state.linked, i)
            removeLinkedGhost(state, ent)
        end
    end

    for ent, ghost in pairs(state.linkedGhosts) do
        if not IsValid(ent) or not isLinkedProp(state, ent) then
            if IsValid(ghost) then
                ghost:Remove()
            end
            state.linkedGhosts[ent] = nil
        end
    end
end

local function commitMode()
    local ctrl = input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL)
    local shift = input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT)

    if ctrl then
        return shift and M.COMMIT_COPY_MOVE or M.COMMIT_COPY, true
    end

    return M.COMMIT_MOVE, shift
end

local lastToolDescription
local lastToolShowsUse
local lastToolShowsWorldPointHint

local function updateToolHelp(tool, state)
    if not tool then return end

    local stateName = istable(state) and state.state or nil
    local description = TOOL_STATUS_DESCRIPTIONS[stateName] or TOOL_DEFAULT_DESCRIPTION
    local showUse = istable(state) and state.preview ~= nil
    local worldPoints = worldPointsApi()
    local showWorldPointHint = worldPoints
        and isfunction(worldPoints.hasToggleHint)
        and worldPoints.hasToggleHint(state)
        or false

    if lastToolDescription ~= description then
        language.Add("tool.magic_align.desc", description)
        lastToolDescription = description
    end

    if lastToolShowsUse ~= showUse or lastToolShowsWorldPointHint ~= showWorldPointHint then
        if showUse then
            tool.Information = showWorldPointHint and TOOL_INFORMATION_READY_WORLD_POINT or TOOL_INFORMATION_READY
        else
            tool.Information = showWorldPointHint and TOOL_INFORMATION_IDLE_WORLD_POINT or TOOL_INFORMATION_IDLE
        end
        lastToolShowsUse = showUse
        lastToolShowsWorldPointHint = showWorldPointHint
    end
end

local function ensureGhostModel(ghost, model)
    if not model or model == "" then
        if IsValid(ghost) then
            ghost:Remove()
        end
        return
    end

    if not IsValid(ghost) or ghost:GetModel() ~= model then
        if IsValid(ghost) then
            ghost:Remove()
        end

        ghost = ClientsideModel(model, RENDERGROUP_TRANSLUCENT)
        if not IsValid(ghost) then return end

        ghost:SetNoDraw(true)
        ghost:SetRenderMode(RENDERMODE_TRANSCOLOR)
        ghost:DrawShadow(false)
    end

    return ghost
end

local function applyGhostAppearance(ghost, src, pos, ang, alphaFn)
    if not IsValid(ghost) or not IsValid(src) then return end

    ghost:SetPos(toVector(pos))
    ghost:SetAngles(toAngle(ang))
    ghost:SetSkin(src:GetSkin() or 0)
    ghost:SetMaterial(src:GetMaterial() or "")
    for i = 0, src:GetNumBodyGroups() - 1 do
        ghost:SetBodygroup(i, src:GetBodygroup(i))
    end

    local subCount = math.max(
        src:GetMaterials() and #src:GetMaterials() or 0,
        ghost:GetMaterials() and #ghost:GetMaterials() or 0
    )
    for i = 0, subCount - 1 do
        ghost:SetSubMaterial(i, src:GetSubMaterial(i) or "")
    end

    local srcColor = src:GetColor()
    ghost:SetColor(Color(srcColor.r, srcColor.g, srcColor.b, alphaFn(srcColor.a)))
    applyGhostScale(ghost, src)
    ghost:SetupBones()
    ghost:SetNoDraw(false)
end

local function hideGhosts(state)
    if IsValid(state.ghost) then
        state.ghost:SetNoDraw(true)
    end

    for _, ghost in pairs(state.linkedGhosts or {}) do
        if IsValid(ghost) then
            ghost:SetNoDraw(true)
        end
    end

    clearAllCompatGhosts(state)
end

hook.Remove("Think", "MagicAlignHideGhostsWhenInactive")
hook.Add("Think", "MagicAlignHideGhostsWhenInactive", function()
    local state = M.ClientState
    if not istable(state) then return end

    local ply = LocalPlayer()
    if IsValid(ply) and M.GetActiveMagicAlignTool(ply) then return end

    hideGhosts(state)
end)

local smartSnapSuppression = M.SmartSnapSuppression or {}
M.SmartSnapSuppression = smartSnapSuppression

local function restoreSmartSnap()
    if not smartSnapSuppression.active then return end

    local restoreValue = smartSnapSuppression.restoreValue
    smartSnapSuppression.active = false
    smartSnapSuppression.restoreValue = nil

    local cvar = GetConVar(SMARTSNAP_ENABLED_CVAR)
    if cvar and restoreValue ~= nil and cvar:GetString() ~= restoreValue then
        RunConsoleCommand(SMARTSNAP_ENABLED_CVAR, restoreValue)
    end
end

local function shouldSuppressSmartSnap()
    local setting = GetConVar(SMARTSNAP_DISABLE_CVAR)
    if not setting or not setting:GetBool() then return false end

    local ply = LocalPlayer()
    return IsValid(ply) and M.GetActiveMagicAlignTool(ply) ~= nil
end

local function updateSmartSnapSuppression()
    local cvar = GetConVar(SMARTSNAP_ENABLED_CVAR)
    if not cvar then return end

    if shouldSuppressSmartSnap() then
        if not smartSnapSuppression.active then
            smartSnapSuppression.active = true
            smartSnapSuppression.restoreValue = cvar:GetString()
        end

        if cvar:GetBool() then
            RunConsoleCommand(SMARTSNAP_ENABLED_CVAR, "0")
        end

        return
    end

    restoreSmartSnap()
end

hook.Remove("Think", "MagicAlignSmartSnapSuppression")
hook.Add("Think", "MagicAlignSmartSnapSuppression", updateSmartSnapSuppression)
hook.Remove("ShutDown", "MagicAlignSmartSnapRestore")
hook.Add("ShutDown", "MagicAlignSmartSnapRestore", restoreSmartSnap)

local function ringCoords(key, localPos)
    if key == "roll" then
        return -localPos.y, localPos.z
    elseif key == "pitch" then
        return localPos.x, localPos.z
    end

    return localPos.x, -localPos.y
end

local function ringAngle(key, localPos)
    local u, v = ringCoords(key, localPos)
    return math.atan2(v, u)
end

local function ringRotationDeltaSign(key)
    -- Die sichtbare Ring-Geometrie fuer Roll/Yaw braucht die gespiegelte lokale
    -- Y-Achse, RotateAroundAxis erwartet fuer diese beiden Achsen aber weiterhin
    -- das urspruengliche Vorzeichen des Drag-Deltas.
    return key == "pitch" and 1 or -1
end

local function clampRotationSnapIndex(index)
    return math.Clamp(math.Round(tonumber(index) or DEFAULT_ROTATION_SNAP_INDEX), 1, #ROTATION_SNAP_DIVISORS)
end

local function clampTranslationSnapStep(step)
    return tonumber(step) or 0 --math.Clamp(tonumber(step) or 0, 0, 62) --nonono --TODO Remove unnecessary clamps
end

local function rotationSnapDivisions(tool)
    local index = clampRotationSnapIndex(clientNumber(tool, "rotation_snap", DEFAULT_ROTATION_SNAP_INDEX))
    return ROTATION_SNAP_DIVISORS[index], index
end

local function rotationSnapStep(tool)
    local divisions = rotationSnapDivisions(tool)
    return 360 / math.max(divisions or ROTATION_SNAP_DIVISORS[DEFAULT_ROTATION_SNAP_INDEX], 1)
end

local function translationSnapStep(tool)
    return clampTranslationSnapStep(clientNumber(tool, "translation_snap", 0))
end

local function normalizeDegrees(angle)
    angle = tonumber(angle) or 0
    angle = angle % 360
    if angle < 0 then
        angle = angle + 360
    end

    return angle
end

local function snapRotationAngle(angle, step)
    if step <= M.COMPUTE_EPSILON then
        return normalizeDegrees(angle)
    end

    return normalizeDegrees(math.Round(normalizeDegrees(angle) / step) * step)
end

local function isAngleMultiple(angle, interval)
    local remainder = normalizeDegrees(angle) % interval
    return remainder <= M.UI_COMPARE_EPSILON or math.abs(remainder - interval) <= M.UI_COMPARE_EPSILON
end

local function isMajorRotationTick(angle)
    return isAngleMultiple(angle, 30) or isAngleMultiple(angle, 45)
end

net.Receive(M.NET_CLIENT_ACTION, function()
    local action = net.ReadUInt(2)

    if action == M.CLIENT_ACTION_RIGHTCLICK then
        local ent = net.ReadEntity()
        local hasHitPos = net.ReadBool()
        local hitPos = hasHitPos and net.ReadPreciseVector() or nil
        local hitWorld = net.ReadBool()

        performClientRightClick({
            Entity = ent,
            Hit = hasHitPos,
            HitPos = hitPos,
            HitWorld = hitWorld
        })
    elseif action == M.CLIENT_ACTION_RESET then
        performClientReload()
    end
end)

net.Receive(M.NET_BOUNDS_REPLY, function()
    local ent = net.ReadEntity()
    local sessionId = net.ReadUInt(32)
    local hasBounds = net.ReadBool()
    local mins = hasBounds and net.ReadPreciseVector() or nil
    local maxs = hasBounds and net.ReadPreciseVector() or nil
    local state = ensureStateShape(M.ClientState)

    if not state or not IsValid(ent) or state.sessionId ~= sessionId then return end

    local entry = state.bounds[ent]
    if not istable(entry) then
        entry = {}
        state.bounds[ent] = entry
    end

    local revision = boundsRevision(ent)
    if entry.requestRevision and revision ~= entry.requestRevision then
        resetBoundsEntry(entry)
        entry.revision = revision
        return
    end

    resetBoundsEntry(entry)
    entry.revision = revision

    if isvector(mins) and isvector(maxs) then
        entry.size = maxs - mins
        entry.mins = mins
        entry.maxs = maxs
        entry.center = (mins + maxs) * 0.5
        entry.ready = true
    end
end)

local function boundsEntry(state, ent)
    if not IsValid(ent) then return end

    local entry = state.bounds[ent]
    if istable(entry) and entry.pending ~= nil then
        return entry
    end

    entry = {
        requestedAt = 0,
        pending = false,
        ready = false,
        size = nil,
        mins = nil,
        maxs = nil,
        center = nil
    }
    state.bounds[ent] = entry

    return entry
end

local function requestBounds(state, ent)
    state = ensureStateShape(state)
    local entry = boundsEntry(state, ent)
    if not entry then return end
    local revision = refreshBoundsEntry(ent, entry)

    local now = RealTime()
    if entry.ready then return true end
    if entry.pending and now - entry.requestedAt < M.AABB_REQUEST_COOLDOWN then return false end
    if now - entry.requestedAt < M.AABB_REQUEST_COOLDOWN then return false end

    entry.pending = true
    entry.requestedAt = now
    entry.requestRevision = revision or boundsRevision(ent)

    net.Start(M.NET_BOUNDS_REQUEST)
        net.WriteEntity(ent)
        net.WriteUInt(state.sessionId, 32)
    net.SendToServer()

    return false
end

local function boundsFor(state, ent)
    local entry = IsValid(ent) and state.bounds[ent] or nil
    refreshBoundsEntry(ent, entry)
    return istable(entry) and entry.ready and entry or nil
end

local function activeTool()
    local ply = LocalPlayer()
    local tool = IsValid(ply) and M.GetActiveMagicAlignTool(ply) or nil
    if not tool then return end

    return tool, state()
end

local function uiBlocked()
    return vgui.CursorVisible() and (IsValid(vgui.GetHoveredPanel()) or IsValid(vgui.GetKeyboardFocus()))
end

local function cycleReferenceSpace(tool, step)
    if not tool then return end

    local currentSpace = tool:GetClientInfo("space")
    local currentIndex = 1

    for i = 1, #M.SPACES do
        if M.SPACES[i] == currentSpace then
            currentIndex = i
            break
        end
    end

    local nextIndex = currentIndex + (tonumber(step) or 1)
    while nextIndex < 1 do
        nextIndex = nextIndex + #M.SPACES
    end
    while nextIndex > #M.SPACES do
        nextIndex = nextIndex - #M.SPACES
    end

    local nextSpace = M.SPACES[nextIndex]
    if not nextSpace then return end

    RunConsoleCommand("magic_align_space", nextSpace)

    if IsValid(M.ClientSheet) and M.ClientTabs then
        local activeTab = M.ClientTabs[nextSpace]
        if IsValid(activeTab) then
            M.ClientSheet:SetActiveTab(activeTab)
        end
    end
end

hook.Add("PlayerBindPress", "MagicAlignCycleReferenceSpace", function(ply, bind, pressed)
    local bindName = string.lower(tostring(bind or ""))
    if not string.find(bindName, "showscores", 1, true) then return end

    local tool = M.GetActiveMagicAlignTool(ply)
    if not tool then return end

    if pressed and string.sub(bindName, 1, 1) == "+" and not uiBlocked() then
        local reverse = input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT)
        cycleReferenceSpace(tool, reverse and -1 or 1)
    end

    return true
end)

local function cfg(tool)
    return {
        gridA = math.Clamp(math.Round(clientNumber(tool, "grid_a", 12)), 2, 24),
        gridAMin = math.Clamp(math.Round(clientNumber(tool, "grid_a_min", 3)), 2, 24),
        gridB = math.Clamp(math.Round(clientNumber(tool, "grid_b", 8)), 2, 24),
        gridBMin = math.Clamp(math.Round(clientNumber(tool, "grid_b_min", 2)), 2, 24),
        gridBEnabled = clientNumber(tool, "grid_b_enable", 0) == 1,
        minLength = math.Clamp(math.Round(clientNumber(tool, "min_length", 4)), 0, 12),
        traceSnapLength = clientNumber(tool, "trace_snap_length", 5),
        translationSnap = translationSnapStep(tool),
        worldTarget = clientNumber(tool, "world_target", 1) == 1,
        alt = input.IsKeyDown(KEY_LALT) or input.IsKeyDown(KEY_RALT),
        shift = input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT)
    }
end

local function offsets(tool)
    local out = {}

    local function effectiveOffsetValue(space, key)
        local fallback = clientNumber(tool, space .. "_" .. key, 0)
        local manager = M.FormulaManager
        if not manager then
            return fallback
        end

        local snapshot = manager:GetSnapshot(("magic_align_%s_%s"):format(space, key))
        if snapshot and snapshot.rawMode == "formula" and snapshot.storedNumericValue ~= nil then
            return tonumber(snapshot.value) or tonumber(snapshot.storedNumericValue) or fallback
        end

        return fallback
    end

    for _, space in ipairs(M.SPACES) do
        out[space] = {
            pos = VectorP(
                effectiveOffsetValue(space, "px"),
                effectiveOffsetValue(space, "py"),
                effectiveOffsetValue(space, "pz")
            ),
            rot = AngleP(
                effectiveOffsetValue(space, "pitch"),
                effectiveOffsetValue(space, "yaw"),
                effectiveOffsetValue(space, "roll")
            )
        }
    end

    return out
end

local function setValue(space, key, value)
    RunConsoleCommand("magic_align_" .. space .. "_" .. key, M.FormatConVarNumber(value))
end

local function completeAnchorOrder(priorityText)
    local order = {}
    local seen = {}

    local function tryAdd(id)
        id = string.lower(tostring(id or ""))
        if id == "" or seen[id] then return end

        for _, anchor in ipairs(M.ANCHORS or {}) do
            if anchor.id == id then
                order[#order + 1] = id
                seen[id] = true
                return
            end
        end
    end

    for _, id in ipairs(M.ParsePriority(priorityText)) do
        tryAdd(id)
    end

    for _, anchor in ipairs(M.ANCHORS or {}) do
        tryAdd(anchor.id)
    end

    return order
end

local function priorityIndex(order, id)
    id = string.lower(tostring(id or ""))

    for index, name in ipairs(order or {}) do
        if name == id then
            return index
        end
    end

    return math.huge
end

local function highestAvailableAnchor(order, count)
    for _, id in ipairs(order or {}) do
        if M.AnchorAvailable(id, count) then
            return id
        end
    end
end

local function syncPreferredAnchor(tool, state, side)
    local sidePoints = side == "from" and state.source or state.target
    local selectedKey = side == "from" and "from_anchor" or "to_anchor"
    local priorityKey = side == "from" and "from_priority" or "to_priority"
    local selectionState = state.anchorSelection[side] or {}
    local selected = string.lower(tool:GetClientInfo(selectedKey) or "")
    local priority = tool:GetClientInfo(priorityKey)
    local order = completeAnchorOrder(priority)
    local count = istable(sidePoints) and #sidePoints or 0
    local previousCount = tonumber(selectionState.pointCount) or 0
    local active = selected

    if selectionState.convarAnchor == selected and selectionState.anchor then
        active = selectionState.anchor
    end

    local bestAvailable = highestAvailableAnchor(order, count)
    local activeAvailable = M.AnchorAvailable(active, count)
    if bestAvailable and (not activeAvailable or (count > previousCount and priorityIndex(order, bestAvailable) < priorityIndex(order, active))) then
        active = bestAvailable
    end

    local resolvedSelected = selected
    if active ~= "" and active ~= selected then
        RunConsoleCommand("magic_align_" .. selectedKey, active)
        resolvedSelected = active
    end

    state.anchorSelection[side] = {
        anchor = active,
        convarAnchor = resolvedSelected,
        pointCount = count,
        priority = priority
    }
end

local function refreshPreferredAnchors(tool, state)
    syncPreferredAnchor(tool, state, "from")
    syncPreferredAnchor(tool, state, "to")
end

local function selectedAnchorState(tool, state, side)
    local selectedKey = side == "from" and "from_anchor" or "to_anchor"
    local priorityKey = side == "from" and "from_priority" or "to_priority"
    local selected = string.lower(tool:GetClientInfo(selectedKey) or "")
    local selection = state.anchorSelection and state.anchorSelection[side]
    if selection and selection.convarAnchor == selected then
        return selection.anchor, selection.priority
    end

    return selected, tool:GetClientInfo(priorityKey)
end

local function gridStep(size, div)
    if size <= M.PICKING_EPSILON then return 0 end
    return size / math.max(1, div)
end

local function pickGridDivisions(size, div, minDiv, minLength)
    local defaultDiv = math.max(1, math.floor(div))
    local fallbackDiv = math.Clamp(math.floor(minDiv), 1, defaultDiv)
    local defaultStep = gridStep(size, defaultDiv)

    if defaultStep > 0 and defaultStep < minLength and fallbackDiv < defaultDiv then
        return fallbackDiv, gridStep(size, fallbackDiv), true
    end

    return defaultDiv, defaultStep, false
end

local function snapToGrid(value, minValue, maxValue, step, divisions)
    if step <= M.COMPUTE_EPSILON or divisions <= 0 then
        return minValue, 0, 0
    end

    local index = math.Clamp(math.Round((value - minValue) / step), 0, divisions)
    local snapped = math.Clamp(minValue + index * step, minValue, maxValue)
    local percent = divisions > 0 and (index / divisions) * 100 or 0

    return snapped, index, percent
end

local function faceAxisLength(face)
    if not face or not isvector(face.mins) or not isvector(face.maxs) then return 0 end

    if face.axis == 1 then
        return math.max(face.maxs.x - face.mins.x, 0)
    elseif face.axis == 2 then
        return math.max(face.maxs.y - face.mins.y, 0)
    end

    return math.max(face.maxs.z - face.mins.z, 0)
end

local function traceOnlyEntity(ent, startPos, endPos)
    if not IsValid(ent) or not isvector(startPos) or not isvector(endPos) then return end

    local tr = util.TraceLine({
        start = toVector(startPos),
        endpos = toVector(endPos),
        filter = { ent },
        whitelist = true,
        ignoreworld = true,
        mask = MASK_ALL
    })

    if tr and tr.Hit and tr.Entity == ent and isvector(tr.HitPos) then
        return tr
    end
end

local function rayBoxFaceHit(startPos, dir, mins, maxs)
    if not isvector(startPos) or not isvector(dir) or not isvector(mins) or not isvector(maxs) then return end
    if M.VectorLengthSqrPrecise(dir) < M.PICKING_VECTOR_EPSILON_SQR then return end

    local tEnter, tExit = -1e9, 1e9
    local enterAxisKey, enterSign
    local exitAxisKey, exitSign
    local axisIndex = { x = 1, y = 2, z = 3 }

    for _, axis in ipairs({ "x", "y", "z" }) do
        local s, d = comp(startPos, axis), comp(dir, axis)
        local mn, mx = comp(mins, axis), comp(maxs, axis)

        if math.abs(d) < M.PICKING_EPSILON then
            if s < mn or s > mx then
                return
            end
        else
            local nearT, nearSign, farT, farSign
            if d > 0 then
                nearT, nearSign = (mn - s) / d, -1
                farT, farSign = (mx - s) / d, 1
            else
                nearT, nearSign = (mx - s) / d, 1
                farT, farSign = (mn - s) / d, -1
            end

            if nearT > tEnter then
                tEnter = nearT
                enterAxisKey = axis
                enterSign = nearSign
            end

            if farT < tExit then
                tExit = farT
                exitAxisKey = axis
                exitSign = farSign
            end

            if tEnter > tExit then
                return
            end
        end
    end

    if tEnter >= 0 and enterAxisKey then
        return {
            axis = axisIndex[enterAxisKey],
            sign = enterSign,
            point = startPos + dir * tEnter
        }
    end

    if tExit >= 0 and exitAxisKey then
        return {
            axis = axisIndex[exitAxisKey],
            sign = exitSign,
            point = startPos + dir * tExit
        }
    end
end

local function pointNearAABBFace(localPos, mins, maxs, epsilon)
    if not isvector(localPos) or not isvector(mins) or not isvector(maxs) then return false end

    epsilon = tonumber(epsilon) or 0

    return math.abs(localPos.x - mins.x) <= epsilon
        or math.abs(localPos.x - maxs.x) <= epsilon
        or math.abs(localPos.y - mins.y) <= epsilon
        or math.abs(localPos.y - maxs.y) <= epsilon
        or math.abs(localPos.z - mins.z) <= epsilon
        or math.abs(localPos.z - maxs.z) <= epsilon
end

local function projectFacePointToProp(ent, face, localPos, worldNormal, fallbackLocalPos, fallbackWorldPos, fallbackNormal)
    if not IsValid(ent) or not face or not isvector(localPos) or not isvector(worldNormal) then
        return fallbackLocalPos, fallbackWorldPos, fallbackNormal
    end

    local outward = copyVec(worldNormal)
    if M.VectorLengthSqrPrecise(outward) < M.PICKING_VECTOR_EPSILON_SQR then
        return fallbackLocalPos, fallbackWorldPos, fallbackNormal
    end
    outward = normalizedVec(outward)
    if not outward then return fallbackLocalPos, fallbackWorldPos, fallbackNormal end

    local gridWorldPos = LocalToWorldPrecise(localPos, AngleP(0, 0, 0), ent:GetPos(), ent:GetAngles())
    local gridNormal = outward
    local backDist = FACE_TRACE_OUTSIDE_OFFSET
    local traceStart = gridWorldPos + gridNormal * backDist
    local orthogonalTrace = traceOnlyEntity(
        ent,
        traceStart,
        gridWorldPos - gridNormal * (faceAxisLength(face) + backDist + FACE_TRACE_END_OVERSHOOT)
    )

    local hitTrace = orthogonalTrace
    if not hitTrace and isvector(face.center) then
        local centerWorldPos = LocalToWorldPrecise(face.center, AngleP(0, 0, 0), ent:GetPos(), ent:GetAngles())
        hitTrace = traceOnlyEntity(ent, traceStart, centerWorldPos)
    end

    if hitTrace and isvector(hitTrace.HitPos) then
        return WorldToLocalPrecise(hitTrace.HitPos, AngleP(0, 0, 0), ent:GetPos(), ent:GetAngles()), copyVec(hitTrace.HitPos), copyVec(hitTrace.HitNormal)
    end

    return fallbackLocalPos, fallbackWorldPos, fallbackNormal
end

local function faceCandidate(ent, tr, settings, box)
    if tr.Entity ~= ent or not isvector(tr.HitPos) then return end

    local localHit = WorldToLocalPrecise(tr.HitPos, AngleP(0, 0, 0), ent:GetPos(), ent:GetAngles())
    if not box then return end

    local mins, maxs = box.mins, box.maxs
    local center = (mins + maxs) * 0.5
    local ply = LocalPlayer()
    local eye = IsValid(ply) and ply:GetShootPos() or nil
    local aim = IsValid(ply) and ply:GetAimVector() or nil
    local localEye = isvector(eye) and WorldToLocalPrecise(eye, AngleP(0, 0, 0), ent:GetPos(), ent:GetAngles()) or nil
    local localAim = isvector(eye) and isvector(aim) and (WorldToLocalPrecise(eye + aim * 16384, AngleP(0, 0, 0), ent:GetPos(), ent:GetAngles()) - localEye) or nil

    if isvector(localAim) and M.VectorLengthSqrPrecise(localAim) > M.PICKING_VECTOR_EPSILON_SQR then
        localAim = normalizedVec(localAim)
    else
        localAim = nil
    end

    local boxFaceHit = isvector(localEye) and isvector(localAim) and rayBoxFaceHit(localEye, localAim, mins, maxs) or nil
    local axis = boxFaceHit and boxFaceHit.axis or nil
    local sign = boxFaceHit and boxFaceHit.sign or nil
    local raw = boxFaceHit and boxFaceHit.point or VectorP(localHit.x, localHit.y, localHit.z)

    if not axis or not sign then
        local localNormal = WorldToLocalPrecise(tr.HitPos + tr.HitNormal, AngleP(0, 0, 0), ent:GetPos(), ent:GetAngles()) - localHit
        localNormal = normalizedVec(localNormal)
        if not localNormal then return end

        axis, sign = 1, localNormal.x >= 0 and 1 or -1
        local absX, absY, absZ = math.abs(localNormal.x), math.abs(localNormal.y), math.abs(localNormal.z)
        if absY > absX and absY > absZ then
            axis, sign = 2, localNormal.y >= 0 and 1 or -1
        elseif absZ > absX and absZ > absY then
            axis, sign = 3, localNormal.z >= 0 and 1 or -1
        end
    end

    local face = {
        axis = axis,
        sign = sign,
        mins = mins,
        maxs = maxs
    }

    local fixed, uMin, uMax, vMin, vMax, u, v, corners
    if axis == 1 then
        fixed = sign > 0 and maxs.x or mins.x
        uMin, uMax, vMin, vMax = mins.y, maxs.y, mins.z, maxs.z
        u, v = raw.y, raw.z
        corners = {
            VectorP(fixed, mins.y, mins.z),
            VectorP(fixed, maxs.y, mins.z),
            VectorP(fixed, maxs.y, maxs.z),
            VectorP(fixed, mins.y, maxs.z)
        }
    elseif axis == 2 then
        fixed = sign > 0 and maxs.y or mins.y
        uMin, uMax, vMin, vMax = mins.x, maxs.x, mins.z, maxs.z
        u, v = raw.x, raw.z
        corners = {
            VectorP(mins.x, fixed, mins.z),
            VectorP(maxs.x, fixed, mins.z),
            VectorP(maxs.x, fixed, maxs.z),
            VectorP(mins.x, fixed, maxs.z)
        }
    else
        fixed = sign > 0 and maxs.z or mins.z
        uMin, uMax, vMin, vMax = mins.x, maxs.x, mins.y, maxs.y
        u, v = raw.x, raw.y
        corners = {
            VectorP(mins.x, mins.y, fixed),
            VectorP(maxs.x, mins.y, fixed),
            VectorP(maxs.x, maxs.y, fixed),
            VectorP(mins.x, maxs.y, fixed)
        }
    end

    local localPos = VectorP(raw.x, raw.y, raw.z)
    local bestU
    local bestV
    local bestGridU
    local bestGridV
    local bestGridUId
    local bestGridVId
    local bestIndexU
    local bestIndexV
    local bestPercentU
    local bestPercentV

    if settings.shift then
        bestU = math.Clamp(u, uMin, uMax)
        bestV = math.Clamp(v, vMin, vMax)
    else
        local sizeU = uMax - uMin
        local sizeV = vMax - vMin
        local divAU, stepAU = pickGridDivisions(sizeU, settings.gridA, settings.gridAMin, settings.minLength)
        local divAV, stepAV = pickGridDivisions(sizeV, settings.gridA, settings.gridAMin, settings.minLength)
        local snapAU, indexAU, percentAU = snapToGrid(u, uMin, uMax, stepAU, divAU)
        local snapAV, indexAV, percentAV = snapToGrid(v, vMin, vMax, stepAV, divAV)
        bestU = snapAU
        bestV = snapAV
        bestGridU = nil
        bestGridV = nil
        bestGridUId = "A"
        bestGridVId = "A"
        bestIndexU, bestIndexV = indexAU, indexAV
        bestPercentU, bestPercentV = percentAU, percentAV
        local bestUDist = (u - snapAU) ^ 2
        local bestVDist = (v - snapAV) ^ 2

        face.gridA = {
            stepU = stepAU,
            stepV = stepAV,
            divU = divAU,
            divV = divAV,
            uMin = uMin,
            uMax = uMax,
            vMin = vMin,
            vMax = vMax
        }
        bestGridU = face.gridA
        bestGridV = face.gridA

        if settings.gridBEnabled then
            local divBU, stepBU = pickGridDivisions(sizeU, settings.gridB, settings.gridBMin, settings.minLength)
            local divBV, stepBV = pickGridDivisions(sizeV, settings.gridB, settings.gridBMin, settings.minLength)
            local snapBU, indexBU, percentBU = snapToGrid(u, uMin, uMax, stepBU, divBU)
            local snapBV, indexBV, percentBV = snapToGrid(v, vMin, vMax, stepBV, divBV)
            local distBU = (u - snapBU) ^ 2
            local distBV = (v - snapBV) ^ 2

            face.gridB = {
                stepU = stepBU,
                stepV = stepBV,
                divU = divBU,
                divV = divBV,
                uMin = uMin,
                uMax = uMax,
                vMin = vMin,
                vMax = vMax
            }

            if distBU < bestUDist then
                bestU = snapBU
                bestUDist = distBU
                bestGridU = face.gridB
                bestGridUId = "B"
                bestIndexU = indexBU
                bestPercentU = percentBU
            end

            if distBV < bestVDist then
                bestV = snapBV
                bestVDist = distBV
                bestGridV = face.gridB
                bestGridVId = "B"
                bestIndexV = indexBV
                bestPercentV = percentBV
            end
        end
    end

    if axis == 1 then
        localPos = VectorP(fixed, bestU, bestV)
        face.origin = VectorP(fixed, center.y, center.z)
    elseif axis == 2 then
        localPos = VectorP(bestU, fixed, bestV)
        face.origin = VectorP(center.x, fixed, center.z)
    else
        localPos = VectorP(bestU, bestV, fixed)
        face.origin = VectorP(center.x, center.y, fixed)
    end

    face.uSnap, face.vSnap = bestU, bestV
    face.snapGridU = bestGridU
    face.snapGridV = bestGridV
    face.snapGridUId = bestGridUId
    face.snapGridVId = bestGridVId
    face.snapIndexU, face.snapIndexV = bestIndexU, bestIndexV
    face.snapPercentU, face.snapPercentV = bestPercentU, bestPercentV

    face.fixed = fixed
    face.corners = corners
    face.center = center

    local worldNormal = LocalToWorldPrecise(axis == 1 and VectorP(sign, 0, 0) or axis == 2 and VectorP(0, sign, 0) or VectorP(0, 0, sign), AngleP(0, 0, 0), VectorP(0, 0, 0), ent:GetAngles())
    local worldPos = LocalToWorldPrecise(localPos, AngleP(0, 0, 0), ent:GetPos(), ent:GetAngles())
    local normal = worldNormal

    if settings.alt then
        local projectedLocalPos, projectedWorldPos, projectedNormal = projectFacePointToProp(
            ent,
            face,
            localPos,
            worldNormal,
            localHit,
            tr.HitPos,
            tr.HitNormal
        )

        if isvector(projectedLocalPos) then
            localPos = projectedLocalPos
        end
        if isvector(projectedWorldPos) then
            worldPos = projectedWorldPos
        end
        if isvector(projectedNormal) then
            normal = projectedNormal
        end
    end

    return {
        ent = ent,
        localPos = localPos,
        worldPos = worldPos,
        localNormal = localNormalFromWorld(ent, worldPos, normal),
        normal = normal,
        face = face,
        mode = settings.alt and (settings.shift and "projected_free_face" or "projected_grid")
            or settings.shift and "free_face"
            or "grid"
    }
end

local function primitiveDrawCandidate(ent, tr, box)
    if not IsValid(ent) or not tr or tr.Entity ~= ent or not isvector(tr.HitPos) then return end
    if not (M.IsPrimitive and M.IsPrimitive(ent)) then return end
    if not box or not isvector(box.mins) or not isvector(box.maxs) then return end

    local localHit = WorldToLocalPrecise(tr.HitPos, AngleP(0, 0, 0), ent:GetPos(), ent:GetAngles())
    if pointNearAABBFace(localHit, box.mins, box.maxs, PRIMITIVE_AABB_FACE_EPSILON) then return end

    return {
        ent = ent,
        localPos = localHit,
        worldPos = copyVec(tr.HitPos),
        localNormal = localNormalFromWorld(ent, tr.HitPos, tr.HitNormal),
        normal = copyVec(tr.HitNormal),
        mode = "trace"
    }
end

local function axisVectorForKey(basis, key)
    if key == "x" then
        return M.AngleForwardPrecise(basis)
    elseif key == "y" then
        return M.AngleRightPrecise(basis)
    end

    return M.AngleUpPrecise(basis)
end

local function markSnapAxis(axes, key)
    if axes and key then
        axes[key] = true
    end
end

local function mergeSnapAxes(target, source)
    if not target or type(source) ~= "table" then return target end

    if source.x then
        target.x = true
    end
    if source.y then
        target.y = true
    end
    if source.z then
        target.z = true
    end

    return target
end

local function applyHandleSnap(item, currentGizmoPos, snapLocalPos, snapAxes)
    if not item or not isvector(currentGizmoPos) or not isvector(snapLocalPos) then return currentGizmoPos end

    local out = VectorP(currentGizmoPos.x, currentGizmoPos.y, currentGizmoPos.z)
    if item.kind == "move" then
        if item.key == "x" then
            out.x = snapLocalPos.x
            markSnapAxis(snapAxes, "x")
        elseif item.key == "y" then
            out.y = snapLocalPos.y
            markSnapAxis(snapAxes, "y")
        else
            out.z = snapLocalPos.z
            markSnapAxis(snapAxes, "z")
        end

        return out
    end

    if item.kind ~= "plane" then return out end

    local first = item.key:sub(1, 1)
    local second = item.key:sub(2, 2)

    if first == "x" or second == "x" then
        out.x = snapLocalPos.x
        markSnapAxis(snapAxes, "x")
    end
    if first == "y" or second == "y" then
        out.y = snapLocalPos.y
        markSnapAxis(snapAxes, "y")
    end
    if first == "z" or second == "z" then
        out.z = snapLocalPos.z
        markSnapAxis(snapAxes, "z")
    end

    return out
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

local function snapTranslationValue(value, step, origin)
    if step <= 0 then
        return tonumber(value) or 0
    end

    local current = tonumber(value) or 0
    local base = tonumber(origin) or 0
    return base + math.Round((current - base) / step) * step
end

local function snapGizmoTranslation(item, startLocal, currentGizmoPos, step, blockedAxes)
    if not item or not isvector(currentGizmoPos) or step <= 0 then return currentGizmoPos end

    local out = VectorP(currentGizmoPos.x, currentGizmoPos.y, currentGizmoPos.z)
    local base = isvector(startLocal) and startLocal or VectorP(0, 0, 0)

    if handleUsesAxis(item, "x") and not (blockedAxes and blockedAxes.x) then
        out.x = snapTranslationValue(out.x, step, base.x)
    end
    if handleUsesAxis(item, "y") and not (blockedAxes and blockedAxes.y) then
        out.y = snapTranslationValue(out.y, step, base.y)
    end
    if handleUsesAxis(item, "z") and not (blockedAxes and blockedAxes.z) then
        out.z = snapTranslationValue(out.z, step, base.z)
    end

    return out
end

local function applyAxisSnap(out, key, snapLocalPos, snapAxes)
    if not isvector(out) or not isvector(snapLocalPos) then return out end

    if key == "x" then
        out.x = snapLocalPos.x
        markSnapAxis(snapAxes, "x")
    elseif key == "y" then
        out.y = snapLocalPos.y
        markSnapAxis(snapAxes, "y")
    else
        out.z = snapLocalPos.z
        markSnapAxis(snapAxes, "z")
    end

    return out
end

local function worldToGizmoLocal(worldPos, press)
    if not isvector(worldPos) or not press then return end

    local localPos = WorldToLocalPrecise(worldPos, AngleP(0, 0, 0), press.origin, press.basis)
    return isvector(localPos) and localPos or nil
end

local function gizmoWorldOrigin(press, currentGizmoPos)
    if not press or not isvector(currentGizmoPos) then return end

    local dragStartLocal = press.dragStartLocal or press.startLocal
    local delta = currentGizmoPos - dragStartLocal
    local worldPos = LocalToWorldPrecise(delta, AngleP(0, 0, 0), press.origin, press.basis)

    return isvector(worldPos) and worldPos or nil
end

local function gizmoTraceDirectionForAxis(press, currentGizmoPos, key)
    if not press or not press.gizmo or not isvector(currentGizmoPos) then return end
    if not handleUsesAxis(press.gizmo, key) then return end

    local dragStartLocal = press.dragStartLocal or press.startLocal
    local delta = comp(currentGizmoPos, key) - comp(dragStartLocal, key)
    if math.abs(delta) <= M.COMPUTE_EPSILON then return end

    local axis = axisVectorForKey(press.basis, key)
    if not isvector(axis) or M.VectorLengthSqrPrecise(axis) < M.COMPUTE_VECTOR_EPSILON_SQR then return end

    axis = normalizedVec(axis)
    if not axis then return end

    return delta >= 0 and axis or -axis
end

local function gizmoTraceFilter(state)
    local filter = {}
    local ply = LocalPlayer()
    local weapon = IsValid(ply) and ply:GetActiveWeapon() or nil

    if IsValid(ply) then
        filter[#filter + 1] = ply
    end
    if IsValid(weapon) then
        filter[#filter + 1] = weapon
    end
    if IsValid(state.prop1) then
        filter[#filter + 1] = state.prop1
    end
    if IsValid(state.ghost) then
        filter[#filter + 1] = state.ghost
    end

    for i = 1, #(state.linked or {}) do
        local ent = state.linked[i]
        if IsValid(ent) then
            filter[#filter + 1] = ent
        end
    end

    for _, ghost in pairs(state.linkedGhosts or {}) do
        if IsValid(ghost) then
            filter[#filter + 1] = ghost
        end
    end

    return filter
end

local function traceSnapStartWorldPos(state, press, currentGizmoPos, dir)
    return gizmoWorldOrigin(press, currentGizmoPos)
end

local function traceSnapWorldPos(startPos, dir, traceLength, filter)
    if not isvector(startPos) or not isvector(dir) or M.VectorLengthSqrPrecise(dir) < M.PICKING_VECTOR_EPSILON_SQR or traceLength <= 0 then return end

    local traceDir = normalizedVec(dir)
    if not traceDir then return end

    local tr = util.TraceLine({
        start = toVector(startPos),
        endpos = toVector(startPos + traceDir * traceLength),
        filter = filter
    })
    if not tr then return end

    local fractionLeftSolid = tonumber(tr.FractionLeftSolid) or 0
    if tr.StartSolid or tr.AllSolid then
        if not tr.AllSolid and fractionLeftSolid > 0 then
            return startPos + traceDir * (traceLength * fractionLeftSolid), tr
        end

        return nil, tr
    end

    if tr.Hit and isvector(tr.HitPos) then
        return copyVec(tr.HitPos), tr
    end
end

local function traceSnapAxisResult(origin, dir, traceLength, filter)
    if not isvector(origin) or not isvector(dir) or M.VectorLengthSqrPrecise(dir) < M.PICKING_VECTOR_EPSILON_SQR or traceLength <= 0 then return end

    local traceDir = normalizedVec(dir)
    if not traceDir then return end

    local limit = traceLength * traceLength + M.UI_COMPARE_EPSILON

    local positiveWorldPos, positiveTrace = traceSnapWorldPos(origin, traceDir, traceLength, filter)
    local positiveHit = isvector(positiveWorldPos) and positiveWorldPos:DistToSqr(origin) <= limit

    local negativeDir = -traceDir
    local negativeWorldPos, negativeTrace = traceSnapWorldPos(origin, negativeDir, traceLength, filter)
    local negativeHit = isvector(negativeWorldPos) and negativeWorldPos:DistToSqr(origin) <= limit

    local worldPos
    local side
    if positiveHit then
        worldPos = positiveWorldPos
        side = "positive"
    elseif negativeHit then
        worldPos = negativeWorldPos
        side = "negative"
    end

    return {
        direction = traceDir,
        positiveHit = positiveHit == true,
        positiveWorldPos = positiveHit and copyVec(positiveWorldPos) or nil,
        positiveTrace = positiveHit and positiveTrace or nil,
        negativeHit = negativeHit == true,
        negativeWorldPos = negativeHit and copyVec(negativeWorldPos) or nil,
        negativeTrace = negativeHit and negativeTrace or nil,
        hit = positiveHit or negativeHit,
        worldPos = isvector(worldPos) and copyVec(worldPos) or nil,
        side = side,
        trace = side == "positive" and positiveTrace or side == "negative" and negativeTrace or nil
    }
end

local function traceSnapFromGizmo(state, press, currentGizmoPos, traceLength)
    if not press or not press.gizmo or traceLength <= 0 then
        if press then
            press.traceSnapAxes = nil
            press.lastTraceSnapHit = nil
        end
        return
    end
    if press.gizmo.kind ~= "move" and press.gizmo.kind ~= "plane" then
        press.traceSnapAxes = nil
        press.lastTraceSnapHit = nil
        return
    end

    local filter = gizmoTraceFilter(state)
    local snapped = VectorP(currentGizmoPos.x, currentGizmoPos.y, currentGizmoPos.z)
    local didSnap = false
    local snappedAxes = {}
    local traceSnapAxes = {}
    local lastTraceSnapHit
    local function snapAxis(key)
        local direction = gizmoTraceDirectionForAxis(press, currentGizmoPos, key)
        if not isvector(direction) or M.VectorLengthSqrPrecise(direction) < M.PICKING_VECTOR_EPSILON_SQR then return end

        local traceStart = traceSnapStartWorldPos(state, press, currentGizmoPos, direction)
        if not isvector(traceStart) then return end

        local axisResult = traceSnapAxisResult(traceStart, direction, traceLength, filter)
        if not axisResult then return end

        local snapWorldPos = axisResult.worldPos
        axisResult.start = copyVec(traceStart)
        traceSnapAxes[key] = axisResult
        if not isvector(snapWorldPos) then return end

        local snapLocalPos = worldToGizmoLocal(snapWorldPos, press)
        if not snapLocalPos then return end

        lastTraceSnapHit = {
            key = key,
            worldPos = copyVec(snapWorldPos),
            trace = axisResult.trace
        }
        applyAxisSnap(snapped, key, snapLocalPos, snappedAxes)
        didSnap = true
    end

    snapAxis("x")
    snapAxis("y")
    snapAxis("z")

    press.traceSnapAxes = next(traceSnapAxes) and traceSnapAxes or nil
    press.lastTraceSnapHit = didSnap and lastTraceSnapHit or nil

    return didSnap and snapped or nil, didSnap and snappedAxes or nil
end

local function snapGizmoPosition(state, press, currentGizmoPos)
    if not press or not press.gizmo or not isvector(currentGizmoPos) then return currentGizmoPos end

    local translationStep = state.hover and state.hover.settings and state.hover.settings.translationSnap or 0
    local priorityAxes = {}
    local function snapToTranslation(localPos)
        if not isvector(localPos) or translationStep <= 0 then return localPos end
        -- Grid-, Anchor- und Trace-Snaps duerfen die bereits festgelegten Achsen
        -- behalten; Translation-Snap ergaenzt nur noch die restlichen Gizmo-Achsen.
        return snapGizmoTranslation(press.gizmo, press.dragStartLocal, localPos, translationStep, priorityAxes)
    end

    local function snapToWorldPos(worldPos)
        if not isvector(worldPos) then return end

        local snapLocalPos = worldToGizmoLocal(worldPos, press)
        if not snapLocalPos then return end

        return applyHandleSnap(press.gizmo, currentGizmoPos, snapLocalPos, priorityAxes)
    end

    local suppressShiftSnap = (state.hover and state.hover.settings and state.hover.settings.shift)
        or input.IsKeyDown(KEY_LSHIFT)
        or input.IsKeyDown(KEY_RSHIFT)

    if suppressShiftSnap then
        press.traceSnapAxes = nil
        press.lastTraceSnapHit = nil
    end

    local hoverPointIsWorld = state.hover and state.hover.point and isWorldTarget(state.hover.ent)
    if not suppressShiftSnap and not hoverPointIsWorld and state.hover and state.hover.point and isvector(state.hover.point.worldPos) then
        press.traceSnapAxes = nil
        press.lastTraceSnapHit = nil
        return snapToTranslation(snapToWorldPos(state.hover.point.worldPos) or currentGizmoPos)
    end

    local hoverCandidate = state.hover and (state.hover.candidate or state.hover.overlay)
    local traceLength = state.hover and state.hover.settings and state.hover.settings.traceSnapLength or 0
    local hoverCandidateIsWorld = hoverCandidate and isWorldTarget(hoverCandidate.ent)

    if hoverCandidate and isvector(hoverCandidate.worldPos) then
        if not suppressShiftSnap and traceLength > 0 then
            traceSnapFromGizmo(state, press, currentGizmoPos, traceLength)
        else
            press.traceSnapAxes = nil
            press.lastTraceSnapHit = nil
        end

        if not hoverCandidateIsWorld then
            return snapToTranslation(snapToWorldPos(hoverCandidate.worldPos) or currentGizmoPos)
        end
    end

    if suppressShiftSnap then
        return currentGizmoPos
    end

    local traceSnapPos, traceSnapAxes = traceSnapFromGizmo(state, press, currentGizmoPos, traceLength)
    if traceSnapPos then
        mergeSnapAxes(priorityAxes, traceSnapAxes)
        return snapToTranslation(traceSnapPos)
    end

    return snapToTranslation(currentGizmoPos)
end

local function hoverPoint(ent, points)
    local x, y = ScrW() * 0.5, ScrH() * 0.5
    local best, bestDist

    for i = 1, #points do
        local world = worldPosFromLocalPoint(ent, points[i])
        if isvector(world) then
            local screen = world:ToScreen()
            if screen.visible then
                local dist = (screen.x - x) ^ 2 + (screen.y - y) ^ 2
                if not bestDist or dist < bestDist then
                    best = { index = i, worldPos = world, screen = screen }
                    bestDist = dist
                end
            end
        end
    end

    if bestDist and bestDist <= 196 then
        return best
    end
end

local function cornerCandidate(ent, samples, minLength, box, probes)
    if #samples < 2 then return end

    local travelled = 0
    local lastWorldPos = sampleWorldPos(ent, samples[1])
    for i = 2, #samples do
        local worldPos = sampleWorldPos(ent, samples[i])
        if isvector(lastWorldPos) and isvector(worldPos) then
            travelled = travelled + lastWorldPos:Distance(worldPos)
        end
        lastWorldPos = worldPos or lastWorldPos
    end
    if travelled < minLength then return end

    probes = istable(probes) and probes or aggregateTraceProbes(samples)
    if #probes < 2 then return end

    local selected = {}
    for i = 1, math.min(#probes, 3) do
        selected[i] = probes[i]
    end

    if #selected >= 3 then
        local a, b, c = selected[1], selected[2], selected[3]
        local cross23 = b.localNormal:Cross(c.localNormal)
        local denom = a.localNormal:Dot(cross23)

        if math.abs(denom) > M.COMPUTE_EPSILON then
            local localPos = (cross23 * a.planeDistance
                + c.localNormal:Cross(a.localNormal) * b.planeDistance
                + a.localNormal:Cross(b.localNormal) * c.planeDistance) / denom

            if not box or M.PointInsideAABB(localPos, box.mins, box.maxs) then
                local localNormal = normalizedVec(a.localNormal + b.localNormal + c.localNormal) or normalizedVec(a.localNormal)
                local candidate = buildTraceProbeCandidate(ent, localPos, localNormal, "corner", selected)
                if candidate then
                    return candidate
                end
            end
        end
    end

    local a, b = selected[1], selected[2]
    local rawAxis = a.localNormal:Cross(b.localNormal)
    local axisLengthSqr = rawAxis:LengthSqr()
    if axisLengthSqr < M.COMPUTE_VECTOR_EPSILON_SQR then return end

    local axisLocalDir = rawAxis / math.sqrt(axisLengthSqr)
    local axisBase = ((b.localNormal * a.planeDistance - a.localNormal * b.planeDistance):Cross(rawAxis)) / axisLengthSqr
    local totalCount = math.max(a.count + b.count, 1)
    local referencePos = (a.localPos * a.count + b.localPos * b.count) / totalCount
    local localPos = axisBase + axisLocalDir * axisLocalDir:Dot(referencePos - axisBase)

    if box and not M.PointInsideAABB(localPos, box.mins, box.maxs) then
        local midpoint = referencePos
        localPos = axisBase + axisLocalDir * axisLocalDir:Dot(midpoint - axisBase)
        if not M.PointInsideAABB(localPos, box.mins, box.maxs) then
            return
        end
    end

    local localNormal = normalizedVec(a.localNormal + b.localNormal) or normalizedVec(a.localNormal)
    return buildTraceProbeCandidate(ent, localPos, localNormal, "edge", selected, axisLocalDir)
end

local function referenceBasisFor(space, preview, solve, prop2)
    if preview.referenceBasis and preview.referenceBasis[space] then
        return preview.referenceBasis[space]
    elseif space == "world" then
        return AngleP(0, 0, 0)
    elseif space == "prop2" and isWorldTarget(prop2) then
        return AngleP(0, 0, 0)
    elseif space == "prop2" and IsValid(prop2) then
        return copyAng(prop2:GetAngles())
    elseif space == "points" and solve then
        if solve.pointsLocalAng then
            local _, worldAng = LocalToWorldPrecise(VectorP(0, 0, 0), solve.pointsLocalAng, VectorP(0, 0, 0), preview.ang)
            return worldAng or preview.ang
        end

        return solve.pointsWorldAng or preview.ang
    end

    return preview.ang
end

local function gizmoBasisFor(space, preview, solve, prop2)
    if preview.spaceBasis and preview.spaceBasis[space] then
        return preview.spaceBasis[space]
    end

    return referenceBasisFor(space, preview, solve, prop2)
end

local function gizmo(tool, state)
    local worldPoints = worldPointsApi()
    if worldPoints and isfunction(worldPoints.getGizmo) then
        local worldPointGizmo = worldPoints.getGizmo(tool, state)
        if worldPointGizmo then
            return worldPointGizmo
        end
    end
    if worldPoints and isfunction(worldPoints.shouldSuppressDefaultGizmo) and worldPoints.shouldSuppressDefaultGizmo(state) then
        return
    end

    local preview = state.preview
    if not preview or not preview.solve then return end

    local space = tool:GetClientInfo("space")
    local press = state.press
    local origin = LocalToWorldPrecise(preview.solve.sourceAnchorLocal, AngleP(0, 0, 0), preview.pos, preview.ang)
    local basis = gizmoBasisFor(space, preview, preview.solve, state.prop2)
    local referenceBasis = referenceBasisFor(space, preview, preview.solve, state.prop2)
    local size = math.Clamp(IsValid(state.prop1) and state.prop1:BoundingRadius() * 0.42 or 32, 18, 72)
    local planeOffset = size * 0.2
    local ringRadius = size * 0.82
    local pickRadius = math.max(324, size * size * 0.18)
    local ringPadding = 0.5
    local x, y = ScrW() * 0.5, ScrH() * 0.5
    local eye = LocalPlayer():GetShootPos()
    local dir = LocalPlayer():GetAimVector()

    if press and press.kind == "gizmo" and press.space == space and press.gizmo and press.gizmo.kind == "rot" then
        origin = press.origin
        basis = press.basis
        referenceBasis = press.referenceBasis
    end

    local basisForward, basisRight, basisUp = M.AngleAxesPrecise(basis)
    local function originOffset(axis, distance)
        return M.AddVectorsPrecise(origin, M.ScaleVectorPrecise(axis, distance))
    end

    local handles = {
        { kind = "move", key = "x", color = colors.x, a = origin, b = originOffset(basisForward, size) },
        { kind = "move", key = "y", color = colors.y, a = origin, b = originOffset(basisRight, size) },
        { kind = "move", key = "z", color = colors.z, a = origin, b = originOffset(basisUp, size) },
        { kind = "plane", key = "xy", color = colors.xy, center = M.AddVectorsPrecise(originOffset(basisForward, planeOffset), M.ScaleVectorPrecise(basisRight, planeOffset)) },
        { kind = "plane", key = "xz", color = colors.xz, center = M.AddVectorsPrecise(originOffset(basisForward, planeOffset), M.ScaleVectorPrecise(basisUp, planeOffset)) },
        { kind = "plane", key = "yz", color = colors.yz, center = M.AddVectorsPrecise(originOffset(basisRight, planeOffset), M.ScaleVectorPrecise(basisUp, planeOffset)) },
        { kind = "rot", key = "roll", axis = basisForward, color = colors.x },
        { kind = "rot", key = "pitch", axis = basisRight, color = colors.y },
        { kind = "rot", key = "yaw", axis = basisUp, color = colors.z }
    }

    local best, bestDist
    local function take(item, dist)
        if dist and dist < pickRadius and (not bestDist or dist < bestDist) then
            best = item
            bestDist = dist
        end
    end

    for i = 1, 3 do
        local b = handles[i].b:ToScreen()
        if b.visible then
            take(handles[i], (x - b.x) ^ 2 + (y - b.y) ^ 2)
        end
    end

    for i = 4, 6 do
        local p = handles[i].center:ToScreen()
        if p.visible then
            take(handles[i], (x - p.x) ^ 2 + (y - p.y) ^ 2)
        end
    end

    for i = 7, 9 do
        local item = handles[i]
        local _, localPos = M.LinePlaneIntersection(dir, eye, item.axis, origin, basis)
        if localPos then
            local u, v = ringCoords(item.key, localPos)
            item.cursorAngle = math.deg(ringAngle(item.key, localPos))
            local dist = math.abs(math.sqrt(u * u + v * v) - ringRadius)
            if dist <= ringPadding then
                take(item, dist)
            end
        end
    end

    return {
        origin = origin,
        basis = basis,
        referenceBasis = referenceBasis,
        size = size,
        planeOffset = planeOffset,
        ringRadius = ringRadius,
        ringPadding = ringPadding,
        hover = press and press.kind == "gizmo" and press.space == space and press.gizmo or best,
        space = space
    }
end

local function solvePreview(tool, state)
    if not IsValid(state.prop1) then
        state.preview = nil
        state.pending = nil
        return
    end

    local sourceAnchorOptions = M.AnchorOptionsFromReader(function(name)
        return tool:GetClientInfo(name)
    end, "from")
    local targetAnchorOptions = M.AnchorOptionsFromReader(function(name)
        return tool:GetClientInfo(name)
    end, "to")
    local sourceAnchorId, sourcePriority = selectedAnchorState(tool, state, "from")
    local targetAnchorId, targetPriority = selectedAnchorState(tool, state, "to")

    local solve = M.Solve(
        state.prop1,
        state.source,
        state.prop2,
        state.target,
        sourceAnchorId,
        sourcePriority,
        targetAnchorId,
        targetPriority,
        sourceAnchorOptions,
        targetAnchorOptions
    )

    if not solve then
        state.preview = nil
        state.pending = nil
        return
    end

    local rawPos, rawAng, spaceBasis, referenceBasis = M.ComposePose(solve, offsets(tool), state.prop2)
    local pos, ang = rawPos, rawAng
    local linkedPreview = {}
    local sourcePos = copyVec(state.prop1:GetPos())
    local sourceAng = copyAng(state.prop1:GetAngles())

    for i = 1, #state.linked do
        local ent = state.linked[i]
        if IsValid(ent) and ent ~= state.prop1 and ent ~= state.prop2 and M.IsProp(ent) then
            local worldPos, worldAng = M.TransformPoseRelativePrecise(ent:GetPos(), ent:GetAngles(), sourcePos, sourceAng, pos, ang)
            if isvector(worldPos) and isangle(worldAng) then
                linkedPreview[#linkedPreview + 1] = {
                    ent = ent,
                    pos = worldPos,
                    ang = worldAng
                }
            end
        end
    end

    state.preview = {
        solve = solve,
        pos = pos,
        ang = ang,
        spaceBasis = spaceBasis,
        referenceBasis = referenceBasis,
        basePos = rawPos,
        baseAng = rawAng,
        linked = linkedPreview
    }
end

local function ensureGhost(state)
    if not state.preview or not IsValid(state.prop1) then
        hideGhosts(state)
        return
    end

    if setCompatGhost(state, state.prop1, state.preview.pos, state.preview.ang, ghostAlpha, false) then
        if IsValid(state.ghost) then
            state.ghost:SetNoDraw(true)
        end
    else
        clearCompatGhost(state)

        local model = state.prop1:GetModel()
        state.ghost = ensureGhostModel(state.ghost, model)
        if not IsValid(state.ghost) then return end

        applyGhostAppearance(state.ghost, state.prop1, state.preview.pos, state.preview.ang, ghostAlpha)
    end

    local activeLinked = {}
    for i = 1, #(state.preview.linked or {}) do
        local preview = state.preview.linked[i]
        if IsValid(preview.ent) then
            activeLinked[preview.ent] = true

            if setCompatGhost(state, preview.ent, preview.pos, preview.ang, linkedGhostAlpha, true) then
                local ghost = state.linkedGhosts[preview.ent]
                if IsValid(ghost) then
                    ghost:SetNoDraw(true)
                end
            else
                clearCompatGhost(state, preview.ent)

                local ghost = ensureGhostModel(state.linkedGhosts[preview.ent], preview.ent:GetModel())
                state.linkedGhosts[preview.ent] = ghost
                if IsValid(ghost) then
                    applyGhostAppearance(ghost, preview.ent, preview.pos, preview.ang, linkedGhostAlpha)
                end
            end
        end
    end

    for ent, ghost in pairs(state.linkedGhosts) do
        if not activeLinked[ent] then
            if IsValid(ghost) then
                ghost:SetNoDraw(true)
            end

            if not IsValid(ent) or not isLinkedProp(state, ent) then
                removeLinkedGhost(state, ent)
            end
        end
    end

    local compatLinked = state.compatGhosts and state.compatGhosts.linked or nil
    if istable(compatLinked) then
        for ent in pairs(compatLinked) do
            if not activeLinked[ent] then
                clearCompatGhost(state, ent)
            end
        end
    end
end

local function hoverState(tool, state)
    local tr = LocalPlayer():GetEyeTrace()
    local settings = cfg(tool)
    local hover = { trace = tr, settings = settings }
    local side, ent, points = editable(state, tr.Entity, tr)

    if IsValid(state.prop1) then requestBounds(state, state.prop1) end
    if IsValid(state.prop2) then requestBounds(state, state.prop2) end

    if state.preview then
        hover.gizmo = gizmo(tool, state)
    end

    if side and ent then
        hover.side = side
        hover.points = points
        hover.ent = ent

        if traceMatchesEntity(tr, ent) then
            hover.point = hoverPoint(ent, points)

            if isWorldTarget(ent) then
                hover.candidate = traceCandidate(ent, tr)
            else
                hover.box = boundsFor(state, ent)
                hover.candidate = faceCandidate(ent, tr, settings, hover.box)
            end
        end
    end

    if not IsValid(state.prop1) and M.IsProp(tr.Entity) then
        hover.pickSource = tr.Entity
    elseif not hasTargetEntity(state.prop2)
        and #state.source > 0
        and ((M.IsProp(tr.Entity) and tr.Entity ~= state.prop1 and not isLinkedProp(state, tr.Entity))
            or (settings.worldTarget and traceHitsWorld(tr))) then
        hover.pickTarget = M.IsProp(tr.Entity) and tr.Entity or M.WORLD_TARGET
    end

    if not hover.candidate and M.IsProp(tr.Entity) then
        requestBounds(state, tr.Entity)
        hover.overlayBox = boundsFor(state, tr.Entity)
        hover.overlay = faceCandidate(tr.Entity, tr, settings, hover.overlayBox)
    elseif not hover.candidate and not hover.overlay and settings.worldTarget and traceHitsWorld(tr) and not hasTargetEntity(state.prop2) and #state.source > 0 then
        hover.overlay = traceCandidate(M.WORLD_TARGET, tr)
    end

    return hover
end

local function pendingPreview(tool, state)
    state.pending = nil

    if not state.hover or state.hover.side ~= "target" or state.hover.point or not state.hover.candidate or #state.target >= M.MAX_POINTS then
        return
    end

    local points = M.CopyPoints(state.target)
    points[#points + 1] = pointFromCandidate(state.hover.candidate)

    local sourceAnchorOptions = M.AnchorOptionsFromReader(function(name)
        return tool:GetClientInfo(name)
    end, "from")
    local targetAnchorOptions = M.AnchorOptionsFromReader(function(name)
        return tool:GetClientInfo(name)
    end, "to")
    local sourceAnchorId, sourcePriority = selectedAnchorState(tool, state, "from")
    local targetAnchorId, targetPriority = selectedAnchorState(tool, state, "to")

    local solve = M.Solve(
        state.prop1,
        state.source,
        state.prop2,
        points,
        sourceAnchorId,
        sourcePriority,
        targetAnchorId,
        targetPriority,
        sourceAnchorOptions,
        targetAnchorOptions
    )

    if solve then
        local rawPos, rawAng, spaceBasis, referenceBasis = M.ComposePose(solve, offsets(tool), state.prop2)
        state.pending = {
            solve = solve,
            pos = rawPos,
            ang = rawAng,
            spaceBasis = spaceBasis,
            referenceBasis = referenceBasis
        }
    end
end

local function writeCommitPoints(points)
    points = istable(points) and points or {}

    net.WriteUInt(#points, 2)
    for i = 1, #points do
        net.WritePreciseVector(points[i])
    end
end

local function beginCommitUpload(tool, payload, keepSession)
    if istable(M.CommitUpload) and not M.CommitUpload.finishedAt then return false end

    local linked = istable(payload.linked) and payload.linked or {}
    local chunkSize = M.GetCommitLinkedPartSize()
    local totalParts = math.ceil(#linked / chunkSize)

    M._nextCommitUploadId = (tonumber(M._nextCommitUploadId) or 0) + 1
    M.CommitUpload = {
        id = M._nextCommitUploadId,
        tool = tool,
        payload = payload,
        linked = linked,
        keepSession = keepSession == true,
        chunkSize = chunkSize,
        totalParts = totalParts,
        partIndex = 0,
        phase = "begin",
        progress = 0,
        startedAt = RealTime()
    }

    return true
end

local function setCommitUploadProgress(upload, step)
    local totalSteps = (upload.totalParts or 0) + 2
    upload.progress = math.Clamp((tonumber(step) or 0) / math.max(totalSteps, 1), 0, 1)
    upload.updatedAt = RealTime()
end

local function sendCommitUploadStep()
    local upload = M.CommitUpload
    if not istable(upload) then return end

    if upload.finishedAt then
        if RealTime() - upload.finishedAt > 0.45 then
            M.CommitUpload = nil
        end
        return
    end

    local payload = upload.payload
    if not istable(payload) then
        M.CommitUpload = nil
        return
    end

    if upload.phase == "begin" then
        net.Start(M.NET)
            net.WriteUInt(upload.id, 32)
            net.WriteEntity(payload.prop1)
            net.WriteEntity(IsValid(payload.prop2) and payload.prop2 or NULL)
            net.WriteEntity(payload.toolEnt)
            net.WritePreciseVector(payload.pos)
            net.WritePreciseAngle(payload.ang)
            writeCommitPoints(payload.source)
            writeCommitPoints(payload.target)
            net.WriteUInt(#upload.linked, 8)
            net.WriteBool(payload.weld)
            net.WriteBool(payload.nocollide)
            net.WriteBool(payload.parent)
            net.WriteUInt(payload.mode, 2)
        net.SendToServer()

        upload.phase = upload.totalParts > 0 and "parts" or "finish"
        setCommitUploadProgress(upload, 1)
        return
    end

    if upload.phase == "parts" then
        upload.partIndex = upload.partIndex + 1

        local startIndex = (upload.partIndex - 1) * upload.chunkSize + 1
        local endIndex = math.min(startIndex + upload.chunkSize - 1, #upload.linked)
        local count = math.max(endIndex - startIndex + 1, 0)

        net.Start(M.NET_COMMIT_LINKED_PART)
            net.WriteUInt(upload.id, 32)
            net.WriteUInt(upload.partIndex, 8)
            net.WriteUInt(upload.totalParts, 8)
            net.WriteUInt(count, 8)
            for i = startIndex, endIndex do
                net.WriteEntity(upload.linked[i])
            end
        net.SendToServer()

        if upload.partIndex >= upload.totalParts then
            upload.phase = "finish"
        end

        setCommitUploadProgress(upload, upload.partIndex + 1)
        return
    end

    net.Start(M.NET_COMMIT_FINISH)
        net.WriteUInt(upload.id, 32)
    net.SendToServer()

    setCommitUploadProgress(upload, (upload.totalParts or 0) + 2)
    upload.finishedAt = RealTime()

    if not upload.keepSession then
        resetClientSession(upload.tool)
    end
end

hook.Remove("Think", "MagicAlignCommitUpload")
hook.Add("Think", "MagicAlignCommitUpload", sendCommitUploadStep)

local function commit(tool, state)
    if not state.preview or not IsValid(state.prop1) then return end

    cleanupLinkedProps(state)

    local linked = {}
    local maxLinked = M.GetMaxLinkedProps()
    for i = 1, math.min(#state.linked, maxLinked) do
        local ent = state.linked[i]
        if IsValid(ent) and ent ~= state.prop1 and ent ~= state.prop2 and M.IsProp(ent) then
            linked[#linked + 1] = ent
        end
    end

    local mode, keepSession = commitMode()
    local weldOnCommit = tool:GetClientNumber("weld") == 1
    local nocollideOnCommit = weldOnCommit or tool:GetClientNumber("nocollide") == 1

    beginCommitUpload(tool, {
        prop1 = state.prop1,
        prop2 = isWorldTarget(state.prop2) and nil or state.prop2,
        toolEnt = LocalPlayer():GetActiveWeapon(),
        pos = state.preview.pos,
        ang = state.preview.ang,
        source = M.CopyPoints(state.source),
        target = isWorldTarget(state.prop2) and {} or M.CopyPoints(state.target),
        linked = linked,
        weld = weldOnCommit,
        nocollide = nocollideOnCommit,
        parent = tool:GetClientNumber("parent") == 1,
        mode = mode
    }, keepSession)
end

local function useCandidate(state, side, candidate, index)
    if not candidate then return end

    local points = side == "source" and state.source or state.target
    local point = pointFromCandidate(candidate)
    if not point then return end

    if index then
        points[index] = point
    elseif #points < M.MAX_POINTS then
        points[#points + 1] = point
    end

    M.RefreshState(state)
end

function traceCandidate(ent, tr)
    if not hasTargetEntity(ent) or not tr or not traceMatchesEntity(tr, ent) or not isvector(tr.HitPos) then return end

    local localPos = localPointFromWorldPos(ent, tr.HitPos)
    if not isvector(localPos) then return end

    return {
        ent = ent,
        localPos = localPos,
        worldPos = copyVec(tr.HitPos),
        localNormal = localNormalFromWorld(ent, tr.HitPos, tr.HitNormal),
        normal = copyVec(tr.HitNormal),
        mode = "trace"
    }
end

local function hoverPickCandidate(hover)
    local candidate = hover and (hover.candidate or hover.overlay) or nil
    if not istable(candidate) then return end

    return candidate
end

local function drawPressCandidate(kind, ent, hover)
    if not hasTargetEntity(ent) or not hover or not hover.trace then return end
    return traceCandidate(ent, hover.trace)
end

local function pickCandidateForPress(press, hover)
    if not press or not hover then return end

    if not press.drawActive then
        local candidate = hoverPickCandidate(hover)
        if candidate and candidate.ent == press.ent then
            return candidate
        end
    end

    if press.kind == "pick" then
        return drawPressCandidate("pick", press.ent, hover)
    elseif press.kind == "select_source_pick" or press.kind == "select_target_pick" then
        return drawPressCandidate(press.kind, press.ent, hover)
    end
end

local function beginPickPress(kind, side, ent, hover)
    if not hasTargetEntity(ent) or not hover or not hover.trace then return end

    local clickCandidate = hoverPickCandidate(hover)
    if clickCandidate and clickCandidate.ent ~= ent then
        clickCandidate = nil
    end

    local drawCandidate = drawPressCandidate(kind, ent, hover)
    local candidate = clickCandidate or drawCandidate
    if not candidate then return end

    local firstSample = buildTraceSample(ent, hover.trace.HitPos, hover.trace.HitNormal, hover.trace)

    return {
        kind = kind,
        side = side,
        ent = ent,
        clickCandidate = clickCandidate,
        currentCandidate = candidate,
        drawDistance = 0,
        drawActive = false,
        samples = firstSample and { firstSample } or {},
        aggregatedProbes = firstSample and aggregateTraceProbes({ firstSample }) or {}
    }
end

local function beginGizmoDrag(tool, state, handle)
    if not handle or not handle.hover then return end

    local ply = LocalPlayer()
    local eye = ply:GetShootPos()
    local dir = ply:GetAimVector()
    local origin = handle.origin
    local basis = handle.basis
    local item = handle.hover
    local normal = item.axis
    local basisForward, basisRight, basisUp = M.AngleAxesPrecise(basis)

    if item.kind == "move" then
        local axis = item.key == "x" and basisForward or item.key == "y" and basisRight or basisUp
        local toEye = normalizedVec(M.SubtractVectorsPrecise(eye, origin))
        normal = toEye and M.CrossVectorsPrecise(M.CrossVectorsPrecise(axis, toEye), axis) or nil
        if not normal or M.VectorLengthSqrPrecise(normal) < M.PICKING_VECTOR_EPSILON_SQR then
            normal = M.CrossVectorsPrecise(M.CrossVectorsPrecise(axis, VectorP(0, 0, 1)), axis)
        end
    elseif item.kind == "plane" then
        local a = item.key == "xy" and basisForward or item.key == "xz" and basisForward or basisRight
        local b = item.key == "xy" and basisRight or item.key == "xz" and basisUp or basisUp
        normal = M.CrossVectorsPrecise(a, b)
        if M.DotVectorsPrecise(normal, M.SubtractVectorsPrecise(eye, origin)) < 0 then normal = -normal end
    end

    normal = normalizedVec(normal)
    if not normal then return end

    if item.kind == "move" or item.kind == "plane" then
        local lookDir = M.SubtractVectorsPrecise(origin, eye)
        if M.VectorLengthSqrPrecise(lookDir) > M.PICKING_VECTOR_EPSILON_SQR then
            setPlayerViewAngles(ply, lookDir:Angle())
            dir = normalizedVec(lookDir) or dir
        end
    end

    local worldPos, localPos = M.LinePlaneIntersection(dir, eye, normal, origin, basis)
    if not worldPos or not localPos then return end

    state.press = {
        kind = "gizmo",
        gizmo = item,
        origin = copyVec(origin),
        basis = copyAng(basis),
        referenceBasis = copyAng(handle.referenceBasis),
        normal = copyVec(normal),
        startWorld = copyVec(worldPos),
        startLocal = copyVec(localPos),
        dragStartLocal = (item.kind == "move" or item.kind == "plane") and VectorP(0, 0, 0) or copyVec(localPos),
        currentGizmoPos = (item.kind == "move" or item.kind == "plane") and VectorP(0, 0, 0) or nil,
        start = {
            x = clientNumber(tool, handle.space .. "_px", 0),
            y = clientNumber(tool, handle.space .. "_py", 0),
            z = clientNumber(tool, handle.space .. "_pz", 0),
            pitch = clientNumber(tool, handle.space .. "_pitch", 0),
            yaw = clientNumber(tool, handle.space .. "_yaw", 0),
            roll = clientNumber(tool, handle.space .. "_roll", 0)
        },
        startRingAngle = item.kind == "rot" and ringAngle(item.key, localPos) or nil,
        currentRingAngle = item.kind == "rot" and math.deg(ringAngle(item.key, localPos)) or nil,
        referenceDelta = VectorP(0, 0, 0),
        rotationDelta = 0,
        space = handle.space
    }
end

local function setReferencePositionFromGizmoCoords(press, startGizmoPos, currentGizmoPos)
    -- DragContext = virtuelle Ebene des aktiven Gizmos im Weltspace.
    -- `LocalToLocal` ist hier fuer Koordinaten gedacht, nicht fuer einen schon
    -- vorher gebildeten Delta-Vektor. Deshalb rechnen wir Start- und Zielpunkt
    -- erst getrennt vom Gizmo-Raum in den Referenzraum und bilden das Delta dort.
    local startRef = M.LocalToLocal(startGizmoPos, AngleP(0, 0, 0), VectorP(0, 0, 0), press.basis, VectorP(0, 0, 0), press.referenceBasis)
    local currentRef = M.LocalToLocal(currentGizmoPos, AngleP(0, 0, 0), VectorP(0, 0, 0), press.basis, VectorP(0, 0, 0), press.referenceBasis)
    if not isvector(startRef) or not isvector(currentRef) then return end

    local deltaRef = currentRef - startRef

    setValue(press.space, "px", press.start.x + deltaRef.x)
    setValue(press.space, "py", press.start.y + deltaRef.y)
    setValue(press.space, "pz", press.start.z + deltaRef.z)

    return deltaRef
end

local function updateGizmo(tool, state)
    local press = state.press
    if not press or press.kind ~= "gizmo" then return end

    local eye = LocalPlayer():GetShootPos()
    local dir = LocalPlayer():GetAimVector()
    local _, localPos = M.LinePlaneIntersection(dir, eye, press.normal, press.origin, press.basis)
    if not localPos then return end

    local dragStartLocal = press.dragStartLocal or press.startLocal

    if press.gizmo.kind == "move" then
        local key = press.gizmo.key
        local currentGizmoPos = VectorP(dragStartLocal.x, dragStartLocal.y, dragStartLocal.z)

        if key == "x" then
            currentGizmoPos.x = localPos.x
        elseif key == "y" then
            currentGizmoPos.y = localPos.y
        else
            currentGizmoPos.z = localPos.z
        end

        currentGizmoPos = snapGizmoPosition(state, press, currentGizmoPos)
        press.currentGizmoPos = copyVec(currentGizmoPos)
        press.referenceDelta = setReferencePositionFromGizmoCoords(press, dragStartLocal, currentGizmoPos) or press.referenceDelta
        press.rotationDelta = 0
    elseif press.gizmo.kind == "plane" then
        local first = press.gizmo.key:sub(1, 1)
        local second = press.gizmo.key:sub(2, 2)
        local currentGizmoPos = VectorP(dragStartLocal.x, dragStartLocal.y, dragStartLocal.z)

        if first == "x" or second == "x" then
            currentGizmoPos.x = localPos.x
        end
        if first == "y" or second == "y" then
            currentGizmoPos.y = localPos.y
        end
        if first == "z" or second == "z" then
            currentGizmoPos.z = localPos.z
        end

        currentGizmoPos = snapGizmoPosition(state, press, currentGizmoPos)
        press.currentGizmoPos = copyVec(currentGizmoPos)
        press.referenceDelta = setReferencePositionFromGizmoCoords(press, dragStartLocal, currentGizmoPos) or press.referenceDelta
        press.rotationDelta = 0
    else
        local currentAngle = math.deg(ringAngle(press.gizmo.key, localPos))
        press.currentRingAngle = currentAngle
        local delta = math.AngleDifference(currentAngle, math.deg(press.startRingAngle))
        if not (input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT)) then
            local step = rotationSnapStep(tool)
            local snappedCurrent = snapRotationAngle(currentAngle, step)
            local snappedStart = snapRotationAngle(math.deg(press.startRingAngle), step)
            delta = math.AngleDifference(snappedCurrent, snappedStart)
        end
        delta = delta * ringRotationDeltaSign(press.gizmo.key)

        -- Das Ring-Drag liefert ein Delta um die bereits rotierte Gizmo-Achse.
        -- Deshalb bauen wir aus der Start-Basis direkt die neue Gizmo-Basis auf
        -- und rechnen diese erst danach zurueck in den Referenzraum des Tabs.
        local axis = axisVectorForKey(press.basis, press.gizmo.key == "roll" and "x" or press.gizmo.key == "pitch" and "y" or "z")
        local newBasis = M.RotateAngleAroundAxisPrecise(press.basis, axis, delta)

        local _, newLocalRot = WorldToLocalPrecise(VectorP(0, 0, 0), newBasis, VectorP(0, 0, 0), copyAng(press.referenceBasis))
        if not isangle(newLocalRot) then return end

        setValue(press.space, "pitch", newLocalRot.p)
        setValue(press.space, "yaw", newLocalRot.y)
        setValue(press.space, "roll", newLocalRot.r)
        press.currentGizmoPos = nil
        press.referenceDelta = VectorP(0, 0, 0)
        press.rotationDelta = delta
    end
end

local function drawFrame(pos, ang, size, alpha)
    render.DrawLine(toVector(pos), toVector(pos + ang:Forward() * size), Color(colors.x.r, colors.x.g, colors.x.b, alpha), true)
    render.DrawLine(toVector(pos), toVector(pos + ang:Right() * size), Color(colors.y.r, colors.y.g, colors.y.b, alpha), true)
    render.DrawLine(toVector(pos), toVector(pos + ang:Up() * size), Color(colors.z.r, colors.z.g, colors.z.b, alpha), true)
end

local function drawRing(origin, a, b, radius, color)
    for step = 0, 31 do
        local p1 = origin + (a * math.cos(math.rad(step * 11.25)) + b * math.sin(math.rad(step * 11.25))) * radius
        local p2 = origin + (a * math.cos(math.rad((step + 1) * 11.25)) + b * math.sin(math.rad((step + 1) * 11.25))) * radius
        render.DrawLine(toVector(p1), toVector(p2), color, true)
    end
end

local function formatFormulaEnvironmentValue(value)
    local number = tonumber(value)
    if number == nil then
        return tostring(value or "n/a")
    end

    return M.FormatDisplayNumber(number, M.GetDisplayRounding(), {
        fallback = M.DEFAULT_DISPLAY_ROUNDING,
        trim = true
    })
end

local function formulaBoundsSize(currentState, ent)
    if not IsValid(ent) or not M.IsProp(ent) then return end

    if istable(currentState) then
        requestBounds(currentState, ent)

        local box = boundsFor(currentState, ent)
        if istable(box) and isvector(box.size) then
            return box.size
        end
    end

    local mins, maxs = M.GetLocalBounds(ent)
    if isvector(mins) and isvector(maxs) then
        return maxs - mins
    end
end

local function addFormulaVariable(env, name, value, description)
    name = string.lower(tostring(name or ""))
    if name == "" then return end

    description = tostring(description or "")
    env.variableNames[#env.variableNames + 1] = name
    env.variableDescriptions[name] = description
    env.variableRows[#env.variableRows + 1] = {
        name = name,
        value = value == nil and "n/a" or formatFormulaEnvironmentValue(value),
        description = description
    }

    local numeric = tonumber(value)
    if numeric ~= nil then
        env.variables[name] = numeric
    end
end

local function addFormulaConstants(env)
    addFormulaVariable(env, "pi", math.pi, "Pi constant")
    addFormulaVariable(env, "tau", math.pi * 2, "Tau constant (2 * pi)")
    addFormulaVariable(env, "deg2rad", math.pi / 180, "Multiply degrees by this to convert to radians")
    addFormulaVariable(env, "rad2deg", 180 / math.pi, "Multiply radians by this to convert to degrees")
end

local function formulaAngleComponent(ang, ...)
    if not isangle(ang) then
        return nil
    end

    local keys = { ... }
    for index = 1, #keys do
        local key = keys[index]
        local value = ang[key]

        if isfunction(value) then
            local ok, result = pcall(value, ang)
            value = ok and result or nil
        end

        value = tonumber(value)
        if value ~= nil then
            return value
        end
    end

    return nil
end

local function addFormulaEntityVariables(env, currentState, prefix, label, ent)
    local size = formulaBoundsSize(currentState, ent)
    local pos = IsValid(ent) and ent:GetPos() or nil
    local ang = IsValid(ent) and ent:GetAngles() or nil
    local pitch = formulaAngleComponent(ang, "Pitch", "pitch", "p")
    local yaw = formulaAngleComponent(ang, "Yaw", "yaw", "y")
    local roll = formulaAngleComponent(ang, "Roll", "roll", "r")

    addFormulaVariable(env, prefix .. "_box_x", isvector(size) and size.x or nil, label .. " AABB size X")
    addFormulaVariable(env, prefix .. "_box_y", isvector(size) and size.y or nil, label .. " AABB size Y")
    addFormulaVariable(env, prefix .. "_box_z", isvector(size) and size.z or nil, label .. " AABB size Z")

    addFormulaVariable(env, prefix .. "_world_x", isvector(pos) and pos.x or nil, label .. " world X")
    addFormulaVariable(env, prefix .. "_world_y", isvector(pos) and pos.y or nil, label .. " world Y")
    addFormulaVariable(env, prefix .. "_world_z", isvector(pos) and pos.z or nil, label .. " world Z")

    addFormulaVariable(env, prefix .. "_world_pitch", pitch, label .. " world pitch")
    addFormulaVariable(env, prefix .. "_world_yaw", yaw, label .. " world yaw")
    addFormulaVariable(env, prefix .. "_world_roll", roll, label .. " world roll")
end

local function formulaAnchorPointSet(points, anchorOptions)
    points = istable(points) and points or {}

    return {
        p1 = M.AnchorPoint(points, "p1", anchorOptions),
        p2 = M.AnchorPoint(points, "p2", anchorOptions),
        p3 = M.AnchorPoint(points, "p3", anchorOptions),
        m12 = M.AnchorPoint(points, "mid12", anchorOptions),
        m23 = M.AnchorPoint(points, "mid23", anchorOptions),
        m13 = M.AnchorPoint(points, "mid13", anchorOptions)
    }
end

local function formulaDistance(left, right)
    if not isvector(left) or not isvector(right) then
        return nil
    end

    return left:Distance(right)
end

local function formulaTriangleAngle(vertex, left, right)
    if not isvector(vertex) or not isvector(left) or not isvector(right) then
        return nil
    end

    local toLeft = left - vertex
    local toRight = right - vertex
    local leftLength = toLeft:Length()
    local rightLength = toRight:Length()

    if leftLength <= M.COMPUTE_EPSILON or rightLength <= M.COMPUTE_EPSILON then
        return nil
    end

    local cosine = toLeft:Dot(toRight) / (leftLength * rightLength)
    cosine = math.Clamp(cosine, -1, 1)

    return math.deg(math.acos(cosine))
end

local function addFormulaAnchorDistanceVariables(env, prefix, label, points, anchorOptions)
    local anchorPoints = formulaAnchorPointSet(points, anchorOptions)

    local function addDistance(nameSuffix, left, right, description)
        addFormulaVariable(
            env,
            ("%s_%s"):format(prefix, nameSuffix),
            formulaDistance(left, right),
            ("%s %s"):format(label, description)
        )
    end

    addDistance("dist_p1_p2", anchorPoints.p1, anchorPoints.p2, "distance P1 <-> P2")
    addDistance("dist_p2_p3", anchorPoints.p2, anchorPoints.p3, "distance P2 <-> P3")
    addDistance("dist_p1_p3", anchorPoints.p1, anchorPoints.p3, "distance P1 <-> P3")
    addDistance("dist_m12_p3", anchorPoints.m12, anchorPoints.p3, "distance M12 <-> P3")
    addDistance("dist_m23_p1", anchorPoints.m23, anchorPoints.p1, "distance M23 <-> P1")
    addDistance("dist_m13_p2", anchorPoints.m13, anchorPoints.p2, "distance M13 <-> P2")
end

local function addFormulaAnchorAngleVariables(env, prefix, label, points, anchorOptions)
    local anchorPoints = formulaAnchorPointSet(points, anchorOptions)

    local function addAngle(nameSuffix, vertex, left, right, description)
        addFormulaVariable(
            env,
            ("%s_%s"):format(prefix, nameSuffix),
            formulaTriangleAngle(vertex, left, right),
            ("%s %s"):format(label, description)
        )
    end

    addAngle("p1_ang", anchorPoints.p1, anchorPoints.p2, anchorPoints.p3, "triangle angle at P1 (degrees)")
    addAngle("p2_ang", anchorPoints.p2, anchorPoints.p1, anchorPoints.p3, "triangle angle at P2 (degrees)")
    addAngle("p3_ang", anchorPoints.p3, anchorPoints.p1, anchorPoints.p2, "triangle angle at P3 (degrees)")
end

local function addFormulaCrossAnchorDistanceVariables(env, leftLabel, rightLabel, leftPoints, leftAnchorOptions, rightPoints, rightAnchorOptions)
    local leftAnchorPoints = formulaAnchorPointSet(leftPoints, leftAnchorOptions)
    local rightAnchorPoints = formulaAnchorPointSet(rightPoints, rightAnchorOptions)
    local pointKeys = { "p1", "p2", "p3" }

    for leftIndex = 1, #pointKeys do
        local leftKey = pointKeys[leftIndex]
        local leftPoint = leftAnchorPoints[leftKey]

        for rightIndex = 1, #pointKeys do
            local rightKey = pointKeys[rightIndex]
            local rightPoint = rightAnchorPoints[rightKey]

            addFormulaVariable(
                env,
                ("dist_%s_%s"):format(leftKey, rightKey),
                formulaDistance(leftPoint, rightPoint),
                ("Distance %s %s <-> %s %s"):format(leftLabel, string.upper(leftKey), rightLabel, string.upper(rightKey))
            )
        end
    end
end

local function formulaEntitySignature(ent)
    if isWorldTarget(ent) then
        return "world"
    end

    return IsValid(ent) and tostring(ent:EntIndex()) or "0"
end

local client = M.Client or {}
M.Client = client
client.spaceLabels = SPACE_LABELS
client.colors = colors
client.ringQualityPresets = RING_QUALITY_PRESETS
client.defaultRingQualityIndex = DEFAULT_RING_QUALITY_INDEX
client.activeTool = activeTool
client.setValue = setValue
client.gizmo = gizmo
client.snapGizmoPosition = snapGizmoPosition
client.drawFrame = drawFrame
client.drawRing = drawRing
client.rotationSnapDivisors = ROTATION_SNAP_DIVISORS
client.defaultRotationSnapIndex = DEFAULT_ROTATION_SNAP_INDEX
    client.rotationSnapDivisions = rotationSnapDivisions
    client.rotationSnapStep = rotationSnapStep
    client.translationSnapStep = translationSnapStep
    client.rotationSnapMaxVisibleTicks = MAX_VISIBLE_ROTATION_TICKS
    client.isMajorRotationTick = isMajorRotationTick
    client.sampleWorldPos = sampleWorldPos
    client.validateState = validateClientState
    client.getFormulaEnvironment = function()
        local currentState = ensureStateShape(M.ClientState)
        cleanupLinkedProps(currentState)
        local tool = select(1, activeTool())
        local sourceAnchorOptions = M.AnchorOptionsFromReader(function(name)
            return tool and tool:GetClientInfo(name)
        end, "from")
        local targetAnchorOptions = M.AnchorOptionsFromReader(function(name)
            return tool and tool:GetClientInfo(name)
        end, "to")

        local env = {
            variables = {},
            variableNames = {},
            variableDescriptions = {},
            variableRows = {}
        }

        addFormulaConstants(env)
        addFormulaEntityVariables(env, currentState, "prop1", "Prop 1", currentState.prop1)
        addFormulaEntityVariables(env, currentState, "prop2", "Prop 2", currentState.prop2)
        addFormulaAnchorDistanceVariables(env, "prop1", "Prop 1", currentState.source, sourceAnchorOptions)
        addFormulaAnchorAngleVariables(env, "prop1", "Prop 1", currentState.source, sourceAnchorOptions)
        addFormulaAnchorDistanceVariables(env, "prop2", "Prop 2", currentState.target, targetAnchorOptions)
        addFormulaAnchorAngleVariables(env, "prop2", "Prop 2", currentState.target, targetAnchorOptions)
        addFormulaCrossAnchorDistanceVariables(
            env,
            "Prop 1",
            "Prop 2",
            currentState.source,
            sourceAnchorOptions,
            currentState.target,
            targetAnchorOptions
        )

        local linkedSignatures = {}
        local linkedCount = 0
        for index = 1, #(currentState.linked or {}) do
            local ent = currentState.linked[index]
            if IsValid(ent) and ent ~= currentState.prop1 and ent ~= currentState.prop2 and M.IsProp(ent) then
                linkedCount = linkedCount + 1
                linkedSignatures[#linkedSignatures + 1] = formulaEntitySignature(ent)
                addFormulaEntityVariables(env, currentState, ("linked%d"):format(linkedCount), ("Linked %d"):format(linkedCount), ent)
            end
        end

        addFormulaVariable(env, "linked_count", linkedCount, "Number of currently linked props")
        env.watchKey = table.concat({
            "prop1=" .. formulaEntitySignature(currentState.prop1),
            "prop2=" .. formulaEntitySignature(currentState.prop2),
            "linked=" .. table.concat(linkedSignatures, ",")
        }, ";")

        return env
    end

hook.Add("EntityRemoved", "magic_align_reset_session_on_prop_remove", function(ent)
    local state = M.ClientState
    if not state then return end
    if ent ~= state.prop1 and ent ~= state.prop2 then return end

    local tool = IsValid(LocalPlayer()) and M.GetActiveMagicAlignTool(LocalPlayer()) or nil
    resetClientSession(tool)
end)

function TOOL:Think()
    local tool, state = activeTool()
    if tool ~= self then return end

    if not validateClientState(self, state) then
        return
    end

    cleanupLinkedProps(state)
    M.RefreshState(state)
    local worldPoints = worldPointsApi()
    if worldPoints and isfunction(worldPoints.sanitizeState) then
        worldPoints.sanitizeState(state)
    end
    refreshPreferredAnchors(self, state)
    state.hover = hoverState(self, state)

    if worldPoints and isfunction(worldPoints.updateActivePress) and worldPoints.updateActivePress(self, state) then
    elseif state.press and state.press.kind == "drag_point" and state.hover.candidate and state.hover.side == state.press.side then
        useCandidate(state, state.press.side, state.hover.candidate, state.press.index)
    elseif state.press
        and (state.press.kind == "pick" or state.press.kind == "select_source_pick" or state.press.kind == "select_target_pick")
        and traceMatchesEntity(state.hover.trace, state.press.ent) then
        local tr = state.hover.trace
        local samples = state.press.samples
        local last = samples[#samples]
        local clickCandidate = hoverPickCandidate(state.hover)
        if clickCandidate and clickCandidate.ent == state.press.ent then
            state.press.clickCandidate = clickCandidate
        end

        local lastWorldPos = sampleWorldPos(state.press.ent, last)
        if not isvector(lastWorldPos) or lastWorldPos:DistToSqr(tr.HitPos) > 1 then
            local sample = buildTraceSample(state.press.ent, tr.HitPos, tr.HitNormal, tr)
            if sample then
                samples[#samples + 1] = sample

                local sampleWorld = sampleWorldPos(state.press.ent, sample)
                if isvector(lastWorldPos) and isvector(sampleWorld) then
                    state.press.drawDistance = (tonumber(state.press.drawDistance) or 0) + lastWorldPos:Distance(sampleWorld)
                end
            end
        end

        state.press.drawActive = (tonumber(state.press.drawDistance) or 0) >= DRAW_SELECT_DEADZONE

        local candidate = pickCandidateForPress(state.press, state.hover)
        if candidate then
            state.press.currentCandidate = candidate
        end

        state.press.aggregatedProbes = aggregateTraceProbes(samples)

        state.corner = cornerCandidate(
            state.press.ent,
            samples,
            CORNER_TRACE_MIN_LENGTH,
            boundsFor(state, state.press.ent),
            state.press.aggregatedProbes
        )
    elseif state.press and state.press.kind == "gizmo" then
        updateGizmo(self, state)
    else
        state.corner = nil
    end

    solvePreview(self, state)
    pendingPreview(self, state)
    ensureGhost(state)
    updateToolHelp(self, state)

    local attack = input.IsMouseDown(MOUSE_LEFT)
    local use = input.IsKeyDown(KEY_E)
    local blocked = uiBlocked()
    if worldPoints and isfunction(worldPoints.handleModifierToggle) then
        worldPoints.handleModifierToggle(state, blocked)
    end
    if blocked then
        if not attack then
            state.press = nil
        end
        state.attackDown = attack
        state.useDown = use
        return
    end

    if attack and not state.attackDown then
        if worldPoints and isfunction(worldPoints.beginMousePress) and worldPoints.beginMousePress(self, state) then
        elseif state.hover.gizmo and state.hover.gizmo.hover then
            beginGizmoDrag(self, state, state.hover.gizmo)
        elseif state.hover.point and state.hover.side then
            state.press = {
                kind = "drag_point",
                side = state.hover.side,
                index = state.hover.point.index
            }
        elseif state.hover.side and state.hover.ent and state.hover.trace and traceMatchesEntity(state.hover.trace, state.hover.ent) then
            state.press = beginPickPress("pick", state.hover.side, state.hover.ent, state.hover)
        elseif state.hover.pickSource then
            state.press = beginPickPress("select_source_pick", "source", state.hover.pickSource, state.hover)
        elseif state.hover.pickTarget then
            state.press = beginPickPress("select_target_pick", "target", state.hover.pickTarget, state.hover)
        end
    elseif not attack and state.attackDown then
        local press = state.press
        local handledWorldPointRelease = worldPoints
            and isfunction(worldPoints.handleMouseRelease)
            and worldPoints.handleMouseRelease(self, state, press)

        if press and not handledWorldPointRelease then
            local finalCandidate

            if press.drawActive then
                finalCandidate = state.corner or press.currentCandidate or press.clickCandidate
            else
                finalCandidate = press.clickCandidate or press.currentCandidate
            end

            if press.kind == "select_source_pick" and M.IsProp(press.ent) then
                state.prop1 = press.ent
                state.prop2 = nil
                resetLinkedProps(state)
                state.source = {}
                state.target = {}
                requestBounds(state, state.prop1)
                useCandidate(state, "source", finalCandidate)
            elseif press.kind == "select_target_pick" and (M.IsProp(press.ent) or isWorldTarget(press.ent)) and press.ent ~= state.prop1 then
                removeLinkedProp(state, press.ent)
                state.prop2 = press.ent
                state.target = {}
                if IsValid(state.prop2) then
                    requestBounds(state, state.prop2)
                end
                useCandidate(state, "target", finalCandidate)
            elseif press.kind == "pick" then
                useCandidate(state, press.side, finalCandidate)
            end
        end

        state.press = nil
        state.corner = nil
    end

    state.attackDown = attack
    if use and not state.useDown and not state.press and state.preview then
        commit(self, state)
    end
    state.useDown = use
end

include("magic_align/client/world_points.lua")
include("magic_align/client/render.lua")
include("magic_align/client/menu.lua")
include("magic_align/client/menuentryhack.lua")
include("magic_align/client/render_toolgun.lua")
