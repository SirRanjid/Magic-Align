MAGIC_ALIGN = MAGIC_ALIGN or {}

local M = MAGIC_ALIGN

M.ROUNDING_MIN = 0
M.ROUNDING_DISABLED = 11
M.ROUNDING_MAX = M.ROUNDING_DISABLED
M.DEFAULT_DISPLAY_ROUNDING = 5

local function normalizeRoundingSetting(value, fallback)
    local defaultValue = tonumber(fallback)
    if defaultValue == nil then
        defaultValue = M.DEFAULT_DISPLAY_ROUNDING
    end

    return math.Clamp(math.Round(tonumber(value) or defaultValue), M.ROUNDING_MIN, M.ROUNDING_MAX)
end

local function negativeZeroText(decimals, trim)
    if trim then
        return "0"
    end

    if decimals and decimals > 0 then
        return string.format("%." .. decimals .. "f", 0)
    end

    return "0"
end

function M.NormalizeRoundingSetting(value, fallback)
    return normalizeRoundingSetting(value, fallback)
end

function M.IsRoundingDisabled(value, fallback)
    return normalizeRoundingSetting(value, fallback) >= M.ROUNDING_DISABLED
end

function M.RoundingSettingToDecimals(value, fallback)
    local setting = normalizeRoundingSetting(value, fallback)
    if setting >= M.ROUNDING_DISABLED then
        return nil
    end

    return setting
end

function M.GetConfiguredRounding(name, fallback, reader)
    local value

    if isfunction(reader) then
        value = reader(name)
    else
        local cvar = GetConVar("magic_align_" .. tostring(name or ""))
        value = cvar and cvar:GetString() or nil
    end

    return normalizeRoundingSetting(value, fallback)
end

function M.GetDisplayRounding(reader)
    return M.GetConfiguredRounding("display_rounding", M.DEFAULT_DISPLAY_ROUNDING, reader)
end

function M.DescribeRoundingSetting(value, fallback)
    local decimals = M.RoundingSettingToDecimals(value, fallback)
    if decimals == nil then
        return "Off"
    end

    if decimals == 1 then
        return "1 decimal"
    end

    return ("%d decimals"):format(decimals)
end

function M.TrimNumericString(text)
    text = tostring(text or "")
    text = text:gsub("(%..-)0+$", "%1")
    text = text:gsub("%.$", "")

    if tonumber(text) == 0 then
        return "0"
    end

    return text
end

function M.FormatFixedNumber(value, decimals, trim)
    decimals = math.max(math.floor(tonumber(decimals) or 0), 0)

    local text = string.format("%." .. decimals .. "f", tonumber(value) or 0)
    if tonumber(text) == 0 then
        return negativeZeroText(decimals, trim == true)
    end

    if trim then
        return M.TrimNumericString(text)
    end

    return text
end

function M.FormatPreciseNumber(value)
    value = tonumber(value) or 0
    if value ~= value or value == math.huge or value == -math.huge then
        value = 0
    end

    local text = string.format("%.17g", value)
    if tonumber(text) == 0 then
        return "0"
    end

    return M.TrimNumericString(text)
end

function M.FormatConVarNumber(value)
    return M.FormatPreciseNumber(value)
end

function M.FormatDisplayNumber(value, setting, options)
    options = options or {}

    local decimals = M.RoundingSettingToDecimals(setting, options.fallback)
    if decimals == nil then
        return M.FormatPreciseNumber(value)
    end

    return M.FormatFixedNumber(value, decimals, options.trim == true)
end

function M.FormatDisplayPreviewNumber(value, setting, options)
    options = options or {}

    local decimals = M.RoundingSettingToDecimals(setting, options.fallback)
    if decimals == nil then
        return M.FormatPreciseNumber(value)
    end

    local rounded = math.Round(tonumber(value) or 0, decimals)
    local text = M.FormatFixedNumber(value, decimals, false)
    local threshold = math.max(1e-12, 10 ^ (-(decimals + 2)))

    if math.abs((tonumber(value) or 0) - rounded) > threshold then
        text = text .. "..."
    end

    return text
end

function M.RoundNumber(value, decimals)
    value = tonumber(value) or 0

    if decimals == nil then
        return value
    end

    return math.Round(value, math.max(math.floor(tonumber(decimals) or 0), 0))
end

function M.RoundNumberForSetting(value, setting, fallback)
    return M.RoundNumber(value, M.RoundingSettingToDecimals(setting, fallback))
end

return M
