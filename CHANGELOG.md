# Changelog

All notable changes to Arranger Lab are documented here.

## Unreleased

### PA700 transport and media

- Added profile-driven USB/CoreMIDI matching for PA700 Standard and Oriental,
  including macOS and firmware endpoint-name variants without cross-pairing.
- Kept endpoint discovery separate from the explicit universal SysEx identity
  confirmation and documented the factory MIDI presets as setup references only.
- Added a read-only KORG `.SET` and standalone-resource inventory with
  deterministic JSON export; firmware installation, backup decryption and
  automatic mapping promotion remain out of scope.

### Show

- Added a separate SpriteKit Backdrop window for HDMI/projector output, with
  per-song palettes, intensity, persistence, sensitivity and ambient motion.
- Added note, velocity, part-channel, chord-cluster and sustain-driven organic
  paint while keeping MIDI input bounded and session-filtered.
- Kept the projected cue independent from chart reading and PA700 commanded or
  observed state; successful Apply activates it automatically and read-only
  songs require the explicit `Ativar visual` action.
- Added preview/fullscreen output, remembered display selection, ambient
  fallback on disconnect, explicit Blackout and Panic cleanup.
- Fixed automatic chart scrolling stalling when focus-mode chrome is hidden or
  shown, while retaining smooth fractional movement at every speed.
- Added a dedicated dark, high-contrast Show window that opens by default and applies confirmed songs with one touch.
- Added SongBook-backed show presets with transpose, Upper 1/2/3, Lower, effects and notes as operator references.
- Added disposable import of external text PDFs, chord-aware extraction and chart transposition.
- Added bounded, cancellable PDF import outside the main UI executor, with file,
  page and extracted-text limits.
- Replaced free-text Upper/Lower fields with a searchable sound browser for captured User sounds and the complete Factory, Legacy and GM/XG libraries.
- Added prominent live readouts for the key played by the hands, PA700 transpose and resulting sounding key.
- Added a stage chart reader with chord visibility, per-song font defaults, manual scrolling and session position memory.
- Added a full-screen performance focus with persistent draggable notes over the chart, large previous/next controls, explicit PA700 preparation, set progress and a locked annotation mode.
- Separated chart reading from PA700 activation: drafts open their lyrics and chords immediately, while only operational presets send direct setup or SongBook.
- Standardized the app on one restrained OKLCH-derived semantic palette, shared spacing/radius tokens and consistent lifecycle copy.
- Made Show responsive by removing the redundant inspector on compact windows, preserved the reader anchor when chords are hidden and added keyboard movement for chart notes.
- Made chart paging reliable while a repertoire row has keyboard focus, with Space to advance and Shift+Space to return.
- Tuned focus mode for stage comfort with a separately saved larger type size, centered reading column, stronger next-song cue and larger paging controls with visible shortcuts.
- Kept preparation save/test actions visible below the scrolling editor and made `Aplicar no PA700` the only transmission action in the Show reader.
- Added separate preparation and laboratory windows, preserving all legacy scenes and test data without exposing them on stage.
- Added schema v2 atomic storage with v1 migration, active repertoire persistence, draft blocking and physical confirmation before live use.

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
