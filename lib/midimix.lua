-- midimix.lua: Akai MIDIMIX controller for italo-sines
-- Adapted for dynamic band count
--
-- Per channel (x8):
--   Fader: volume
--   Knob row 1: degree (melodic) / unused (drums)
--   Knob row 2: chord type (chord) / melody pattern (lead/bass) / drum kit (drums)
--   Knob row 3: arp rate
--   Mute: toggle mute (LED feedback)
--   Rec Arm: cycle arp mode
--
-- Global:
--   Master fader (CC 62): BPM
--   SEND ALL (note 27): panic
--   BANK LEFT (note 25): prev 8 bands
--   BANK RIGHT (note 26): next 8 bands
--   SOLO (note 28): play/stop

local MidiMix = {}
MidiMix.__index = MidiMix

-- MIDIMIX CC/note mapping (same hardware layout as midi-sines)
local FADER_CCS  = {19, 23, 27, 31, 49, 53, 57, 61}
local KNOB1_CCS  = {16, 20, 24, 28, 46, 50, 54, 58}
local KNOB2_CCS  = {17, 21, 25, 29, 47, 51, 55, 59}
local KNOB3_CCS  = {18, 22, 26, 30, 48, 52, 56, 60}
local MUTE_NOTES  = {1, 4, 7, 10, 13, 16, 19, 22}
local REC_NOTES   = {3, 6, 9, 12, 15, 18, 21, 24}
local MASTER_CC   = 62
local SEND_ALL_NOTE = 27
local BANK_LEFT_NOTE = 25
local BANK_RIGHT_NOTE = 26
local SOLO_NOTE = 28

function MidiMix.new()
  local self = setmetatable({}, MidiMix)
  self.midi = nil
  self.bank = 0  -- 0 = bands 1-8, 1 = bands 9-16, etc.

  -- Build reverse lookup maps
  self._fader_map = {}
  self._knob1_map = {}
  self._knob2_map = {}
  self._knob3_map = {}
  self._mute_map = {}
  self._rec_map = {}

  for i = 1, 8 do
    self._fader_map[FADER_CCS[i]] = i
    self._knob1_map[KNOB1_CCS[i]] = i
    self._knob2_map[KNOB2_CCS[i]] = i
    self._knob3_map[KNOB3_CCS[i]] = i
    self._mute_map[MUTE_NOTES[i]] = i
    self._rec_map[REC_NOTES[i]] = i
  end

  -- Callbacks (set by main script)
  self.on_volume = nil      -- (band_idx, val_0_127)
  self.on_degree = nil      -- (band_idx, val_0_127)
  self.on_knob2 = nil       -- (band_idx, val_0_127)
  self.on_arp_rate = nil    -- (band_idx, val_0_127)
  self.on_mute = nil        -- (band_idx)
  self.on_arp_cycle = nil   -- (band_idx)
  self.on_bpm = nil         -- (val_0_127)
  self.on_panic = nil       -- ()
  self.on_bank_left = nil   -- ()
  self.on_bank_right = nil  -- ()
  self.on_play_stop = nil   -- ()

  return self
end

function MidiMix:connect(device_num)
  self.midi = midi.connect(device_num)
  print("MIDIMIX connected to device " .. device_num .. " name: " .. (self.midi.name or "unknown"))
  self.midi.event = function(data)
    self:handle_event(data)
  end
  -- Start with all LEDs off
  self:all_leds_off()
end

function MidiMix:all_leds_off()
  if not self.midi then return end
  for slot = 1, 8 do
    self:set_mute_led(slot, false)
  end
end

function MidiMix:band_idx(slot)
  return self.bank * 8 + slot
end

function MidiMix:handle_event(data)
  local msg = midi.to_msg(data)

  if msg.type == "cc" then
    local cc = msg.cc
    local val = msg.val
    print("MIDIMIX CC: " .. cc .. " val: " .. val)

    -- Master fader
    if cc == MASTER_CC then
      if self.on_bpm then self.on_bpm(val) end
      return
    end

    -- Per-channel CCs
    local slot = self._fader_map[cc]
    if slot then
      print("  -> fader slot " .. slot .. " band " .. self:band_idx(slot) .. " val " .. val)
      if self.on_volume then self.on_volume(self:band_idx(slot), val) end
      return
    end

    slot = self._knob1_map[cc]
    if slot then
      if self.on_degree then self.on_degree(self:band_idx(slot), val) end
      return
    end

    slot = self._knob2_map[cc]
    if slot then
      if self.on_knob2 then self.on_knob2(self:band_idx(slot), val) end
      return
    end

    slot = self._knob3_map[cc]
    if slot then
      if self.on_arp_rate then self.on_arp_rate(self:band_idx(slot), val) end
      return
    end

  elseif msg.type == "note_on" then
    local note = msg.note

    if note == SEND_ALL_NOTE then
      if self.on_panic then self.on_panic() end
      return
    end
    if note == BANK_LEFT_NOTE then
      if self.on_bank_left then self.on_bank_left() end
      return
    end
    if note == BANK_RIGHT_NOTE then
      if self.on_bank_right then self.on_bank_right() end
      return
    end
    if note == SOLO_NOTE then
      if self.on_play_stop then self.on_play_stop() end
      return
    end

    -- Mute/rec: process on note_on, but defer LED update to note_off
    local slot = self._mute_map[note]
    if slot then
      if self.on_mute then self.on_mute(self:band_idx(slot)) end
      self._pending_led_update = true
      return
    end

    slot = self._rec_map[note]
    if slot then
      if self.on_arp_cycle then self.on_arp_cycle(self:band_idx(slot)) end
      self._pending_led_update = true
      return
    end

  elseif msg.type == "note_off" or (msg.type == "note_on" and msg.vel == 0) then
    -- Update LEDs on button release (after hardware is done toggling)
    if self._pending_led_update then
      self._pending_led_update = false
      self:update_leds()
    end
  end
end

-- Update mute LED for a slot
function MidiMix:set_mute_led(slot, on)
  if self.midi and slot >= 1 and slot <= 8 then
    -- MIDIMIX responds to note_on vel 127 = LED on, note_on vel 0 = LED off
    self.midi:note_on(MUTE_NOTES[slot], on and 127 or 0, 1)
  end
end

-- Update rec arm LED for a slot
function MidiMix:set_rec_led(slot, on)
  if self.midi and slot >= 1 and slot <= 8 then
    if on then
      self.midi:note_on(REC_NOTES[slot], 127, 1)
    else
      self.midi:note_on(REC_NOTES[slot], 0, 1)
      self.midi:note_off(REC_NOTES[slot], 0, 1)
    end
  end
end

-- Update all LEDs based on band states (caches bands for bank switches)
function MidiMix:update_leds(bands)
  if bands then self._bands = bands end
  bands = bands or self._bands
  if not bands then return end
  for slot = 1, 8 do
    local bi = self:band_idx(slot)
    if bands[bi] then
      -- Mute LED: on = unmuted AND velocity > 0
      self:set_mute_led(slot, not bands[bi].muted and bands[bi].velocity > 0)
      -- Rec arm LED: on = arp active (mode > 1)
      self:set_rec_led(slot, bands[bi].arp_mode and bands[bi].arp_mode > 1)
    else
      self:set_mute_led(slot, false)
      self:set_rec_led(slot, false)
    end
  end
  -- Bank indicator LEDs: left = page 1, right = page 2+
  if self.midi then
    self.midi:note_on(BANK_LEFT_NOTE, self.bank == 0 and 127 or 0, 1)
    self.midi:note_on(BANK_RIGHT_NOTE, self.bank > 0 and 127 or 0, 1)
  end
end

function MidiMix:all_leds_off()
  if not self.midi then return end
  for slot = 1, 8 do
    self:set_mute_led(slot, false)
    self:set_rec_led(slot, false)
  end
  -- Start on page 1
  self.bank = 0
  self.midi:note_on(BANK_LEFT_NOTE, 127, 1)
  self.midi:note_on(BANK_RIGHT_NOTE, 0, 1)
end

return MidiMix
