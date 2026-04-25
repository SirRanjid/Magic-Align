MAGIC_ALIGN = MAGIC_ALIGN or {}

local M = MAGIC_ALIGN
local DEG_TO_RAD = math.pi / 180
local RAD_TO_DEG = 180 / math.pi
local GVector = Vector
local GAngle = Angle
local gIsVector = isvector or function() return false end
local gIsAngle = isangle or function() return false end

M.COMPUTE_EPSILON = M.COMPUTE_EPSILON or 1e-12
M.COMPUTE_VECTOR_EPSILON_SQR = M.COMPUTE_VECTOR_EPSILON_SQR or (M.COMPUTE_EPSILON * M.COMPUTE_EPSILON)
M.DIRECTION_DOT_EPSILON = M.DIRECTION_DOT_EPSILON or 1e-12
M.MATRIX_ANGLE_SINGULARITY_EPSILON = M.MATRIX_ANGLE_SINGULARITY_EPSILON or 1e-12
M.PICKING_EPSILON = M.PICKING_EPSILON or 1e-6
M.PICKING_VECTOR_EPSILON_SQR = M.PICKING_VECTOR_EPSILON_SQR or 1e-12
M.VALIDATION_EPSILON = M.VALIDATION_EPSILON or 1e-6
M.CONVAR_ROUNDTRIP_EPSILON = M.CONVAR_ROUNDTRIP_EPSILON or 1e-12
M.UI_COMPARE_EPSILON = M.UI_COMPARE_EPSILON or 1e-4
M.MODEL_SCALE_EPSILON = M.MODEL_SCALE_EPSILON or 0.001
M.AABB_PICKING_PADDING = M.AABB_PICKING_PADDING or 0.25

local vectorLengthSqr
local dotVectors
local crossVectors
local scaleVector
local normalizeVector
local angleMatrix
local matrixAngle
local toGModVector
local toGModAngle

local function finiteNumber(value)
    value = tonumber(value)
    return value ~= nil and value == value and value ~= math.huge and value ~= -math.huge
end

local function numberOrZero(value)
    value = tonumber(value)
    if finiteNumber(value) then
        return value
    end

    return 0
end

local VectorPMethods = {}
local AnglePMethods = {}
local VectorPMeta = {}
local AnglePMeta = {}

local function isVectorP(value)
    return istable(value) and getmetatable(value) == VectorPMeta
end

local function isAngleP(value)
    return istable(value) and getmetatable(value) == AnglePMeta
end

local function isVectorLike(value)
    return isVectorP(value) or gIsVector(value)
end

local function isAngleLike(value)
    return isAngleP(value) or gIsAngle(value)
end

local function parseTripleString(value)
    local out = {}

    for token in tostring(value or ""):gmatch("[-+]?%d*%.?%d+[eE]?[-+]?%d*") do
        local parsed = tonumber(token)
        if parsed ~= nil then
            out[#out + 1] = parsed
            if #out >= 3 then break end
        end
    end

    if #out < 3 then return end
    return out[1], out[2], out[3]
end

local function VectorP(x, y, z)
    if y == nil and z == nil then
        if isVectorLike(x) then
            return setmetatable({
                x = numberOrZero(x.x),
                y = numberOrZero(x.y),
                z = numberOrZero(x.z)
            }, VectorPMeta)
        elseif isstring(x) then
            x, y, z = parseTripleString(x)
        end
    end

    return setmetatable({
        x = numberOrZero(x),
        y = numberOrZero(y),
        z = numberOrZero(z)
    }, VectorPMeta)
end

local function AngleP(p, y, r)
    if y == nil and r == nil then
        if isAngleLike(p) then
            return setmetatable({
                p = numberOrZero(p.p),
                y = numberOrZero(p.y),
                r = numberOrZero(p.r)
            }, AnglePMeta)
        elseif isstring(p) then
            p, y, r = parseTripleString(p)
        end
    end

    return setmetatable({
        p = numberOrZero(p),
        y = numberOrZero(y),
        r = numberOrZero(r)
    }, AnglePMeta)
end

local function angleAliasKey(key)
    if key == "pitch" then return "p" end
    if key == "yaw" then return "y" end
    if key == "roll" then return "r" end
end

local function vectorOperand(value)
    return isVectorLike(value) and value or VectorP(0, 0, 0)
end

local function angleOperand(value)
    return isAngleLike(value) and value or AngleP(0, 0, 0)
end

local function safeDivisor(value)
    value = numberOrZero(value)
    if math.abs(value) > M.COMPUTE_EPSILON then
        return value
    end

    return value < 0 and -M.COMPUTE_EPSILON or M.COMPUTE_EPSILON
end

VectorPMeta.__index = VectorPMethods
VectorPMeta.__type = "VectorP"
VectorPMeta.__tostring = function(v)
    return ("%.17g %.17g %.17g"):format(numberOrZero(v.x), numberOrZero(v.y), numberOrZero(v.z))
end
VectorPMeta.__unm = function(v)
    v = vectorOperand(v)
    return VectorP(-v.x, -v.y, -v.z)
end
VectorPMeta.__add = function(a, b)
    a = vectorOperand(a)
    b = vectorOperand(b)
    return VectorP(a.x + b.x, a.y + b.y, a.z + b.z)
end
VectorPMeta.__sub = function(a, b)
    a = vectorOperand(a)
    b = vectorOperand(b)
    return VectorP(a.x - b.x, a.y - b.y, a.z - b.z)
end
VectorPMeta.__mul = function(a, b)
    if isVectorLike(a) and isVectorLike(b) then
        return VectorP(a.x * b.x, a.y * b.y, a.z * b.z)
    elseif isVectorLike(a) then
        return VectorP(a.x * numberOrZero(b), a.y * numberOrZero(b), a.z * numberOrZero(b))
    elseif isVectorLike(b) then
        return VectorP(numberOrZero(a) * b.x, numberOrZero(a) * b.y, numberOrZero(a) * b.z)
    end

    return VectorP(0, 0, 0)
end
VectorPMeta.__div = function(a, b)
    a = vectorOperand(a)

    if isVectorLike(b) then
        return VectorP(
            a.x / safeDivisor(b.x),
            a.y / safeDivisor(b.y),
            a.z / safeDivisor(b.z)
        )
    end

    local divisor = safeDivisor(b)
    return VectorP(a.x / divisor, a.y / divisor, a.z / divisor)
end
VectorPMeta.__eq = function(a, b)
    return isVectorLike(a) and isVectorLike(b)
        and a.x == b.x
        and a.y == b.y
        and a.z == b.z
end

AnglePMeta.__index = function(a, key)
    local alias = angleAliasKey(key)
    if alias then
        return rawget(a, alias)
    end

    return AnglePMethods[key]
end
AnglePMeta.__newindex = function(a, key, value)
    rawset(a, angleAliasKey(key) or key, numberOrZero(value))
end
AnglePMeta.__type = "AngleP"
AnglePMeta.__tostring = function(a)
    return ("%.17g %.17g %.17g"):format(numberOrZero(a.p), numberOrZero(a.y), numberOrZero(a.r))
end
AnglePMeta.__eq = function(a, b)
    return isAngleLike(a) and isAngleLike(b)
        and a.p == b.p
        and a.y == b.y
        and a.r == b.r
end

function VectorPMethods:Clone()
    return VectorP(self)
end

function VectorPMethods:Set(value)
    value = vectorOperand(value)
    self.x = numberOrZero(value.x)
    self.y = numberOrZero(value.y)
    self.z = numberOrZero(value.z)
end

function VectorPMethods:Unpack()
    return self.x, self.y, self.z
end

function VectorPMethods:LengthSqr()
    return vectorLengthSqr(self)
end

function VectorPMethods:Length()
    return math.sqrt(vectorLengthSqr(self))
end

function VectorPMethods:Dot(other)
    return dotVectors(self, other)
end

function VectorPMethods:Cross(other)
    return crossVectors(self, other)
end

function VectorPMethods:Distance(other)
    return math.sqrt(self:DistToSqr(other))
end

function VectorPMethods:DistToSqr(other)
    other = vectorOperand(other)
    local dx = self.x - other.x
    local dy = self.y - other.y
    local dz = self.z - other.z
    return dx * dx + dy * dy + dz * dz
end

function VectorPMethods:GetNormalized()
    return normalizeVector(self, M.COMPUTE_VECTOR_EPSILON_SQR) or VectorP(0, 0, 0)
end

function VectorPMethods:Normalize()
    local normalized = normalizeVector(self, M.COMPUTE_VECTOR_EPSILON_SQR)
    if normalized then
        self:Set(normalized)
    end

    return self
end

function VectorPMethods:Angle()
    local forward = normalizeVector(self, M.COMPUTE_VECTOR_EPSILON_SQR)
    if not forward then return AngleP(0, 0, 0) end

    local xyDist = math.sqrt(forward.x * forward.x + forward.y * forward.y)
    return AngleP(
        math.atan2(-forward.z, xyDist) * RAD_TO_DEG,
        math.atan2(forward.y, forward.x) * RAD_TO_DEG,
        0
    )
end

function VectorPMethods:ToScreen()
    local vec = toGModVector(self)
    if CLIENT and vec then
        return vec:ToScreen()
    end

    return { visible = false, x = 0, y = 0 }
end

function AnglePMethods:Clone()
    return AngleP(self)
end

function AnglePMethods:Set(value)
    value = angleOperand(value)
    self.p = numberOrZero(value.p)
    self.y = numberOrZero(value.y)
    self.r = numberOrZero(value.r)
end

function AnglePMethods:Unpack()
    return self.p, self.y, self.r
end

function AnglePMethods:Pitch()
    return self.p
end

function AnglePMethods:Yaw()
    return self.y
end

function AnglePMethods:Roll()
    return self.r
end

function AnglePMethods:Forward()
    return M.AngleForwardPrecise(self)
end

function AnglePMethods:Right()
    return M.AngleRightPrecise(self)
end

function AnglePMethods:Up()
    return M.AngleUpPrecise(self)
end

function AnglePMethods:RotateAroundAxis(axis, degrees)
    self:Set(M.RotateAngleAroundAxisPrecise(self, axis, degrees))
    return self
end

function toGModVector(value)
    if gIsVector(value) then return value end
    if not isVectorP(value) then return end
    if not GVector then return end

    return GVector(value.x, value.y, value.z)
end

function toGModAngle(value)
    if gIsAngle(value) then return value end
    if not isAngleP(value) then return end
    if not GAngle then return end

    return GAngle(value.p, value.y, value.r)
end

M.VectorP = VectorP
M.AngleP = AngleP
M.VectorPMeta = VectorPMeta
M.AnglePMeta = AnglePMeta
M.IsVectorP = isVectorP
M.IsAngleP = isAngleP
M.IsVectorLike = isVectorLike
M.IsAngleLike = isAngleLike
M.ToVector = toGModVector
M.ToAngle = toGModAngle

_G.VectorP = VectorP
_G.AngleP = AngleP

local function vecOrZero(value)
    return isVectorLike(value) and value or VectorP(0, 0, 0)
end

local function angOrZero(value)
    return isAngleLike(value) and value or AngleP(0, 0, 0)
end

local function copyVector(value)
    value = vecOrZero(value)
    return VectorP(numberOrZero(value.x), numberOrZero(value.y), numberOrZero(value.z))
end

local function copyAngle(value)
    value = angOrZero(value)
    return AngleP(numberOrZero(value.p), numberOrZero(value.y), numberOrZero(value.r))
end

vectorLengthSqr = function(vec)
    if not isVectorLike(vec) then return 0 end

    local x = numberOrZero(vec.x)
    local y = numberOrZero(vec.y)
    local z = numberOrZero(vec.z)

    return x * x + y * y + z * z
end

dotVectors = function(a, b)
    if not isVectorLike(a) or not isVectorLike(b) then return 0 end

    return numberOrZero(a.x) * numberOrZero(b.x)
        + numberOrZero(a.y) * numberOrZero(b.y)
        + numberOrZero(a.z) * numberOrZero(b.z)
end

crossVectors = function(a, b)
    if not isVectorLike(a) or not isVectorLike(b) then return VectorP(0, 0, 0) end

    local ax, ay, az = numberOrZero(a.x), numberOrZero(a.y), numberOrZero(a.z)
    local bx, by, bz = numberOrZero(b.x), numberOrZero(b.y), numberOrZero(b.z)

    return VectorP(
        ay * bz - az * by,
        az * bx - ax * bz,
        ax * by - ay * bx
    )
end

local function addVectors(a, b)
    a = vecOrZero(a)
    b = vecOrZero(b)

    return VectorP(
        numberOrZero(a.x) + numberOrZero(b.x),
        numberOrZero(a.y) + numberOrZero(b.y),
        numberOrZero(a.z) + numberOrZero(b.z)
    )
end

local function subtractVectors(a, b)
    a = vecOrZero(a)
    b = vecOrZero(b)

    return VectorP(
        numberOrZero(a.x) - numberOrZero(b.x),
        numberOrZero(a.y) - numberOrZero(b.y),
        numberOrZero(a.z) - numberOrZero(b.z)
    )
end

scaleVector = function(vec, scale)
    vec = vecOrZero(vec)
    scale = numberOrZero(scale)

    return VectorP(
        numberOrZero(vec.x) * scale,
        numberOrZero(vec.y) * scale,
        numberOrZero(vec.z) * scale
    )
end

normalizeVector = function(vec, epsilonSqr)
    if not isVectorLike(vec) then return end

    local lengthSqr = vectorLengthSqr(vec)
    if lengthSqr <= (tonumber(epsilonSqr) or M.COMPUTE_VECTOR_EPSILON_SQR) then return end

    local invLength = 1 / math.sqrt(lengthSqr)
    return scaleVector(vec, invLength)
end

local function projectVector(vec, axis, epsilonSqr)
    if not isVectorLike(vec) then return end

    local out = copyVector(vec)
    local unitAxis = normalizeVector(axis, epsilonSqr)
    if unitAxis then
        out = subtractVectors(out, scaleVector(unitAxis, dotVectors(out, unitAxis)))
    end

    return normalizeVector(out, epsilonSqr)
end

angleMatrix = function(ang)
    ang = angOrZero(ang)

    local sp, sy, sr = math.sin(ang.p * DEG_TO_RAD), math.sin(ang.y * DEG_TO_RAD), math.sin(ang.r * DEG_TO_RAD)
    local cp, cy, cr = math.cos(ang.p * DEG_TO_RAD), math.cos(ang.y * DEG_TO_RAD), math.cos(ang.r * DEG_TO_RAD)

    return {
        { cp * cy, sp * sr * cy - cr * sy, sp * cr * cy + sr * sy },
        { cp * sy, sp * sr * sy + cr * cy, sp * cr * sy - sr * cy },
        { -sp, sr * cp, cr * cp }
    }
end

local function multiplyMatrix(a, b)
    return {
        {
            a[1][1] * b[1][1] + a[1][2] * b[2][1] + a[1][3] * b[3][1],
            a[1][1] * b[1][2] + a[1][2] * b[2][2] + a[1][3] * b[3][2],
            a[1][1] * b[1][3] + a[1][2] * b[2][3] + a[1][3] * b[3][3]
        },
        {
            a[2][1] * b[1][1] + a[2][2] * b[2][1] + a[2][3] * b[3][1],
            a[2][1] * b[1][2] + a[2][2] * b[2][2] + a[2][3] * b[3][2],
            a[2][1] * b[1][3] + a[2][2] * b[2][3] + a[2][3] * b[3][3]
        },
        {
            a[3][1] * b[1][1] + a[3][2] * b[2][1] + a[3][3] * b[3][1],
            a[3][1] * b[1][2] + a[3][2] * b[2][2] + a[3][3] * b[3][2],
            a[3][1] * b[1][3] + a[3][2] * b[2][3] + a[3][3] * b[3][3]
        }
    }
end

local function transposeMultiplyMatrix(a, b)
    return {
        {
            a[1][1] * b[1][1] + a[2][1] * b[2][1] + a[3][1] * b[3][1],
            a[1][1] * b[1][2] + a[2][1] * b[2][2] + a[3][1] * b[3][2],
            a[1][1] * b[1][3] + a[2][1] * b[2][3] + a[3][1] * b[3][3]
        },
        {
            a[1][2] * b[1][1] + a[2][2] * b[2][1] + a[3][2] * b[3][1],
            a[1][2] * b[1][2] + a[2][2] * b[2][2] + a[3][2] * b[3][2],
            a[1][2] * b[1][3] + a[2][2] * b[2][3] + a[3][2] * b[3][3]
        },
        {
            a[1][3] * b[1][1] + a[2][3] * b[2][1] + a[3][3] * b[3][1],
            a[1][3] * b[1][2] + a[2][3] * b[2][2] + a[3][3] * b[3][2],
            a[1][3] * b[1][3] + a[2][3] * b[2][3] + a[3][3] * b[3][3]
        }
    }
end

local function transformVector(matrix, vec)
    vec = vecOrZero(vec)
    local x, y, z = numberOrZero(vec.x), numberOrZero(vec.y), numberOrZero(vec.z)

    return VectorP(
        matrix[1][1] * x + matrix[1][2] * y + matrix[1][3] * z,
        matrix[2][1] * x + matrix[2][2] * y + matrix[2][3] * z,
        matrix[3][1] * x + matrix[3][2] * y + matrix[3][3] * z
    )
end

local function localToWorldPosition(localPos, originPos, originAng)
    localPos = vecOrZero(localPos)
    originPos = vecOrZero(originPos)
    originAng = angOrZero(originAng)

    local x, y, z = numberOrZero(localPos.x), numberOrZero(localPos.y), numberOrZero(localPos.z)
    local sp, sy, sr = math.sin(originAng.p * DEG_TO_RAD), math.sin(originAng.y * DEG_TO_RAD), math.sin(originAng.r * DEG_TO_RAD)
    local cp, cy, cr = math.cos(originAng.p * DEG_TO_RAD), math.cos(originAng.y * DEG_TO_RAD), math.cos(originAng.r * DEG_TO_RAD)

    return VectorP(
        numberOrZero(originPos.x) + (cp * cy) * x + (sp * sr * cy - cr * sy) * y + (sp * cr * cy + sr * sy) * z,
        numberOrZero(originPos.y) + (cp * sy) * x + (sp * sr * sy + cr * cy) * y + (sp * cr * sy - sr * cy) * z,
        numberOrZero(originPos.z) + (-sp) * x + (sr * cp) * y + (cr * cp) * z
    )
end

local function worldToLocalPosition(worldPos, originPos, originAng)
    worldPos = vecOrZero(worldPos)
    originPos = vecOrZero(originPos)
    originAng = angOrZero(originAng)

    local x = numberOrZero(worldPos.x) - numberOrZero(originPos.x)
    local y = numberOrZero(worldPos.y) - numberOrZero(originPos.y)
    local z = numberOrZero(worldPos.z) - numberOrZero(originPos.z)
    local sp, sy, sr = math.sin(originAng.p * DEG_TO_RAD), math.sin(originAng.y * DEG_TO_RAD), math.sin(originAng.r * DEG_TO_RAD)
    local cp, cy, cr = math.cos(originAng.p * DEG_TO_RAD), math.cos(originAng.y * DEG_TO_RAD), math.cos(originAng.r * DEG_TO_RAD)

    local m11, m12, m13 = cp * cy, sp * sr * cy - cr * sy, sp * cr * cy + sr * sy
    local m21, m22, m23 = cp * sy, sp * sr * sy + cr * cy, sp * cr * sy - sr * cy
    local m31, m32, m33 = -sp, sr * cp, cr * cp

    return VectorP(
        m11 * x + m21 * y + m31 * z,
        m12 * x + m22 * y + m32 * z,
        m13 * x + m23 * y + m33 * z
    )
end

local function inverseTransformVector(matrix, vec)
    vec = vecOrZero(vec)
    local x, y, z = numberOrZero(vec.x), numberOrZero(vec.y), numberOrZero(vec.z)

    return VectorP(
        matrix[1][1] * x + matrix[2][1] * y + matrix[3][1] * z,
        matrix[1][2] * x + matrix[2][2] * y + matrix[3][2] * z,
        matrix[1][3] * x + matrix[2][3] * y + matrix[3][3] * z
    )
end

local function matrixFromBasis(forward, left, up)
    return {
        { numberOrZero(forward.x), numberOrZero(left.x), numberOrZero(up.x) },
        { numberOrZero(forward.y), numberOrZero(left.y), numberOrZero(up.y) },
        { numberOrZero(forward.z), numberOrZero(left.z), numberOrZero(up.z) }
    }
end

local function axisAngleMatrix(axis, degrees)
    axis = normalizeVector(axis, M.COMPUTE_VECTOR_EPSILON_SQR)
    if not axis then return end

    local rad = numberOrZero(degrees) * DEG_TO_RAD
    local c = math.cos(rad)
    local s = math.sin(rad)
    local t = 1 - c
    local x, y, z = numberOrZero(axis.x), numberOrZero(axis.y), numberOrZero(axis.z)

    return {
        { t * x * x + c, t * x * y - s * z, t * x * z + s * y },
        { t * x * y + s * z, t * y * y + c, t * y * z - s * x },
        { t * x * z - s * y, t * y * z + s * x, t * z * z + c }
    }
end

matrixAngle = function(matrix)
    local forwardX = matrix[1][1]
    local forwardY = matrix[2][1]
    local forwardZ = matrix[3][1]
    local leftX = matrix[1][2]
    local leftY = matrix[2][2]
    local leftZ = matrix[3][2]
    local upZ = matrix[3][3]
    local xyDist = math.sqrt(forwardX * forwardX + forwardY * forwardY)

    if xyDist > M.MATRIX_ANGLE_SINGULARITY_EPSILON then
        return AngleP(
            math.atan2(-forwardZ, xyDist) * RAD_TO_DEG,
            math.atan2(forwardY, forwardX) * RAD_TO_DEG,
            math.atan2(leftZ, upZ) * RAD_TO_DEG
        )
    end

    return AngleP(
        math.atan2(-forwardZ, xyDist) * RAD_TO_DEG,
        math.atan2(-leftX, leftY) * RAD_TO_DEG,
        0
    )
end

function M.IsFiniteNumber(value)
    return finiteNumber(value)
end

function M.IsFiniteVector(vec)
    return isVectorLike(vec) and finiteNumber(vec.x) and finiteNumber(vec.y) and finiteNumber(vec.z)
end

function M.IsFiniteAngle(ang)
    return isAngleLike(ang) and finiteNumber(ang.p) and finiteNumber(ang.y) and finiteNumber(ang.r)
end

function M.CopyVectorPrecise(vec)
    return copyVector(vec)
end

function M.CopyAnglePrecise(ang)
    return copyAngle(ang)
end

function M.AddVectorsPrecise(a, b)
    return addVectors(a, b)
end

function M.SubtractVectorsPrecise(a, b)
    return subtractVectors(a, b)
end

function M.ScaleVectorPrecise(vec, scale)
    return scaleVector(vec, scale)
end

function M.DotVectorsPrecise(a, b)
    return dotVectors(a, b)
end

function M.CrossVectorsPrecise(a, b)
    return crossVectors(a, b)
end

function M.VectorLengthSqrPrecise(vec)
    return vectorLengthSqr(vec)
end

function M.NormalizeVectorPrecise(vec, epsilonSqr)
    return normalizeVector(vec, epsilonSqr)
end

function M.ProjectVectorPrecise(vec, axis, epsilonSqr)
    return projectVector(vec, axis, epsilonSqr)
end

function M.AngleMatrixPrecise(ang)
    return angleMatrix(ang)
end

function M.MatrixAnglePrecise(matrix)
    return matrixAngle(matrix)
end

function M.AngleForwardPrecise(ang)
    local matrix = angleMatrix(ang)
    return VectorP(matrix[1][1], matrix[2][1], matrix[3][1])
end

function M.AngleLeftPrecise(ang)
    local matrix = angleMatrix(ang)
    return VectorP(matrix[1][2], matrix[2][2], matrix[3][2])
end

function M.AngleRightPrecise(ang)
    local left = M.AngleLeftPrecise(ang)
    return VectorP(-left.x, -left.y, -left.z)
end

function M.AngleUpPrecise(ang)
    local matrix = angleMatrix(ang)
    return VectorP(matrix[1][3], matrix[2][3], matrix[3][3])
end

function M.AngleAxesPrecise(ang)
    return M.AngleForwardPrecise(ang), M.AngleRightPrecise(ang), M.AngleUpPrecise(ang)
end

function M.AngleFromForwardUpPrecise(forward, upHint)
    local forwardAxis = normalizeVector(forward, M.COMPUTE_VECTOR_EPSILON_SQR)
    if not forwardAxis then return end

    local upAxis = projectVector(upHint, forwardAxis, M.COMPUTE_VECTOR_EPSILON_SQR)
    if not upAxis then return end

    local leftAxis = normalizeVector(crossVectors(upAxis, forwardAxis), M.COMPUTE_VECTOR_EPSILON_SQR)
    if not leftAxis then return end

    upAxis = normalizeVector(crossVectors(forwardAxis, leftAxis), M.COMPUTE_VECTOR_EPSILON_SQR) or upAxis
    return matrixAngle(matrixFromBasis(forwardAxis, leftAxis, upAxis))
end

function M.RotateAngleAroundAxisPrecise(ang, axis, degrees)
    degrees = numberOrZero(degrees)
    if math.abs(degrees) <= M.COMPUTE_EPSILON then
        return copyAngle(ang)
    end

    local rotationMatrix = axisAngleMatrix(axis, degrees)
    if not rotationMatrix then
        return copyAngle(ang)
    end

    return matrixAngle(multiplyMatrix(rotationMatrix, angleMatrix(ang)))
end

function M.LocalToWorldPrecise(localPos, localAng, originPos, originAng)
    local originMatrix = angleMatrix(originAng)
    local localMatrix = angleMatrix(localAng)
    local pos = addVectors(originPos, transformVector(originMatrix, localPos))
    local ang = matrixAngle(multiplyMatrix(originMatrix, localMatrix))

    return pos, ang
end

function M.LocalToWorldPosPrecise(localPos, originPos, originAng)
    return localToWorldPosition(localPos, originPos, originAng)
end

function M.WorldToLocalPosPrecise(worldPos, originPos, originAng)
    return worldToLocalPosition(worldPos, originPos, originAng)
end

function M.WorldToLocalPrecise(worldPos, worldAng, originPos, originAng)
    local originMatrix = angleMatrix(originAng)
    local worldMatrix = angleMatrix(worldAng)
    local delta = subtractVectors(worldPos, originPos)
    local pos = inverseTransformVector(originMatrix, delta)
    local ang = matrixAngle(transposeMultiplyMatrix(originMatrix, worldMatrix))

    return pos, ang
end

function M.TransformPoseRelativePrecise(pos, ang, fromPos, fromAng, toPos, toAng)
    local localPos, localAng = M.WorldToLocalPrecise(pos, ang, fromPos, fromAng)
    local worldPos, worldAng = M.LocalToWorldPrecise(localPos, localAng, toPos, toAng)

    return worldPos, worldAng, localPos, localAng
end

LocalToWorldPrecise = M.LocalToWorldPrecise
WorldToLocalPrecise = M.WorldToLocalPrecise

if net then
    function net.WritePreciseVector(vec)
        vec = vecOrZero(vec)
        net.WriteDouble(tonumber(vec.x) or 0)
        net.WriteDouble(tonumber(vec.y) or 0)
        net.WriteDouble(tonumber(vec.z) or 0)
    end

    function net.ReadPreciseVector()
        return VectorP(net.ReadDouble(), net.ReadDouble(), net.ReadDouble())
    end

    function net.WritePreciseAngle(ang)
        ang = angOrZero(ang)
        net.WriteDouble(tonumber(ang.p) or 0)
        net.WriteDouble(tonumber(ang.y) or 0)
        net.WriteDouble(tonumber(ang.r) or 0)
    end

    function net.ReadPreciseAngle()
        return AngleP(net.ReadDouble(), net.ReadDouble(), net.ReadDouble())
    end
end

return M
