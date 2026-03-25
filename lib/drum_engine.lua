-- drum_engine.lua: Internal drum sample player using Timber engine
-- Loads kits from drum_room's sample library

local MusicUtil = require "musicutil"

local DrumEngine = {}

-- GM-ish note mapping for our drum slots
DrumEngine.SLOTS = {
  kick  = 0,
  snare = 1,
  hat   = 2,
  tom   = 3,
}

-- Available kits (from drum_room's sample library)
DrumEngine.KITS = {
  { name = "TR-808", path = "audio/common/808/",
    samples = {
      kick  = "808-BD.wav",
      snare = "808-SD.wav",
      hat   = "808-CH.wav",
      tom   = "808-LT.wav",
    }
  },
  { name = "TR-909", path = "audio/common/909/",
    samples = {
      kick  = "909-BD.wav",
      snare = "909-SD.wav",
      hat   = "909-CH.wav",
    }
  },
  { name = "TR-606", path = "audio/common/606/",
    samples = {
      kick  = "606-BD.wav",
      snare = "606-SD.wav",
      hat   = "606-CH.wav",
      tom   = "606-HT.wav",
    }
  },
}

DrumEngine.current_kit = 1
DrumEngine.loaded = false

-- Check if a sample file exists, try common naming variations
local function find_sample(base_path, filename)
  local full = _path.dust .. base_path .. filename
  if util.file_exists(full) then return full end
  -- Try lowercase
  full = _path.dust .. base_path .. filename:lower()
  if util.file_exists(full) then return full end
  return nil
end

-- Initialize engine settings for all slots
function DrumEngine.init()
  for _, slot_id in pairs(DrumEngine.SLOTS) do
    engine.playMode(slot_id, 3)  -- one-shot
    engine.ampAttack(slot_id, 0)
    engine.ampDecay(slot_id, 0.5)
    engine.ampSustain(slot_id, 0)
    engine.ampRelease(slot_id, 0.1)
  end
  DrumEngine.load_kit(1)
end

-- Load a kit by index
function DrumEngine.load_kit(kit_idx)
  kit_idx = util.clamp(kit_idx, 1, #DrumEngine.KITS)
  local kit = DrumEngine.KITS[kit_idx]
  DrumEngine.current_kit = kit_idx

  for role, slot_id in pairs(DrumEngine.SLOTS) do
    local filename = kit.samples[role]
    if filename then
      local path = find_sample(kit.path, filename)
      if path then
        engine.loadSample(slot_id, path)
        print("Drum loaded: " .. role .. " = " .. path)
      else
        print("Drum sample not found: " .. kit.path .. filename)
      end
    end
  end

  DrumEngine.loaded = true
  print("Drum kit loaded: " .. kit.name)
end

-- Trigger a drum hit
-- role: "kick", "snare", "hat", "tom"
-- vel: 0-127
function DrumEngine.trigger(role, vel)
  local slot_id = DrumEngine.SLOTS[role]
  if slot_id == nil then return end
  local amp = vel / 127
  engine.amp(slot_id, amp)
  engine.noteOn(slot_id, MusicUtil.note_num_to_freq(60), vel / 127, slot_id)
end

-- Stop a drum voice
function DrumEngine.release(role)
  local slot_id = DrumEngine.SLOTS[role]
  if slot_id then
    engine.noteOff(slot_id)
  end
end

function DrumEngine.kit_name(idx)
  idx = idx or DrumEngine.current_kit
  local kit = DrumEngine.KITS[idx]
  return kit and kit.name or "?"
end

function DrumEngine.num_kits()
  return #DrumEngine.KITS
end

return DrumEngine
