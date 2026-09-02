OPX_STATUS_CONFIG = {
  -- The corner the effect strip sits in -- on OPX77_HUD's surface, not on one of ours: this
  -- resource draws nothing, it publishes the corner and opx77_hud places the strip there.
  -- So the accepted set is opx77_hud's, and only its: "bottom-left" | "bottom-right" |
  -- "top-left" | "top-right". Anything else is dropped silently by web/hud.js, which then
  -- leaves the strip in the HUD's own corner.
  ANCHOR = "bottom-left",
  OFFSET = 120, -- pixels the effect strip sits above the corner, clear of the gauges
  MAX_VISIBLE = 6, -- chips drawn at once, the rest are counted in a "+3" chip
}
