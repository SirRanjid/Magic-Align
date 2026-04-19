MAGIC_ALIGN = MAGIC_ALIGN or include("autorun/magic_align.lua")

local M = MAGIC_ALIGN

if M.MathParser then
    return M.MathParser
end

local Parser = {}

local ALLOWED_PATTERN = "[^%s%d%a_%.%+%-%*%/%^%%%(%)%,]"

local function normalizeInput(input)
    input = tostring(input or "")
    input = string.Trim(input)
    input = input:gsub(",", ".")
    input = input:gsub("sin%s*%^%s*%-%s*1%s*%(", "asin(")
    input = input:gsub("cos%s*%^%s*%-%s*1%s*%(", "acos(")
    input = input:gsub("tan%s*%^%s*%-%s*1%s*%(", "atan(")
    input = input:gsub("arcsin%s*%(", "asin(")
    input = input:gsub("arccos%s*%(", "acos(")
    input = input:gsub("arctan%s*%(", "atan(")
    return input
end

local function trimNumberString(text)
    text = tostring(text or "")
    text = text:gsub("(%..-)0+$", "%1")
    text = text:gsub("%.$", "")
    if text == "-0" then
        return "0"
    end

    return text
end

local function formatNumber(value)
    return trimNumberString(string.format("%.15f", tonumber(value) or 0))
end

local function hasOnlyAllowedCharacters(input)
    input = normalizeInput(input)
    if input == "" then return true end
    return not input:find(ALLOWED_PATTERN)
end

local function numericLiteral(input)
    input = normalizeInput(input)
    if input == "" or input == "." or input == "+" or input == "-" or input == "+." or input == "-." then
        return false
    end

    return tonumber(input) ~= nil
end

local function fail(kind, message, extra)
    extra = extra or {}
    extra.kind = kind
    extra.message = message
    error(extra, 0)
end

local function tokenize(input)
    local tokens = {}
    local index = 1
    local length = #input

    while index <= length do
        local char = input:sub(index, index)

        if char:match("%s") then
            index = index + 1
        elseif char:match("[%d.]") then
            local startIndex = index
            local seenDot = false
            local seenDigit = false

            while index <= length do
                local current = input:sub(index, index)
                if current:match("%d") then
                    seenDigit = true
                    index = index + 1
                elseif current == "." and not seenDot then
                    seenDot = true
                    index = index + 1
                else
                    break
                end
            end

            if seenDigit and index <= length then
                local exponentMarker = input:sub(index, index)
                if exponentMarker == "e" or exponentMarker == "E" then
                    local exponentIndex = index + 1
                    local exponentSign = input:sub(exponentIndex, exponentIndex)
                    if exponentSign == "+" or exponentSign == "-" then
                        exponentIndex = exponentIndex + 1
                    end

                    local exponentStart = exponentIndex
                    while exponentIndex <= length and input:sub(exponentIndex, exponentIndex):match("%d") do
                        exponentIndex = exponentIndex + 1
                    end

                    if exponentIndex > exponentStart then
                        index = exponentIndex
                    end
                end
            end

            local text = input:sub(startIndex, index - 1)
            local number = tonumber(text)
            if number == nil then
                fail("syntax", ("Invalid number '%s'"):format(text))
            end

            tokens[#tokens + 1] = {
                type = "number",
                value = number
            }
        elseif char:match("[%a_]") then
            local startIndex = index

            while index <= length do
                local current = input:sub(index, index)
                if current:match("[%w_]") then
                    index = index + 1
                else
                    break
                end
            end

            tokens[#tokens + 1] = {
                type = "identifier",
                value = string.lower(input:sub(startIndex, index - 1))
            }
        elseif char == "(" or char == ")" or char == "+" or char == "-" or char == "*" or char == "/" or char == "%" or char == "^" then
            tokens[#tokens + 1] = {
                type = char,
                value = char
            }
            index = index + 1
        else
            fail("invalid_characters", ("Character '%s' is not allowed"):format(char))
        end
    end

    return tokens
end

local function resolveIdentifier(name, options)
    local variables = istable(options) and options.variables or nil
    if istable(variables) then
        local direct = variables[name]
        if direct == nil then
            direct = variables[string.upper(name)]
        end
        if direct == nil then
            direct = variables[string.lower(name)]
        end
        if direct ~= nil then
            local number = tonumber(direct)
            if number == nil then
                fail("invalid_placeholder", ("Placeholder '%s' is not numeric"):format(name), {
                    name = name
                })
            end

            return number
        end
    end

    local resolver = istable(options) and options.resolveIdentifier or nil
    if isfunction(resolver) then
        local value, found = resolver(name, options)
        if found ~= false and value ~= nil then
            local number = tonumber(value)
            if number == nil then
                fail("invalid_placeholder", ("Placeholder '%s' is not numeric"):format(name), {
                    name = name
                })
            end

            return number
        end
    end

    fail("unresolved", ("Placeholder '%s' is unresolved"):format(name), {
        name = name
    })
end

local function checkedValue(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        fail("math", "Expression evaluated to an invalid number")
    end

    return value
end

local functions = {
    sin = function(value)
        return math.sin(math.rad(value))
    end,
    cos = function(value)
        return math.cos(math.rad(value))
    end,
    tan = function(value)
        return math.tan(math.rad(value))
    end,
    asin = function(value)
        return math.deg(math.asin(value))
    end,
    acos = function(value)
        return math.deg(math.acos(value))
    end,
    atan = function(value)
        return math.deg(math.atan(value))
    end
}
local supportedFunctionNames = { "sin", "cos", "tan", "asin", "acos", "atan", "arcsin", "arccos", "arctan" }

local function currentToken(state)
    return state.tokens[state.index]
end

local function matchToken(state, tokenType)
    local token = currentToken(state)
    if token and token.type == tokenType then
        state.index = state.index + 1
        return token
    end
end

local function expectToken(state, tokenType, message)
    local token = matchToken(state, tokenType)
    if token then
        return token
    end

    fail("syntax", message)
end

local parseExpression
local parseUnary

local function parsePrimary(state)
    local token = currentToken(state)
    if not token then
        fail("syntax", "Unexpected end of expression")
    end

    if token.type == "number" then
        state.index = state.index + 1
        return token.value
    end

    if token.type == "(" then
        state.index = state.index + 1
        local value = parseExpression(state)
        expectToken(state, ")", "Missing closing ')'")
        return value
    end

    if token.type == "identifier" then
        state.index = state.index + 1
        local identifier = token.value

        if matchToken(state, "(") then
            local fn = functions[identifier]
            if not fn then
                fail("syntax", ("Function '%s' is not supported"):format(identifier))
            end

            local argument = parseExpression(state)
            expectToken(state, ")", ("Missing ')' after %s(...)"):format(identifier))
            return checkedValue(fn(argument))
        end

        return checkedValue(resolveIdentifier(identifier, state.options))
    end

    fail("syntax", ("Unexpected token '%s'"):format(token.value or token.type))
end

local function parsePower(state)
    local left = parsePrimary(state)

    if matchToken(state, "^") then
        local right = parseUnary(state)
        left = checkedValue(left ^ right)
    end

    return left
end

function parseUnary(state)
    if matchToken(state, "+") then
        return parseUnary(state)
    end

    if matchToken(state, "-") then
        return checkedValue(-parseUnary(state))
    end

    return parsePower(state)
end

local function parseMulDiv(state)
    local value = parseUnary(state)

    while true do
        if matchToken(state, "*") then
            value = checkedValue(value * parseUnary(state))
        elseif matchToken(state, "/") then
            local divisor = parseUnary(state)
            if math.abs(divisor) <= 1e-12 then
                fail("math", "Division by zero")
            end
            value = checkedValue(value / divisor)
        elseif matchToken(state, "%") then
            local divisor = parseUnary(state)
            if math.abs(divisor) <= 1e-12 then
                fail("math", "Modulo by zero")
            end
            value = checkedValue(value % divisor)
        else
            break
        end
    end

    return value
end

function parseExpression(state)
    local value = parseMulDiv(state)

    while true do
        if matchToken(state, "+") then
            value = checkedValue(value + parseMulDiv(state))
        elseif matchToken(state, "-") then
            value = checkedValue(value - parseMulDiv(state))
        else
            break
        end
    end

    return value
end

function Parser.HasOnlyAllowedCharacters(input)
    return hasOnlyAllowedCharacters(input)
end

function Parser.IsNumericLiteral(input)
    return numericLiteral(input)
end

function Parser.FormatNumber(value)
    return formatNumber(value)
end

function Parser.GetSupportedFunctions()
    local out = {}
    for index = 1, #supportedFunctionNames do
        out[index] = supportedFunctionNames[index]
    end

    return out
end

function Parser.ExtractIdentifiers(input)
    local normalized = normalizeInput(input)
    if normalized == "" or not hasOnlyAllowedCharacters(normalized) then
        return {}
    end

    local ok, tokens = pcall(tokenize, normalized)
    if not ok or not istable(tokens) then
        return {}
    end

    local out = {}
    local seen = {}

    for index = 1, #tokens do
        local token = tokens[index]
        local nextToken = tokens[index + 1]
        if token.type == "identifier" and not (nextToken and nextToken.type == "(") and not seen[token.value] then
            seen[token.value] = true
            out[#out + 1] = token.value
        end
    end

    table.sort(out)
    return out
end

function Parser.Evaluate(input, options)
    local normalized = normalizeInput(input)
    if normalized == "" then
        return {
            ok = false,
            reason = "syntax",
            error = "Expression is empty"
        }
    end

    if not hasOnlyAllowedCharacters(normalized) then
        return {
            ok = false,
            reason = "invalid_characters",
            error = "Expression contains unsupported characters"
        }
    end

    local success, result = xpcall(function()
        local tokens = tokenize(normalized)
        local state = {
            tokens = tokens,
            index = 1,
            options = options or {}
        }

        local value = parseExpression(state)
        if currentToken(state) then
            fail("syntax", ("Unexpected token '%s'"):format(currentToken(state).value or currentToken(state).type))
        end

        return {
            value = checkedValue(value),
            normalized = normalized
        }
    end, function(err)
        if istable(err) then
            return err
        end

        return {
            kind = "runtime",
            message = tostring(err)
        }
    end)

    if not success then
        return {
            ok = false,
            reason = result.kind or "runtime",
            error = result.message or "Failed to evaluate expression",
            name = result.name
        }
    end

    return {
        ok = true,
        value = result.value,
        normalized = result.normalized
    }
end

M.MathParser = Parser

return Parser
