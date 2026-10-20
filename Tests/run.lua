-- lua5.1 run.lua <addon folder> <tests folder> [test names...]
ADDON_PATH = arg[1]
local TESTS = arg[2]
local H = dofile(TESTS .. "/harness.lua")

local names = { select(3, unpack(arg)) }
if #names == 0 then
    names = { "unit", "sync", "export" }
end
for _, name in ipairs(names) do
    local chunk = assert(loadfile(TESTS .. "/test_" .. name .. ".lua"))
    local ok, err = xpcall(function()
        chunk(H)
    end, debug.traceback)
    if not ok then
        H.failures = H.failures + 1
        print("CRASH in " .. name .. ": " .. tostring(err))
    end
end
print(("\n%d passed, %d failed"):format(H.passes, H.failures))
os.exit(H.failures == 0 and 0 or 1)
