# Arranger Lab — Domain Context

## Glossary

### Instrument Profile

Versioned, declarative mapping for one instrument model. It contains identity signatures, aliases, required setup, channels, exact presets, message templates, lifecycle state and evidence references. A profile describes data; it does not implement protocol state machines.

### Instrument Driver

Tested code that identifies an instrument, declares capabilities, validates parameters, compiles universal actions into scheduled MIDI messages and interprets incoming MIDI. Complex or stateful protocols belong here. The operational API may use only mappings marked `Verified`.

### Instrument Action

A manufacturer-independent request such as setting a part volume, selecting a device preset, changing a transport state or selecting a SongBook entry. It contains intent and validated values, never raw MIDI.

### Keyboard Part

A target expressed as `zone + layer`. `Korg Upper1` and `Yamaha Right1` are aliases of `zone:right, layer:1`; `Korg Lower` is an alias of `zone:left, layer:1`.

### Capture Session

An ordered, bidirectional record of raw MIDI events, endpoint identity, protocol and monotonic timestamps. Filtering affects presentation only; it never deletes the raw capture.

### Batch Sound Catalog

An autosaved, deduplicated list of complete device preset selections observed during one passive mapping session. Each entry retains its exact channel, CC0, CC32 and Program Change, an editable displayed name and occurrence count. Bulk capture is discovery evidence only: exported entries remain `Draft` until the normal physical and audio verification requirements are met.

### Screen Capture Group

An ordered subset of a Batch Sound Catalog associated with one photographed instrument screen. It preserves every selection in touch order, including selections already known elsewhere in the catalog. A list of displayed names can be applied only when its count exactly matches the captured addresses; count or prior-name conflicts reject the whole assignment.

### Experiment

A reproducible procedure that links a hypothesis, starting device state, actions, capture sessions, evidence, analysis and conclusion. Experiments are stored as `.arrlab` packages.

### Capture Diff

A comparison of normalized events from two capture sessions. It reports changed controller values and added or removed messages. Clock, Active Sensing and notes are ignored by default but remain available.

### Audio Evidence

A short mono 48 kHz WAV clip and derived measurements: RMS, peak, normalized spectrum, spectral centroid and spectral distance. It is never a continuous recording.

### Manual Confirmation

A timestamped human assertion about a physical observation that MIDI cannot prove alone, such as the preset name shown on the keyboard display or audible arranger start.

### Device State Snapshot

The instrument model, firmware, selected MIDI preset, clock source, mode, endpoints and other setup values relevant to reproducing an experiment.

### Draft

A mapping that is available only in laboratory flows. It may be explored and captured, but cannot be called by the operational API.

### Verified

A mapping backed by raw bytes, firmware version, device configuration and physical confirmation. Volume and timbre mappings also require Audio Evidence.

## Relationships

An Experiment starts from a Device State Snapshot and owns one or more Capture Sessions. A Batch Sound Catalog may own Screen Capture Groups for photo-assisted discovery. An Instrument Driver reads an Instrument Profile and compiles Instrument Actions. The resulting events become captures and may generate Audio Evidence, Manual Confirmation and a Capture Diff. Those artifacts can promote a mapping from Draft to Verified.

## Example Dialogue

“Set right layer 1 to 50%” becomes `setPartVolume(KeyboardPartTarget(zone: .right, layer: 1), level: 0.5)`. “Reduce its performance expression to 25%” becomes `setPartExpression(..., level: 0.25)`. “Move it fully left” becomes `setPartPan(..., position: -1)`, where `-1...1` means left through center to right. “Engage sustain” becomes `setPartDamper(..., engaged: true)`. The PA700 driver resolves the alias and compiles CC7, CC11, CC10 or CC64 on the configured channel. A future Yamaha driver can compile different messages without changing the actions.

## Deliberate Ambiguities

- A “preset” is an opaque, driver-scoped identifier until exact bank/program bytes and the displayed name are observed.
- Transport domains are separate: arranger, song player and MIDI clock state must not be conflated.
- An identity match carries a confidence level; a name match alone is weaker than a verified universal identity response.
