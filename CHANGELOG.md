# Changelog

All notable changes to Arranger Lab are documented here.

## 1.0.0 - 2026-07-17

### Laboratory

- Added CoreMIDI endpoint discovery by Unique ID, hot-plug handling, bidirectional MIDI 1.0 monitoring and mandatory Panic cleanup.
- Added Note, CC, Program Change, Pitch Bend, SysEx and realtime parsing with presentation-only Clock and Active Sensing filters.
- Added capture, annotations, safe replay, normalized diff, canonical `.arrlab` packages and CSV/SMF compatibility exports.
- Added short mono 48 kHz audio evidence with RMS, peak, normalized spectrum, spectral centroid and spectral distance.
- Added guarded Expert mode with model challenge, complete byte visibility, SysEx confirmation and automatic expiry.

### PA700

- Added a firmware 1.5.0 profile with Verified identity, part mixer controls, exact presets, transport, SongBook, Keyboard Sets, Arranger Elements and contextual controls.
- Added all 1,727 documented sounds, 379 factory Styles and 298 factory Keyboard Sets.
- Added passive sound mapping, photo-assisted naming, fast bank sampling and Draft JSON export without automatic promotion.
- Completed physical and audio verification for the PA700 v1 operational mappings while preserving Draft separation in laboratory flows.

### Performance

- Added manufacturer-independent scenes, ordered set lists and a focused Show Mode.
- Added a deterministic local musical assistant that recognizes exact Verified catalogue names and variations, shows a before/after preview and sends no MIDI before explicit confirmation.

### Safety

- Operational driver calls reject Draft mappings.
- Stop, disconnect, replay completion, failures, backgrounding and app close trigger Panic.
- Unknown SysEx is excluded from automatic replay.

### Deferred to later releases

- Semantic or generative AI interpretation.
- Operational MIDI 2.0.
- Public signing, notarization, App Store distribution and drivers physically verified for other manufacturers.
