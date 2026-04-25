MAGIC_ALIGN = MAGIC_ALIGN or include("autorun/magic_align.lua")

local M = MAGIC_ALIGN
local MathParser = M.MathParser or include("magic_align/client/math_parser.lua")

M.MathParser = MathParser

if M.FormulaManager then
    return M.FormulaManager
end

local Manager = {}

local COOKIE_PREFIX = "magic_align_slider_text_"
local PENDING_CONVAR_GRACE = 0.35
local PENDING_CONVAR_STALE_TIMEOUT = 2

local function nearlyEqual(a, b)
    return math.abs((tonumber(a) or 0) - (tonumber(b) or 0)) <= M.CONVAR_ROUNDTRIP_EPSILON
end

local function formatSmart(value)
    return M.FormatConVarNumber(value)
end

local function isFormulaText(text)
    return string.Trim(tostring(text or "")):sub(1, 1) == "="
end

local function hasEntryStateChanged(entry, newState)
    return entry.rawText ~= newState.rawText
        or entry.rawMode ~= newState.rawMode
        or not nearlyEqual(entry.storedNumericValue, newState.storedNumericValue)
        or entry.watchKey ~= newState.watchKey
        or tostring(entry.validationState or "ok") ~= tostring(newState.validationState or "ok")
        or tostring(entry.validationMessage or "") ~= tostring(newState.validationMessage or "")
end

local function applyEntryState(entry, newState)
    entry.rawText = newState.rawText
    entry.rawMode = newState.rawMode
    entry.storedNumericValue = tonumber(newState.storedNumericValue)
    entry.watchKey = newState.watchKey
    entry.validationState = newState.validationState or "ok"
    entry.validationMessage = newState.validationMessage
end

local function snapshotDisplayText(entry)
    if entry.rawText ~= nil and entry.rawText ~= "" then
        return entry.rawText
    end

    if entry.currentString ~= nil and entry.currentString ~= "" then
        return entry.currentString
    end

    return formatSmart(entry.currentValue)
end

function Manager:EnsureHook()
    if self.hookInstalled then
        return
    end

    self.hookInstalled = true

    hook.Remove("Think", "MagicAlignFormulaManager")
    hook.Add("Think", "MagicAlignFormulaManager", function()
        self:Think()
    end)
end

function Manager:EnsureEntry(cvarName)
    self.entries = self.entries or {}

    local entry = self.entries[cvarName]
    if entry then
        return entry
    end

    entry = {
        cvar = cvarName,
        rawText = nil,
        rawMode = nil,
        storedNumericValue = nil,
        watchKey = nil,
        currentValue = 0,
        currentString = "0",
        observedValue = nil,
        observedString = nil,
        pendingConVarValue = nil,
        pendingConVarString = nil,
        pendingConVarUntil = 0,
        pendingConVarBaseString = nil,
        pendingConVarBaseValue = nil,
        pendingConVarStartedAt = 0,
        validationState = "ok",
        validationMessage = nil,
        revision = 0,
        initialized = false,
        optionsProvider = nil
    }

    self.entries[cvarName] = entry

    return entry
end

function Manager:Touch(entry)
    entry.revision = (tonumber(entry.revision) or 0) + 1
    self.revision = (tonumber(self.revision) or 0) + 1
end

function Manager:GetRevision()
    return tonumber(self.revision) or 0
end

function Manager:GetEntryRevision(cvarName)
    local entry = self.entries and self.entries[cvarName]
    return entry and (tonumber(entry.revision) or 0) or 0
end

function Manager:GetCookieKey(cvarName)
    cvarName = tostring(cvarName or "")
    if cvarName == "" then
        return nil
    end

    return COOKIE_PREFIX .. cvarName
end

function Manager:PersistEntry(entry)
    local key = self:GetCookieKey(entry.cvar)
    if not key then
        return
    end

    cookie.Set(key, entry.rawText or "")
end

function Manager:GetExpressionOptions(cvarName, panel)
    local entry = self:EnsureEntry(cvarName)
    local options

    if isfunction(entry.optionsProvider) then
        local ok, value = pcall(entry.optionsProvider, self, cvarName, panel, entry)
        if ok and istable(value) then
            options = value
        end
    end

    if not istable(options) and IsValid(panel) and isfunction(panel.GetExpressionContextProvider) then
        local provider = panel:GetExpressionContextProvider()
        if isfunction(provider) then
            local ok, value = pcall(provider, panel)
            if ok and istable(value) then
                options = value
            end
        end
    end

    if not istable(options) and isfunction(M.GetFormulaEnvironment) then
        local ok, value = pcall(M.GetFormulaEnvironment, M, panel, cvarName)
        if ok and istable(value) then
            options = value
        end
    end

    if not istable(options) then
        options = {}
    end

    return options
end

function Manager:ResolveIdentifierValueRaw(name, options)
    options = istable(options) and options or {}

    local variables = istable(options.variables) and options.variables or nil
    if istable(variables) then
        local value = variables[name]
        if value == nil then
            value = variables[string.lower(name)]
        end
        if value == nil then
            value = variables[string.upper(name)]
        end
        if value ~= nil then
            return value, true
        end
    end

    local resolver = options.resolveIdentifier
    if isfunction(resolver) then
        local value, found = resolver(name, options)
        if found ~= false and value ~= nil then
            return value, true
        end
    end

    return nil, false
end

function Manager:IsKnownIdentifier(name, options)
    options = istable(options) and options or {}
    name = string.lower(tostring(name or ""))
    if name == "" then
        return false
    end

    if istable(options.variableNames) then
        for index = 1, #options.variableNames do
            if string.lower(tostring(options.variableNames[index] or "")) == name then
                return true
            end
        end
    end

    local descriptions = istable(options.variableDescriptions) and options.variableDescriptions or nil
    if istable(descriptions) then
        if descriptions[name] ~= nil or descriptions[string.upper(name)] ~= nil then
            return true
        end
    end

    if istable(options.variableRows) then
        for index = 1, #options.variableRows do
            local row = options.variableRows[index]
            if istable(row) and string.lower(tostring(row.name or "")) == name then
                return true
            end
        end
    end

    return false
end

function Manager:ResolveIdentifierValue(name, options)
    local value, found = self:ResolveIdentifierValueRaw(name, options)
    if found then
        return value, true
    end

    if self:IsKnownIdentifier(name, options) then
        return 0, true
    end

    return nil, false
end

function Manager:GetEvaluationOptions(cvarName, panel)
    local options = self:GetExpressionOptions(cvarName, panel)
    local baseOptions = istable(options) and options or {}
    local evalOptions = table.Copy(baseOptions)
    local baseResolver = baseOptions.resolveIdentifier
    local baseVariables = istable(baseOptions.variables) and baseOptions.variables or nil

    evalOptions.resolveIdentifier = function(name)
        if istable(baseVariables) then
            local value = baseVariables[name]
            if value == nil then
                value = baseVariables[string.upper(name)]
            end
            if value == nil then
                value = baseVariables[string.lower(name)]
            end
            if value ~= nil then
                return value, true
            end
        end

        if isfunction(baseResolver) then
            local value, found = baseResolver(name, baseOptions)
            if found ~= false and value ~= nil then
                return value, true
            end
        end

        if self:IsKnownIdentifier(name, baseOptions) then
            return 0, true
        end

        return nil, false
    end

    return evalOptions
end

function Manager:BuildFormulaWatchKey(cvarName, text, panel, options)
    local rawText = string.Trim(tostring(text or ""))
    if rawText:sub(1, 1) == "=" then
        rawText = string.Trim(rawText:sub(2))
    end

    if rawText == "" then
        return ""
    end

    options = istable(options) and options or self:GetEvaluationOptions(cvarName, panel)

    local identifiers = MathParser.ExtractIdentifiers(rawText)
    local parts = { rawText }

    if options.watchKey ~= nil then
        parts[#parts + 1] = "__watch=" .. tostring(options.watchKey)
    end

    for index = 1, #identifiers do
        local name = identifiers[index]
        local value, found = self:ResolveIdentifierValue(name, options)
        if found then
            parts[#parts + 1] = ("%s=%s"):format(name, tostring(value))
        else
            parts[#parts + 1] = ("%s=<unresolved>"):format(name)
        end
    end

    return table.concat(parts, "|")
end

function Manager:BuildTextCommit(cvarName, text, panel, options, currentValue)
    local rawText = string.Trim(tostring(text or ""))
    if rawText == "" then
        return {
            ok = true,
            value = 0,
            displayText = "0",
            clearStoredText = true,
            validationState = "ok",
            validationMessage = nil,
            convarText = "0"
        }
    end

    local isFormula = rawText:sub(1, 1) == "="
    local expression = isFormula and string.Trim(rawText:sub(2)) or rawText
    if expression == "" then
        return {
            ok = false,
            error = "Expression is empty"
        }
    end

    options = istable(options) and options or self:GetEvaluationOptions(cvarName, panel)

    local result = MathParser.Evaluate(expression, options)
    if not result.ok then
        if isFormula then
            return {
                ok = true,
                value = 0,
                displayText = rawText,
                rawText = rawText,
                rawMode = "formula",
                storedNumericValue = 0,
                convarText = "0",
                validationState = "invalid",
                validationMessage = result.error or "Expression could not be evaluated",
                watchKey = self:BuildFormulaWatchKey(cvarName, rawText, panel, options)
            }
        end

        return {
            ok = false,
            error = result.error or "Expression could not be evaluated"
        }
    end

    local normalizedExpression = expression:gsub(",", ".")
    local appliedValue = tonumber(result.value) or 0
    if IsValid(panel) and isfunction(panel.NormalizeValue) then
        appliedValue = panel:NormalizeValue(appliedValue, "text")
    end

    local keepLiteral = not isFormula
        and MathParser.IsNumericLiteral(expression)
        and nearlyEqual(tonumber(normalizedExpression), appliedValue)

    local displayText = rawText
    local convarText
    local clearStoredText = false
    local rawTextForStorage = rawText
    if isFormula then
        convarText = IsValid(panel) and isfunction(panel.FormatConVarValue)
            and panel:FormatConVarValue(appliedValue, "text")
            or formatSmart(appliedValue)
    elseif keepLiteral then
        convarText = normalizedExpression
    else
        displayText = IsValid(panel) and isfunction(panel.FormatDisplayValue)
            and panel:FormatDisplayValue(appliedValue, "text")
            or formatSmart(appliedValue)
        convarText = IsValid(panel) and isfunction(panel.FormatConVarValue)
            and panel:FormatConVarValue(appliedValue, "text")
            or formatSmart(appliedValue)
        clearStoredText = true
        rawTextForStorage = nil
    end

    return {
        ok = true,
        value = appliedValue,
        displayText = displayText,
        rawText = rawTextForStorage,
        rawMode = isFormula and "formula" or "literal",
        storedNumericValue = appliedValue,
        convarText = convarText,
        validationState = "ok",
        validationMessage = nil,
        clearStoredText = clearStoredText,
        watchKey = isFormula and self:BuildFormulaWatchKey(cvarName, rawText, panel, options) or nil
    }
end

function Manager:ClearPendingState(entry)
    entry.pendingConVarValue = nil
    entry.pendingConVarString = nil
    entry.pendingConVarUntil = 0
    entry.pendingConVarBaseString = nil
    entry.pendingConVarBaseValue = nil
    entry.pendingConVarStartedAt = 0
end

function Manager:ApplyStoredState(entry, newState)
    if not hasEntryStateChanged(entry, newState) then
        return false
    end

    applyEntryState(entry, newState)
    self:PersistEntry(entry)
    return true
end

function Manager:ClearStoredState(entry)
    return self:ApplyStoredState(entry, {
        rawText = nil,
        rawMode = nil,
        storedNumericValue = nil,
        watchKey = nil,
        validationState = "ok",
        validationMessage = nil
    })
end

function Manager:PushConVar(entry, value, outputString)
    local currentObservedString = entry.observedString or entry.currentString

    entry.currentValue = tonumber(value) or 0
    entry.currentString = tostring(outputString or formatSmart(value))
    entry.pendingConVarValue = entry.currentValue
    entry.pendingConVarString = entry.currentString
    entry.pendingConVarUntil = RealTime() + PENDING_CONVAR_GRACE
    entry.pendingConVarBaseString = currentObservedString
    entry.pendingConVarBaseValue = tonumber(currentObservedString)
    entry.pendingConVarStartedAt = RealTime()

    RunConsoleCommand(entry.cvar, entry.currentString)
end

function Manager:ApplyTextCommit(cvarName, commit)
    local entry = self:EnsureEntry(cvarName)
    local changed = false

    if commit.clearStoredText then
        changed = self:ClearStoredState(entry) or changed
    else
        changed = self:ApplyStoredState(entry, {
            rawText = tostring(commit.rawText or commit.displayText or ""),
            rawMode = commit.rawMode or "literal",
            storedNumericValue = commit.storedNumericValue or commit.value,
            watchKey = commit.watchKey,
            validationState = commit.validationState or "ok",
            validationMessage = commit.validationMessage
        }) or changed
    end

    if not commit.skipConVar then
        local targetString = tostring(commit.convarText or formatSmart(commit.value))
        if not nearlyEqual(entry.currentValue, commit.value) or entry.currentString ~= targetString then
            self:PushConVar(entry, commit.value, targetString)
            changed = true
        end
    end

    if changed then
        self:Touch(entry)
    end

    return self:GetSnapshot(cvarName)
end

function Manager:ApplyDirectValue(cvarName, value, outputString)
    local entry = self:EnsureEntry(cvarName)
    local changed = self:ClearStoredState(entry)
    local targetString = tostring(outputString or formatSmart(value))

    if not nearlyEqual(entry.currentValue, value) or entry.currentString ~= targetString then
        self:PushConVar(entry, value, targetString)
        changed = true
    end

    if changed then
        self:Touch(entry)
    end

    return self:GetSnapshot(cvarName)
end

function Manager:ReadConVar(entry)
    local cvar = GetConVar(entry.cvar)
    if not cvar then
        return nil
    end

    local rawValue = cvar:GetString()
    local numericValue = tonumber(rawValue)
    if numericValue == nil then
        return nil
    end

    return rawValue, numericValue
end

function Manager:PollConVar(cvarName, force)
    local entry = self:EnsureEntry(cvarName)
    local rawValue, numericValue = self:ReadConVar(entry)
    if rawValue == nil then
        return false
    end

    if not force and entry.pendingConVarString ~= nil then
        local pendingAge = RealTime() - (tonumber(entry.pendingConVarStartedAt) or 0)
        if nearlyEqual(numericValue, entry.pendingConVarValue) then
            self:ClearPendingState(entry)
        else
            local matchesPreviousValue = entry.pendingConVarBaseString ~= nil
                and rawValue == entry.pendingConVarBaseString
                and nearlyEqual(numericValue, entry.pendingConVarBaseValue)

            if matchesPreviousValue and pendingAge < PENDING_CONVAR_STALE_TIMEOUT then
                return false
            end

            if RealTime() < (tonumber(entry.pendingConVarUntil) or 0) then
                return false
            end

            self:ClearPendingState(entry)
        end
    end

    if not force
        and entry.observedString == rawValue
        and nearlyEqual(entry.observedValue, numericValue) then
        return false
    end

    entry.observedString = rawValue
    entry.observedValue = numericValue

    local changed = false
    if entry.rawMode == "formula" and entry.storedNumericValue ~= nil then
        if nearlyEqual(numericValue, entry.storedNumericValue) then
            if not nearlyEqual(entry.currentValue, entry.storedNumericValue) or entry.currentString ~= rawValue then
                entry.currentValue = entry.storedNumericValue
                entry.currentString = rawValue
                changed = true
            end
        else
            self:PushConVar(entry, entry.storedNumericValue, formatSmart(entry.storedNumericValue))
            changed = true
        end
    elseif entry.rawText ~= nil and entry.storedNumericValue ~= nil then
        if nearlyEqual(numericValue, entry.storedNumericValue) then
            if not nearlyEqual(entry.currentValue, numericValue) or entry.currentString ~= rawValue then
                entry.currentValue = numericValue
                entry.currentString = rawValue
                changed = true
            end
        else
            changed = self:ClearStoredState(entry) or changed
            entry.currentValue = numericValue
            entry.currentString = rawValue
        end
    else
        if not nearlyEqual(entry.currentValue, numericValue) or entry.currentString ~= rawValue then
            entry.currentValue = numericValue
            entry.currentString = rawValue
            changed = true
        end
    end

    if changed or force then
        self:Touch(entry)
    end

    return changed or force
end

function Manager:RegisterConVar(cvarName, options)
    cvarName = tostring(cvarName or "")
    if cvarName == "" then
        return nil
    end

    self:EnsureHook()

    local entry = self:EnsureEntry(cvarName)
    if istable(options) and isfunction(options.optionsProvider) then
        entry.optionsProvider = options.optionsProvider
    end

    if entry.initialized then
        return entry
    end

    entry.initialized = true
    self:PollConVar(cvarName, true)

    local key = self:GetCookieKey(cvarName)
    local saved = key and cookie.GetString(key, "") or ""
    if saved ~= "" then
        local commit = self:BuildTextCommit(cvarName, saved, nil, nil, entry.currentValue)
        if commit.ok then
            self:ApplyTextCommit(cvarName, commit)
        else
            cookie.Set(key, "")
        end
    end

    return entry
end

function Manager:Think()
    local entries = self.entries
    if not istable(entries) then
        return
    end

    local ply = LocalPlayer()
    if not (IsValid(ply) and isfunction(M.GetActiveMagicAlignTool) and M.GetActiveMagicAlignTool(ply)) then
        return
    end

    for cvarName, entry in pairs(entries) do
        if entry.initialized then
            self:PollConVar(cvarName, false)
            self:ReevaluateFormula(cvarName)
        end
    end
end

function Manager:ReevaluateFormula(cvarName)
    local entry = self:EnsureEntry(cvarName)
    if entry.rawMode ~= "formula" or not isFormulaText(entry.rawText) then
        return false
    end

    local options = self:GetExpressionOptions(cvarName, nil)
    local watchKey = self:BuildFormulaWatchKey(cvarName, entry.rawText, nil, options)
    if entry.watchKey ~= nil and entry.watchKey == watchKey then
        return false
    end

    local commit = self:BuildTextCommit(cvarName, entry.rawText, nil, options, entry.currentValue)
    if not commit.ok then
        return false
    end

    commit.watchKey = watchKey
    return self:ApplyTextCommit(cvarName, commit)
end

function Manager:GetSnapshot(cvarName)
    local entry = self.entries and self.entries[cvarName]
    if not entry then
        return nil
    end

    return {
        revision = tonumber(entry.revision) or 0,
        value = tonumber(entry.currentValue) or 0,
        displayText = snapshotDisplayText(entry),
        rawText = entry.rawText,
        rawMode = entry.rawMode,
        storedNumericValue = tonumber(entry.storedNumericValue),
        formulaWatchKey = entry.watchKey,
        convarText = entry.currentString,
        validationState = entry.validationState or "ok",
        validationMessage = entry.validationMessage
    }
end

function Manager:GetNumericValue(cvarName, fallback)
    local entry = self.entries and self.entries[cvarName]
    if not entry then
        return fallback
    end

    if entry.rawMode == "formula" and entry.storedNumericValue ~= nil then
        return tonumber(entry.currentValue) or tonumber(entry.storedNumericValue) or fallback
    end

    return fallback
end

M.FormulaManager = Manager

return Manager
