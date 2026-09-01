--- The registry of live effects: validation, ordering and expiry.

OpxStatus = OpxStatus or {}

--- Mirrors `version` in open77.lua, which no Lua code can read.
OpxStatus.VERSION = "0.1.0"

local Config = OPX_STATUS_CONFIG

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

---@param value any
---@return boolean
local function finite(value)
  -- `value == value` is the NaN check, not a typo
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

--- Display text, cleaned rather than refused: a label is cosmetic.
---@param value any
---@param maximum integer
---@return string|nil
local function displayText(value, maximum)
  if value == nil then return nil end
  if type(value) == "number" then value = tostring(value) end
  if type(value) ~= "string" then return nil end
  value = value:gsub("[%c]", " ")
  if #value > maximum then value = value:sub(1, maximum) end
  return value
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

  local label = displayText(spec.label, MAX_LABEL)
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
    icon = displayText(spec.icon, MAX_ICON),
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
    chips[#chips + 1] = {
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

--- Effects whose time is up.
---@param atMs integer
---@return table[]
function State.expired(atMs)
  local due = {}
  for _, mine in pairs(State.byOwner) do
    for _, effect in pairs(mine) do
      if effect.expiresAtMs ~= nil and atMs >= effect.expiresAtMs then due[#due + 1] = effect end
    end
  end
  return due
end
