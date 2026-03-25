# Italo Sines

Instant gratification italo disco song maker for monome norns. Sends MIDI to hardware synths. Pick a progression, pick a vibe, and you've got a track. Sounds good the second it loads.

## Requirements

- monome norns
- MIDI interface + hardware synths
- Optional: Akai MIDIMIX controller

## Install

From Maiden REPL:
```
;install https://github.com/cfurrow7/italo-sines.git
```

## Default Synth Map

| Band | Role | Channel | Synth |
|------|------|---------|-------|
| B | Bass | 2 | Mother 32 |
| C1 | Chord | 4 | OB-6 |
| C2 | Chord | 11 | PRO-800 |
| L1 | Lead | 10 | MS-101 |
| L2 | Lead | 3 | Pro 3 |
| K | Kick | 15 | Digitakt |
| S | Snare | 15 | Digitakt |
| H | Hat | 15 | Digitakt |
| T | Tom | 15 | Digitakt |

Bands are dynamic. Add or remove on the BANDS page.

## Pages

### PLAY (page 1)
Live performance view. Band columns show activity with flash on trigger.

- **E1**: switch page
- **E2**: select band
- **E3**: adjust velocity
- **K2**: play/stop
- **K3**: mute/unmute selected band

### BANDS (page 2)
Edit selected band's settings. Navigate to "+Band" at the end to add new bands.

- **E2**: select band (or "+Band" to add)
- **E3**: adjust current field
- **K2**: on "+Band" = add new band, on existing = remove band
- **K3**: cycle edit field

Edit fields (melodic bands): vel, ch, oct, type (chord type or melody pattern), arp mode, arp rate, degree.

Edit fields (drum bands): vel, ch, kit, role.

### PROG (page 3)
Progression editor with pop/italo presets.

- **E2**: select field (Prog, BPM, Beats/Step, Key, Scale)
- **E3**: adjust value
- **K2**: play/stop
- **K3**: load random preset progression

16 preset progressions: italo classic (i-VII-VI-V), pop anthem (I-V-vi-IV), emotional (vi-IV-I-V), dark italo, depeche mode, and more.

### CONFIG (page 4)
MIDI channel assignment per band.

- **E2**: select band
- **E3**: change MIDI channel
- **K2**: cycle role

## Chord Engine

Chord bands send actual multi-note chords (triads and 7ths), not single notes. 9 chord types: maj, min, 7, maj7, min7, sus2, sus4, dim, aug. With arp enabled, chord tones arpeggiate across 2 octaves.

## Melody Generator

Lead and bass bands play generated phrases that follow the chord progression:

**Lead patterns**: step up, step down, bounce, repeat, call/response, octave, zigzag, hook

**Bass patterns**: pump, root-5th, octave, walking, syncopated, arp

Phrases regenerate on every chord change to stay musically coherent.

## Drum Kits

8 coordinated italo drum kits (kick + snare + hat + tom patterns designed together):
Classic Italo, Moroder, Hi-NRG, Euro Disco, Cosmic, Minimal, Synth Pop, Funky Disco.

## MIDIMIX Controller Map

```
 KNOB ROW 1:  degree  degree  degree  degree  degree  degree  degree  degree
 KNOB ROW 2:  chType  chType  melody  melody  melody  kit     kit     kit
 KNOB ROW 3:  arpRt   arpRt   arpRt   arpRt   arpRt   arpRt   arpRt   arpRt

 MUTE:        [on/off per band]
 REC ARM:     [cycle arp mode per band]

 FADERS:       VEL     VEL     VEL     VEL     VEL     VEL     VEL     VEL

 BANK L/R:    bands 1-8 / 9+
 SEND ALL:    PANIC (all notes off)
 SOLO:        play/stop
 MASTER:      BPM (80-260)
```

## On Startup

Loads in A minor with the "italo classic" progression (i-VII-VI-V) at 120 BPM. All 9 bands active. Auto-plays immediately. Adjust from there.

## Credits

- Inspired by [Sines](https://github.com/aidanreilly/sines) by Aidan Reilly
- v0.1 @clf
