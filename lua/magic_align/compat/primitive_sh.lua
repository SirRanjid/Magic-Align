MAGIC_ALIGN = MAGIC_ALIGN or {}

local M = MAGIC_ALIGN
local Compat = M.Compat or {}

M.Compat = Compat

local function isPrimitiveBaseClass(class)
    if not isstring(class) or class == "" then return false end
    if class == "primitive_base" then return true end
    if not scripted_ents or not scripted_ents.IsBasedOn then return false end

    local ok, basedOn = pcall(scripted_ents.IsBasedOn, class, "primitive_base")
    return ok and basedOn == true
end

function Compat.IsPrimitive(ent)
    if not IsValid(ent) then return false end
    if ent.IsPrimitive == true then return true end

    return isPrimitiveBaseClass(ent:GetClass())
end

M.IsPrimitive = Compat.IsPrimitive
