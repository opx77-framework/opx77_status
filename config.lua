--- Configuration for opx77_status: the effect strip, and the needs this resource owns.

OPX_STATUS_CONFIG = {
  -- the corner opx77_hud places the strip in: "bottom-left", "bottom-right", "top-left" or
  -- "top-right". Anything else leaves the strip in the HUD's own corner.
  ANCHOR = "bottom-left",
  OFFSET = 120, -- pixels the effect strip sits above the corner, clear of the gauges
  MAX_VISIBLE = 6, -- chips drawn at once, the rest are counted in a "+3" chip

  NEEDS_EVENT = "opx77:status:needs", -- raised on the client after every change to a need

  -- Every need this resource owns, with its bounds, its value on a new character, and how
  -- fast it falls. A key absent from here is refused by every export and never stored.
  NEEDS = {
    hunger = { MIN = 0, MAX = 100, DEFAULT = 100, DECAY_PER_MINUTE = 0.20 },
    thirst = { MIN = 0, MAX = 100, DEFAULT = 100, DECAY_PER_MINUTE = 0.28 },
    stamina = { MIN = 0, MAX = 100, DEFAULT = 100 },
    streetCred = { MIN = 0, MAX = 100000, DEFAULT = 0 },
  },

  DECAY_MS = 60000, -- how often DECAY_PER_MINUTE is charged against hunger and thirst
  PUSH_MS = 120000, -- how often the client pushes its values to the server half
  PUSH_DELTA = 5, -- a move this large on any need pushes at once instead of waiting
  AUTOSAVE_MS = 300000, -- how often the server writes the pushes it is holding
}
