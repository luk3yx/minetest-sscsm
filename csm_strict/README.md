# Minetest server-sent CSM proof-of-concept

This CSM asks permission before allowing SSCSMs to run. The allow/deny formspec
name is randomly generated to prevent servers from creating fake allow/deny
formspecs.

Permanently allowing SSCSMs does not apply to SSCSMs added/modified after
allowing them. If a modified or new SSCSM is found, no more SSCSMs will be
loaded until the user allows them. However, some (but not all) previously
trusted SSCSMs may be loaded.

CSM installation guide: https://forum.minetest.net/viewtopic.php?f=53&t=17830
