-- ITALO SINES
-- Instant gratification italo disco song maker
-- MIDI sequencer for hardware synths via norns
--
-- E1: page | E2: select | E3: edit
-- K2: play/stop | K3: cycle edit field
--
-- Default synth map:
--   B  bass    ch 2  Mother 32
--   C1 chord   ch 4  OB-6
--   C2 chord   ch 11 PRO-800
--   L1 lead    ch 10 MS-101
--   L2 lead    ch 3  Pro 3
--   K  kick    ch 15 Digitakt
--   S  snare   ch 15
--   H  hat     ch 15
--   T  tom     ch 15
--
-- v0.2 @clf

engine.name = "Timber"

local MusicUtil = require "musicutil"
local Band = include("italo-sines/lib/band")
local Chords = include("italo-sines/lib/chords")
local Melody = include("italo-sines/lib/melody")
local Drummer = include("italo-sines/lib/drummer")
local DrumEngine = include("italo-sines/lib/drum_engine")
local Progressions = include("italo-sines/lib/progressions")
local MidiMix = include("italo-sines/lib/midimix")

local drum_output = "internal"  -- "internal" = Timber engine, "midi" = MIDI out

-- ===== CONSTANTS =====

local PAGES = {"PLAY", "BANDS", "PROG", "CONFIG"}
local NOTE_NAMES = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
local NUMERALS = {"I", "ii", "iii", "IV", "V", "vi", "vii"}

-- ===== STATE =====

local bands = {}           -- array of band tables
local midi_out = nil
local mm = nil             -- MIDIMIX

-- Playback
-- playing is no longer used -- clock always runs, prog.active controls progression
local sixteenth = 0        -- current 16th note counter (1-based within bar)
local beat_count = 0       -- total beats elapsed
-- Faders always gate voices in/out (like midi-sines).
-- Bass plays patterns, chords arp, drums hit -- all clock-driven.
-- Progression is separate from transport: toggle independently.

-- Progression
local prog = {
  idx = 1,                 -- preset index
  steps = {1, 7, 6, 5},   -- current degree sequence
  position = 1,            -- current step (1-based)
  beats_per_step = 4,
  active = false,          -- progression on/off (separate from play/stop)
}

-- Scale
local key_idx = 1          -- 1=C ... 12=B
local key_octave = 2       -- base octave
local scale_idx = 1        -- MusicUtil scale index
local scale_notes = {}

-- UI
local page = 1
local cursor = 1           -- selected band
local edit_field = 1       -- which field is being edited
local prog_cursor = 1      -- cursor on PROG page
local flash = {}           -- per-band visual flash
local adding_band = false  -- "+Band" mode
local last_touched = nil   -- {band_idx, param, value, time} from MIDIMIX

-- ===== SCALE =====

local function build_scale()
  local root = (key_idx - 1) + (key_octave * 12)
  local name = MusicUtil.SCALES[scale_idx].name
  scale_notes = MusicUtil.generate_scale_of_length(root, name, 64)
end

local function key_name()
  return NOTE_NAMES[key_idx] .. tostring(key_octave)
end

-- ===== CHORD / PHRASE GENERATION =====

local function get_chord_root_degree()
  if prog.active then
    return prog.steps[prog.position] or 1
  end
  return 1  -- stay on root when progression is off
end

-- Get scale note for a degree at an octave
local function degree_to_note(degree, octave)
  local idx = degree + (octave or 0) * 7
  idx = math.max(1, math.min(#scale_notes, idx))
  return scale_notes[idx]
end

-- Build chord notes for a band
local function build_chord(b)
  local root_deg = get_chord_root_degree()
  -- Combine chord root degree with band's own degree offset
  local combined = root_deg + (b.degree - 1)
  local root_note = degree_to_note(combined, b.octave + 3) -- +3 to center in range
  return Chords.build(root_note, b.chord_type, 0)
end

-- Generate phrase for a melodic band
local function generate_phrase(b)
  local root_deg = get_chord_root_degree()
  local combined = root_deg + (b.degree - 1)
  local root_note = degree_to_note(combined, b.octave + 3)
  local chord_notes = Chords.build(root_note, 1, 0)  -- maj triad for reference

  if b.role == "bass" then
    b.phrase = Melody.generate_bass(scale_notes, chord_notes, b.melody_pattern, 8)
  else
    b.phrase = Melody.generate_lead(scale_notes, chord_notes, b.melody_pattern, 8, 0)
  end
  b.phrase_pos = 0
end

-- Regenerate all phrases (on chord change)
local function regenerate_all()
  for _, b in ipairs(bands) do
    if b.role == "chord" then
      -- Chord notes will be rebuilt on next trigger
    elseif b.role == "bass" or b.role == "lead" then
      generate_phrase(b)
    end
  end
end


-- ===== CLOCK =====

local function advance_progression()
  if not prog.active then return end
  prog.position = (prog.position % #prog.steps) + 1
  regenerate_all()
end

local function tick_band(b, step)
  if b.muted or b.velocity < 1 then return end

  if b.is_drum then
    local vel = Drummer.get_vel(b.drum_kit, b.role, step)
    if vel > 0 then
      local combined_vel = math.floor(vel * b.velocity / 127)
      if drum_output == "internal" then
        DrumEngine.trigger(b.role, combined_vel)
        b.flash = 4
      else
        local note = Band.DRUM_NOTES[b.role] or 36
        Band.retrigger(b, midi_out, {note}, combined_vel)
      end
    end
    return
  end

  if b.role == "chord" then
    local arp_rate = Band.ARP_RATES[b.arp_rate] or 2
    if b.arp_mode > 1 then
      -- Arpeggiated chord
      if (step - 1) % arp_rate == 0 then
        local chord_notes = build_chord(b)
        local mode_name = Band.ARP_MODES[b.arp_mode] or "up"
        local note = Chords.arp_note(chord_notes, b.arp_pos, mode_name, 2)
        if note then
          Band.retrigger(b, midi_out, {note}, b.velocity)
          b.arp_pos = b.arp_pos + 1
        end
      end
    else
      -- Full chord on rhythm hits
      local rhythm = b.rhythm or {1,0,0,0, 1,0,0,0, 1,0,0,0, 1,0,0,0}
      local idx = ((step - 1) % #rhythm) + 1
      if rhythm[idx] == 1 then
        local chord_notes = build_chord(b)
        Band.retrigger(b, midi_out, chord_notes, b.velocity)
      end
    end
    return
  end

  if b.role == "bass" or b.role == "lead" then
    local arp_rate = Band.ARP_RATES[b.arp_rate] or 2

    if b.arp_mode > 1 then
      -- Arp mode
      if (step - 1) % arp_rate == 0 then
        if #b.phrase > 0 then
          local mode_name = Band.ARP_MODES[b.arp_mode] or "up"
          local note = Chords.arp_note(b.phrase, b.arp_pos, mode_name, 2)
          if note then
            Band.retrigger(b, midi_out, {note}, b.velocity)
            b.arp_pos = b.arp_pos + 1
          end
        end
      end
    else
      -- Play through phrase on rhythm hits
      local rhythm = b.rhythm or {1,0,1,0, 1,0,1,0, 1,0,1,0, 1,0,1,0}
      local idx = ((step - 1) % #rhythm) + 1
      if rhythm[idx] == 1 then
        if #b.phrase > 0 then
          b.phrase_pos = (b.phrase_pos % #b.phrase) + 1
          local note = b.phrase[b.phrase_pos]
          if note and note > 0 then
            Band.retrigger(b, midi_out, {note}, b.velocity)
          else
            Band.release(b, midi_out)
          end
        end
      end
    end
    return
  end
end

local function release_short_notes()
  -- Release notes after half their duration (for staccato feel)
  for _, b in ipairs(bands) do
    if #b.sounding > 0 and not b.is_drum then
      -- Will be released on next retrigger
    end
    if b.is_drum and #b.sounding > 0 then
      Band.release(b, midi_out)
    end
  end
end

local function start_clock()
  clock.run(function()
    while true do
      clock.sync(1/4)  -- 16th notes

      sixteenth = sixteenth + 1
      local step = ((sixteenth - 1) % 16) + 1

      -- Clock always runs (free-running, like midi-sines)
      -- Tick all bands
      for _, b in ipairs(bands) do
        tick_band(b, step)
      end

      -- Release drum MIDI notes after a short time (internal drums are one-shot)
      if drum_output == "midi" then
        clock.run(function()
          clock.sleep(0.05)
          for _, b in ipairs(bands) do
            if b.is_drum then Band.release(b, midi_out) end
          end
        end)
      end

      -- Advance progression on beat boundaries (only when active)
      if step == 1 then
        beat_count = beat_count + 1
      end
      if prog.active and (sixteenth - 1) % (prog.beats_per_step * 4) == 0 and sixteenth > 1 then
        advance_progression()
      end

      -- Decay flash counters
      for i, b in ipairs(bands) do
        if b.flash > 0 then b.flash = b.flash - 1 end
      end
    end
  end)
end

local function all_off()
  for _, b in ipairs(bands) do
    Band.release(b, midi_out)
    Band.panic(b, midi_out)
  end
end

local function start_progression()
  prog.active = true
  prog.position = 1
  sixteenth = 0
  beat_count = 0
  regenerate_all()
end

local function stop_progression()
  prog.active = false
  prog.position = 1
  regenerate_all()  -- snap back to root
end

local function toggle_progression()
  if prog.active then stop_progression() else start_progression() end
end

-- ===== INIT =====

function init()
  -- Create default bands
  bands = Band.default_set()

  -- Load first progression
  local p = Progressions.get(prog.idx)
  prog.steps = {table.unpack(p.steps)}

  -- Build scale (A minor = classic italo)
  key_idx = 10    -- A
  key_octave = 2
  scale_idx = 1   -- Major (progression handles minor feel via degrees)
  -- Actually use Natural Minor for italo
  for i = 1, #MusicUtil.SCALES do
    if MusicUtil.SCALES[i].name == "Natural Minor" then
      scale_idx = i
      break
    end
  end
  build_scale()

  -- ===== PARAMS =====
  params:add_separator("italo_header", "ITALO SINES")

  params:add_number("midi_device", "MIDI Device", 1, 16, 1)
  params:set_action("midi_device", function(val)
    midi_out = midi.connect(val)
  end)

  params:add_number("midimix_device", "MIDIMIX Device", 1, 16, 2)
  params:set_action("midimix_device", function(val)
    mm:connect(val)
  end)

  params:add_option("drum_output", "Drum Output", {"Internal", "MIDI"}, 1)
  params:set_action("drum_output", function(val)
    drum_output = val == 1 and "internal" or "midi"
  end)

  -- Internal drum kit names
  local kit_names = {}
  for i = 1, DrumEngine.num_kits() do
    kit_names[i] = DrumEngine.kit_name(i)
  end
  params:add_option("internal_drum_kit", "Drum Kit", kit_names, 1)
  params:set_action("internal_drum_kit", function(val)
    DrumEngine.load_kit(val)
  end)

  params:add_option("key", "Key", NOTE_NAMES, key_idx)
  params:set_action("key", function(val)
    key_idx = val
    build_scale()
    regenerate_all()
  end)

  params:add_option("scale", "Scale",
    (function()
      local names = {}
      for i = 1, #MusicUtil.SCALES do names[i] = MusicUtil.SCALES[i].name end
      return names
    end)(), scale_idx)
  params:set_action("scale", function(val)
    scale_idx = val
    build_scale()
    regenerate_all()
  end)

  params:add_number("drum_kit", "Drum Kit", 1, Drummer.num_kits(), 1)
  params:set_action("drum_kit", function(val)
    for _, b in ipairs(bands) do
      if b.is_drum then b.drum_kit = val end
    end
  end)

  -- Drum FX
  params:add_separator("drum_fx_header", "DRUM FX")

  params:add_control("drum_pitch", "Drum Pitch", controlspec.new(-24, 24, 'lin', 1, 0, 'st'))
  params:set_action("drum_pitch", function(val)
    -- Convert semitones to ratio
    DrumEngine.set_pitch(math.pow(2, val / 12))
  end)

  params:add_control("drum_filter", "Drum Filter", controlspec.new(60, 20000, 'exp', 0, 20000, 'Hz'))
  params:set_action("drum_filter", function(val)
    DrumEngine.set_filter_freq(val)
  end)

  params:add_control("drum_reso", "Drum Resonance", controlspec.new(0, 1, 'lin', 0.01, 0.1))
  params:set_action("drum_reso", function(val)
    DrumEngine.set_filter_reso(val)
  end)

  params:add_option("drum_filter_type", "Filter Type", {"LP", "HP", "BP"}, 1)
  params:set_action("drum_filter_type", function(val)
    DrumEngine.set_filter_type(val - 1)
  end)

  -- Reverb (norns built-in)
  params:add_separator("reverb_header", "REVERB")

  params:add_control("reverb_level", "Reverb Level", controlspec.new(0, 1, 'lin', 0.01, 0.3))
  params:set_action("reverb_level", function(val)
    audio.level_eng_rev(val)
  end)

  params:add_control("reverb_time", "Reverb Time", controlspec.new(0.1, 15, 'exp', 0.1, 3, 's'))
  params:set_action("reverb_time", function(val)
    audio.rev_param("t60", val)
  end)

  params:add_control("reverb_damp", "Reverb Damp", controlspec.new(500, 16000, 'exp', 0, 4000, 'Hz'))
  params:set_action("reverb_damp", function(val)
    audio.rev_param("damp", val)
  end)

  -- ===== MIDIMIX =====
  mm = MidiMix.new()

  mm.on_volume = function(bi, val)
    if bands[bi] then
      bands[bi].velocity = val
      last_touched = {idx = bi, val = val}
      -- Also send CC 7 (volume) so synths that ignore velocity still respond
      if midi_out then
        midi_out:cc(7, val, bands[bi].channel)
      end
      mm:update_leds(bands)
    end
  end

  mm.on_degree = function(bi, val)
    if not bands[bi] then return end
    local b = bands[bi]
    if b.is_drum and drum_output == "internal" then
      -- Knob 1 for drums = pitch (-24 to +24 semitones)
      local st = math.floor(val / 127 * 48) - 24
      DrumEngine.set_pitch(math.pow(2, st / 12))
      params:set("drum_pitch", st, true)
    elseif b.role == "bass" then
      -- Knob 1 for bass = octave (-5 to +5)
      b.octave = math.floor(val / 128 * 11) - 5
      generate_phrase(b)
    elseif Band.is_melodic(b.role) then
      -- Knob 1 for chord/lead = degree
      b.degree = math.floor(val / 128 * 7) + 1
      if b.role == "lead" then generate_phrase(b) end
    end
  end

  mm.on_knob2 = function(bi, val)
    if not bands[bi] then return end
    local b = bands[bi]
    if b.is_drum and drum_output == "internal" then
      -- Drum bands: cycle internal sample kit (808/909/606)
      local ikit = math.floor(val / 128 * DrumEngine.num_kits()) + 1
      DrumEngine.load_kit(ikit)
      params:set("internal_drum_kit", ikit, true)
    elseif b.is_drum then
      -- MIDI drums: cycle drum pattern kit
      local kit = math.floor(val / 128 * Drummer.num_kits()) + 1
      for _, db in ipairs(bands) do
        if db.is_drum then db.drum_kit = kit end
      end
      params:set("drum_kit", kit, true)
    else
      -- Melodic bands: Program Change (0-127)
      b.program = math.floor(val / 128 * 128)
      Band.send_pc(b, midi_out)
    end
  end

  mm.on_arp_rate = function(bi, val)
    if not bands[bi] then return end
    local b = bands[bi]
    if b.is_drum and drum_output == "internal" then
      -- Knob 3 for drums = filter cutoff (log scale 60Hz-20kHz)
      local freq = 60 * math.pow(20000/60, val/127)
      if val == 127 then freq = 20000 end
      DrumEngine.set_filter_freq(freq)
      params:set("drum_filter", freq, true)
    else
      b.arp_rate = math.floor(val / 128 * #Band.ARP_RATES) + 1
    end
  end

  mm.on_mute = function(bi)
    if bands[bi] then
      bands[bi].muted = not bands[bi].muted
      if bands[bi].muted then Band.release(bands[bi], midi_out) end
      mm:update_leds(bands)
    end
  end

  mm.on_arp_cycle = function(bi)
    if bands[bi] then
      local b = bands[bi]
      b.arp_mode = (b.arp_mode % #Band.ARP_MODES) + 1
    end
  end

  mm.on_bpm = function(val)
    local bpm = math.floor(val / 127 * 180) + 80  -- 80-260 BPM
    params:set("clock_tempo", bpm)
  end

  mm.on_panic = function() all_off() end

  mm.on_bank_left = function()
    mm.bank = math.max(0, mm.bank - 1)
    mm:update_leds(bands)
  end

  mm.on_bank_right = function()
    local max_bank = math.floor((#bands - 1) / 8)
    mm.bank = math.min(max_bank, mm.bank + 1)
    mm:update_leds(bands)
  end

  mm.on_play_stop = function()
    toggle_progression()
  end

  -- Auto-detect MIDI devices
  for i = 1, 16 do
    local dev = midi.connect(i)
    if dev and dev.name and dev.name ~= "none" and dev.name ~= "" then
      if dev.name:find("MIDIMIX") or dev.name:find("MIDI Mix") then
        params:set("midimix_device", i)
      else
        if not midi_out then
          params:set("midi_device", i)
        end
      end
    end
  end

  -- Set BPM
  params:set("clock_tempo", 120)

  -- Initialize internal drum engine (Timber)
  DrumEngine.init()

  -- Send PC 0 (init patch) to all melodic bands on startup
  for _, b in ipairs(bands) do
    if not b.is_drum then
      Band.send_pc(b, midi_out)
    end
  end

  -- Generate initial phrases
  regenerate_all()

  -- Start clock (always running -- faders bring voices in/out)
  start_clock()
  -- Progression starts OFF. K2 to start it.

  -- Redraw clock
  clock.run(function()
    while true do
      clock.sleep(1/15)
      redraw()
    end
  end)
end

-- ===== CONTROLS =====

function enc(n, d)
  if page == 1 then
    -- PLAY page
    if n == 1 then
      page = util.clamp(page + d, 1, #PAGES)
    elseif n == 2 then
      cursor = util.clamp(cursor + d, 1, #bands)
    elseif n == 3 then
      -- Quick velocity adjust
      local b = bands[cursor]
      if b then
        b.velocity = util.clamp(b.velocity + d * 4, 0, 127)
        if midi_out then midi_out:cc(7, b.velocity, b.channel) end
      end
    end

  elseif page == 2 then
    -- BANDS page
    if n == 1 then
      page = util.clamp(page + d, 1, #PAGES)
    elseif n == 2 then
      cursor = util.clamp(cursor + d, 1, #bands + 1)  -- +1 for "+Band"
    elseif n == 3 then
      if cursor <= #bands then
        local b = bands[cursor]
        if edit_field == 1 then
          -- Volume
          b.velocity = util.clamp(b.velocity + d * 4, 0, 127)
        elseif edit_field == 2 then
          -- Channel
          b.channel = util.clamp(b.channel + d, 1, 16)
          Band.send_pc(b, midi_out)
        elseif edit_field == 3 then
          -- Octave
          b.octave = util.clamp(b.octave + d, -5, 5)
          if b.role == "bass" or b.role == "lead" then generate_phrase(b) end
        elseif edit_field == 4 then
          if b.role == "chord" then
            -- Chord type
            b.chord_type = util.clamp(b.chord_type + d, 1, #Chords.TYPES)
          elseif b.role == "bass" then
            b.melody_pattern = util.clamp(b.melody_pattern + d, 1, #Melody.BASS_PATTERNS)
            generate_phrase(b)
          elseif b.role == "lead" then
            b.melody_pattern = util.clamp(b.melody_pattern + d, 1, #Melody.PATTERNS)
            generate_phrase(b)
          elseif b.is_drum then
            b.drum_kit = util.clamp(b.drum_kit + d, 1, Drummer.num_kits())
            params:set("drum_kit", b.drum_kit, true)
          end
        elseif edit_field == 5 then
          if b.is_drum then
            -- Program change (drums)
            b.program = util.clamp(b.program + d, -1, 127)
            Band.send_pc(b, midi_out)
          else
            -- Arp mode
            b.arp_mode = util.clamp(b.arp_mode + d, 1, #Band.ARP_MODES)
          end
        elseif edit_field == 6 then
          -- Arp rate
          b.arp_rate = util.clamp(b.arp_rate + d, 1, #Band.ARP_RATES)
        elseif edit_field == 7 then
          -- Degree
          b.degree = util.clamp(b.degree + d, 1, 7)
          if b.role == "bass" or b.role == "lead" then generate_phrase(b) end
        elseif edit_field == 8 then
          -- Program change (melodic)
          b.program = util.clamp(b.program + d, -1, 127)
          Band.send_pc(b, midi_out)
        end
      end
    end

  elseif page == 3 then
    -- PROG page
    if n == 1 then
      page = util.clamp(page + d, 1, #PAGES)
    elseif n == 2 then
      prog_cursor = util.clamp(prog_cursor + d, 1, 5)
    elseif n == 3 then
      if prog_cursor == 1 then
        -- Preset
        prog.idx = util.clamp(prog.idx + d, 1, Progressions.count())
        local p = Progressions.get(prog.idx)
        prog.steps = {table.unpack(p.steps)}
        regenerate_all()
      elseif prog_cursor == 2 then
        -- BPM
        local bpm = params:get("clock_tempo")
        params:set("clock_tempo", util.clamp(bpm + d, 60, 300))
      elseif prog_cursor == 3 then
        -- Beats per step
        prog.beats_per_step = util.clamp(prog.beats_per_step + d, 1, 16)
      elseif prog_cursor == 4 then
        -- Key
        local new_key = key_idx + d
        local new_oct = key_octave
        while new_key > 12 do new_key = new_key - 12; new_oct = new_oct + 1 end
        while new_key < 1 do new_key = new_key + 12; new_oct = new_oct - 1 end
        key_idx = new_key
        key_octave = util.clamp(new_oct, 0, 6)
        params:set("key", key_idx, true)
        build_scale()
        regenerate_all()
      elseif prog_cursor == 5 then
        -- Scale
        scale_idx = util.clamp(scale_idx + d, 1, #MusicUtil.SCALES)
        params:set("scale", scale_idx, true)
        build_scale()
        regenerate_all()
      end
    end

  elseif page == 4 then
    -- CONFIG page
    if n == 1 then
      page = util.clamp(page + d, 1, #PAGES)
    elseif n == 2 then
      cursor = util.clamp(cursor + d, 1, #bands)
    elseif n == 3 then
      local b = bands[cursor]
      if b then
        b.channel = util.clamp(b.channel + d, 1, 16)
      end
    end
  end
end

function key(n, z)
  if z == 0 then return end

  if n == 1 then
    -- K1 held state handled elsewhere if needed
    return
  end

  if page == 1 then
    if n == 2 then
      toggle_progression()
    elseif n == 3 then
      -- Mute/unmute selected band
      if bands[cursor] then
        bands[cursor].muted = not bands[cursor].muted
        if bands[cursor].muted then Band.release(bands[cursor], midi_out) end
        mm:update_leds(bands)
      end
    end

  elseif page == 2 then
    if n == 2 then
      if cursor == #bands + 1 then
        -- Add new band
        local new_id = "X" .. #bands
        local new_band = Band.new(new_id, "chord", 1)
        table.insert(bands, new_band)
        generate_phrase(new_band)
      else
        -- Remove selected band
        if #bands > 1 then
          Band.release(bands[cursor], midi_out)
          Band.panic(bands[cursor], midi_out)
          table.remove(bands, cursor)
          cursor = util.clamp(cursor, 1, #bands)
        end
      end
    elseif n == 3 then
      -- Cycle edit field
      local max_fields = 8
      if bands[cursor] and bands[cursor].is_drum then max_fields = 5 end
      edit_field = (edit_field % max_fields) + 1
    end

  elseif page == 3 then
    if n == 2 then
      toggle_progression()
    elseif n == 3 then
      -- Random progression
      prog.idx = math.random(1, Progressions.count())
      local p = Progressions.get(prog.idx)
      prog.steps = {table.unpack(p.steps)}
      regenerate_all()
    end

  elseif page == 4 then
    if n == 2 then
      -- Cycle role for selected band
      if bands[cursor] then
        local b = bands[cursor]
        local ri = 1
        for i, r in ipairs(Band.ROLES) do
          if r == b.role then ri = i; break end
        end
        ri = (ri % #Band.ROLES) + 1
        local new_role = Band.ROLES[ri]
        Band.release(b, midi_out)
        b.role = new_role
        b.is_drum = (new_role == "kick" or new_role == "snare" or new_role == "hat" or new_role == "tom")
        if not b.is_drum then
          b.rhythm = Band._default_rhythm(new_role)
          generate_phrase(b)
        end
      end
    end
  end
end

-- ===== DRAWING =====

function redraw()
  screen.clear()
  screen.aa(0)
  screen.font_face(1)
  screen.font_size(8)

  -- Page header
  screen.level(15)
  screen.move(0, 7)
  screen.text(PAGES[page])

  -- Page dots
  for i = 1, #PAGES do
    screen.level(i == page and 15 or 3)
    screen.rect(128 - (#PAGES - i + 1) * 6, 2, 3, 3)
    screen.fill()
  end

  if page == 1 then draw_play()
  elseif page == 2 then draw_bands()
  elseif page == 3 then draw_prog()
  elseif page == 4 then draw_config()
  end

  screen.update()
end

function draw_play()
  -- Current chord + key info
  local deg = get_chord_root_degree()
  local numeral = NUMERALS[deg] or tostring(deg)
  local bpm = math.floor(params:get("clock_tempo"))
  screen.level(8)
  screen.move(40, 7)
  screen.text(key_name() .. " " .. numeral .. " " .. bpm .. "bpm")

  -- Playing indicator
  screen.level(prog.active and 15 or 3)
  screen.move(120, 7)
  screen.text(prog.active and "PROG" or "I")

  -- Band columns
  local num = #bands
  local col_w = math.floor(124 / math.max(num, 1))
  col_w = math.min(col_w, 14)

  for i, b in ipairs(bands) do
    local x = (i - 1) * col_w + 2
    local selected = (i == cursor)

    -- Activity bar (height = velocity, brightens on trigger)
    local bar_h = 0
    if not b.muted and b.velocity > 0 then
      bar_h = math.floor(b.velocity / 127 * 38)
    end

    if bar_h > 0 then
      local color = Band.ROLE_COLORS[b.role] or 5
      local bright = b.flash > 0 and 15 or color
      screen.level(bright)
      screen.rect(x, 52 - bar_h, col_w - 2, bar_h)
      screen.fill()
    end

    -- Band label
    screen.level(selected and 15 or (b.muted and 2 or 8))
    screen.move(x + 1, 60)
    screen.text(b.id)

    -- Mute indicator
    if b.muted then
      screen.level(2)
      screen.move(x, 12)
      screen.text("x")
    end

    -- Selection bracket
    if selected then
      screen.level(15)
      screen.rect(x - 1, 10, col_w, 1)
      screen.fill()
    end
  end

  -- Bottom: show last-touched MIDIMIX fader, or selected band
  screen.level(5)
  screen.move(0, 64)
  if last_touched and bands[last_touched.idx] then
    local b = bands[last_touched.idx]
    screen.level(12)
    screen.text(b.id .. " vel:" .. last_touched.val)
  elseif bands[cursor] then
    local b = bands[cursor]
    screen.text(b.id .. " vel:" .. b.velocity)
  end
end

function draw_bands()
  if cursor > #bands then
    -- "+Band" selected
    screen.level(15)
    screen.move(40, 35)
    screen.text("+ ADD BAND")
    screen.level(5)
    screen.move(20, 48)
    screen.text("K2 to add / K3 n/a")
    return
  end

  local b = bands[cursor]
  local fields = {}

  local pc_str = b.program < 0 and "off" or tostring(b.program)

  if b.is_drum then
    fields = {
      {"vel",  tostring(b.velocity)},
      {"ch",   tostring(b.channel)},
      {"kit",  Drummer.kit_name(b.drum_kit)},
      {"role", b.role},
      {"PC",   pc_str},
    }
  else
    local pat_name
    if b.role == "chord" then
      pat_name = Chords.type_name(b.chord_type)
    elseif b.role == "bass" then
      pat_name = Melody.pattern_name(b.melody_pattern, true)
    else
      pat_name = Melody.pattern_name(b.melody_pattern, false)
    end

    fields = {
      {"vel",   tostring(b.velocity)},
      {"ch",    tostring(b.channel)},
      {"oct",   tostring(b.octave)},
      {"type",  pat_name},
      {"arp",   Band.ARP_MODES[b.arp_mode]},
      {"rate",  "1/" .. tostring(Band.ARP_RATES[b.arp_rate] * 4)},
      {"deg",   NUMERALS[b.degree] or tostring(b.degree)},
      {"PC",    pc_str},
    }
  end

  -- Band header
  screen.level(15)
  screen.move(0, 16)
  screen.text(b.id .. " [" .. b.role .. "] ch " .. b.channel)

  -- Navigate hint
  screen.level(3)
  screen.move(128, 16)
  screen.text_right(cursor .. "/" .. #bands)

  -- Fields
  for i, f in ipairs(fields) do
    local y = 24 + (i - 1) * 7
    if y > 60 then break end
    local selected = (edit_field == i)
    screen.level(selected and 15 or 5)
    screen.move(4, y)
    screen.text(f[1])
    screen.move(40, y)
    screen.text(f[2])
    if selected then
      screen.move(0, y)
      screen.text(">")
    end
  end

  -- Footer
  screen.level(3)
  screen.move(0, 64)
  screen.text("K2:remove  K3:field")
end

function draw_prog()
  local p = Progressions.get(prog.idx)
  local bpm = math.floor(params:get("clock_tempo"))
  local scale_name = MusicUtil.SCALES[scale_idx].name

  local fields = {
    {"Prog",  p.name .. " (" .. p.tag .. ")"},
    {"BPM",   tostring(bpm)},
    {"Beats", tostring(prog.beats_per_step)},
    {"Key",   key_name()},
    {"Scale", scale_name:sub(1, 16)},
  }

  for i, f in ipairs(fields) do
    local y = 14 + (i - 1) * 10
    local selected = (prog_cursor == i)
    screen.level(selected and 15 or 5)
    screen.move(0, y)
    screen.text(f[1])
    screen.move(40, y)
    screen.text(f[2])
    if selected then
      screen.move(128, y)
      screen.text_right("<")
    end
  end

  -- Current position indicator
  screen.level(15)
  screen.move(0, 62)
  for i, step in ipairs(prog.steps) do
    local num = NUMERALS[step] or tostring(step)
    if i == prog.position and prog.active then
      screen.level(15)
    else
      screen.level(5)
    end
    screen.text(num .. " ")
  end

  screen.level(3)
  screen.move(128, 62)
  screen.text_right("K2:" .. (prog.active and "stop" or "start") .. " K3:rnd")
end

function draw_config()
  screen.level(8)
  screen.move(0, 16)
  screen.text("Band   Role     Ch")

  for i = 1, math.min(#bands, 6) do
    local b = bands[i + (cursor > 6 and cursor - 6 or 0)]
    if not b then break end
    local y = 24 + (i - 1) * 7
    local bi = i + (cursor > 6 and cursor - 6 or 0)
    local selected = (bi == cursor)
    screen.level(selected and 15 or 5)
    screen.move(0, y)
    screen.text(b.id)
    screen.move(40, y)
    screen.text(b.role)
    screen.move(90, y)
    screen.text(tostring(b.channel))
    if selected then
      screen.move(128, y)
      screen.text_right("<")
    end
  end

  screen.level(3)
  screen.move(0, 64)
  screen.text("E3:ch  K2:role")
end

function cleanup()
  all_off()
end
