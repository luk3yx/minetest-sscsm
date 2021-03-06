--
-- SSCSM: Server-Sent Client-Side Mods proof-of-concept
-- Testing code
--
-- Copyright © 2019-2020 by luk3yx
-- License: https://git.minetest.land/luk3yx/sscsm/src/branch/master/LICENSE.md
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU Lesser General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.

-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU Lesser General Public License for more details.

-- You should have received a copy of the GNU Lesser General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.
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

print('assert = ' .. tostring(assert))
sscsm.every(60, function(param1)
    assert(param1 == 123)
    print('sscsm.every test called.')
end, 123)

sscsm.register_on_com_receive('sscsm:testing', function(msg)
    if #msg > 400 then
        print('Got large message of length ' .. #msg .. ' from the server')
    else
        sscsm.com_send('sscsm:testing', msg)
        print('Got ' .. minetest.serialize(msg):sub(8) .. ' from the server')
    end
end)
