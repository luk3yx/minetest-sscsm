-- Originally from bls_custom

unused_args = false
allow_defined_top = true
max_line_length = 80

globals = {
    'INIT',
    'minetest',
    'sscsm',
    table = {fields = {'copy'}},
    'core',
}

read_globals = {
    string = {fields = {'split', 'trim'}},
    "__FLAGS__",
}

files["example_sscsm.lua"].ignore = { "" }
