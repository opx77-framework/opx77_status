--- Every export answers a table carrying `ok`, and an `error` code when it is false.

local State = OpxStatus.state
local Runtime = OpxStatus.runtime
local Needs = OpxStatus.needs

---@param ok boolean
---@param values table|nil
---@return table
local function response(ok, values)
  values = values or {}
  values.ok = ok == true
  return values
end

--- Who is calling, and at which generation of their code, both from the host.
---@return string|nil owner
---@return string|integer generation the refusal reason when owner is nil
local function caller()
  local owner = GetInvokingResource()
  local generation = GetInvokingResourceGeneration()
  if not State.validName(owner, 64) or type(generation) ~= "number" then
    return nil, "export_call_required"
  end
  Runtime.noteOwner(owner, generation)
  return owner, generation
end

--- Show an effect, or replace one of yours with the same id.
---@param spec StatusSpec
---@return table
exports("add", function(spec)
  local owner, generation = caller()
  if not owner then return response(false, { error = generation }) end
  local effect, reason = Runtime.add(owner, spec)
  if effect == nil then return response(false, { error = reason }) end
  return response(true, { id = effect.id })
end)

--- Change one of yours in place; a patch without `durationMs` keeps the deadline.
---@param id string
---@param patch StatusSpec fields absent from it keep the value they have
---@return table
exports("update", function(id, patch)
  local owner, generation = caller()
  if not owner then return response(false, { error = generation }) end
  if not State.validName(id, 64) then return response(false, { error = "invalid_id" }) end
  local ok, reason = Runtime.update(owner, id, patch)
  if not ok then return response(false, { error = reason }) end
  return response(true, {})
end)

--- Take one of yours down; removing what is not there is `not_found`, never a raise.
---@param id string
---@return table
exports("remove", function(id)
  local owner, generation = caller()
  if not owner then return response(false, { error = generation }) end
  if not State.validName(id, 64) then return response(false, { error = "invalid_id" }) end
  if not Runtime.remove(owner, id) then return response(false, { error = "not_found" }) end
  return response(true, {})
end)

--- Take down everything of yours. Never touches another resource's.
---@return table
exports("clear", function()
  local owner, generation = caller()
  if not owner then return response(false, { error = generation }) end
  return response(true, { removed = Runtime.clear(owner) })
end)

--- The character's needs as this client holds them. `opx77_hud` draws from this and redraws
--- on OPX_STATUS_CONFIG.NEEDS_EVENT rather than polling it.
---@return NeedsResponse
exports("needs", function()
  local owner, generation = caller()
  if not owner then return response(false, { error = generation }) end
  if Needs.citizenId == nil then return response(false, { error = "no_character" }) end
  if not Needs.ready then
    return response(false, { error = "not_loaded", citizenId = Needs.citizenId })
  end
  return response(true, {
    values = Needs.snapshot(),
    citizenId = Needs.citizenId,
    ready = true,
  })
end)

--- Set one or more needs outright. Values are clamped to the bounds in config.lua.
---@param patch table<NeedKey, number>
---@return NeedsWriteResponse
exports("setNeeds", function(patch)
  local owner, generation = caller()
  if not owner then return response(false, { error = generation }) end
  if not Needs.ready then return response(false, { error = "not_loaded" }) end
  local changed, reason = Runtime.patchNeeds(patch, false, "set")
  if changed == nil then return response(false, { error = reason }) end
  return response(true, { values = Needs.snapshot(), changed = changed })
end)

--- Move one or more needs by a delta: a meal, a shot of stamina, a street cred payout.
---@param patch table<NeedKey, number>
---@return NeedsWriteResponse
exports("addNeeds", function(patch)
  local owner, generation = caller()
  if not owner then return response(false, { error = generation }) end
  if not Needs.ready then return response(false, { error = "not_loaded" }) end
  local changed, reason = Runtime.patchNeeds(patch, true, "add")
  if changed == nil then return response(false, { error = reason }) end
  return response(true, { values = Needs.snapshot(), changed = changed })
end)
