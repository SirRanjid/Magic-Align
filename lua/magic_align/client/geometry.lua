MAGIC_ALIGN = MAGIC_ALIGN or include("autorun/magic_align.lua")

local M = MAGIC_ALIGN
local client = M.Client or {}
M.Client = client

local geometry = client.geometry or {}
client.geometry = geometry

local VectorP = M.VectorP
local AngleP = M.AngleP
local isvector = M.IsVectorLike
local isangle = M.IsAngleLike
local copyVec = M.CopyVectorPrecise
local localToWorld = M.LocalToWorldPrecise
local worldToLocal = M.WorldToLocalPrecise

local function normalizedVec(value)
    return M.NormalizeVectorPrecise(value, M.COMPUTE_VECTOR_EPSILON_SQR)
end

local function worldIdentityPos()
    return VectorP(0, 0, 0)
end

local function worldIdentityAng()
    return AngleP(0, 0, 0)
end

local function entityBasePos(ent)
    if geometry.isWorldTarget(ent) then
        return worldIdentityPos()
    end

    return IsValid(ent) and ent:GetPos() or nil
end

local function entityBaseAng(ent)
    if geometry.isWorldTarget(ent) then
        return worldIdentityAng()
    end

    return IsValid(ent) and ent:GetAngles() or nil
end

function geometry.isWorldTarget(ent)
    return M.IsWorldTarget and M.IsWorldTarget(ent) or false
end

function geometry.hasTargetEntity(ent)
    return M.HasTargetEntity and M.HasTargetEntity(ent) or geometry.isWorldTarget(ent) or IsValid(ent)
end

function geometry.traceHitsWorld(tr)
    return tr ~= nil
        and tr.Hit ~= false
        and tr.HitSky ~= true
        and isvector(tr.HitPos)
        and (tr.HitWorld == true or geometry.isWorldTarget(tr.Entity))
end

function geometry.traceMatchesEntity(tr, ent)
    if not tr then return false end

    if geometry.isWorldTarget(ent) then
        return geometry.traceHitsWorld(tr)
    end

    return IsValid(ent) and tr.Hit ~= false and tr.Entity == ent and isvector(tr.HitPos)
end

function geometry.worldPosFromLocalPoint(ent, localPos)
    if not isvector(localPos) then return end

    if geometry.isWorldTarget(ent) then
        return copyVec(localPos)
    end

    local pos = entityBasePos(ent)
    local ang = entityBaseAng(ent)
    if not isvector(pos) or not isangle(ang) then return end

    return localToWorld(localPos, AngleP(0, 0, 0), pos, ang)
end

function geometry.localPointFromWorldPos(ent, worldPos)
    if not isvector(worldPos) then return end

    if geometry.isWorldTarget(ent) then
        return copyVec(worldPos)
    end

    local pos = entityBasePos(ent)
    local ang = entityBaseAng(ent)
    if not isvector(pos) or not isangle(ang) then return end

    return worldToLocal(worldPos, AngleP(0, 0, 0), pos, ang)
end

function geometry.localNormalFromWorld(ent, worldPos, worldNormal)
    local worldPoint = copyVec(worldPos)
    local normal = normalizedVec(worldNormal)
    if not isvector(worldPoint) or not normal then return end

    if geometry.isWorldTarget(ent) then
        return copyVec(normal)
    end

    local localPos = geometry.localPointFromWorldPos(ent, worldPoint)
    local pos = entityBasePos(ent)
    local ang = entityBaseAng(ent)
    if not isvector(localPos) or not isvector(pos) or not isangle(ang) then return end

    local normalTip = worldToLocal(worldPoint + normal, AngleP(0, 0, 0), pos, ang)
    if not isvector(normalTip) then return end

    return normalizedVec(normalTip - localPos)
end

function geometry.worldNormalFromLocal(ent, localPos, localNormal)
    local normal = normalizedVec(localNormal)
    if not normal then return end

    if geometry.isWorldTarget(ent) then
        return copyVec(normal)
    end

    local worldPos = geometry.worldPosFromLocalPoint(ent, localPos)
    local pos = entityBasePos(ent)
    local ang = entityBaseAng(ent)
    if not isvector(worldPos) or not isvector(pos) or not isangle(ang) then return end

    local worldTip = localToWorld(localPos + normal, AngleP(0, 0, 0), pos, ang)
    if not isvector(worldTip) then return end

    return normalizedVec(worldTip - worldPos)
end

function geometry.pointFromCandidate(candidate)
    if not istable(candidate) or not isvector(candidate.localPos) then return end

    local point = VectorP(candidate.localPos.x, candidate.localPos.y, candidate.localPos.z)
    local localNormal = normalizedVec(candidate.localNormal)

    if not localNormal and isvector(candidate.normal) then
        local worldPos = isvector(candidate.worldPos) and candidate.worldPos or geometry.worldPosFromLocalPoint(candidate.ent, candidate.localPos)
        localNormal = geometry.localNormalFromWorld(candidate.ent, worldPos, candidate.normal)
    end

    if localNormal then
        point.normal = copyVec(localNormal)
    end

    if geometry.isWorldTarget(candidate.ent) then
        point.world = true
    end

    return point
end

function geometry.traceCandidate(ent, tr)
    if not geometry.hasTargetEntity(ent) or not tr or not geometry.traceMatchesEntity(tr, ent) or not isvector(tr.HitPos) then
        return
    end

    local localPos = geometry.localPointFromWorldPos(ent, tr.HitPos)
    if not isvector(localPos) then return end

    return {
        ent = ent,
        localPos = localPos,
        worldPos = copyVec(tr.HitPos),
        localNormal = geometry.localNormalFromWorld(ent, tr.HitPos, tr.HitNormal),
        normal = copyVec(tr.HitNormal),
        mode = "trace"
    }
end

return geometry
