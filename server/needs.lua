--- Hunger and thirst: the two numbers this resource owns.
---
--- Server-side, because they are durable character state. opx77_core stores them in
--- `PlayerData.metadata` and saves them; this file decides how fast they fall and what
--- running out costs. opx77_hud draws them and decides nothing.

local Config = OPX_STATUS_CONFIG

--- The two needs, and what each does at zero. Health is not here: the engine owns it, and a
--- need that emptied it directly would fight whatever else is writing to it.
local NEEDS = { "hunger", "thirst" }

---@param value any
---@return number|nil
local function finite(value)
  value = tonumber(value)
  if value == nil or value ~= value then return nil end
  return value
end

--- Drop every loaded character's needs by one tick's worth.
---
--- Written through `Functions.SetMetaData` rather than into the table, so the core marks the
--- character changed and the autosave carries it. A character at zero stays at zero; the
--- damage below is what running out costs, not a further drop.
local function tick()
  for _, player in pairs(OPX.GetPlayers()) do
    local data = player.PlayerData
    local metadata = data.metadata or {}
    local emptied = {}

    for _, need in ipairs(NEEDS) do
      local held = finite(metadata[need])
      if held ~= nil then
        local next = math.max(0, held - Config.NEEDS[need].PER_TICK)
        if next ~= held then player.Functions.SetMetaData(need, next) end
        if next <= 0 then emptied[#emptied + 1] = need end
      end
    end

    if #emptied > 0 and Config.NEEDS.DAMAGE_AT_ZERO > 0 then
      local health = finite(metadata.health)
      if health ~= nil and health > 0 then
        player.Functions.SetMetaData("health",
          math.max(0, health - Config.NEEDS.DAMAGE_AT_ZERO * #emptied))
      end
    end
  end
end

CreateThread(function()
  while true do
    Wait(Config.NEEDS.TICK_SECONDS * 1000)
    -- wrapped: one character with a malformed metadata row must not stop the tick for
    -- everybody else, and this loop never gets a second chance if it raises
    local ok, err = pcall(tick)
    if not ok then Open77.log.error("needs tick: " .. tostring(err)) end
  end
end)

Open77.log.info(("needs: hunger -%g and thirst -%g every %ds"):format(
  Config.NEEDS.hunger.PER_TICK, Config.NEEDS.thirst.PER_TICK, Config.NEEDS.TICK_SECONDS))
