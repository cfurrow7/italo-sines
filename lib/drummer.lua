-- drummer.lua: Italo disco drum pattern engine

local Drummer = {}

-- Coordinated drum kits (each kit has kick/snare/hat/tom patterns)
-- 16-step arrays: value = velocity (0 = rest)
Drummer.KITS = {
  { name = "Classic Italo",
    kick  = {120,0,0,0, 120,0,0,0, 120,0,0,0, 120,0,0,0},
    snare = {0,0,0,0, 110,0,0,0, 0,0,0,0, 110,0,0,0},
    hat   = {0,0,100,0, 0,0,100,0, 0,0,100,0, 0,0,100,0},
    tom   = {0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0},
  },
  { name = "Moroder",
    kick  = {120,0,0,0, 120,0,0,0, 120,0,0,0, 120,0,0,0},
    snare = {0,0,0,0, 110,0,0,60, 0,0,0,0, 110,0,0,60},
    hat   = {90,90,90,90, 90,90,90,90, 90,90,90,90, 90,90,90,90},
    tom   = {0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,80},
  },
  { name = "Hi-NRG",
    kick  = {120,0,0,0, 120,0,0,0, 120,0,0,0, 120,0,0,0},
    snare = {0,0,0,0, 120,0,0,0, 0,0,0,0, 120,0,0,0},
    hat   = {100,60,100,60, 100,60,100,60, 100,60,100,60, 100,60,100,60},
    tom   = {0,0,0,0, 0,0,0,0, 0,0,0,0, 80,0,80,0},
  },
  { name = "Euro Disco",
    kick  = {120,0,0,60, 120,0,0,0, 120,0,0,60, 120,0,0,0},
    snare = {0,0,0,0, 110,0,0,0, 0,0,0,0, 110,0,40,0},
    hat   = {0,0,90,0, 0,0,90,0, 0,0,90,0, 0,0,90,90},
    tom   = {0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0},
  },
  { name = "Cosmic",
    kick  = {120,0,0,0, 120,0,0,0, 120,0,60,0, 120,0,0,0},
    snare = {0,0,0,0, 110,0,0,0, 0,0,0,0, 110,0,0,0},
    hat   = {80,0,80,80, 0,0,80,80, 80,0,80,80, 0,0,80,80},
    tom   = {0,0,0,0, 0,0,0,0, 0,80,0,0, 0,0,0,0},
  },
  { name = "Minimal",
    kick  = {120,0,0,0, 120,0,0,0, 120,0,0,0, 120,0,0,0},
    snare = {0,0,0,0, 100,0,0,0, 0,0,0,0, 100,0,0,0},
    hat   = {0,0,80,0, 0,0,80,0, 0,0,80,0, 0,0,80,0},
    tom   = {0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0},
  },
  { name = "Synth Pop",
    kick  = {120,0,0,0, 0,0,100,0, 120,0,0,0, 0,0,100,0},
    snare = {0,0,0,0, 120,0,0,0, 0,0,0,0, 120,0,0,80},
    hat   = {90,0,90,0, 90,0,90,0, 90,0,90,0, 90,0,90,0},
    tom   = {0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0},
  },
  { name = "Funky Disco",
    kick  = {120,0,0,0, 0,0,0,0, 120,0,80,0, 0,0,0,0},
    snare = {0,0,0,0, 120,0,0,60, 0,0,0,0, 120,0,0,0},
    hat   = {80,80,80,80, 80,80,80,80, 80,80,80,80, 80,80,80,80},
    tom   = {0,0,0,0, 0,0,0,0, 0,0,0,60, 0,0,80,0},
  },
}

-- Get velocity at a step for a drum type within a kit
-- Returns 0 for rest, >0 for hit
function Drummer.get_vel(kit_idx, drum_type, step)
  local kit = Drummer.KITS[kit_idx]
  if not kit then return 0 end
  local pattern = kit[drum_type]
  if not pattern then return 0 end
  local idx = ((step - 1) % 16) + 1
  return pattern[idx] or 0
end

function Drummer.kit_name(idx)
  local kit = Drummer.KITS[idx]
  return kit and kit.name or "?"
end

function Drummer.num_kits()
  return #Drummer.KITS
end

return Drummer
