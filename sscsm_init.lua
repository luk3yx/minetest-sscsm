--
-- SSCSM: Server-Sent Client-Side Mods proof-of-concept
-- Initial code sent to the client
--
-- © 2019 by luk3yx
--

-- Make sure table.unpack exists
if table.unpack then
    unpack = table.unpack
else
    table.unpack = unpack
end

-- Make sure a few basic functions exist, these may have been blocked because
--  of security or laziness.
if not rawget   then function rawget(n, name) return n[name] end end
if not rawset   then function rawset(n, k, v) n[k] = v end end
if not rawequal then function rawequal(a, b) return a == b end end
if not assert then
    function assert(value, err)
        if not value then
            error(err or 'Assertion failed!', 2)
        end
        return value
    end
end

-- Create the API
sscsm = {}
function sscsm.global_exists(name)
    return rawget(_G, name) ~= nil
end
minetest.global_exists = sscsm.global_exists

-- Check if join_mod_channel and leave_mod_channel exist.
if sscsm.global_exists('join_mod_channel')
        and sscsm.global_exists('leave_mod_channel') then
    sscsm.join_mod_channel  = join_mod_channel
    sscsm.leave_mod_channel = leave_mod_channel
    join_mod_channel, leave_mod_channel = nil, nil
else
    local dummy = function() end
    sscsm.join_mod_channel  = dummy
    sscsm.leave_mod_channel = dummy
end

-- Add print()
function print(...)
    local msg = '[SSCSM] '
    for i = 1, select('#', ...) do
        if i > 1 then msg = msg .. '\t' end
        msg = msg .. tostring(select(i, ...))
    end
    minetest.log('none', msg)
end
print('Hello from the server-sent CSMs!')

-- Add register_on_mods_loaded
do
    local funcs = {}
    function sscsm.register_on_mods_loaded(callback)
        table.insert(funcs, callback)
    end

    function sscsm._done_loading_()
        sscsm._done_loading_ = nil
        for _, func in ipairs(funcs) do func() end
    end
end

sscsm.register_on_mods_loaded(function()
    print('SSCSMs loaded, leaving mod channel.')
    sscsm.leave_mod_channel()
end)

-- Register "server-side" chatcommands
-- Can allow instantaneous responses in some cases.
sscsm.registered_chatcommands = {}
local function on_chat_message(msg)
    if msg:sub(1, 1) ~= '/' then return false end

    local cmd, param = msg:match('^/([^ ]+) *(.*)')
    if not cmd then
        minetest.display_chat_message('-!- Empty command')
        return true
    end

    if not sscsm.registered_chatcommands[cmd] then return false end

    local _, res = sscsm.registered_chatcommands[cmd].func(param or '')
    if res then minetest.display_chat_message(tostring(res)) end

    return true
end

function sscsm.register_chatcommand(cmd, def)
    if type(def) == 'function' then
        def = {func = def}
    elseif type(def.func) ~= 'function' then
        error('Invalid definition passed to sscsm.register_chatcommand.')
    end

    sscsm.registered_chatcommands[cmd] = def

    if on_chat_message then
        minetest.register_on_sending_chat_message(on_chat_message)
        on_chat_message = false
    end
end

function sscsm.unregister_chatcommand(cmd)
    sscsm.registered_chatcommands[cmd] = nil
end
