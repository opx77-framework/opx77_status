--- The registry of live effects, and the character's needs: validation, ordering and expiry.

OpxStatus = OpxStatus or {}

--- Mirrors `version` in open77.lua, which no Lua code can read; a release moves both lines.
OpxStatus.VERSION = "0.4.0"

local Config = OPX_STATUS_CONFIG
local Text = OpxStatus.Text

local State = {}
OpxStatus.state = State

local MAX_LABEL = 32
local MAX_ICON = 2
local MAX_EVENT = 96
local MAX_DURATION_MS = 3600000

-- `data` rides in every event raised: the host drops a payload past 1024 nodes in silence
local MAX_DATA_NODES = 64
local MAX_DATA_DEPTH = 4

--- owner -> { id -> effect }
State.byOwner = {}

--- owner -> the generation we last saw it at
State.generations = {}

--- A finite number: a number, not NaN, and neither infinity.
---@param value any
---@return boolean
local function finite(value)
  -- `value == value` is the NaN check, not a typo: NaN is the one value unequal to itself
  return type(value) == "number" and value == value
    and value > -math.huge and value < math.huge
end

---@param value any
---@param maximum integer
---@return boolean
function State.validName(value, maximum)
  return type(value) == "string" and #value > 0 and #value <= maximum
    and value:match("^[%w_:%-%.]+$") ~= nil
end

--- Count a caller's opaque table, refusing rather than truncating it.
---@param value any
---@param depth integer
---@param budget table
---@return boolean
local function fitsInPayload(value, depth, budget)
  budget.data = budget.data + 1
  if budget.data > MAX_DATA_NODES then return false end
  if type(value) ~= "table" then return true end
  if depth > MAX_DATA_DEPTH then return false end
  for key, nested in pairs(value) do
    if not fitsInPayload(key, depth + 1, budget) then return false end
    if not fitsInPayload(nested, depth + 1, budget) then return false end
  end
  return true
end

local TONES = {
  ok = true, warn = true, bad = true, accent = true,
  bleed = true, burn = true, shock = true, chem = true,
}

---@param owner string
---@param spec table
---@param atMs integer
---@return table|nil effect
---@return string|nil reason
function State.normalize(owner, spec, atMs)
  if type(spec) ~= "table" then return nil, "spec_must_be_a_table" end

  local id = spec.id
  if id == nil then return nil, "missing_id" end
  if not State.validName(id, 64) then return nil, "invalid_id" end

  local label = Text.clean(spec.label, MAX_LABEL)
  if label == nil or label == "" then return nil, "invalid_label" end

  if spec.event ~= nil and not State.validName(spec.event, MAX_EVENT) then
    return nil, "invalid_event"
  end

  local tone = spec.tone
  if tone ~= nil and not TONES[tone] then return nil, "invalid_tone" end

  local duration = spec.durationMs
  if duration ~= nil then
    if not finite(duration) or duration <= 0 or duration > MAX_DURATION_MS then
      return nil, "invalid_duration"
    end
  end

  if spec.data ~= nil then
    if type(spec.data) ~= "table" then return nil, "invalid_data" end
    if not fitsInPayload(spec.data, 1, { data = 0 }) then return nil, "data_too_large" end
  end

  local progress = spec.progress
  if progress ~= nil then
    if not finite(progress) then return nil, "invalid_progress" end
    if progress < 0 then progress = 0 end
    if progress > 1 then progress = 1 end
  end

  return {
    owner = owner,
    id = id,
    label = label,
    icon = Text.clean(spec.icon, MAX_ICON),
    tone = tone,
    -- absolute, not remaining: the page counts down from this on its own clock
    expiresAtMs = duration and (atMs + math.floor(duration)) or nil,
    startedAtMs = atMs,
    progress = progress,
    priority = finite(spec.priority) and spec.priority or 0,
    event = spec.event,
    data = spec.data,
  }
end

---@param owner string
---@param id string
---@return table|nil
function State.get(owner, id)
  local mine = State.byOwner[owner]
  return mine and mine[id] or nil
end

---@param effect table
function State.put(effect)
  local mine = State.byOwner[effect.owner]
  if mine == nil then
    mine = {}
    State.byOwner[effect.owner] = mine
  end
  mine[effect.id] = effect
end

---@param owner string
---@return integer
function State.count(owner)
  local mine = State.byOwner[owner]
  if mine == nil then return 0 end
  local total = 0
  for _ in pairs(mine) do total = total + 1 end
  return total
end

---@param owner string
---@param id string
---@return boolean
function State.remove(owner, id)
  local mine = State.byOwner[owner]
  if mine == nil or mine[id] == nil then return false end
  mine[id] = nil
  return true
end

---@param owner string
---@return integer removed
function State.removeOwner(owner)
  local mine = State.byOwner[owner]
  if mine == nil then return 0 end
  local removed = State.count(owner)
  State.byOwner[owner] = nil
  return removed
end

--- Everything live, highest priority first, then most recently started.
---@return table[]
function State.ordered()
  local all = {}
  for _, mine in pairs(State.byOwner) do
    for _, effect in pairs(mine) do all[#all + 1] = effect end
  end
  table.sort(all, function(a, b)
    if a.priority ~= b.priority then return a.priority > b.priority end
    if a.startedAtMs ~= b.startedAtMs then return a.startedAtMs > b.startedAtMs end
    -- a total order: equal keys would leave the strip reshuffling on `pairs` order
    return a.owner .. "\1" .. a.id < b.owner .. "\1" .. b.id
  end)
  return all
end

--- What the page draws: the visible chips, and how many were left out.
---@param atMs integer
---@return table
function State.view(atMs)
  local all = State.ordered()
  local chips = {}
  local limit = Config.MAX_VISIBLE
  for index = 1, math.min(#all, limit) do
    local effect = all[index]
    chips[index] = {
      id = effect.owner .. ":" .. effect.id,
      label = effect.label,
      icon = effect.icon,
      tone = effect.tone,
      progress = effect.progress,
      remainingMs = effect.expiresAtMs and math.max(0, effect.expiresAtMs - atMs) or nil,
      totalMs = effect.expiresAtMs and (effect.expiresAtMs - effect.startedAtMs) or nil,
    }
  end
  return { chips = chips, hidden = math.max(0, #all - limit) }
end

--- Effects whose time is up, or nil when none are. Built lazily: this runs every tick and
--- almost every tick has nothing to collect.
---@param atMs integer
---@return table[]|nil
function State.expired(atMs)
  local due = nil
  for _, mine in pairs(State.byOwner) do
    for _, effect in pairs(mine) do
      if effect.expiresAtMs ~= nil and atMs >= effect.expiresAtMs then
        due = due or {}
        due[#due + 1] = effect
      end
    end
  end
  return due
end

-- ---------------------------------------------------------------------------
-- The needs
-- ---------------------------------------------------------------------------

--- The character's needs. The client owns these during play; the server half only stores
--- what it was last pushed.
local Needs = {}
OpxStatus.needs = Needs

local FIELDS = Config.NEEDS

--- The character these values belong to, or nil when none is loaded.
---@type CitizenId|nil
Needs.citizenId = nil

--- True once the server half has answered for `citizenId`.
Needs.ready = false

--- key -> number, one entry per key of Config.NEEDS.
---@type NeedValues
Needs.values = {}

--- The last values the server acknowledged, so a push that would say nothing is skipped.
---@type NeedValues|nil
Needs.pushed = nil

--- Every push sent, by its send index, until it is acknowledged. The acknowledgement names
--- no push, so the nth one settles the nth push and no later one.
---@type table<integer, NeedValues>
Needs.sent = {}

--- How many pushes have been sent, and how many of those have been acknowledged.
Needs.sentCount = 0
Needs.ackedCount = 0

--- Pushes held for an acknowledgement that may never arrive. Past this the oldest is
--- forgotten, which leaves `pushed` where it is: a redundant push, never a lost value.
local MAX_UNACKED = 8

--- Forget every push still waiting, without moving `pushed`.
local function forgetSent()
  Needs.sent = {}
  Needs.sentCount = 0
  Needs.ackedCount = 0
end

--- Note a push on its way out.
---@param values NeedValues  the snapshot that was sent
function Needs.sending(values)
  Needs.sentCount = Needs.sentCount + 1
  Needs.sent[Needs.sentCount] = values
  Needs.sent[Needs.sentCount - MAX_UNACKED] = nil
end

--- Settle the oldest push still waiting. `pushed` only ever moves to a snapshot the server
--- has certainly seen, so the drift a dropped push carried is sent again rather than lost.
---@return boolean settled
function Needs.acknowledge()
  if Needs.ackedCount >= Needs.sentCount then return false end
  Needs.ackedCount = Needs.ackedCount + 1
  local values = Needs.sent[Needs.ackedCount]
  Needs.sent[Needs.ackedCount] = nil
  if values == nil then return false end
  Needs.pushed = values
  return true
end

--- Whether a key is a need this resource owns.
---@param key any
---@return boolean
function Needs.isField(key)
  return type(key) == "string" and FIELDS[key] ~= nil
end

--- One value in its field's bounds, or nil when it is not a finite number.
---@param key NeedKey
---@param value any
---@return number|nil
function Needs.clamp(key, value)
  local field = FIELDS[key]
  if field == nil then return nil end
  local number = tonumber(value)
  if not finite(number) then return nil end
  if number < field.MIN then return field.MIN end
  if number > field.MAX then return field.MAX end
  return number
end

---@return NeedValues
function Needs.defaults()
  local values = {}
  for key, field in pairs(FIELDS) do values[key] = field.DEFAULT end
  return values
end

---@return NeedValues
function Needs.snapshot()
  local copy = {}
  for key, value in pairs(Needs.values) do copy[key] = value end
  return copy
end

--- Start over on a character, at the defaults, until the server answers.
---@param citizenId CitizenId
function Needs.begin(citizenId)
  Needs.citizenId = citizenId
  Needs.ready = false
  Needs.values = Needs.defaults()
  Needs.pushed = nil
  forgetSent()
end

--- Adopt what the server sent, with the defaults filling anything it left out.
---@param raw any
function Needs.receive(raw)
  local values = Needs.defaults()
  if type(raw) == "table" then
    for key in pairs(FIELDS) do
      local clamped = Needs.clamp(key, raw[key])
      if clamped ~= nil then values[key] = clamped end
    end
  end
  Needs.values = values
  Needs.ready = true
  -- what the server just said IS the last push: there is nothing to send back yet
  Needs.pushed = Needs.snapshot()
  forgetSent()
end

function Needs.forget()
  Needs.citizenId = nil
  Needs.ready = false
  Needs.values = {}
  Needs.pushed = nil
  forgetSent()
end

--- Apply a patch, absolute or relative, and answer which keys actually moved.
---@param patch table<string, number>
---@param relative boolean  add to the held value rather than replace it
---@return NeedKey[]|nil changed
---@return StatusError|nil reason
function Needs.apply(patch, relative)
  if type(patch) ~= "table" then return nil, "spec_must_be_a_table" end

  local wanted, count = {}, 0
  for key, raw in pairs(patch) do
    if not Needs.isField(key) then return nil, "unknown_need" end
    local value = tonumber(raw)
    if not finite(value) then return nil, "invalid_need_value" end
    local target = value
    if relative then target = (Needs.values[key] or FIELDS[key].DEFAULT) + value end
    wanted[key] = Needs.clamp(key, target)
    count = count + 1
  end
  if count == 0 then return nil, "empty_patch" end

  local changed = {}
  for key, value in pairs(wanted) do
    if Needs.values[key] ~= value then
      Needs.values[key] = value
      changed[#changed + 1] = key
    end
  end
  -- a total order: `pairs` order would reshuffle the list between two identical patches
  table.sort(changed)
  return changed
end

--- Charge `DECAY_PER_MINUTE` against every need that declares one.
---@param elapsedMs integer
---@return NeedKey[] changed
function Needs.decay(elapsedMs)
  local minutes = elapsedMs / 60000
  local patch, count = {}, 0
  for key, field in pairs(FIELDS) do
    -- `finite`, not `~= nil`: a NaN or an infinity in config.lua passes a bare `> 0`
    local rate = field.DECAY_PER_MINUTE
    if finite(rate) and rate > 0 then
      patch[key] = -(rate * minutes)
      count = count + 1
    end
  end
  if count == 0 then return {} end
  return Needs.apply(patch, true) or {}
end

--- The largest move on any need since the last acknowledged push. A character with no push
--- behind it has everything to say, so that answers infinity.
---@return number
function Needs.drift()
  local pushed = Needs.pushed
  if pushed == nil then return math.huge end
  local worst = 0
  for key, value in pairs(Needs.values) do
    local difference = math.abs(value - (pushed[key] or 0))
    if difference > worst then worst = difference end
  end
  return worst
end
