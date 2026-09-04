resource "opx77_status"
version "0.4.0"
open77_version ">=0.0.1"
auto_start true

reload_policy "reconnect"

-- No surface: this resource owns the effect registry and opx77_hud draws it.
shared_script "config.lua"
shared_script "shared/text.lua"

server_script "server/main.lua"

client_script "client/state.lua"
client_script "client/main.lua"
client_script "client/exports.lua"

permissions {
  "network.events", -- opx77_status:pull, :push, :values and :pushed
  -- opx77_character_status is this resource's own table. opx77_characters belongs to
  -- opx77_core and is only ever READ here, to check that a caller owns the character
  -- whose needs they are asking for.
  "database.access",
}
