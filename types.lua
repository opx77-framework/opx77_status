---@meta
--- Type annotations for opx77_status. Never loaded at runtime.

---@alias CitizenId string  the character key, e.g. "H7K-M4X3"

---@alias NeedKey "hunger"|"thirst"|"stamina"|"streetCred"

--- A presentation role, or one of 2077's damage types.
---@alias StatusTone "ok"|"warn"|"bad"|"accent"|"bleed"|"burn"|"shock"|"chem"

--- Why a call was refused. Every export answers one of these in `error`.
---@alias StatusError
---| "export_call_required" no invoking resource, so the call came from inside
---| "spec_must_be_a_table"  the effect spec, or the needs patch, was not a table
---| "missing_id"            the effect spec carries no id
---| "invalid_id"            an id longer than 64, or outside [%w_:-.]
---| "invalid_label"         empty after control characters were stripped
---| "invalid_event"         an event name longer than 96, or outside [%w_:-.]
---| "invalid_tone"          not one of StatusTone
---| "invalid_duration"      not finite, not positive, or past one hour
---| "invalid_data"          `data` was not a table
---| "data_too_large"        past 64 nodes or 4 levels deep
---| "invalid_progress"      not a finite number
---| "owner_limit"           this resource already holds 24 effects
---| "not_found"             no effect of yours with that id
---| "unknown_need"          not a key of OPX_STATUS_CONFIG.NEEDS
---| "invalid_need_value"    not a finite number
---| "empty_patch"           the patch named no need
---| "no_character"          opx77_core has no character loaded
---| "not_loaded"            the server half has not answered for this character yet

--- One effect handed to the `addEffect` export.
---@class StatusSpec
---@field id string unique per owner
---@field label string
---@field icon? string one or two glyphs
---@field tone? StatusTone
---@field durationMs? integer it removes itself when this elapses, and tells you
---@field progress? number 0..1, drawn as a fill
---@field priority? number higher survives the MAX_VISIBLE cut
---@field event? string raised for this effect in addition to the global one
---@field data? table opaque, echoed in the payload

--- One chip of the strip published on `opx77:status:effects`.
---@class StatusChip
---@field id string "<owner>:<effect id>"
---@field label string
---@field icon string|nil
---@field tone StatusTone|nil
---@field progress number|nil
---@field remainingMs integer|nil
---@field totalMs integer|nil

--- The payload of `opx77:status:effects`, which opx77_hud draws.
---@class StatusEffectsEvent
---@field anchor string
---@field offset integer
---@field chips StatusChip[]
---@field hidden integer  effects past MAX_VISIBLE

--- The payload of an effect's own event, and of the global `opx77:status`.
---@class StatusEffectEvent
---@field status string  the effect's id
---@field owner string
---@field action "removed"|"expired"
---@field label string
---@field tone StatusTone|nil
---@field data table|nil

--- Every need this resource owns; bounds come from OPX_STATUS_CONFIG.NEEDS. Health, armour
--- and the death flags are not here: they stay in opx77_core's `PlayerData.metadata`.
---@class NeedValues
---@field hunger number      0-100
---@field thirst number      0-100
---@field stamina number     0-100
---@field streetCred number  0-100000

--- The payload of OPX_STATUS_CONFIG.NEEDS_EVENT, raised on the client after every change.
--- On "unloaded" `ready` is false and `values` is empty.
---@class NeedsEvent
---@field values NeedValues
---@field changed NeedKey[]
---@field source "loaded"|"decay"|"set"|"add"|"unloaded"
---@field citizenId CitizenId|nil
---@field ready boolean

--- Every export answers a table carrying `ok` and never raises.
---@class StatusResponse
---@field ok boolean
---@field error StatusError|nil

--- What the `getNeeds` export answers when a character is loaded and the server has replied.
---@class NeedsResponse : StatusResponse
---@field values NeedValues|nil
---@field citizenId CitizenId|nil
---@field ready boolean|nil

--- What `setNeeds` and `addNeeds` answer.
---@class NeedsWriteResponse : StatusResponse
---@field values NeedValues|nil
---@field changed NeedKey[]|nil

--- What the server half selects out of opx77_character_status: the one column it reads.
---@class StatusRow
---@field needs string  JSON, decoded into NeedValues
