--- The server half: the status table, the net events, and the save paths. Every value here
--- came off a client and is bounded before it reaches a column, never re-derived.

local Config = OPX_STATUS_CONFIG
local FIELDS = Config.NEEDS
local Text = OpxStatus.Text

--- How long a log line off the wire may be, in characters.
local MAX_LOGGED = 64

local CREATE = [[
CREATE TABLE IF NOT EXISTS opx77_character_status (
    citizen_id VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
    needs JSON NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB
]]

local SELECT_NEEDS = "SELECT needs FROM opx77_character_status WHERE citizen_id = @citizen"

local UPSERT_NEEDS = [[
INSERT INTO opx77_character_status (citizen_id, needs) VALUES (@citizen, @needs)
ON DUPLICATE KEY UPDATE needs = @needs
]]

--- player -> { citizenId, values, dirty }. The last push each loaded player sent.
local held = {}

local pullWindows, pushWindows = {}, {}

--- The rate limit on both net events, per player. A guard against a flood, not a budget a
--- well-behaved client ever reaches.
local WINDOW_MS = 10000
local PULLS_PER_WINDOW = 4
local PUSHES_PER_WINDOW = 12

--- False until the table exists; nothing is read or written before it does.
local schemaReady = false

---@return integer
local function nowMs()
  return math.floor(Open77.time.monotonic() * 1000)
end

---@return boolean
local function within(windows, player, limit, spanMs)
  local at = nowMs()
  local window = windows[player]
  if window == nil or at - window.started >= spanMs then
    window = { started = at, count = 0 }
    windows[player] = window
  end
  if window.count >= limit then return false end
  window.count = window.count + 1
  return true
end

--- One bridge call. `MySQL.<method>.await` RAISES rather than answering a reason, and a raise
--- inside a CreateThread kills it silently. Coroutine only.
---@param method string
---@param sql string
---@param params? table
---@return boolean ok
---@return any value  the rows, or the failure reason
local function run(method, sql, params)
  local api = rawget(_G, "MySQL")
  local fn = api and api[method]
  if not fn or type(fn.await) ~= "function" then
    return false, ("MySQL.%s.await is unavailable"):format(method)
  end
  local ok, value = pcall(fn.await, sql, params)
  if not ok then return false, tostring(value) end
  return true, value
end

--- Truncate and strip control characters before a value off the wire reaches a log line.
---@param value any
---@return string
local function safe(value)
  return Text.clean(tostring(value or ""), MAX_LOGGED, "...") or ""
end

--- A citizen id, taken at face value: shaped like one and short enough for the column.
---@param value any
---@return CitizenId|nil
local function citizenId(value)
  if type(value) ~= "string" or #value < 1 or #value > 16 then return nil end
  if value:match("^[%u%d%-]+$") == nil then return nil end
  return value
end

--- Every configured need, in its own bounds, with the default filling anything missing.
--- `count` is what separates "a payload of needs" from "a table with none of them in it".
---@param raw any
---@return NeedValues|nil
local function bounded(raw)
  if type(raw) ~= "table" then return nil end
  local clean, count = {}, 0
  for key, field in pairs(FIELDS) do
    local number = tonumber(raw[key])
    -- `number ~= number` is the NaN check, not a typo: NaN is the one value unequal to itself
    if number == nil or number ~= number or number == math.huge or number == -math.huge then
      clean[key] = field.DEFAULT
    else
      if number < field.MIN then number = field.MIN end
      if number > field.MAX then number = field.MAX end
      clean[key] = number
      count = count + 1
    end
  end
  if count == 0 then return nil end
  return clean
end

---@return NeedValues
local function defaults()
  local values = {}
  for key, field in pairs(FIELDS) do values[key] = field.DEFAULT end
  return values
end

--- The stored row, or the configured defaults when there is none. Coroutine only.
---@param id CitizenId
---@return NeedValues|nil values
---@return string|nil reason
local function load(id)
  local ok, row = run("single", SELECT_NEEDS, { citizen = id })
  if not ok then return nil, tostring(row) end
  if type(row) ~= "table" or row.needs == nil then return defaults() end

  local stored = row.needs
  if type(stored) == "string" then
    local decoded, value = pcall(json.decode, stored)
    stored = decoded and value or nil
  end
  return bounded(stored) or defaults()
end

--- Write one character's needs. Coroutine only.
---@param id CitizenId
---@param values NeedValues
---@return boolean
local function save(id, values)
  local encoded, payload = pcall(json.encode, values)
  if not encoded then
    Open77.log.warn(("%s not saved: %s"):format(safe(id), tostring(payload)))
    return false
  end
  local ok, reason = run("update", UPSERT_NEEDS, { citizen = id, needs = payload })
  if not ok then
    Open77.log.warn(("%s not saved: %s"):format(safe(id), tostring(reason)))
    return false
  end
  return true
end

--- Write a player's last push, if there is one that has not been written yet.
---@param player integer
---@param forget boolean  also drop the record, for a player who has gone
local function flush(player, forget)
  local record = held[player]
  if forget then held[player] = nil end
  if record == nil or not record.dirty or not schemaReady then return end
  record.dirty = false
  CreateThread(function()
    if not save(record.citizenId, record.values) then record.dirty = not forget end
  end)
end

--- A client says which character it is. The id is trusted; only its shape is checked.
RegisterNetEvent("opx77_status:pull", function(rawCitizenId)
  local player = tonumber(source) or 0
  if player <= 0 then return end
  if not within(pullWindows, player, PULLS_PER_WINDOW, WINDOW_MS) then return end
  local id = citizenId(rawCitizenId)
  if id == nil or not schemaReady then return end

  CreateThread(function()
    local values, reason = load(id)
    if values == nil then
      Open77.log.warn(("%s could not be read: %s"):format(safe(id), tostring(reason)))
      return
    end
    held[player] = { citizenId = id, values = values, dirty = false }
    TriggerClientEvent("opx77_status:values", player, id, values)
  end)
end)

--- The client owns the values during play and pushes them here on a throttle. Nothing is
--- written now: the last push is what the save paths below write.
RegisterNetEvent("opx77_status:push", function(rawCitizenId, rawValues)
  local player = tonumber(source) or 0
  if player <= 0 then return end
  if not within(pushWindows, player, PUSHES_PER_WINDOW, WINDOW_MS) then return end
  local id = citizenId(rawCitizenId)
  if id == nil then return end
  local values = bounded(rawValues)
  if values == nil then return end
  held[player] = { citizenId = id, values = values, dirty = true }
  -- the client holds its drift until this lands, so a push refused above is sent again
  TriggerClientEvent("opx77_status:pushed", player, id)
end)

--- The player has gone. Their last push during play is the freshest thing that exists: the
--- client cannot send anything from here.
---@param rawPlayerId any
local function departed(rawPlayerId)
  local player = tonumber(rawPlayerId) or 0
  if player <= 0 then return end
  flush(player, true)
  pullWindows[player] = nil
  pushWindows[player] = nil
end

-- the only departure event this platform raises
AddEventHandler("onPlayerDisconnected", departed)

AddEventHandler("onResourceStop", function(name)
  if name ~= GetCurrentResourceName() then return end
  for player in pairs(held) do flush(player, false) end
end)

--- One autosave pass, so a raise from a host call ends the pass rather than the loop.
local function autosave()
  for player in pairs(held) do flush(player, false) end
end

CreateThread(function()
  local created, reason = run("update", CREATE)
  if not created then
    Open77.log.error("cannot create opx77_character_status: " .. tostring(reason))
    Open77.log.error("no character's needs will be loaded or saved until this is fixed")
    return
  end
  schemaReady = true
  Open77.log.info("ready")

  local failing = false
  while true do
    Wait(Config.AUTOSAVE_MS)
    local ok, failure = pcall(autosave)
    if ok then
      failing = false
    elseif not failing then
      failing = true
      Open77.log.error(("the autosave failed: %s"):format(tostring(failure)))
    end
  end
end)
