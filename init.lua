--
-- SSCSM: Server-Sent Client-Side Mods proof-of-concept
--
-- © 2019 by luk3yx
--

local sscsm = {minify=true}
local modname = minetest.get_current_modname()
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
    local loaded = {[':init'] = true, [':cleanup'] = true}
    local not_loaded = {}
    local order = {':init'}
    for k, v in pairs(sscsm.registered_csms) do
        if k:sub(1, 1) ~= ':' then
            table.insert(not_loaded, v)
        end
    end
    while #not_loaded > 0 do
        local def = not_loaded[1]
        g = not def.depends or #def.depends == 0
        if not g then
            g = true
            for _, mod in ipairs(def.depends) do
                if not sscsm.registered_csms[mod] then
                    minetest.log('error', '[SSCSM] SSCSM "' .. def.name ..
                        '" has an unsatisfied dependency: ' .. mod)
                    g = false
                    break
                elseif not loaded[mod] then
                    table.insert(not_loaded, def)
                    g = false
                    break
                end
            end
        end

        if g then
            table.insert(order, def.name)
            loaded[def.name] = true
        end
        table.remove(not_loaded, 1)
    end

    -- Set csm_order
    table.insert(order, ':cleanup')
    csm_order = order
end

-- Register SSCSMs
-- TODO: Automatically minify code (remove whitespace+comments)
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

-- Testing
minetest.after(1, function()
    local c = 0
    for k, v in pairs(sscsm.registered_csms) do
        c = c + 1
        if c > 2 then break end
    end
    if c == 2 then
        minetest.log('warning', '[SSCSM] Testing mode enabled.')

        sscsm.register({
            name = 'sscsm:testing_cmds',
            file = modpath .. '/sscsm_testing.lua'
        })

        sscsm.register({
            name = 'sscsm:another_test',
            code = 'yay()',
            depends = {'sscsm:testing_cmds'},
        })

        sscsm.register({
            name = 'sscsm:badtest',
            code = 'error("Oops, badtest loaded!")',
            depends = {':init', ':cleanup', ':no'}
        })
    end
end)
