-- band.lua: Band (track) data structure and management

local Band = {}

-- Role types
Band.ROLES = { "bass", "chord", "lead", "kick", "snare", "hat", "tom" }
Band.ROLE_SHORT = { bass="B", chord="C", lead="L", kick="K", snare="S", hat="H", tom="T" }
Band.ROLE_COLORS = { bass=12, chord=15, lead=10, kick=6, snare=5, hat=4, tom=3 }

Band.ARP_MODES = { "off", "up", "down", "updn", "rand" }
Band.ARP_RATES = { 1, 2, 3, 4, 6, 8 }  -- in 16th notes (1=16th, 2=8th, 4=quarter, etc.)

-- Default drum MIDI notes (Digitakt defaults)
Band.DRUM_NOTES = { kick = 36, snare = 38, hat = 42, tom = 45 }

-- Create a new band
function Band.new(id, role, channel)
  local is_drum = (role == "kick" or role == "snare" or role == "hat" or role == "tom")
  return {
    id = id,              -- display name: "B", "C1", "C2", "L1", etc.
    role = role,          -- "bass", "chord", "lead", "kick", "snare", "hat", "tom"
    channel = channel,    -- MIDI channel
    is_drum = is_drum,

    -- Volume / state
    velocity = 0,         -- start silent, faders bring voices in
    muted = false,
    octave = is_drum and 0 or (role == "bass" and -1 or 0),

    -- Chord-specific
    chord_type = role == "chord" and 1 or 1,  -- index into Chords.TYPES (1=maj)
    degree = 1,           -- scale degree (1-7)

    -- Melody/bass-specific
    melody_pattern = 1,   -- index into Melody patterns
    phrase = {},           -- generated note sequence
    phrase_pos = 0,        -- position in phrase

    -- Arp
    arp_mode = role == "chord" and 2 or 1,  -- 1=off, 2=up (chords default to arp)
    arp_rate = 2,         -- index into ARP_RATES (2 = 8th notes)
    arp_pos = 0,

    -- Rhythm (16-step: 1=play, 0=rest)
    rhythm = is_drum and nil or Band._default_rhythm(role),

    -- Program change
    program = 0,          -- MIDI program (0-127), -1 = don't send

    -- Drum kit (shared across all drum bands)
    drum_kit = 1,         -- index into Drummer.KITS

    -- Output mode: "midi", "nb", "internal" (drums default)
    output = is_drum and "internal" or "midi",

    -- State
    sounding = {},        -- array of currently sounding MIDI notes
    nb_sounding = {},     -- notes currently sounding via nb
    flash = 0,            -- visual flash counter
  }
end

function Band._default_rhythm(role)
  if role == "bass" then
    return {1,0,1,0, 1,0,1,0, 1,0,1,0, 1,0,1,0}  -- 8th notes
  elseif role == "chord" then
    return {1,0,0,0, 1,0,0,0, 1,0,0,0, 1,0,0,0}  -- quarter notes
  elseif role == "lead" then
    return {1,0,1,0, 1,0,1,0, 1,0,1,0, 1,0,1,0}  -- 8th notes
  end
  return {1,0,0,0, 1,0,0,0, 1,0,0,0, 1,0,0,0}
end

-- Create the default italo setup
function Band.default_set()
  return {
    Band.new("B",  "bass",  2),   -- Mother 32
    Band.new("C1", "chord", 4),   -- OB-6
    Band.new("C2", "chord", 11),  -- PRO-800
    Band.new("L1", "lead",  10),  -- MS-101
    Band.new("L2", "lead",  3),   -- Pro 3
    Band.new("K",  "kick",  15),  -- Digitakt
    Band.new("S",  "snare", 15),
    Band.new("H",  "hat",   15),
    Band.new("T",  "tom",   15),
  }
end

-- Send note-on for given notes, track in sounding
function Band.trigger(band, midi_out, notes, vel)
  if not midi_out or band.muted then return end
  vel = vel or band.velocity
  if vel < 1 then return end
  for _, n in ipairs(notes) do
    if n > 0 and n <= 127 then
      midi_out:note_on(n, vel, band.channel)
      band.sounding[#band.sounding + 1] = n
    end
  end
  band.flash = 4
end

-- Release all sounding notes
function Band.release(band, midi_out)
  if not midi_out then return end
  for _, n in ipairs(band.sounding) do
    midi_out:note_off(n, 0, band.channel)
  end
  band.sounding = {}
end

-- Retrigger: release then trigger
function Band.retrigger(band, midi_out, notes, vel)
  Band.release(band, midi_out)
  Band.trigger(band, midi_out, notes, vel)
end

-- Send program change
function Band.send_pc(band, midi_out)
  if not midi_out or band.program < 0 then return end
  midi_out:program_change(band.program, band.channel)
end

-- Check if role is melodic
function Band.is_melodic(role)
  return role == "bass" or role == "chord" or role == "lead"
end

-- All notes off on a band's channel
function Band.panic(band, midi_out)
  if midi_out then
    midi_out:cc(123, 0, band.channel)
  end
  band.sounding = {}
end

return Band
