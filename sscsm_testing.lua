--
-- SSCSM: Server-Sent Client-Side Mods proof-of-concept
-- Testing code
--
-- © 2019 by luk3yx
--

--[==[
error("Bad")
]==]

-- Make sure the minifier is sane
a = 0
--[[
a = a + 1
--]]

-- [[
a = a + 2
--]]

--;a = a + 4

a = a + #('Test    message with \'"quotes"\'   .')

assert(a == 37, 'The minifier is breaking code!')

-- Create a few chatcommands
sscsm.register_chatcommand('error_test', function(param)
    error('Testing: ' .. param)
end)

sscsm.register_chatcommand('sscsm', {
    func = function(param)
        return true, 'Hello from the SSCSM!'
    end,
})

sscsm.register_chatcommand('slap', function(param)
    if param:gsub(' ', '') == '' then
        return false, 'Invalid usage. Usage: ' .. minetest.colorize('#00ffff',
            '/slap <victim>') .. '.'
    end

    minetest.run_server_chatcommand('me', 'slaps ' .. param ..
        ' around a bit with a large trout.')
end)

-- A potentially useful example
sscsm.register_chatcommand('msg', function(param)
    -- If you're actually using this, remove this.
    assert(param ~= '<error>', 'Test')

    local sendto, msg = param:match('^(%S+)%s(.+)$')
    if not sendto then
        return false, 'Invalid usage, see ' .. minetest.colorize('#00ffff',
            '/help msg') .. '.'
    end

    minetest.run_server_chatcommand('msg', param)
end)

sscsm.register_chatcommand('privs', function(param)
    if param == '' and minetest.get_privilege_list then
        local privs = {}
        for priv, n in pairs(minetest.get_privilege_list()) do
            if n then
                table.insert(privs, priv)
            end
        end
        table.sort(privs)
        return true, minetest.colorize('#00ffff', 'Privileges of ' ..
            minetest.localplayer:get_name() .. ': ') .. table.concat(privs, ' ')
    end

    minetest.run_server_chatcommand('privs', param)
end)

-- Create yay() to test dependencies
function yay()
    print('yay() called')
end
