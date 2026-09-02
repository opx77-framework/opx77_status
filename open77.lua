resource "opx77_status"
version "0.2.0"
open77_version ">=0.0.1"
auto_start true

reload_policy "reconnect"

-- No surface: this resource owns the effect registry and opx77_hud draws it. Two surfaces for
-- one corner of the screen was two things to place, theme and keep in step.
--
-- Hunger and thirst moved to opx77_core: they are character metadata, and a server resource
-- cannot read another's players.
client_script "config.lua"
client_script "client/state.lua"
client_script "client/main.lua"
client_script "client/exports.lua"

-- Empty on purpose, not by omission. This resource sends and receives nothing over the
-- network, declares no web_ui_page, and touches no world API: its whole surface is four
-- exports and the local events they raise, and neither needs a grant. open77_zones, the
-- first-party service shaped exactly like this one, ships an empty block for the same reason.
permissions {}
