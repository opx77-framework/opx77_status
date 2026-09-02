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
local CORE = "opx77_core"

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
  -- once, not twice, when the owner named GLOBAL_EVENT as its own event
  if GLOBAL_EVENT ~= effect.event then TriggerEvent(GLOBAL_EVENT, payload) end
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

--- The patched value, or the held one when the patch says nothing. An `if` rather than
--- `given ~= nil and given or held`, which collapses on `false`.
---@param given any
---@param held any
---@return any
local function pick(given, held)
  if given ~= nil then return given end
  return held
end

---@param owner string
---@param id string
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

-- ---------------------------------------------------------------------------
-- The needs
-- ---------------------------------------------------------------------------

local Needs = OpxStatus.needs

--- How long the client waits before asking the server half again for a character it has an
--- id for but no values.
local PULL_RETRY_MS = 10000

local lastDecayAtMs, lastPushAtMs, lastPullAtMs = 0, 0, 0

--- Tell everything on the client that a need moved. opx77_hud redraws from this.
---@param source string
---@param changed NeedKey[]
local function publishNeeds(source, changed)
  TriggerEvent(Config.NEEDS_EVENT, {
    values = Needs.snapshot(),
    changed = changed,
    source = source,
    citizenId = Needs.citizenId,
    ready = Needs.ready,
  })
end

--- Ask the server half for this character's stored values.
---@param atMs integer
local function pull(atMs)
  lastPullAtMs = atMs
  local accepted, reason = TriggerServerEvent("opx77_status:pull", Needs.citizenId)
  if not accepted then
    Open77.log.warn(("needs not requested: %s"):format(tostring(reason)))
  end
end

--- Send the held values back. Skipped unless PUSH_MS has passed or a need moved PUSH_DELTA,
--- because the disconnect is the one moment this client cannot speak.
---@param atMs integer
---@param force boolean|nil
---@return boolean sent
local function push(atMs, force)
  if not Needs.ready or Needs.citizenId == nil then return false end
  local drift = Needs.drift()
  if drift <= 0 and not force then return false end
  if not force and drift < Config.PUSH_DELTA and atMs - lastPushAtMs < Config.PUSH_MS then
    return false
  end

  local values = Needs.snapshot()
  local accepted, reason = TriggerServerEvent("opx77_status:push", Needs.citizenId, values)
  if not accepted then
    Open77.log.warn(("needs not pushed: %s"):format(tostring(reason)))
    return false
  end
  Needs.pushed = values
  lastPushAtMs = atMs
  return true
end

Runtime.pushNeeds = push

--- Adopt a character and ask for its values. Idempotent: the same id twice does nothing.
---@param citizenId any
function Runtime.bindCharacter(citizenId)
  if type(citizenId) ~= "string" or citizenId == "" then return end
  if Needs.citizenId == citizenId then return end
  Needs.begin(citizenId)
  local atMs = nowMs()
  lastDecayAtMs, lastPushAtMs = atMs, atMs
  pull(atMs)
end

--- Apply a patch from an export and publish whatever moved.
---@param patch table
---@param relative boolean
---@param source string
---@return NeedKey[]|nil changed
---@return string|nil reason
function Runtime.patchNeeds(patch, relative, source)
  local changed, reason = Needs.apply(patch, relative)
  if changed == nil then return nil, reason end
  if #changed > 0 then
    publishNeeds(source, changed)
    push(nowMs(), false)
  end
  return changed
end

--- Decay, the throttled push, and the retry for a character the server never answered for.
local function needsTick()
  local atMs = nowMs()

  if Needs.citizenId == nil then return end
  if not Needs.ready then
    if atMs - lastPullAtMs >= PULL_RETRY_MS then pull(atMs) end
    return
  end

  local elapsed = atMs - lastDecayAtMs
  if elapsed >= Config.DECAY_MS then
    lastDecayAtMs = atMs
    local changed = Needs.decay(elapsed)
    if #changed > 0 then publishNeeds("decay", changed) end
  end

  push(atMs, false)
end

AddEventHandler("opx77:client:onPlayerLoaded", function(playerData)
  if type(playerData) ~= "table" then return end
  Runtime.bindCharacter(playerData.citizenId)
end)

AddEventHandler("opx77:client:onPlayerUnloaded", function()
  if Needs.citizenId == nil then return end
  Needs.forget()
  publishNeeds("unloaded", {})
end)

--- The server half answered the pull. A late answer for a character that has already been
--- swapped out is dropped.
RegisterNetEvent("opx77_status:values", function(citizenId, values)
  if citizenId ~= Needs.citizenId then return end
  Needs.receive(values)
  local atMs = nowMs()
  lastDecayAtMs, lastPushAtMs = atMs, atMs
  local changed = {}
  for key in pairs(Needs.values) do changed[#changed + 1] = key end
  table.sort(changed)
  publishNeeds("loaded", changed)
end)

--- Catch up when this resource starts mid-session: the core's loaded event has already been
--- and gone, so the character is read straight off its export. Coroutine only.
local function adoptRunningCharacter()
  if GetResourceState(CORE) ~= "running" then return end
  local promise = Open77.exports.call(CORE, "GetPlayerData")
  if not promise then return end
  local result, callError = promise:await()
  if callError or type(result) ~= "table" or result.ok ~= true then return end
  if type(result.data) == "table" then Runtime.bindCharacter(result.data.citizenId) end
end

AddEventHandler("onClientResourceStart", function(name)
  if name ~= RESOURCE then return end

  CreateThread(function()
    while true do
      tick()
      Wait(TICK_MS)
    end
  end)

  CreateThread(function()
    adoptRunningCharacter()
    local cadence = math.max(1000, math.min(Config.DECAY_MS, Config.PUSH_MS))
    while true do
      Wait(cadence)
      needsTick()
    end
  end)
end)

--- Teardown for both halves: our own stop takes the strip down, another resource's stop
--- takes its chips down now rather than at the next tick.
AddEventHandler("onClientResourceStop", function(name)
  if name == RESOURCE then
    -- a reload is the one stop this client survives, so the values go back first
    Runtime.pushNeeds(nowMs(), true)
    State.byOwner = {}
    State.generations = {}
    -- forced: nothing in opx77_hud's page knows this resource stopped, and there is no
    -- later publish to correct an empty strip with
    draw(true)
    -- no `emit`: an owner's handler is free to call straight back into an export, and this
    -- VM is halfway through stopping
    return
  end

  if State.removeOwner(name) > 0 then draw() end
  State.generations[name] = nil
end)
