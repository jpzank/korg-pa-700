# PA700 mapping backlog

Date: 2026-07-15
Reference: local copy of the official PA700 User Manual v1.5, pages 877–885.

## Verified foundation

- Identity and firmware.
- Part volume on the configured Keyboard Part channel.
- Exact Sound selection with CC0, CC32 and Program Change.
- Per-part Expression on the configured Keyboard Part channel.
- Per-part Pan on the configured Keyboard Part channel, with center restoration after every test stimulus.
- Arranger Start/Stop with external USB clock and restoration to Internal.
- SongBook entry selection on Control channel 16.
- Keyboard Set 1–4 on Control channel 16; Kbd2/Organ and Kbd4/Harmonica physically confirmed with panel photos, then Kbd1 restored.

## Officially documented candidates — Draft until physical evidence

### Batch 1 — Control channel

- Verified individually: Intro 1–3 / Count In (PC80–82), Variation 1–4 (PC83–86), Fill 1–4 (PC87–90), Break (PC91), Ending 1–3 (PC92–94) and Arranger Start/Stop toggle (PC103).
- Intro 1–2: Program Change 80–81, selection and playback physically Verified. Intro 1 required a controlled retest after two earlier inconclusive attempts.
- Variation 1–4: Program Change 83–86, all physically Verified after a stable USB reconnect and identity check.
- Fill 1–4: Program Change 87–90, audible transitions physically Verified.
- Break: Program Change 91, audible pause and resume physically Verified.
- Ending 1–3: Program Change 92–94, each ending and automatic stop physically Verified.
- Verified context controls: Fade In/Out (PC95), Style to Keyboard Set (PC96, three-state cycle), Auto Fill (PC97), Memory (PC98), Bass Inversion (PC99), Manual Bass (PC100, requires SPLIT active), Tempo Lock (PC101), Arranger Start/Stop (PC103) and Player Play/Stop (PC104, verified with the internal DISK song `Late 1`).

### Batch 2 — Per-part mixer and expression

- Pan: CC10 is Verified for right/layer 1. The universal `setPartPan(target, position)` action uses `-1...1`; the guided experiment sent 0/64/127, recorded three short clips and restored center after every stimulus. The user physically confirmed center, left and right. Mono microphone RMS (−51.44, −50.16 and −50.02 dBFS) is retained for audit only, not as directional proof. Canonical package: `Part-Pan-2026-07-16T00-50-15Z.arrlab`.
- Expression: CC11 is Verified for right/layer 1. With CC7 fixed at 75%, the guided 25/50/75% experiment measured −62.46, −59.90 and −54.72 dBFS: strict monotonic growth and 7.75 dB total. The user physically confirmed that 25% was audibly very low. Canonical package: `Part-Expression-2026-07-16T00-37-03Z.arrlab`.
- Damper: CC64 is Verified for right/layer 1. With the PA700 in Sound mode, MIDI preset `14 ArrangerLab`, and channel 1 mapped directly to Upper 1, the guided OFF/ON/OFF test produced a dry first note and a sustained second note. The user confirmed the audible result with the physical damper jack disconnected; the app restored CC64 to OFF and saved `Part-Damper-2026-07-16T02-36-54Z.arrlab` as canonical evidence.
- Portamento, Sostenuto and Soft: CC65–67.
- Release, Attack, Filter Cutoff/Brilliance, Decay and LFO controls: CC72–79.
- Reverb send: CC91.
- Modulation effect send: CC93.

### Batch 3 — Exact resources

- The complete Sound catalogue is imported from the official v1.5 Musical Resources appendix: 1,727 documented entries plus seven captured User entries. A full representative-per-bank MIDI/audio sweep and physical sample checks promoted the catalogue under `catalogSampling`; individually heard entries retain their stronger evidence basis.
- Bulk discovery remains available in **Mapear timbres** for future User sounds and corrections. It passively captures canonical Upper1 `CC0.CC32.PC`, deduplicates repeated selections, autosaves the session and exports profile-compatible data.
- Future low-interference refinement: optional on-device OCR and automated short audio validation of selected Drafts. Neither may promote an entry without human confirmation.
- Style selection catalogue Verified: all 379 factory Styles are searchable by category and compile as exact `CC0.CC32.PC` on Control channel 16. The live `Bossa Nova` sample (`0.6.2`) and working rhythms were physically confirmed on the PA700.
- Keyboard Set Library catalogue Verified: all 298 factory Keyboard Sets from pages 948–952 are searchable by category and compile as exact `CC0.CC32.PC` on Control channel 16. The live `Jimmy Organ` sample (`16.1.0`) was physically confirmed on the PA700 display.
- Pads and Style tracks after assigning temporary laboratory channels without replacing the persisted performance preset.

## Safety boundary

- No firmware operations, memory writes, destructive SysEx or unknown SysEx.
- Official documentation creates only a Draft candidate; promotion also requires captured bytes, firmware, PA700 configuration and physical confirmation. Timbre or mixer changes additionally require short audio evidence where meaningful.
- Toggle commands are never represented as absolute on/off state unless the current state can be observed or safely established.
