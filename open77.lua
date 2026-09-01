resource "opx77_status"
version "0.2.0"
open77_version ">=0.0.1"
auto_start true

reload_policy "reconnect"

-- No surface. This resource owns the DATA -- hunger and thirst, and the effect registry --
-- and opx77_hud draws it. Two surfaces for one corner of the screen was two things to place,
-- theme and keep in step.
server_script "config.lua"
server_script "server/needs.lua"

client_script "config.lua"
client_script "client/state.lua"
client_script "client/main.lua"
client_script "client/exports.lua"

permissions {
  "network.events", -- the needs tick tells opx77_hud's client half what changed
}
