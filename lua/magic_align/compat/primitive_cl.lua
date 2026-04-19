if SERVER then return end

MAGIC_ALIGN = MAGIC_ALIGN or {}

local M = MAGIC_ALIGN
local Compat = M.Compat or {}
local isvector = M.IsVectorLike
local isangle = M.IsAngleLike
local toVector = M.ToVector
local toAngle = M.ToAngle

M.Compat = Compat

hook.Remove("PostDrawTranslucentRenderables", "MagicAlignPrimitiveCompatGhosts")
hook.Remove("Think", "MagicAlignPrimitiveCompatGhosts")
hook.Remove("Think", "MagicAlignPrimitiveCompatGhostsThink")

local function cloneVec(v)
    if not isvector(v) then return end
    return M.CopyVectorPrecise(v)
end

local function cloneAng(a)
    if not isangle(a) then return end
    return M.CopyAnglePrecise(a)
end

local function cloneValue(value)
    if isvector(value) then
        return toVector(value)
    end

    if isangle(value) then
        return toAngle(value)
    end

    if istable(value) then
        return table.Copy(value)
    end

    return value
end

local function valueSignature(value)
    if isvector(value) then
        return ("v:%0.5f,%0.5f,%0.5f"):format(value.x, value.y, value.z)
    end

    if isangle(value) then
        return ("a:%0.5f,%0.5f,%0.5f"):format(value.p, value.y, value.r)
    end

    if istable(value) then
        local ok, json = pcall(util.TableToJSON, value)
        return ok and json or tostring(value)
    end

    return tostring(value)
end

local function ghostState(state)
    if not istable(state) then return end

    state.compatGhosts = state.compatGhosts or {}
    state.compatGhosts.linked = state.compatGhosts.linked or {}

    return state.compatGhosts
end

local function removeGhostEntity(entry)
    if not istable(entry) then return end

    if IsValid(entry.ghost) then
        entry.ghost:Remove()
    end

    entry.ghost = nil
    entry.revision = nil
    entry.failed = nil
end

local function primitiveRevision(ent)
    if not IsValid(ent) then return "invalid" end

    local parts = {
        ent:GetClass(),
        tostring(math.max(tonumber(ent:GetModelScale() or 1) or 1, M.MODEL_SCALE_EPSILON)),
        tostring(ent:GetSkin() or 0),
        tostring(ent:GetMaterial() or "")
    }

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
                parts[#parts + 1] = name .. "=" .. valueSignature(keys[name])
            end
        end
    end

    return table.concat(parts, "|")
end

local function previewRenderMode(src, alpha)
    local mode = isfunction(src.GetRenderMode) and src:GetRenderMode() or RENDERMODE_NORMAL

    if alpha < 255 then
        if mode == RENDERMODE_NORMAL or mode == RENDERMODE_NONE or mode == RENDERMODE_TRANSCOLOR then
            mode = RENDERMODE_TRANSALPHA
        end
    end

    return mode
end

local function ensureGhostEntity(entry)
    if not istable(entry) or not IsValid(entry.ent) then return end
    if entry.failed then return end

    local ghost = entry.ghost
    if IsValid(ghost) and ghost:GetClass() == entry.ent:GetClass() then
        return ghost
    end

    removeGhostEntity(entry)

    if not ents or not isfunction(ents.CreateClientside) then
        entry.failed = true
        return
    end

    ghost = ents.CreateClientside(entry.ent:GetClass(), RENDERGROUP_TRANSLUCENT)
    if not IsValid(ghost) then
        entry.failed = true
        return
    end

    local model = entry.ent:GetModel()
    if isstring(model) and model ~= "" and isfunction(ghost.SetModel) then
        ghost:SetModel(model)
    end

    ghost:SetNoDraw(true)
    ghost:SetRenderMode(RENDERMODE_TRANSALPHA)
    ghost:DrawShadow(false)

    if isfunction(ghost.Spawn) then
        ghost:Spawn()
    end

    if isfunction(ghost.Activate) then
        ghost:Activate()
    end

    entry.ghost = ghost
    entry.failed = nil
    entry.revision = nil

    return ghost
end

local function syncGhostEntity(entry)
    local src = istable(entry) and entry.ent or nil
    local ghost = istable(entry) and entry.ghost or nil
    if not IsValid(src) or not IsValid(ghost) then return false end
    if not isvector(entry.pos) or not isangle(entry.ang) then return false end

    local revision = primitiveRevision(src)
    if entry.revision ~= revision then
        if isfunction(src.PrimitiveGetKeys) then
            local keys = src:PrimitiveGetKeys()
            if istable(keys) then
                for name, value in pairs(keys) do
                    local setter = ghost["Set" .. name]
                    if isfunction(setter) then
                        setter(ghost, cloneValue(value))
                    end
                end
            end
        end

        if isfunction(ghost.PrimitiveReconstruct) then
            ghost:PrimitiveReconstruct()
        end

        entry.revision = revision
    end

    local srcColor = src:GetColor()
    local color = entry.color or Color(srcColor.r, srcColor.g, srcColor.b, 120)
    local model = src:GetModel()

    if isstring(model) and model ~= "" and isfunction(ghost.SetModel) and ghost:GetModel() ~= model then
        ghost:SetModel(model)
    end

    ghost:SetPos(toVector(entry.pos))
    ghost:SetAngles(toAngle(entry.ang))
    ghost:SetSkin(src:GetSkin() or 0)
    ghost:SetMaterial(src:GetMaterial() or "")
    ghost:SetColor(color)
    ghost:SetRenderMode(previewRenderMode(src, color.a or 255))
    ghost:SetCollisionGroup(src:GetCollisionGroup())
    ghost:SetModelScale(math.max(tonumber(src:GetModelScale() or 1) or 1, M.MODEL_SCALE_EPSILON), 0)

    if isfunction(src.GetRenderFX) and isfunction(ghost.SetRenderFX) then
        ghost:SetRenderFX(src:GetRenderFX())
    end

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

    if isfunction(ghost.SetupBones) then
        ghost:SetupBones()
    end

    ghost:SetNoDraw(false)

    return true
end

local function refreshGhostEntry(entry)
    local ghost = ensureGhostEntity(entry)
    if not IsValid(ghost) then return false end

    if syncGhostEntity(entry) then
        return true
    end

    ghost:SetNoDraw(true)
    return false
end

local function hideGhostEntry(entry)
    if not istable(entry) then return end
    if IsValid(entry.ghost) then
        entry.ghost:SetNoDraw(true)
    end
end

function Compat.ClearGhost(state, ent)
    local ghosts = ghostState(state)
    if not ghosts then return end

    if IsValid(ent) then
        removeGhostEntity(ghosts.linked[ent])
        ghosts.linked[ent] = nil
        return
    end

    removeGhostEntity(ghosts.main)
    ghosts.main = nil
end

function Compat.ClearGhosts(state)
    local ghosts = ghostState(state)
    if not ghosts then return end

    removeGhostEntity(ghosts.main)
    ghosts.main = nil

    for ent in pairs(ghosts.linked) do
        removeGhostEntity(ghosts.linked[ent])
        ghosts.linked[ent] = nil
    end
end

function Compat.SetGhost(state, ent, pos, ang, alphaFn, linked)
    if not Compat.IsPrimitive(ent) then return false end

    local ghosts = ghostState(state)
    if not ghosts then return true end

    local entry = linked and ghosts.linked[ent] or ghosts.main
    if not istable(entry) or entry.ent ~= ent then
        removeGhostEntity(entry)
        entry = { ent = ent }
    end

    local srcColor = ent:GetColor()
    local alpha = isfunction(alphaFn) and alphaFn(srcColor.a) or tonumber(alphaFn) or 120

    entry.ent = ent
    entry.pos = cloneVec(pos)
    entry.ang = cloneAng(ang)
    entry.color = Color(srcColor.r, srcColor.g, srcColor.b, math.Clamp(alpha, 0, 255))
    entry.failed = nil

    if linked then
        ghosts.linked[ent] = entry
    else
        ghosts.main = entry
    end

    refreshGhostEntry(entry)

    return true
end

hook.Add("Think", "MagicAlignPrimitiveCompatGhostsThink", function()
    local state = M.ClientState
    if not istable(state) then return end

    local ghosts = state.compatGhosts
    if not istable(ghosts) then return end

    local ply = LocalPlayer()
    if not (IsValid(ply) and M.GetActiveMagicAlignTool and M.GetActiveMagicAlignTool(ply)) then
        hideGhostEntry(ghosts.main)

        for _, entry in pairs(ghosts.linked or {}) do
            hideGhostEntry(entry)
        end

        return
    end

    if ghosts.main and not refreshGhostEntry(ghosts.main) then
        removeGhostEntity(ghosts.main)
        ghosts.main = nil
    end

    for ent, entry in pairs(ghosts.linked or {}) do
        if not refreshGhostEntry(entry) then
            removeGhostEntity(entry)
            ghosts.linked[ent] = nil
        end
    end
end)

if istable(M.ClientState) then
    Compat.ClearGhosts(M.ClientState)
end
