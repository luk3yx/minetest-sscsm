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

-- A proper get_player_control didn't exist before Minetest 5.3.0.
if minetest.localplayer.get_control then
    function sscsm.get_player_control()
        return minetest.localplayer:get_control()
    end
else
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

    -- In Minetest 5.2.0, minetest.get_node_light() segfaults.
    minetest.get_node_light = nil
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
sscsm.restrictions.lookup_nodes = sscsm.restrictions.lookup_nodes_limit

-- Add minetest.get_csm_restrictions() if it doesn't exist already.
if not minetest.get_csm_restrictions then
    function minetest.get_csm_restrictions()
        return table.copy(sscsm.restrictions)
    end
end

-- SSCSM communication
-- A lot of this is copied from init.lua.
local function validate_channel(channel)
    if type(channel) ~= 'string' then
        error('SSCSM com channels must be strings!', 3)
    end
    if channel:find('\001', nil, true) then
        error('SSCSM com channels cannot contain U+0001!', 3)
    end
end

function sscsm.com_send(channel, msg)
    assert(not sscsm.restrictions.chat_messages, 'Server restrictions ' ..
        'prevent SSCSM com messages from being sent!')
    validate_channel(channel)
    if type(msg) == 'string' then
        msg = '\002' .. msg
    else
        msg = minetest.write_json(msg)
    end
    minetest.run_server_chatcommand('admin', '\001SSCSM_COM\001' .. channel ..
        '\001' .. msg)
end

local registered_on_receive = {}
function sscsm.register_on_com_receive(channel, func)
    if not registered_on_receive[channel] then
        registered_on_receive[channel] = {}
    end
    table.insert(registered_on_receive[channel], func)
end

-- Load split messages
local incoming_messages = {}
local function load_split_message(chan, msg)
    local id, i, l, pkt = msg:match('^\1([^\1]+)\1([^\1]+)\1([^\1]+)\1(.*)$')
    id, i, l = tonumber(id), tonumber(i), tonumber(l)

    if not incoming_messages[id] then
        incoming_messages[id] = {}
    end
    local msgs = incoming_messages[id]
    msgs[i] = pkt

    -- Return true if all the messages have been received
    if #msgs < l then return end
    for i = 1, l do
        if not msgs[i] then
            return
        end
    end
    incoming_messages[id] = nil
    return table.concat(msgs, '')
end

-- Detect messages and handle them
minetest.register_on_receiving_chat_message(function(message)
    local chan, msg = message:match('^\001SSCSM_COM\001([^\001]*)\001(.*)$')
    if not chan or not msg then return end

    -- Get the callbacks
    local callbacks = registered_on_receive[chan]
    if not callbacks then return true end

    -- Handle split messages
    local prefix = msg:sub(1, 1)
    if prefix == '\001' then
        msg = load_split_message(chan, msg)
        if not msg then
            return true
        end
        prefix = msg:sub(1, 1)
    end

    -- Load the message
    if prefix == '\002' then
        msg = msg:sub(2)
    else
        msg = minetest.parse_json(msg)
    end

    -- Run callbacks
    for _, func in ipairs(callbacks) do
        local ok, msg = pcall(func, msg)
        if not ok then
            minetest.log('error', '[SSCSM] ' .. tostring(msg))
        end
    end
    return true
end)

sscsm.register_on_mods_loaded(function()
    print('SSCSMs loaded, leaving mod channel.')
    sscsm.leave_mod_channel()
    sscsm.com_send('sscsm:com_test', {flags = sscsm.restriction_flags})
end)
