local EXPECTED_KEY = "Jack"

local providedKey
if type(getgenv) == "function" then
    providedKey = getgenv().key
end
if providedKey == nil and type(_G) == "table" then
    providedKey = _G.key
end

if providedKey ~= EXPECTED_KEY then
    warn("ENGINE KEY: invalid key provided")
    return false
end

return true
