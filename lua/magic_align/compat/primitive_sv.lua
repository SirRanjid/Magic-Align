if CLIENT then return end

MAGIC_ALIGN = MAGIC_ALIGN or {}

local M = MAGIC_ALIGN
local Compat = M.Compat or {}
local toVector = M.ToVector
local toAngle = M.ToAngle

M.Compat = Compat

local function clonePrimitiveEntity(ply, src, pos, ang)
    if not Compat.IsPrimitive(src) then return false end
    if not duplicator
        or not isfunction(duplicator.CopyEntTable)
        or not isfunction(duplicator.CreateEntityFromTable) then
        return true
    end

    -- Legacy fallback: the main commit path now prefers the stock duplicator
    -- first, but primitives still keep this narrower rescue path.
    local okCopy, data = pcall(duplicator.CopyEntTable, src)
    if not okCopy or not istable(data) then
        return true
    end

    if istable(data.BuildDupeInfo) then
        data.BuildDupeInfo = table.Copy(data.BuildDupeInfo)
        data.BuildDupeInfo.DupeParentID = nil
    end

    local okCreate, ent = pcall(duplicator.CreateEntityFromTable, ply, data)
    if not okCreate or not IsValid(ent) then
        return true
    end

    local model = src:GetModel()
    if model and model ~= "" then
        ent:SetModel(model)
    end

    ent:SetPos(toVector(pos))
    ent:SetAngles(toAngle(ang))
    ent:SetSkin(src:GetSkin() or 0)
    ent:SetMaterial(src:GetMaterial() or "")
    ent:SetColor(src:GetColor())
    ent:SetRenderMode(src:GetRenderMode())
    ent:SetCollisionGroup(src:GetCollisionGroup())
    ent:Spawn()
    ent:SetModelScale(math.max(tonumber(src:GetModelScale() or 1) or 1, M.MODEL_SCALE_EPSILON), 0)
    ent:Activate()

    for i = 0, src:GetNumBodyGroups() - 1 do
        ent:SetBodygroup(i, src:GetBodygroup(i))
    end

    local subCount = src:GetMaterials() and #src:GetMaterials() or 0
    for i = 0, subCount - 1 do
        local material = src:GetSubMaterial(i)
        if material and material ~= "" then
            ent:SetSubMaterial(i, material)
        end
    end

    if ent.SetCreator then
        ent:SetCreator(ply)
    end

    if ent.CPPISetOwner then
        ent:CPPISetOwner(ply)
    end

    if ply.AddCleanup then
        ply:AddCleanup("props", ent)
    else
        cleanup.Add(ply, "props", ent)
    end

    hook.Run("PlayerSpawnedProp", ply, ent:GetModel(), ent)

    return true, ent
end

Compat.CloneEntity = clonePrimitiveEntity
