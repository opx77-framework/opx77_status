--- Every export answers a table carrying `ok`, and an `error` code when it is false.

local State = OpxStatus.state
local Runtime = OpxStatus.runtime

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


---@alias StatusTone "ok"|"warn"|"bad"|"accent"|"bleed"|"burn"|"shock"|"chem"

---@class StatusSpec
---@field id string unique per owner
---@field label string
---@field icon? string one or two glyphs
---@field tone? StatusTone a presentation role, or one of 2077's damage types
---@field durationMs? integer it removes itself when this elapses, and tells you
---@field progress? number 0..1, drawn as a fill
---@field priority? number higher survives the MAX_VISIBLE cut
---@field event? string raised for this effect in addition to the global one
---@field data? table opaque, echoed in the payload

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
