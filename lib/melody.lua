-- melody.lua: Melody/bass phrase generator
-- Creates short phrases that follow chord changes

local Melody = {}

-- Pattern types for leads
Melody.PATTERNS = {
  { name = "step up",    desc = "ascending scale run" },
  { name = "step dn",    desc = "descending scale run" },
  { name = "bounce",     desc = "chord tone bounce 1-3-5-3" },
  { name = "repeat",     desc = "repeated root with rhythm" },
  { name = "call/resp",  desc = "up phrase then answer" },
  { name = "octave",     desc = "octave jumps on chord tones" },
  { name = "zigzag",     desc = "alternating up-down steps" },
  { name = "hook",       desc = "catchy repeated motif" },
}

-- Pattern types for bass
Melody.BASS_PATTERNS = {
  { name = "pump",       desc = "root 8th notes" },
  { name = "root-5th",   desc = "alternating root and fifth" },
  { name = "octave",     desc = "root low-high alternation" },
  { name = "walk",       desc = "walking bass line" },
  { name = "synco",      desc = "syncopated root" },
  { name = "arp",        desc = "root-3rd-5th-octave" },
}

-- Find the closest scale note at or above a given MIDI note
local function closest_scale_note(scale_notes, target)
  local best = scale_notes[1]
  local best_dist = 999
  for _, n in ipairs(scale_notes) do
    local dist = math.abs(n - target)
    if dist < best_dist then
      best = n
      best_dist = dist
    end
  end
  return best
end

-- Find scale index for a given MIDI note
local function scale_index_of(scale_notes, midi_note)
  for i, n in ipairs(scale_notes) do
    if n >= midi_note then return i end
  end
  return #scale_notes
end

-- Generate a lead phrase (array of MIDI notes)
-- scale_notes: full scale array from MusicUtil
-- chord_notes: array of chord MIDI notes (from chords.build)
-- pattern_idx: which pattern
-- length: phrase length (default 8)
-- octave: base octave offset
function Melody.generate_lead(scale_notes, chord_notes, pattern_idx, length, octave)
  length = length or 8
  octave = octave or 0
  local root = chord_notes[1] or 60
  local root_idx = scale_index_of(scale_notes, root)
  local phrase = {}

  if pattern_idx == 1 then
    -- Step up: ascending from root
    for i = 0, length - 1 do
      local idx = math.min(root_idx + i, #scale_notes)
      phrase[#phrase + 1] = scale_notes[idx]
    end

  elseif pattern_idx == 2 then
    -- Step down: descending from root + octave
    local top_idx = math.min(root_idx + 7, #scale_notes)
    for i = 0, length - 1 do
      local idx = math.max(1, top_idx - i)
      phrase[#phrase + 1] = scale_notes[idx]
    end

  elseif pattern_idx == 3 then
    -- Bounce: chord tones 1-3-5-3-1-3-5-3
    local tones = {}
    for _, n in ipairs(chord_notes) do tones[#tones + 1] = n end
    if #tones < 3 then
      for i = 1, length do phrase[i] = root end
    else
      local bounce = {1, 2, 3, 2}
      for i = 1, length do
        local ti = bounce[((i - 1) % #bounce) + 1]
        phrase[i] = tones[math.min(ti, #tones)]
      end
    end

  elseif pattern_idx == 4 then
    -- Repeat: root with occasional neighbor
    for i = 1, length do
      if i == 3 or i == 7 then
        local idx = math.min(root_idx + 2, #scale_notes)
        phrase[i] = scale_notes[idx]
      elseif i == 5 then
        local idx = math.min(root_idx + 1, #scale_notes)
        phrase[i] = scale_notes[idx]
      else
        phrase[i] = root
      end
    end

  elseif pattern_idx == 5 then
    -- Call/response: up 4 then down 4
    local half = math.floor(length / 2)
    for i = 0, half - 1 do
      local idx = math.min(root_idx + i, #scale_notes)
      phrase[#phrase + 1] = scale_notes[idx]
    end
    for i = half - 1, 0, -1 do
      local idx = math.min(root_idx + i, #scale_notes)
      phrase[#phrase + 1] = scale_notes[idx]
    end

  elseif pattern_idx == 6 then
    -- Octave jumps on chord tones
    for i = 1, length do
      local tone = chord_notes[((i - 1) % #chord_notes) + 1] or root
      if i % 2 == 0 then tone = tone + 12 end
      phrase[i] = math.min(127, tone)
    end

  elseif pattern_idx == 7 then
    -- Zigzag: alternating steps up and back
    for i = 0, length - 1 do
      local step = math.floor(i / 2) + 1
      local idx
      if i % 2 == 0 then
        idx = math.min(root_idx + step, #scale_notes)
      else
        idx = math.max(1, root_idx + step - 2)
      end
      phrase[#phrase + 1] = scale_notes[idx]
    end

  elseif pattern_idx == 8 then
    -- Hook: short catchy motif repeated (e.g. 1-1-3-5 x2)
    local motif = {root}
    motif[2] = root
    local idx3 = math.min(root_idx + 2, #scale_notes)
    motif[3] = scale_notes[idx3]
    local idx5 = math.min(root_idx + 4, #scale_notes)
    motif[4] = scale_notes[idx5]
    for i = 1, length do
      phrase[i] = motif[((i - 1) % #motif) + 1]
    end

  else
    -- Fallback: just root
    for i = 1, length do phrase[i] = root end
  end

  return phrase
end

-- Generate a bass phrase
function Melody.generate_bass(scale_notes, chord_notes, pattern_idx, length)
  length = length or 8
  local root = chord_notes[1] or 48
  local root_idx = scale_index_of(scale_notes, root)
  local fifth = chord_notes[3] or root  -- 3rd element is the fifth in a triad
  local phrase = {}

  if pattern_idx == 1 then
    -- Pump: all root
    for i = 1, length do phrase[i] = root end

  elseif pattern_idx == 2 then
    -- Root-fifth alternation
    for i = 1, length do
      phrase[i] = (i % 2 == 1) and root or fifth
    end

  elseif pattern_idx == 3 then
    -- Octave: low-high
    local low = root
    local high = root + 12
    for i = 1, length do
      phrase[i] = (i % 2 == 1) and low or math.min(127, high)
    end

  elseif pattern_idx == 4 then
    -- Walking bass: root up through scale
    for i = 0, length - 1 do
      local idx = root_idx + (i % 5)
      idx = math.min(idx, #scale_notes)
      phrase[#phrase + 1] = scale_notes[idx]
    end

  elseif pattern_idx == 5 then
    -- Syncopated: root with rests (0 = rest)
    local pat = {1, 0, 1, 0, 0, 1, 1, 0}
    for i = 1, length do
      phrase[i] = pat[((i - 1) % #pat) + 1] == 1 and root or 0
    end

  elseif pattern_idx == 6 then
    -- Arp: root-3rd-5th-octave
    local notes = {root}
    if chord_notes[2] then notes[#notes + 1] = chord_notes[2] end
    if chord_notes[3] then notes[#notes + 1] = chord_notes[3] end
    notes[#notes + 1] = math.min(127, root + 12)
    for i = 1, length do
      phrase[i] = notes[((i - 1) % #notes) + 1]
    end

  else
    for i = 1, length do phrase[i] = root end
  end

  return phrase
end

function Melody.pattern_name(idx, is_bass)
  if is_bass then
    local p = Melody.BASS_PATTERNS[idx]
    return p and p.name or "?"
  else
    local p = Melody.PATTERNS[idx]
    return p and p.name or "?"
  end
end

return Melody
