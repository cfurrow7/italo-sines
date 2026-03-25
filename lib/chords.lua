-- chords.lua: Chord voicing engine
-- Builds multi-note chords from scale degrees + chord types

local MusicUtil = require "musicutil"

local Chords = {}

Chords.TYPES = {
  { name = "maj",  intervals = {0, 4, 7} },
  { name = "min",  intervals = {0, 3, 7} },
  { name = "7",    intervals = {0, 4, 7, 10} },
  { name = "maj7", intervals = {0, 4, 7, 11} },
  { name = "min7", intervals = {0, 3, 7, 10} },
  { name = "sus2", intervals = {0, 2, 7} },
  { name = "sus4", intervals = {0, 5, 7} },
  { name = "dim",  intervals = {0, 3, 6} },
  { name = "aug",  intervals = {0, 4, 8} },
}

-- Build chord from a MIDI root note + chord type index
-- Returns array of MIDI notes
function Chords.build(root_midi, chord_type_idx, octave_offset)
  local ct = Chords.TYPES[chord_type_idx] or Chords.TYPES[1]
  octave_offset = octave_offset or 0
  local notes = {}
  for _, interval in ipairs(ct.intervals) do
    local n = root_midi + interval + (octave_offset * 12)
    if n >= 0 and n <= 127 then
      table.insert(notes, n)
    end
  end
  return notes
end

-- Build chord from scale degree
-- scale_notes: array of MIDI notes from MusicUtil
-- degree: 1-7
-- chord_type_idx: index into TYPES
-- octave: octave offset
function Chords.from_degree(scale_notes, degree, chord_type_idx, octave)
  -- Find root note from scale at given degree
  -- Scale notes repeat every 7 degrees
  local idx = degree + (octave or 0) * 7
  idx = math.max(1, math.min(#scale_notes, idx))
  local root = scale_notes[idx]
  return Chords.build(root, chord_type_idx, 0)
end

-- Get a single arp note from a chord
-- chord_notes: array from build()
-- pos: arp position (0-based, wraps)
-- mode: "up", "down", "updn", "rand"
-- arp_octaves: how many octaves to span (default 2)
function Chords.arp_note(chord_notes, pos, mode, arp_octaves)
  if #chord_notes == 0 then return nil end
  arp_octaves = arp_octaves or 2

  -- Build the full arp sequence across octaves
  local seq = {}
  for oct = 0, arp_octaves - 1 do
    for _, n in ipairs(chord_notes) do
      table.insert(seq, n + oct * 12)
    end
  end

  local len = #seq
  if len == 0 then return nil end

  if mode == "down" then
    -- Reverse the sequence
    local rev = {}
    for i = len, 1, -1 do rev[#rev + 1] = seq[i] end
    seq = rev
  elseif mode == "updn" then
    -- Up then down (skip endpoints to avoid doubling)
    local updn = {}
    for i = 1, len do updn[#updn + 1] = seq[i] end
    for i = len - 1, 2, -1 do updn[#updn + 1] = seq[i] end
    seq = updn
    len = #seq
  elseif mode == "rand" then
    return seq[math.random(1, len)]
  end

  return seq[(pos % len) + 1]
end

-- Name of a chord type
function Chords.type_name(idx)
  local ct = Chords.TYPES[idx]
  return ct and ct.name or "?"
end

return Chords
