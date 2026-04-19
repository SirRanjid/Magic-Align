MAGIC_ALIGN = MAGIC_ALIGN or include("autorun/magic_align.lua")

util.AddNetworkString(MAGIC_ALIGN.NET)
util.AddNetworkString(MAGIC_ALIGN.NET_COMMIT_LINKED_PART)
util.AddNetworkString(MAGIC_ALIGN.NET_COMMIT_FINISH)
util.AddNetworkString(MAGIC_ALIGN.NET_BOUNDS_REQUEST)
util.AddNetworkString(MAGIC_ALIGN.NET_BOUNDS_REPLY)
util.AddNetworkString(MAGIC_ALIGN.NET_CLIENT_ACTION)
util.AddNetworkString(MAGIC_ALIGN.NET_VIEW_ANGLES)

local M = MAGIC_ALIGN
local VectorP = M.VectorP
local AngleP = M.AngleP
local isvector = M.IsVectorLike
local isangle = M.IsAngleLike
local toVector = M.ToVector
local toAngle = M.ToAngle
local REQUEST_STATE = setmetatable({}, { __mode = "k" })
local COMMIT_LOCK = setmetatable({}, { __mode = "k" })
local PENDING_COMMITS = setmetatable({}, { __mode = "k" })
local COMMIT_QUEUE = {}
local COMMIT_UPLOAD_TIMEOUT = 8
local runCommit

local function cloneVec(v)
    if not isvector(v) then return end
    return VectorP(v.x, v.y, v.z)
end

local function cloneAng(a)
    if not isangle(a) then return end
    return AngleP(a.p, a.y, a.r)
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

local function advResizerData(ent)
    if not IsValid(ent) then return end

    local entityMods = ent.EntityMods
    local modifierData = istable(entityMods) and entityMods.advr or nil
    if istable(modifierData) then
        return table.Copy(modifierData)
    end

    -- Fallback for already-resized props whose duplicator modifier table is gone.
    local handler = findSizeHandler(ent)
    if not IsValid(handler) then return end

    local physical = isfunction(handler.GetActualPhysicsScale) and parseScaleVector(handler:GetActualPhysicsScale()) or nil
    local visual = isfunction(handler.GetVisualScale) and parseScaleVector(handler:GetVisualScale()) or nil

    if not isvector(physical) or vectorApprox(physical, SCALE_ZERO) then
        physical = VectorP(1, 1, 1)
    end

    if not isvector(visual) or vectorApprox(visual, SCALE_ZERO) then
        visual = VectorP(1, 1, 1)
    end

    if vectorApprox(physical, SCALE_IDENTITY) and vectorApprox(visual, SCALE_IDENTITY) then
        return
    end

    return {
        physical.x,
        physical.y,
        physical.z,
        visual.x,
        visual.y,
        visual.z,
        false
    }
end

local function applyAdvResizerData(ply, src, ent)
    if not IsValid(src) or not IsValid(ent) then return end
    if not duplicator or not isfunction(duplicator.StoreEntityModifier) or not isfunction(duplicator.ApplyEntityModifiers) then
        return
    end

    local data = advResizerData(src)
    if not istable(data) then return end

    duplicator.StoreEntityModifier(ent, "advr", data)
    duplicator.ApplyEntityModifiers(ply, ent)
end

local function entityModel(ent)
    if not IsValid(ent) or not isfunction(ent.GetModel) then return end

    local model = ent:GetModel()
    if not isstring(model) or model == "" then return end

    return model
end

local function applyEntityAppearance(src, ent, pos, ang)
    if not IsValid(src) or not IsValid(ent) then return end

    local model = entityModel(src)
    if model and isfunction(ent.SetModel) and ent:GetModel() ~= model then
        ent:SetModel(model)
    end

    if isvector(pos) and isfunction(ent.SetPos) then
        ent:SetPos(toVector(pos))
    end

    if isangle(ang) and isfunction(ent.SetAngles) then
        ent:SetAngles(toAngle(ang))
    end

    if isfunction(ent.SetSkin) then
        ent:SetSkin(src:GetSkin() or 0)
    end

    if isfunction(ent.SetMaterial) then
        ent:SetMaterial(src:GetMaterial() or "")
    end

    if isfunction(ent.SetColor) then
        ent:SetColor(src:GetColor())
    end

    if isfunction(ent.SetRenderMode) and isfunction(src.GetRenderMode) then
        ent:SetRenderMode(src:GetRenderMode())
    end

    if isfunction(ent.SetRenderFX) and isfunction(src.GetRenderFX) then
        ent:SetRenderFX(src:GetRenderFX())
    end

    if isfunction(ent.SetCollisionGroup) then
        ent:SetCollisionGroup(src:GetCollisionGroup())
    end

    if isfunction(ent.SetModelScale) then
        ent:SetModelScale(modelScale(src), 0)
    end

    local bodygroupCount = isfunction(src.GetNumBodyGroups) and src:GetNumBodyGroups() or 0
    if isfunction(ent.SetBodygroup) then
        for i = 0, bodygroupCount - 1 do
            ent:SetBodygroup(i, src:GetBodygroup(i))
        end
    end

    if isfunction(ent.SetSubMaterial) and isfunction(src.GetSubMaterial) then
        local srcMaterials = isfunction(src.GetMaterials) and src:GetMaterials() or nil
        local entMaterials = isfunction(ent.GetMaterials) and ent:GetMaterials() or nil
        local subCount = math.max(
            istable(srcMaterials) and #srcMaterials or 0,
            istable(entMaterials) and #entMaterials or 0
        )

        for i = 0, subCount - 1 do
            ent:SetSubMaterial(i, src:GetSubMaterial(i) or "")
        end
    end
end

local function copyPhysicsState(src, ent)
    local srcPhys = IsValid(src) and src:GetPhysicsObject() or nil
    local dstPhys = IsValid(ent) and ent:GetPhysicsObject() or nil
    if not IsValid(srcPhys) or not IsValid(dstPhys) then return end

    if isfunction(dstPhys.SetMass) and isfunction(srcPhys.GetMass) then
        dstPhys:SetMass(srcPhys:GetMass())
    end

    if isfunction(dstPhys.SetMaterial) and isfunction(srcPhys.GetMaterial) then
        dstPhys:SetMaterial(srcPhys:GetMaterial())
    end

    if isfunction(dstPhys.EnableGravity) and isfunction(srcPhys.IsGravityEnabled) then
        dstPhys:EnableGravity(srcPhys:IsGravityEnabled())
    end
end

local function registerClonedEntity(ply, ent, src)
    if not IsValid(ply) or not IsValid(ent) then return end

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

    local model = entityModel(ent) or entityModel(src)
    if model then
        hook.Run("PlayerSpawnedProp", ply, model, ent)
    end
end

local function applyDuplicatorData(ply, src, ent, data)
    if not IsValid(ent) or not istable(data) then return end

    if isfunction(ent.RestoreNetworkVars) then
        ent:RestoreNetworkVars(data.DT)
    end

    if isfunction(ent.OnDuplicated) then
        ent:OnDuplicated(data)
    end

    if istable(data.EntityMods) then
        ent.EntityMods = table.Copy(data.EntityMods)
    end

    if istable(data.BoneMods) then
        ent.BoneMods = table.Copy(data.BoneMods)
    end

    if istable(data.PhysicsObjects) then
        ent.PhysicsObjects = table.Copy(data.PhysicsObjects)
    end

    if not (istable(data.EntityMods) and istable(data.EntityMods.advr))
        and duplicator
        and isfunction(duplicator.StoreEntityModifier) then
        local advrData = advResizerData(src)
        if istable(advrData) then
            duplicator.StoreEntityModifier(ent, "advr", advrData)
        end
    end

    if duplicator and isfunction(duplicator.ApplyEntityModifiers) then
        duplicator.ApplyEntityModifiers(ply, ent)
    end

    if duplicator and isfunction(duplicator.ApplyBoneModifiers) then
        duplicator.ApplyBoneModifiers(ply, ent)
    end

    if isfunction(ent.PostEntityPaste) then
        local created = IsValid(src) and { [src:EntIndex()] = ent } or { ent }
        ent:PostEntityPaste(ply or NULL, ent, created)
    end
end

local function cloneViaDuplicator(ply, src, pos, ang)
    if not duplicator
        or not isfunction(duplicator.CopyEntTable)
        or not isfunction(duplicator.CreateEntityFromTable) then
        return
    end

    local okCopy, data = pcall(duplicator.CopyEntTable, src)
    if not okCopy or not istable(data) then return end

    if istable(data.BuildDupeInfo) then
        data.BuildDupeInfo = table.Copy(data.BuildDupeInfo)
        data.BuildDupeInfo.DupeParentID = nil
    end

    local okCreate, ent = pcall(duplicator.CreateEntityFromTable, ply, data)
    if not okCreate or not IsValid(ent) then return end

    applyEntityAppearance(src, ent, pos, ang)
    applyDuplicatorData(ply, src, ent, data)

    if isfunction(ent.Activate) then
        ent:Activate()
    end

    registerClonedEntity(ply, ent, src)

    return ent
end

local function cloneViaSpawnFallback(ply, src, pos, ang)
    local ent = ents.Create(src:GetClass())
    if not IsValid(ent) then return end

    local model = entityModel(src)
    if model and isfunction(ent.SetModel) then
        ent:SetModel(model)
    end

    if isvector(pos) and isfunction(ent.SetPos) then
        ent:SetPos(toVector(pos))
    end

    if isangle(ang) and isfunction(ent.SetAngles) then
        ent:SetAngles(toAngle(ang))
    end

    if isfunction(ent.Spawn) then
        ent:Spawn()
    end

    applyEntityAppearance(src, ent, pos, ang)

    if isfunction(ent.Activate) then
        ent:Activate()
    end

    applyAdvResizerData(ply, src, ent)
    copyPhysicsState(src, ent)

    if ply.AddCount then
        ply:AddCount("props", ent)
    end

    registerClonedEntity(ply, ent, src)

    return ent
end

local function captureEntityState(ent)
    if not IsValid(ent) then return end

    local pos = ent:GetPos()
    local ang = ent:GetAngles()
    if not isvector(pos) or not isangle(ang) then return end

    return {
        ent = ent,
        pos = cloneVec(pos),
        ang = cloneAng(ang),
        parent = IsValid(ent:GetParent()) and ent:GetParent() or nil
    }
end

local function canUse(ply, ent)
    if not M.IsProp(ent) then return false end

    if ent.CPPICanTool and ent:CPPICanTool(ply, "magic_align") == false then
        return false
    end

    local tr = {
        Entity = ent,
        HitPos = ent:WorldSpaceCenter(),
        HitNormal = toVector(VectorP(0, 0, 1)),
        StartPos = ply:EyePos()
    }

    if hook.Run("CanTool", ply, tr, "magic_align") == false then
        return false
    end

    return true
end

local function readPoints()
    local count = net.ReadUInt(2)
    local points = {}

    for i = 1, count do
        points[i] = net.ReadPreciseVector()
    end

    return points
end

local function readEntities(count)
    count = math.Clamp(math.floor(tonumber(count) or net.ReadUInt(8)), 0, M.MAX_COMMIT_PROPS)
    local entities = {}

    for i = 1, count do
        entities[i] = net.ReadEntity()
    end

    return entities
end

local function finitePoints(points)
    if not istable(points) then return false end

    for i = 1, #points do
        if not M.IsFiniteVector(points[i]) then
            return false
        end
    end

    return true
end

local function queueCommit(task)
    if not istable(task) or not IsValid(task.ply) or COMMIT_LOCK[task.ply] then return false end

    COMMIT_LOCK[task.ply] = true
    task.co = coroutine.create(function()
        runCommit(task)
    end)
    COMMIT_QUEUE[#COMMIT_QUEUE + 1] = task

    return true
end

local function cloneEntity(ply, src, pos, ang)
    if not IsValid(src) or not isvector(pos) or not isangle(ang) then return end
    if ply.CheckLimit and not ply:CheckLimit("props") then return end

    -- Prefer the stock duplicator path first so scripted entities can carry
    -- their own registered duplicate/restore logic without relying on AdvDupe.
    local ent = cloneViaDuplicator(ply, src, pos, ang)
    if IsValid(ent) then
        return ent
    end

    if M.Compat and isfunction(M.Compat.CloneEntity) then
        local handled, compatEnt = M.Compat.CloneEntity(ply, src, pos, ang)
        if handled then
            return compatEnt
        end
    end

    return cloneViaSpawnFallback(ply, src, pos, ang)
end

local function settlePhysics(ent)
    local phys = ent:GetPhysicsObject()
    if not IsValid(phys) then return end

    phys:SetPos(ent:GetPos())
    phys:SetAngles(ent:GetAngles())
    phys:EnableMotion(false)
    phys:Sleep()
end

local function removeEntities(entities)
    for i = 1, #entities do
        if IsValid(entities[i]) then
            entities[i]:Remove()
        end
    end
end

local function commitCheckpoint(task)
    if SysTime() < (task.deadline or 0) then return end
    coroutine.yield()
end

local function releaseCommitLock(task)
    if task and task.ply then
        COMMIT_LOCK[task.ply] = nil
    end
end

local function restoreCommitStep(_, props, created)
    -- A commit undo only needs the props' previous transforms plus the entities
    -- created by that step, such as constraints, copies or copy&move backups.
    local validProps = {}

    for i = 1, #(created or {}) do
        local ent = created[i]
        if IsValid(ent) then
            ent:Remove()
        end
    end

    for i = 1, #(props or {}) do
        local state = props[i]
        local ent = state and state.ent or nil
        if IsValid(ent) and isvector(state.pos) and isangle(state.ang) then
            validProps[#validProps + 1] = state
        end
    end

    for i = 1, #validProps do
        validProps[i].ent:SetParent(nil)
    end

    for i = 1, #validProps do
        local state = validProps[i]
        local ent = state.ent
        if IsValid(ent) then
            ent:SetPos(toVector(state.pos))
            ent:SetAngles(toAngle(state.ang))
        end
    end

    for i = 1, #validProps do
        local state = validProps[i]
        local parent = IsValid(state.parent) and state.parent or nil
        state.ent:SetParent(parent)
    end

    for i = 1, #validProps do
        settlePhysics(validProps[i].ent)
    end
end

local function expandWorldBounds(mins, maxs, point)
    if not isvector(point) then return mins, maxs end

    if not isvector(mins) or not isvector(maxs) then
        return cloneVec(point), cloneVec(point)
    end

    mins.x = math.min(mins.x, point.x)
    mins.y = math.min(mins.y, point.y)
    mins.z = math.min(mins.z, point.z)
    maxs.x = math.max(maxs.x, point.x)
    maxs.y = math.max(maxs.y, point.y)
    maxs.z = math.max(maxs.z, point.z)

    return mins, maxs
end

local function worldBounds(ent)
    local mins, maxs = M.GetLocalBounds(ent)
    if not isvector(mins) or not isvector(maxs) then return end

    local worldMins, worldMaxs
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

    local entPos = ent:GetPos()
    local entAng = ent:GetAngles()
    if not isvector(entPos) or not isangle(entAng) then return end

    for i = 1, #corners do
        local worldPos = LocalToWorldPrecise(corners[i], AngleP(0, 0, 0), entPos, entAng)
        worldMins, worldMaxs = expandWorldBounds(worldMins, worldMaxs, worldPos)
    end

    return worldMins, worldMaxs
end

local function aabbOverlap(minsA, maxsA, minsB, maxsB)
    if not isvector(minsA) or not isvector(maxsA) or not isvector(minsB) or not isvector(maxsB) then
        return false
    end

    return minsA.x <= maxsB.x and maxsA.x >= minsB.x
        and minsA.y <= maxsB.y and maxsA.y >= minsB.y
        and minsA.z <= maxsB.z and maxsA.z >= minsB.z
end

local function pairKey(a, b)
    if not IsValid(a) or not IsValid(b) then return end

    local first = a:EntIndex()
    local second = b:EntIndex()

    if first > second then
        first, second = second, first
    end

    return ("%d:%d"):format(first, second)
end

local function addNoCollideConstraint(a, b, made, nocollidePairs)
    if not IsValid(a) or not IsValid(b) or a == b then return end

    local key = pairKey(a, b)
    if not key or nocollidePairs[key] then return end

    local c = constraint.NoCollide(a, b, 0, 0)
    if IsValid(c) then
        nocollidePairs[key] = true
        made[#made + 1] = c
    end
end

local function applyOverlapNoCollides(entities, made, nocollidePairs, task)
    local bounds = {}
    local valid = {}

    for i = 1, #entities do
        local ent = entities[i]
        if IsValid(ent) then
            local mins, maxs = worldBounds(ent)
            if isvector(mins) and isvector(maxs) then
                bounds[ent] = {
                    mins = mins,
                    maxs = maxs
                }
                valid[#valid + 1] = ent
            end
        end

        commitCheckpoint(task)
    end

    for i = 1, #valid do
        local entA = valid[i]
        local dataA = bounds[entA]

        for j = i + 1, #valid do
            local entB = valid[j]
            local dataB = bounds[entB]

            if dataA and dataB and aabbOverlap(dataA.mins, dataA.maxs, dataB.mins, dataB.maxs) then
                addNoCollideConstraint(entA, entB, made, nocollidePairs)
            end

            commitCheckpoint(task)
        end
    end
end

local function applyCommitRelations(target, anchor, weld, nocollide, parent, made, nocollidePairs)
    if not IsValid(target) or not IsValid(anchor) or target == anchor then return end

    if weld then
        local c = constraint.Weld(target, anchor, 0, 0, 0, true, false)
        if IsValid(c) then
            made[#made + 1] = c
        end
    end

    if nocollide then
        addNoCollideConstraint(target, anchor, made, nocollidePairs)
    end

    if parent then
        target:SetParent(anchor)
    end
end

function runCommit(task)
    local ply = task.ply
    local prop1 = task.prop1
    local prop2 = task.prop2
    local pos, ang = task.pos, task.ang
    local sourcePoints = task.sourcePoints
    local targetPoints = task.targetPoints
    local linkedProps = task.linkedProps
    local weld = task.weld
    local nocollide = task.nocollide
    local parent = task.parent
    local mode = task.mode
    local effectiveNocollide = nocollide or weld

    if not IsValid(ply) then return end
    if not canUse(ply, prop1) then return end
    if IsValid(prop2) and not canUse(ply, prop2) then return end
    if prop1 == prop2 then return end
    if #linkedProps > M.GetMaxLinkedProps() then return end

    if #sourcePoints < 1 or #sourcePoints > M.MAX_POINTS then return end
    if #targetPoints > M.MAX_POINTS then return end
    if not finitePoints(sourcePoints) or not finitePoints(targetPoints) then return end
    if IsValid(prop2) and #targetPoints < 1 then return end
    if not IsValid(prop2) and #targetPoints > 0 then return end
    if not M.IsFiniteVector(pos) or not M.IsFiniteAngle(ang) then return end
    if mode ~= M.COMMIT_MOVE and mode ~= M.COMMIT_COPY and mode ~= M.COMMIT_COPY_MOVE then return end

    local sourceMins, sourceMaxs = M.GetLocalBounds(prop1)
    if not sourceMins or not sourceMaxs then return end

    for i = 1, #sourcePoints do
        if not M.PointInsideAABB(sourcePoints[i], sourceMins, sourceMaxs) then return end
        commitCheckpoint(task)
    end

    if IsValid(prop2) then
        local targetMins, targetMaxs = M.GetLocalBounds(prop2)
        if not targetMins or not targetMaxs then return end

        for i = 1, #targetPoints do
            if not M.PointInsideAABB(targetPoints[i], targetMins, targetMaxs) then return end
            commitCheckpoint(task)
        end
    end

    local sources = { prop1 }
    local seen = { [prop1] = true }
    if IsValid(prop2) then
        seen[prop2] = true
    end

    for i = 1, #linkedProps do
        local ent = linkedProps[i]
        if not IsValid(ent) or seen[ent] or not canUse(ply, ent) then return end

        seen[ent] = true
        sources[#sources + 1] = ent
        commitCheckpoint(task)
    end

    local sourcePos = cloneVec(prop1:GetPos())
    local sourceAng = cloneAng(prop1:GetAngles())
    local undoProps = {}
    local undoSeen = {}

    local function addUndoProp(ent)
        if not IsValid(ent) or undoSeen[ent] then return true end

        local start = captureEntityState(ent)
        if not start then return false end

        undoSeen[ent] = true
        undoProps[#undoProps + 1] = start
        return true
    end

    if not isvector(sourcePos) or not isangle(sourceAng) then return end
    if not addUndoProp(prop1) then return end
    if IsValid(prop2) and not addUndoProp(prop2) then return end

    local specs = {}
    for i = 1, #sources do
        local ent = sources[i]
        local start = captureEntityState(ent)
        if not start then return end
        local targetPos, targetAng, localPos, localAng = M.TransformPoseRelativePrecise(start.pos, start.ang, sourcePos, sourceAng, pos, ang)

        if not M.IsFiniteVector(localPos) or not M.IsFiniteAngle(localAng)
            or not M.IsFiniteVector(targetPos) or not M.IsFiniteAngle(targetAng) then
            return
        end

        specs[i] = {
            source = ent,
            start = start,
            targetPos = cloneVec(targetPos),
            targetAng = cloneAng(targetAng)
        }

        if not addUndoProp(ent) then return end
        commitCheckpoint(task)
    end

    local created = {}
    local committed = {}

    if mode == M.COMMIT_COPY then
        for i = 1, #specs do
            if not IsValid(ply) then
                removeEntities(created)
                return
            end

            local spec = specs[i]
            if not IsValid(spec.source) then
                removeEntities(created)
                return
            end

            local target = cloneEntity(ply, spec.source, spec.targetPos, spec.targetAng)
            if not IsValid(target) then
                removeEntities(created)
                return
            end

            settlePhysics(target)
            committed[#committed + 1] = target
            created[#created + 1] = target
            commitCheckpoint(task)
        end
    else
        if mode == M.COMMIT_COPY_MOVE then
            for i = 1, #specs do
                if not IsValid(ply) then
                    removeEntities(created)
                    return
                end

                local spec = specs[i]
                if not IsValid(spec.source) then
                    removeEntities(created)
                    return
                end

                local backup = cloneEntity(ply, spec.source, spec.start.pos, spec.start.ang)
                if not IsValid(backup) then
                    removeEntities(created)
                    return
                end

                settlePhysics(backup)
                created[#created + 1] = backup
                commitCheckpoint(task)
            end
        end

        for i = 1, #specs do
            local spec = specs[i]
            local target = spec.source
            if not IsValid(target) then
                removeEntities(created)
                return
            end

            target:SetParent(nil)
            target:SetPos(toVector(spec.targetPos))
            target:SetAngles(toAngle(spec.targetAng))
            settlePhysics(target)
            committed[#committed + 1] = target
            commitCheckpoint(task)
        end
    end

    local nocollidePairs = {}
    local committedProp1 = committed[1]

    if IsValid(committedProp1) and IsValid(prop2) then
        applyCommitRelations(committedProp1, prop2, weld, effectiveNocollide, parent, created, nocollidePairs)
        commitCheckpoint(task)
    end

    for i = 2, #committed do
        applyCommitRelations(committed[i], committedProp1, weld, effectiveNocollide, parent, created, nocollidePairs)
        commitCheckpoint(task)
    end

    if effectiveNocollide then
        local overlapEntities = {}

        if IsValid(prop2) then
            overlapEntities[#overlapEntities + 1] = prop2
        end

        for i = 1, #committed do
            overlapEntities[#overlapEntities + 1] = committed[i]
        end

        applyOverlapNoCollides(overlapEntities, created, nocollidePairs, task)
    end

    if not IsValid(ply) then return end

    undo.Create("Magic Align")
        undo.SetPlayer(ply)
        undo.AddFunction(restoreCommitStep, undoProps, created)
    undo.Finish()
end

hook.Add("Think", "MagicAlignCommitQueue", function()
    local now = RealTime()
    for ply, pending in pairs(PENDING_COMMITS) do
        if not IsValid(ply) or now > (pending.expiresAt or 0) then
            PENDING_COMMITS[ply] = nil
        end
    end

    local task = table.remove(COMMIT_QUEUE, 1)
    if not task then return end

    task.deadline = SysTime() + M.GetCommitBudgetSeconds()

    local ok, err = coroutine.resume(task.co)
    if not ok then
        ErrorNoHalt(("[Magic Align] commit failed: %s\n"):format(tostring(err)))
        releaseCommitLock(task)
        return
    end

    if coroutine.status(task.co) == "dead" then
        releaseCommitLock(task)
        return
    end

    COMMIT_QUEUE[#COMMIT_QUEUE + 1] = task
end)

net.Receive(M.NET_BOUNDS_REQUEST, function(_, ply)
    if not IsValid(ply) then return end

    local ent = net.ReadEntity()
    local sessionId = net.ReadUInt(32)
    if not canUse(ply, ent) then return end

    local byPlayer = REQUEST_STATE[ply]
    if not byPlayer then
        byPlayer = {}
        REQUEST_STATE[ply] = byPlayer
    end

    local now = RealTime()
    local idx = ent:EntIndex()
    if now < (byPlayer[idx] or 0) then return end
    byPlayer[idx] = now + M.AABB_REQUEST_COOLDOWN

    local mins, maxs = M.GetLocalBounds(ent)

    net.Start(M.NET_BOUNDS_REPLY)
        net.WriteEntity(ent)
        net.WriteUInt(sessionId, 32)
        net.WriteBool(isvector(mins) and isvector(maxs))
        if isvector(mins) and isvector(maxs) then
            net.WritePreciseVector(mins)
            net.WritePreciseVector(maxs)
        end
    net.Send(ply)
end)

net.Receive(M.NET_VIEW_ANGLES, function(_, ply)
    if not game.SinglePlayer() or not IsValid(ply) then return end

    local ang = net.ReadPreciseAngle()
    if not M.IsFiniteAngle(ang) then return end

    local weapon = ply:GetActiveWeapon()
    if not IsValid(weapon) or weapon:GetClass() ~= "gmod_tool" then return end

    local tool = ply:GetTool()
    if not tool or tool.Mode ~= "magic_align" then return end

    ply:SetEyeAngles(toAngle(ang))
end)

net.Receive(M.NET, function(_, ply)
    if not IsValid(ply) or COMMIT_LOCK[ply] then return end

    local commitId = net.ReadUInt(32)
    local prop1 = net.ReadEntity()
    local prop2 = net.ReadEntity()
    local toolEnt = net.ReadEntity()
    local pos = net.ReadPreciseVector()
    local ang = net.ReadPreciseAngle()
    local sourcePoints = readPoints()
    local targetPoints = readPoints()
    local linkedCount = net.ReadUInt(8)
    local weld = net.ReadBool()
    local nocollide = net.ReadBool()
    local parent = net.ReadBool()
    local mode = net.ReadUInt(2)

    if PENDING_COMMITS[ply] and RealTime() < (PENDING_COMMITS[ply].expiresAt or 0) then return end
    if linkedCount > M.GetMaxLinkedProps() then return end
    if not M.IsFiniteVector(pos) or not M.IsFiniteAngle(ang) then return end
    if not finitePoints(sourcePoints) or not finitePoints(targetPoints) then return end
    if not IsValid(toolEnt) or toolEnt ~= ply:GetActiveWeapon() or toolEnt:GetClass() ~= "gmod_tool" then return end

    PENDING_COMMITS[ply] = {
        id = commitId,
        expiresAt = RealTime() + COMMIT_UPLOAD_TIMEOUT,
        totalLinked = linkedCount,
        totalParts = math.ceil(linkedCount / M.GetCommitLinkedPartSize()),
        receivedParts = {},
        receivedCount = 0,
        linkedProps = {},
        task = {
            ply = ply,
            prop1 = prop1,
            prop2 = prop2,
            pos = pos,
            ang = ang,
            sourcePoints = sourcePoints,
            targetPoints = targetPoints,
            linkedProps = {},
            weld = weld,
            nocollide = nocollide,
            parent = parent,
            mode = mode
        }
    }
end)

net.Receive(M.NET_COMMIT_LINKED_PART, function(_, ply)
    if not IsValid(ply) then return end

    local commitId = net.ReadUInt(32)
    local partIndex = net.ReadUInt(8)
    local totalParts = net.ReadUInt(8)
    local count = net.ReadUInt(8)
    local pending = PENDING_COMMITS[ply]
    if not pending or pending.id ~= commitId or RealTime() > (pending.expiresAt or 0) then return end
    if pending.receivedParts[partIndex] or totalParts ~= pending.totalParts then return end
    if partIndex < 1 or partIndex > pending.totalParts then return end
    local partSize = M.GetCommitLinkedPartSize()
    if count < 1 or count > partSize then return end

    local firstIndex = (partIndex - 1) * partSize + 1
    if firstIndex + count - 1 > pending.totalLinked then return end

    local entities = readEntities(count)
    for i = 1, #entities do
        pending.linkedProps[firstIndex + i - 1] = entities[i]
    end

    pending.receivedParts[partIndex] = true
    pending.receivedCount = pending.receivedCount + count
    pending.expiresAt = RealTime() + COMMIT_UPLOAD_TIMEOUT
end)

net.Receive(M.NET_COMMIT_FINISH, function(_, ply)
    if not IsValid(ply) or COMMIT_LOCK[ply] then return end

    local commitId = net.ReadUInt(32)
    local pending = PENDING_COMMITS[ply]
    if not pending or pending.id ~= commitId or RealTime() > (pending.expiresAt or 0) then return end
    if pending.receivedCount ~= pending.totalLinked then return end

    local linkedProps = {}
    for i = 1, pending.totalLinked do
        local ent = pending.linkedProps[i]
        if not IsValid(ent) then return end
        linkedProps[i] = ent
    end

    pending.task.linkedProps = linkedProps
    PENDING_COMMITS[ply] = nil
    queueCommit(pending.task)
end)
