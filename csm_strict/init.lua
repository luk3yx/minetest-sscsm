--
-- SSCSM: Server-Sent Client-Side Mods proof-of-concept: "Strict" version
--
-- Copyright © 2019-2020 by luk3yx
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

-- Spectre mitigations make measuring performance harder
local ENABLE_SPECTRE_MITIGATIONS = true

-- Add a random number onto the current time in case servers try and predict
--  the random seed
math.randomseed(os.time() + math.random())

local storage = minetest.get_mod_storage()

-- Load the Env class
-- Mostly copied from https://stackoverflow.com/a/26367080
-- Don't copy metatables
local function copy(obj, s)
	if s and s[obj] ~= nil then return s[obj] end
	if type(obj) ~= 'table' then return obj end
	s = s or {}
	local res = {}
	s[obj] = res
	for k, v in pairs(obj) do res[copy(k, s)] = copy(v, s) end
	return res
end

-- Safe functions
local Env = {}
local safe_funcs = {}

-- No getmetatable()
if rawget(_G, 'getmetatable') then
	safe_funcs[getmetatable] = function() end
end

-- Get the current value of string.rep in case other CSMs decide to break
do
	safe_funcs[math.randomseed] = function() end

	local rep = string.rep
	safe_funcs[string.rep] = function(str, n)
		if #str * n > 1048576 then
			error('string.rep: string length overflow', 2)
		end
		return rep(str, n)
	end

	local show_formspec = minetest.show_formspec
	safe_funcs[show_formspec] = function(formname, ...)
		if type(formname) == 'string' then
			return show_formspec('sscsm:_' .. formname, ...)
		end
	end

	local after = minetest.after
	safe_funcs[after] = function(n, ...)
		if type(n) == 'number' then return after(n, pcall, ...) end
	end

	local on_fs_input = minetest.register_on_formspec_input
	safe_funcs[on_fs_input] = function(func)
		on_fs_input(function(formname, fields)
			if formname:sub(1, 7) == 'sscsm:_' then
				pcall(func, formname:sub(8), copy(fields))
			end
		end)
	end

	local deserialize = minetest.deserialize
	safe_funcs[deserialize] = function(str)
		return deserialize(str, true)
	end

	if ENABLE_SPECTRE_MITIGATIONS then
		local get_us_time, floor = minetest.get_us_time, math.floor
		safe_funcs[get_us_time] = function()
			return floor(get_us_time() / 100) * 100
		end
	end

	local wrap = function(n)
		local orig = minetest[n] or minetest[n .. 's']
		if type(orig) == 'function' then
			return function(func)
				orig(function(...)
					local r = {pcall(func, ...)}
					if r[1] then
						table.remove(r, 1)
						return (table.unpack or unpack)(r)
					else
						minetest.log('error', '[SSCSM] ' .. tostring(r[2]))
					end
				end)
			end
		end
	end

	for _, k in ipairs({'register_globalstep', 'register_on_death',
			'register_on_hp_modification', 'register_on_damage_taken',
			'register_on_dignode', 'register_on_punchnode',
			'register_on_placenode', 'register_on_item_use',
			'register_on_modchannel_message', 'register_on_modchannel_signal',
			'register_on_inventory_open', 'register_on_sending_chat_message',
			'register_on_receiving_chat_message'}) do
		safe_funcs[minetest[k]] = wrap(k)
	end
end

-- Environment
function Env.new_empty()
	local self = {_raw = {}, _seen = copy(safe_funcs)}
	self._raw['_G'] = self._raw
	return setmetatable(self, {__index = Env}) or self
end
-- function Env:get(k) return self._raw[self._seen[k] or k] end
function Env:set(k, v) self._raw[copy(k, self._seen)] = copy(v, self._seen) end
function Env:set_copy(k, v)
	self:set(k, v)
	self._seen[k] = nil
	self._seen[v] = nil
end
function Env:add_globals(...)
	for i = 1, select('#', ...) do
		local var = select(i, ...)
		self:set(var, _G[var])
	end
end
function Env:update(data) for k, v in pairs(data) do self:set(k, v) end end
function Env:del(k)
	if self._seen[k] then
		self._raw[self._seen[k]] = nil
		self._seen[k] = nil
	end
	self._raw[k] = nil
end

-- function Env:copy()
--	 local new = {_seen = copy(safe_funcs)}
--	 new._raw = copy(self._raw, new._seen)
--	 return setmetatable(new, {__index = Env}) or new
-- end

-- Load code into a callable function.
function Env:loadstring(code, file)
	if code:byte(1) == 27 then return nil, 'Invalid code!' end
	local f, msg = loadstring(code, ('=%q'):format(file))
	if not f then return nil, msg end
	setfenv(f, self._raw)
	return function(...)
		local good, res = pcall(f, ...)
		if good then
			return res
		else
			minetest.log('error', '[SSCSM] ' .. tostring(res))
		end
	end
end

function Env:exec(code, file)
	local f, msg = self:loadstring(code, file)
	if not f then
		minetest.log('error', '[SSCSM] Syntax error: ' .. tostring(msg))
		return false
	end
	f()
	return true
end

-- Create the environment
local env = Env:new_empty()

-- Clone everything
env:add_globals('assert', 'dump', 'dump2', 'error', 'ipairs', 'math',
	'next', 'pairs', 'pcall', 'select', 'setmetatable', 'string', 'table',
	'tonumber', 'tostring', 'type', 'vector', 'xpcall', '_VERSION')

env:set_copy('os', {clock = os.clock, difftime = os.difftime, time = os.time})

-- Create a slightly locked down "minetest" table
do
	local t = {}
	for _, k in ipairs({"add_particle", "add_particlespawner", "after",
			"clear_out_chat_queue", "colorize", "compress", "debug",
			"decode_base64", "decompress", "delete_particlespawner",
			"deserialize", "disconnect", "display_chat_message",
			"encode_base64", "explode_scrollbar_event", "explode_table_event",
			"explode_textlist_event", "find_node_near", "find_nodes_in_area",
			"find_nodes_in_area_under_air", "find_nodes_with_meta",
			"formspec_escape", "get_background_escape_sequence",
			"get_color_escape_sequence", "get_day_count", "get_item_def",
			"get_language", "get_meta", "get_node_def", "get_node_level",
			"get_node_light", "get_node_max_level", "get_node_or_nil",
			"get_player_names", "get_privilege_list", "get_server_info",
			"get_timeofday", "get_translator", "get_us_time", "get_version",
			"get_wielded_item", "gettext", "is_nan", "is_yes", "line_of_sight",
			"log", "mod_channel_join", "parse_json",
			"pointed_thing_to_face_pos", "pos_to_string", "privs_to_string",
			"raycast", "register_globalstep", "register_on_damage_taken",
			"register_on_death", "register_on_dignode",
			"register_on_formspec_input", "register_on_hp_modification",
			"register_on_inventory_open", "register_on_item_use",
			"register_on_modchannel_message", "register_on_modchannel_signal",
			"register_on_placenode", "register_on_punchnode",
			"register_on_receiving_chat_message",
			"register_on_sending_chat_message", "rgba",
			"run_server_chatcommand", "send_chat_message", "send_respawn",
			"serialize", "sha1", "show_formspec", "sound_play", "sound_stop",
			"string_to_area", "string_to_pos", "string_to_privs",
			"strip_background_colors", "strip_colors",
			"strip_foreground_colors", "translate", "wrap_text",
			"write_json"}) do
		local func = minetest[k]
		t[k] = safe_funcs[func] or func
	end

	env:set_copy('minetest', t)
end

-- Add table.unpack
if not table.unpack then
	env._raw.table.unpack = unpack
end

-- Make sure copy() worked correctly
assert(env._raw.minetest.register_on_sending_chat_message ~=
	minetest.register_on_sending_chat_message, 'Error in copy()!')

-- SSCSM functions
-- When calling these from an SSCSM, make sure they exist first.
local mod_channel
local loaded_sscsms = {}
env:set('join_mod_channel', function()
	if not mod_channel then
		mod_channel = minetest.mod_channel_join('sscsm:exec_pipe')
	end
end)

local function leave_mod_channel()
	if mod_channel then
		mod_channel:leave()
		mod_channel = false
	end
end
env:set('leave_mod_channel', leave_mod_channel)

-- Get the address
local get_address
do
	local addr
	function get_address()
		if not addr then
			local info = minetest.get_server_info()
			addr = tostring(info.address)
			if addr == '' then
				addr = 'singleplayer'
			else
				addr = addr .. ':' .. tostring(info.port)
			end
		end
		return addr
	end
end

-- Get trusted SSCSMs
local trust, trustdb, allowed
local function is_sscsm_trusted(name, code)
	if allowed or trust then return true end

	-- Don't return false if trust is nil.
	if trust == false then return false end

	if code == nil and type(name) == 'table' then
		name, code = name.name, name.code
	end
	if type(name) ~= 'string' or type(code) ~= 'string' then return false end

	if not trustdb then
		local raw = storage:get_string('trust-' .. get_address())
		if raw then trustdb = minetest.deserialize(raw) end
		trustdb = trustdb or {}
	end

	if trustdb[name] == code then
		return true
	else
		trust = false
		return false
	end
end

-- exec() code sent by the server.
local sscsm_queue = {}
local sscsms_running = false

minetest.register_on_modchannel_message(function(channel_name, sender, message)
	if channel_name ~= 'sscsm:exec_pipe' or (sender and sender ~= '')
			or #sscsm_queue > 512 then
		return
	end

	-- The first character is currently a version code, currently 0.
	-- Do not change unless absolutely necessary.
	local version = message:sub(1, 1)
	local name, code
	if version == '0' then
		local s, e = message:find('\n')
		if not s or not e then return end
		local target = message:sub(2, s - 1)
		if target ~= minetest.localplayer:get_name() then return end
		message = message:sub(e + 1)
		s, e = message:find('\n')
		if not s or not e then return end
		name = message:sub(1, s - 1)
		code = message:sub(e + 1)
	else
		return
	end

	-- Don't load the same SSCSM twice
	if not loaded_sscsms[name] then
		loaded_sscsms[name] = true
		if allowed or is_sscsm_trusted(name, code) then
			-- Create the environment
			minetest.log('action', '[SSCSM] Loading ' .. name)
			sscsms_running = true
			env:exec(code, name)
		elseif sscsm_queue then
			if allowed == nil then
				local a = get_address()
				minetest.display_chat_message(minetest.colorize('#eeeeee',
					'[SSCSM] This server (' .. minetest.formspec_escape(a) ..
					') wants to run sandboxed code on your client. ' ..
					'Run .sscsm to allow or deny this.'))
				if sscsms_running then
					minetest.display_chat_message(minetest.colorize('yellow',
						'[SSCSM] WARNING: New SSCSMs have been added or '
						.. 'modified since you last trusted this server. '
						.. 'SSCSMs are in a partially loaded state, '
						.. 'please run .sscsm and fix this.'))
				end
				allowed = false
			end
			table.insert(sscsm_queue, {name=name, code=code})
		end
	end
end)

-- Send "0" when the "sscsm:exec_pipe" channel is first joined.
local sent_request = false
minetest.register_on_modchannel_signal(function(channel_name, signal)
	if sent_request or channel_name ~= 'sscsm:exec_pipe' then
		return
	end

	if signal == 0 then
		env._raw.minetest.localplayer = minetest.localplayer
		env._raw.minetest.camera = minetest.camera
		env._raw.minetest.ui = table.copy(minetest.ui)
		mod_channel:send_all('0')
		sent_request = true
	elseif signal == 1 then
		mod_channel:leave()
		mod_channel = nil
	end
end)

local function attempt_to_join_mod_channel()
	-- Wait for minetest.localplayer to become available.
	if not minetest.localplayer then
		minetest.after(0.05, attempt_to_join_mod_channel)
		return
	end

	-- Join the mod channel
	mod_channel = minetest.mod_channel_join('sscsm:exec_pipe')
end
minetest.after(0, attempt_to_join_mod_channel)

-- "Securely" display a formspec
local function random_identifier()
	return tostring(math.random() + math.random(0, 1000000000))
end

local secure_show_formspec, current_formname
local inspecting = false
do
	local _show_formspec = minetest.show_formspec
	function secure_show_formspec(spec, preserve)
		if preserve == nil then
			inspecting = false
		end

		-- Regenerate the formname every time.
		current_formname = 'sscsm:' .. random_identifier()

		-- Display the formspec
		_show_formspec(current_formname, spec)
	end
end

local allow_id, deny_id, inspect_id, checkbox_id
local function show_default_formspec()
	leave_mod_channel()
	local allow_text, deny_text, allowed_msg
	if allowed or (sscsms_running and sscsm_queue and #sscsm_queue == 0) then
		deny_text  = 'Exit to menu'
		allow_text = 'Close dialog'
		allowed_msg = minetest.colorize('orange', 'running')
	elseif sscsm_queue then
		allow_text = 'Allow'

		if sscsms_running then
			allowed_msg = minetest.colorize('red', 'partially running')
			deny_text = 'Exit to menu'
		else
			allowed_msg = 'inactive'
			deny_text = 'Deny'
		end
	else
		allowed_msg = minetest.colorize('lightgreen', 'disabled')
	end

	-- Randomly generate identifiers
	allow_id = 'btn_' .. random_identifier()
	deny_id = allow_id
	while deny_id == allow_id do
		deny_id = 'btn_' .. random_identifier()
	end

	local formspec = 'size[8,4]no_prepend[]' ..
		'image_button[0,0;8,1;blank.png;ignore;SSCSM;true;false;]' ..
		'label[0,1;SSCSMs are currently ' ..
		minetest.formspec_escape(allowed_msg) .. '.]'

	if allow_text == 'Allow' then
		inspect_id = allow_id
		while inspect_id == allow_id or inspect_id == deny_id do
			inspect_id = 'btn_' .. random_identifier()
		end
		formspec = formspec ..
			'label[0,1.5;Do you want to allow this server to ' ..
				'execute (sandboxed) code locally?]' ..
			'image_button[6,0.2;2,0.6;;' .. inspect_id ..
				';Inspect code;true;true;]'
	else
		inspect_id = nil
		formspec = formspec ..
			'label[0,1.5;You cannot change this without reconnecting.]'
	end

	if allowed or sscsm_queue then
		local tr = trust
		if tr == nil and sscsms_running and sscsm_queue and
				#sscsm_queue == 0 then
			tr = true
		end

		if tr or sscsm_queue then
			checkbox_id = allow_id
			while checkbox_id == allow_id or checkbox_id == deny_id or
					checkbox_id == inspect_id do
				checkbox_id = 'btn_' .. random_identifier()
			end

			formspec = formspec ..'checkbox[0,2;' .. checkbox_id ..
				';Permanently allow these SSCSMs.;' ..
				(tr and 'true' or 'false') .. ']'
		else
			checkbox_id = nil
			formspec = formspec ..'checkbox[0,2;ignore;' ..
				minetest.colorize('#888888',
					'Permanently allow these SSCSMs.') .. ';false]'
		end

	else
		checkbox_id = nil
	end

	if allow_text and deny_text then
		 formspec = formspec .. 'button_exit[0,3;4,1;' .. deny_id .. ';' ..
			minetest.formspec_escape(deny_text) .. ']' ..
			'button_exit[4,3;4,1;' .. allow_id .. ';' ..
			minetest.formspec_escape(allow_text) .. ']'
	else
		formspec = formspec .. 'button_exit[0,3;8,1;' .. deny_id
			.. ';Close dialog]'
	end

	secure_show_formspec(formspec)
end

-- The inspect formspec
local inspect_file = 1

local function show_inspect_formspec()
	if not sscsm_queue then return end

	if not inspecting then
		inspecting = random_identifier()
		minetest.display_chat_message('[SSCSM] If the number displayed in' ..
			' the inspector changes, the server has tampered with it and ' ..
			'you should not allow SSCSMs.')
	end
	inspect_id = random_identifier()
	deny_id = inspect_id
	while deny_id == inspect_id do deny_id = random_identifier() end

	local formspec = 'size[10,9]no_prepend[]' ..
		'label[0,0;SSCSM: Code Inspector.\n\n' ..
		minetest.colorize('#eeeeee', 'This number should not change while ' ..
			'the inspector is running:\n' .. tostring(inspecting)) .. ']' ..
		'button[9,0;1,1;' .. deny_id .. ';X]' ..
		'textlist[0,2;2,7;' .. tostring(inspect_id) .. ';'

	for id, code in ipairs(sscsm_queue) do
		if id > 1 then formspec = formspec .. ',' end
		formspec = formspec .. '##' .. minetest.formspec_escape(code.name)
	end

	formspec = formspec .. ';' .. inspect_file .. ']' ..
		'textarea[2.5,2;7.75,8.2;;Code:;'

	if sscsm_queue[inspect_file] then
		formspec = formspec ..
			minetest.formspec_escape(sscsm_queue[inspect_file].code)
	end

	secure_show_formspec(formspec .. ']box[2.2,2;7.5,7;#000000]', true)
end

-- Handle formspec input
minetest.register_on_formspec_input(function(formname, fields)
	-- Sanity check
	if not current_formname or formname ~= current_formname then return end

	-- Minetest doesn't(?) leak the formname, however this is still here in
	--  case that changes in the future (or for if the server can somehow trick
	--  the client into leaking formspec inputs).
	current_formname = false

	-- Check for options
	if inspecting then
		if fields.quit then
			inspecting = false
			minetest.after(0.1, show_default_formspec)
			return true
		elseif fields[deny_id] then
			inspecting = false
			show_default_formspec()
			return true
		elseif fields[inspect_id] then
			local event = minetest.explode_textlist_event(fields[inspect_id])
			if event.type == 'CHG' then inspect_file = event.index end
		end

		show_inspect_formspec()
	elseif fields[deny_id] then
		if allowed or sscsms_running then
			minetest.disconnect()
		end
		if sscsm_queue then
			sscsm_queue = false
			minetest.display_chat_message('[SSCSM] SSCSMs have been denied.')
			storage:set_string('trust-' .. get_address(), '')
		end
	elseif fields[allow_id] then
		if allowed or (sscsm_queue and #sscsm_queue == 0) then
			return true
		end

		minetest.display_chat_message('[SSCSM] SSCSMs have been allowed.')
		allowed = true
		if sscsm_queue then
			sscsms_running = true
			local mods
			if trust then mods = {} end
			for _, def in ipairs(sscsm_queue) do
				minetest.log('action', '[SSCSM] Loading ' .. def.name)
				if mods then mods[def.name] = def.code end
				env:exec(def.code, def.name)
			end
			if mods then
				storage:set_string('trust-' .. get_address(),
					minetest.serialize(mods))
			end
		end
		sscsm_queue = false
	elseif fields[inspect_id] then
		inspect_file = 1
		show_inspect_formspec()
	elseif fields.quit then
		minetest.display_chat_message(minetest.colorize('#eeeeee',
			'[SSCSM] No action specified.'))
	elseif fields[checkbox_id] then
		trust = minetest.is_yes(fields[checkbox_id])
		if not trust then
			storage:set_string('trust-' .. get_address(), '')
		end
		show_default_formspec()
	else
		show_default_formspec()
	end

	return true
end)

-- Add .sscsm
minetest.register_chatcommand('sscsm', {
	descrption = 'Displays SSCSM options for this server.',
	func = function(_)
		if allowed == nil and not sscsms_running then
			return false, 'This server has not attempted to load any SSCSMs.'
		else
			show_default_formspec()
		end
	end
})
