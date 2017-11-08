-- https://github.com/pfirsich/jprof

-- we need to make sure we have our own instance, so we can adjust settings
local msgpack_old = package.loaded["MessagePack"]
package.loaded["MessagePack"] = nil
local msgpack = require "MessagePack"
package.loaded["MessagePack"] = msgpack_old

-- We need to make sure the number format is "double", so our timestamps have enough accuracy.
-- NOTE: It might be possible to subtract the first timestamp from all others
-- and gain a bunch of significant digits, but we probably want about 0.01ms accuracy
-- which corresponds to 1e-5 s. With ~7 significant digits in single precision floats,
-- our accuracy might suffer already at about 100 seconds, so we go with double
msgpack.set_number("double")

local profiler = {}

local zoneStack = {} -- this is just for assertions
local profData = {}
local profEnabled = true

local function getByte(n, byte)
    return bit.rshift(bit.band(n, bit.lshift( 0xff, 8*byte )), 8*byte)
end

-- I need this function (and not just msgpack.pack), so I can pack and write
-- the file in chunks. If we attempt to pack a big table, the amount of memory
-- used during packing can exceed the luajit memory limit pretty quickly, which will
-- terminate the program before the file is written.
local function msgpackListIntoFile(list, file)
    local n = #list
    -- https://github.com/msgpack/msgpack/blob/master/spec.md#array-format-family
    if n < 16 then
        file:write(string.char(144 + n))
    elseif n < 0xFFFF then
        file:write(string.char( 0xDC, getByte(n, 1), getByte(n, 0) ))
    elseif n < 0xFFffFFff then
        file:write(string.char( 0xDD, getByte(n, 3), getByte(n, 2), getByte(n, 1), getByte(n, 0)))
    else
        error("List too big")
    end
    for _, elem in ipairs(list) do
        file:write(msgpack.pack(elem))
    end
end

if PROF_CAPTURE then
    function profiler.push(name, annotation)
        if not profEnabled then return end

        table.insert(zoneStack, name)
        table.insert(profData, {name, love.timer.getTime(), collectgarbage("count"), annotation})
    end

    function profiler.pop(name)
        if not profEnabled then return end

        if name then
            assert(zoneStack[#zoneStack] == name,
                ("(jprof) Top of zone stack, does not match the zone passed to prof.pop ('%s', on top: '%s')!"):format(name, zoneStack[#zoneStack]))
        end
        table.remove(zoneStack)
        table.insert(profData, {"pop", love.timer.getTime(), collectgarbage("count")})
    end

    function profiler.write(filename)
        assert(#zoneStack == 0, "(jprof) Zone stack is not empty")

        local file, msg = lf.newFile(filename, "w")
        assert(file, msg)
        msgpackListIntoFile(profData, file)
        file:close()
    end

    function profiler.enabled(enabled)
        profEnabled = enabled
    end
else
    local noop = function() end

    profiler.push = noop
    profiler.pop = noop
    profiler.write = noop
    profiler.enabled = noop
end

return profiler