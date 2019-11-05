--
-- SSCSM: Server-Sent Client-Side Mods proof-of-concept
-- Initial code sent to the client
--
-- Copyright © 2019 by luk3yx
-- License: https://git.minetest.land/luk3yx/sscsm/src/branch/master/LICENSE.md
--

-- Make sure both table.unpack and unpack exist.
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

-- Older versions of the CSM don't provide assert(), this function exists for
-- compatibility.
if not assert then
    function assert(value, ...)
        if value then
            return value, ...
        else
            error(... or 'assertion failed!', 2)
        end
    end
end

-- Create the API
sscsm = {}
function sscsm.global_exists(name)
    return rawget(_G, name) ~= nil
end

if not sscsm.global_exists('minetest') then
    minetest = assert(core, 'No "minetest" global found!')
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
        if funcs then table.insert(funcs, callback) end
    end

    function sscsm._done_loading_()
        sscsm._done_loading_ = nil
        for _, func in ipairs(funcs) do func() end
        funcs = nil
    end
end

sscsm.register_on_mods_loaded(function()
    print('SSCSMs loaded, leaving mod channel.')
    sscsm.leave_mod_channel()
end)

-- Helper functions
if not minetest.get_node then
    function minetest.get_node(pos)
        return minetest.get_node_or_nil(pos) or {name = 'ignore', param1 = 0,
            param2 = 0}
    end
end

-- Make minetest.run_server_chatcommand allow param to be unspecified.
function minetest.run_server_chatcommand(cmd, param)
    minetest.send_chat_message('/' .. cmd .. ' ' .. (param or ''))
end

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
        on_chat_message = nil
    end
end

function sscsm.unregister_chatcommand(cmd)
    sscsm.registered_chatcommands[cmd] = nil
end

-- A proper get_player_control doesn't exist yet.
function sscsm.get_player_control()
    local n = minetest.localplayer:get_key_pressed()
    return {
        up    = n % 2 == 1,
        down  = math.floor(n / 2) % 2 == 1,
        left  = math.floor(n / 4) % 2 == 1,
        right = math.floor(n / 8) % 2 == 1,
        jump  = math.floor(n / 16) % 2 == 1,
        aux1  = math.floor(n / 32) % 2 == 1,
        sneak = math.floor(n / 64) % 2 == 1,
        LMB   = math.floor(n / 128) % 2 == 1,
        RMB   = math.floor(n / 256) % 2 == 1,
    }
end

-- Call func(...) every <interval> seconds.
local function sscsm_every(interval, func, ...)
    minetest.after(interval, sscsm_every, interval, func, ...)
    return func(...)
end

function sscsm.every(interval, func, ...)
    assert(type(interval) == 'number' and type(func) == 'function',
        'Invalid sscsm.every() invocation.')
    return sscsm_every(interval, func, ...)
end

-- Allow SSCSMs to know about CSM restriction flags.
-- "__FLAGS__" is replaced with the actual value in init.lua.
local flags = __FLAGS__
sscsm.restriction_flags = assert(flags)
sscsm.restrictions = {
    chat_messages = math.floor(flags / 2) % 2 == 1,
    read_itemdefs = math.floor(flags / 4) % 2 == 1,
    read_nodedefs = math.floor(flags / 8) % 2 == 1,
    lookup_nodes_limit = math.floor(flags / 16) % 2 == 1,
    read_playerinfo = math.floor(flags / 32) % 2 == 1,
}
