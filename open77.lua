resource "opx77_status"
version "0.2.0"
open77_version ">=0.0.1"
auto_start true

reload_policy "reconnect"

-- No surface: this resource owns the effect registry and opx77_hud draws it.
shared_script "config.lua"

server_script "server/main.lua"

client_script "client/state.lua"
client_script "client/main.lua"
client_script "client/exports.lua"

permissions {
  "network.events", -- opx77_status:pull, :push and :values
  "database.access", -- opx77_character_status, this resource's own table
}
