--- The surface, the tick, and the events raised back to an effect's owner.

OpxStatus = OpxStatus or {}

local Config = OPX_STATUS_CONFIG

--- How often expired effects and stopped owners are swept, and the event raised beside each
--- effect's own so one listener can watch them all. Cadence and a name, not settings.
local TICK_MS = 250

--- The most effects one resource may hold. A guard rail against a caller that leaks, not a
--- number an operator would tune.
local MAX_PER_OWNER = 24
local GLOBAL_EVENT = "opx77:status"

--- What opx77_hud listens on to draw the strip. A client-side event, because the client
--- runtime has a cross-resource bus and this is exactly what it is for.
local EFFECTS_EVENT = "opx77:status:effects"
local State = OpxStatus.state

local Runtime = {}
OpxStatus.runtime = Runtime

local RESOURCE = GetCurrentResourceName()


local drawn = nil

local function nowMs()
  return math.floor(Open77.time.monotonic() * 1000)
end

--- Tell an effect's owner what happened to it: no export can answer a callback.
---@param effect table
---@param action string
local function emit(effect, action)
  local payload = {
    status = effect.id,
    owner = effect.owner,
    action = action,
    label = effect.label,
    tone = effect.tone,
    data = effect.data,
  }
  if effect.event then TriggerEvent(effect.event, payload) end
  local global = GLOBAL_EVENT
  if global and global ~= false and global ~= effect.event then
    TriggerEvent(global, payload)
  end
end

--- What would be drawn, minus the countdowns the hud animates on its own clock.
---@param view table
---@return string
local function signature(view)
  local chips = view.chips
  local parts = { tostring(view.hidden) }
  for index = 1, #chips do
    local chip = chips[index]
    parts[index + 1] = table.concat({
      chip.id, chip.label, chip.icon or "", chip.tone or "",
      tostring(chip.progress or ""), tostring(chip.totalMs or ""),
    }, "\1")
  end
  return table.concat(parts, "\2")
end

--- What this resource holds, published for opx77_hud to draw.
---
--- An event, not a surface. This resource owns the effects; the one corner of the screen they
--- appear in belongs to the hud, which already places, themes and animates a surface there.
---@param force boolean|nil
local function draw(force)
  local view = State.view(nowMs())
  local current = signature(view)
  if not force and current == drawn then return end
  drawn = current
  TriggerEvent(EFFECTS_EVENT, {
    anchor = Config.ANCHOR,
    offset = Config.OFFSET,
    chips = view.chips,
    hidden = view.hidden,
  })
end

Runtime.draw = draw

--- Kept for the export surface, which refuses when there is nothing to publish to.
---@return boolean
function Runtime.unavailable()
  return false
end


--- Note the caller's generation, dropping everything it held if it has reloaded.
---@param owner string
---@param generation integer
function Runtime.noteOwner(owner, generation)
  if State.generations[owner] ~= nil and State.generations[owner] ~= generation then
    if State.removeOwner(owner) > 0 then draw() end
  end
  State.generations[owner] = generation
end

---@param owner string
---@param spec table
---@return table|nil effect
---@return string|nil reason
function Runtime.add(owner, spec)
  local effect, reason = State.normalize(owner, spec, nowMs())
  if effect == nil then return nil, reason end
  -- replacing your own is not a new effect: the limit only guards additions
  if State.get(owner, effect.id) == nil and State.count(owner) >= MAX_PER_OWNER then
    return nil, "owner_limit"
  end
  State.put(effect)
  draw()
  return effect
end

---@param owner string
---@param id string
--- The patched value, or the held one when the patch says nothing.
---
--- An `if`, not `given ~= nil and given or held`: that collapses on `false` and
--- keeps the old value, so a caller passing `false` for a label was answered
--- `ok` instead of `invalid_label`.
---@param given any
---@param held any
---@return any
local function pick(given, held)
  if given ~= nil then return given end
  return held
end

---@param patch table
---@return boolean ok
---@return string|nil reason
function Runtime.update(owner, id, patch)
  local current = State.get(owner, id)
  if current == nil then return false, "not_found" end
  if type(patch) ~= "table" then return false, "spec_must_be_a_table" end
  local merged = {
    id = id,
    label = pick(patch.label, current.label),
    icon = pick(patch.icon, current.icon),
    tone = pick(patch.tone, current.tone),
    progress = pick(patch.progress, current.progress),
    priority = pick(patch.priority, current.priority),
    event = pick(patch.event, current.event),
    data = pick(patch.data, current.data),
    durationMs = patch.durationMs,
  }
  local effect, reason = State.normalize(owner, merged, nowMs())
  if effect == nil then return false, reason end
  -- a patch that says nothing about the deadline keeps the one it had
  if patch.durationMs == nil then
    effect.expiresAtMs = current.expiresAtMs
    effect.startedAtMs = current.startedAtMs
  end
  State.put(effect)
  draw()
  return true
end

---@param owner string
---@param id string
---@return boolean
function Runtime.remove(owner, id)
  local effect = State.get(owner, id)
  if effect == nil then return false end
  State.remove(owner, id)
  emit(effect, "removed")
  draw()
  return true
end

---@param owner string
---@return integer removed
function Runtime.clear(owner)
  local removed = State.removeOwner(owner)
  if removed > 0 then draw() end
  return removed
end

--- Removes what expired, and what an owner that stopped or reloaded left behind.
local function tick()
  local atMs = nowMs()

  local due = State.expired(atMs)
  local expired = #due
  for index = 1, expired do
    local effect = due[index]
    State.remove(effect.owner, effect.id)
    emit(effect, "expired")
  end

  -- Resolved once for the sweep. It cannot change between two owners of the same pass, and
  -- inside the loop it was two `type` calls per owner every TICK_MS.
  local generationOf
  if type(Open77.resource) == "table" and type(Open77.resource.generation) == "function" then
    generationOf = Open77.resource.generation
  end

  -- Built only when there is something to put in it: the common tick has nothing stopped,
  -- and an empty table four times a second is four allocations that answer nothing.
  local stopped, stoppedCount = nil, 0
  for owner, generation in pairs(State.generations) do
    local running = GetResourceState(owner) == "running"
    local current
    if generationOf ~= nil then current = generationOf(owner) end
    if not running or (current ~= nil and current ~= generation) then
      stoppedCount = stoppedCount + 1
      stopped = stopped or {}
      stopped[stoppedCount] = owner
    end
  end
  for index = 1, stoppedCount do
    local owner = stopped[index]
    State.removeOwner(owner)
    State.generations[owner] = nil
  end

  if expired > 0 or stoppedCount > 0 then draw() end
end

AddEventHandler("onClientResourceStart", function(name)
  if name ~= RESOURCE then return end

  CreateThread(function()
    while true do
      tick()
      Wait(TICK_MS)
    end
  end)
end)

AddEventHandler("onClientResourceStop", function(name)
  if name ~= RESOURCE then return end
  drawn = nil
end)
