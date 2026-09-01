OPX_STATUS_CONFIG = {
  ANCHOR = "bottom-left", -- "bottom-left" | "bottom-right" | "top-left" | "top-right"
  OFFSET = 120, -- pixels the effect strip sits above the corner, clear of the gauges
  MAX_VISIBLE = 6, -- chips drawn at once, the rest are counted in a "+3" chip

  NEEDS = { -- hunger and thirst, owned here and drawn by opx77_hud
    TICK_SECONDS = 300, -- how often they fall
    DAMAGE_AT_ZERO = 2, -- health lost per tick per empty need; 0 to make them cosmetic
    hunger = { PER_TICK = 1.0 },
    thirst = { PER_TICK = 1.4 }, -- thirst outruns hunger, as it does in every survival system
  },
}
