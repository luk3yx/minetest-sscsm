--
-- SSCSM: Server-Sent Client-Side Mods proof-of-concept
--
-- Copyright © 2019 by luk3yx
--

local modname = minetest.get_current_modname()

-- If this is running as a CSM (improper installation), load the CSM code.
if INIT == 'client' then
    local modpath
    if minetest.get_modpath then
        modpath = minetest.get_modpath(modname)
    else
        modpath = modname .. ':'
    end
    dofile(modpath .. 'csm/init.lua')
    return
end

local sscsm = {minify=true}
_G[modname] = sscsm
local modpath = minetest.get_modpath(modname)

-- Remove excess whitespace from code to allow larger files to be sent.
if sscsm.minify then
    local f = loadfile(modpath .. '/minify.lua')
    if f then
        sscsm.minify_code = f()
    else
        minetest.log('warning', '[SSCSM] Could not load minify.lua!')
    end
end

if not sscsm.minify_code then
    function sscsm.minify_code(code)
        assert(type(code) == 'string')
        return code
    end
end

-- Register code
sscsm.registered_csms = {}
local csm_order = false

-- Recalculate the CSM loading order
-- TODO: Make this nicer
local function recalc_csm_order()
    local loaded = {}
    local staging = {}
    local order = {':init'}
    local unsatisfied = {}
    for name, def in pairs(sscsm.registered_csms) do
        assert(name == def.name)
        if name:sub(1, 1) == ':' then
            loaded[name] = true
        elseif not def.depends or #def.depends == 0 then
            loaded[name] = true
            table.insert(staging, name)
        else
            unsatisfied[name] = {}
            for _, mod in ipairs(def.depends) do
                if mod:sub(1, 1) ~= ':' then
                    unsatisfied[name][mod] = true
                end
            end
        end
    end
    while #staging > 0 do
        local name = staging[1]
        for name2, u in pairs(unsatisfied) do
            if u[name] then
                u[name] = nil
                if #u == 0 then
                    table.insert(staging, name2)
                end
            end
        end

        table.insert(order, name)
        table.remove(staging, 1)
    end

    for name, u in pairs(unsatisfied) do
        if next(u) then
            local msg = 'SSCSM "' .. name .. '" has unsatisfied dependencies: '
            local n = false
            for dep, _ in pairs(u) do
                if n then msg = msg .. ', ' else n = true end
                msg = msg .. '"' .. dep .. '"'
            end
            minetest.log('error', msg)
        end
    end

    -- Set csm_order
    table.insert(order, ':cleanup')
    csm_order = order
end

-- Register SSCSMs
local block_colon = false
sscsm.registered_csms = {}
function sscsm.register(def)
    -- Read files now in case MT decides to block access later.
    if not def.code and def.file then
        local f = io.open(def.file, 'rb')
        if not f then
            error('Invalid "file" parameter passed to sscsm.register_csm.', 2)
        end
        def.code = f:read('*a')
        f:close()
        def.file = nil
    end

    if type(def.name) ~= 'string' or def.name:find('\n')
            or (def.name:sub(1, 1) == ':' and block_colon) then
        error('Invalid "name" parameter passed to sscsm.register_csm.', 2)
    end

    if type(def.code) ~= 'string' then
        error('Invalid "code" parameter passed to sscsm.register_csm.', 2)
    end

    def.code = sscsm.minify_code(def.code)
    if (#def.name + #def.code) > 65300 then
        error('The code (or name) passed to sscsm.register_csm is too large.'
            .. ' Consider refactoring your SSCSM code.', 2)
    end

    -- Copy the table to prevent mods from betraying our trust.
    sscsm.registered_csms[def.name] = table.copy(def)
    if csm_order then recalc_csm_order() end
end

function sscsm.unregister(name)
    sscsm.registered_csms[name] = nil
    if csm_order then recalc_csm_order() end
end

-- Recalculate the CSM order once all other mods are loaded
minetest.register_on_mods_loaded(recalc_csm_order)

-- Handle players joining
local mod_channel = minetest.mod_channel_join('sscsm:exec_pipe')
minetest.register_on_modchannel_message(function(channel_name, sender, message)
    if channel_name ~= 'sscsm:exec_pipe' or not sender or
            not mod_channel:is_writeable() or message ~= '0' or
            sender:find('\n') then
        return
    end
    minetest.log('action', '[SSCSM] Sending CSMs on request for ' .. sender
        .. '...')
    for _, name in ipairs(csm_order) do
        mod_channel:send_all('0' .. sender .. '\n' .. name
            .. '\n' .. sscsm.registered_csms[name].code)
    end
end)

-- Register the SSCSM "builtins"
sscsm.register({
    name = ':init',
    file = modpath .. '/sscsm_init.lua'
})

sscsm.register({
    name = ':cleanup',
    code = 'sscsm._done_loading_()'
})

block_colon = true

-- Set the CSM restriction flags
do
    local flags = tonumber(minetest.settings:get('csm_restriction_flags'))
    if not flags or flags ~= flags then
        flags = 62
    end
    flags = math.floor(math.max(math.min(flags, 63), 0))

    local def = sscsm.registered_csms[':init']
    def.code = def.code:gsub('__FLAGS__', tostring(flags))
end

-- Testing
minetest.after(1, function()
    -- Check if any other SSCSMs have been registered.
    local c = 0
    for k, v in pairs(sscsm.registered_csms) do
        c = c + 1
        if c > 2 then break end
    end
    if c ~= 2 then return end

    -- If not, enter testing mode.
    minetest.log('warning', '[SSCSM] Testing mode enabled.')

    sscsm.register({
        name = 'sscsm:testing_cmds',
        file = modpath .. '/sscsm_testing.lua',
    })

    sscsm.register({
        name = 'sscsm:another_test',
        code = 'yay()',
        depends = {'sscsm:testing_cmds'},
    })

    sscsm.register({
        name = 'sscsm:badtest',
        code = 'error("Oops, badtest loaded!")',
        depends = {':init', ':cleanup', 'bad_mod', ':bad2', 'bad3'},
    })
end)
