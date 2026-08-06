# Arranger Lab

Arranger Lab is a macOS laboratory and live-performance companion for arranger
keyboards. It provides guarded MIDI discovery, reproducible evidence captures,
PA700-aware controls, set lists, chord charts and an optional second-screen
backdrop. The architecture is manufacturer-independent; the KORG PA700 running
firmware 1.5 is the first documented hardware profile.

The project is designed around a simple safety rule: mappings discovered in the
laboratory remain **Draft** until they have sufficient evidence to become
**Verified**. Operational features cannot send Draft mappings.

> Arranger Lab is an independent community project. It is not affiliated with,
> endorsed by or sponsored by KORG. KORG and PA700 are trademarks of their
> respective owners.

## Highlights

- Safe CoreMIDI discovery, monitoring, capture, replay and emergency Panic.
- Versioned instrument profiles and manufacturer-independent actions.
- PA700 catalogs for 1,727 documented sounds, 379 factory Styles and 298
  factory Keyboard Sets.
- `.arrlab` evidence packages with JSONL events, analysis and optional WAV
  clips, plus CSV and Standard MIDI File exports.
- High-contrast Show mode with set lists, editable chord charts, explicit
  PA700 application and per-song visual backdrops.
- Read-only KORG media inventory that reports metadata without installing,
  decrypting or importing proprietary resources.
- Deterministic local assistant for exact Verified catalog names. No cloud or
  generative-AI service is required.

No songs, lyrics, commercial set lists, source PDFs or user captures are
bundled. Import only documents and media you have permission to use.

## Requirements

- macOS 14 or later
- Swift 5.10 or later
- Xcode Command Line Tools or Xcode
- A CoreMIDI device for hardware workflows; tests and most UI exploration work
  without a keyboard

## Quick start

```sh
git clone https://github.com/jpzank/korg-pa-700.git
cd korg-pa-700
bash scripts/test.sh
swift run ArrangerLabApp
```

For the complete local verification gate:

```sh
./scripts/verify.sh
open "outputs/Arranger Lab.app"
```

`verify.sh` runs the Swift Testing suites, the dependency-free integration
harness and a release build with an ad-hoc signature. It does not create a
release archive. `scripts/release.sh` additionally creates a versioned ZIP and
SHA-256 checksum under `outputs/`.

The app is ad-hoc signed for local use; it is not notarized. macOS may require
you to approve the app in Privacy & Security. Never bypass security warnings for
a binary you did not build or obtain from a trusted release.

## Using hardware safely

1. Back up your keyboard data and read the relevant manufacturer documentation.
2. Connect MIDI and confirm that Arranger Lab found the intended input and
   output endpoints.
3. Run the explicit identity check before sending operational controls.
4. Keep new or uncertain mappings in Laboratory mode as Draft.
5. Verify the displayed hardware state after every test. Use Panic immediately
   if the instrument behaves unexpectedly.

The PA700 test profile expects a dedicated MIDI preset with Upper 1/2/3 on
channels 1/2/3, Lower on channel 4 and Control on channel 16. Arranger Start/Stop
testing requires a temporary external USB clock configuration; restore the
keyboard to its normal internal clock afterward. The software does not alter
panel configuration automatically.

See [CONTEXT.md](CONTEXT.md) for the domain vocabulary and
[docs/verification/pa700-2026-07-14.md](docs/verification/pa700-2026-07-14.md)
for the evidence behind currently Verified mappings.

## Data and privacy

Runtime data stays outside the repository in:

```text
~/Library/Application Support/Arranger Lab/Experiments
```

This may include MIDI captures, locally imported chart text, metadata and short
audio evidence recorded only after an explicit action. PDF imports are limited
to 32 MiB, 256 pages and 4 MiB of extracted text; extraction runs off the main
UI executor. The structured chart is stored locally and the source PDF is not
copied into the project.

Before opening an issue, remove names, private repertoire, copyrighted lyrics,
device serials and other sensitive material from logs or sample files.

## Project layout

```text
Sources/ArrangerLabCore/         Models, profiles, parsing, capture and safety
Sources/ArrangerLabMIDI/         CoreMIDI transport and lifecycle
Sources/ArrangerLabAudio/        Short evidence recording and measurements
Sources/ArrangerLabApp/          SwiftUI application and Backdrop output
Sources/ArrangerLabTestHarness/  Dependency-free integration checks
Tests/                           Swift Testing suites
docs/                            Architecture, research and verification notes
scripts/                         Test, build, verification and release tools
```

The design and trust boundaries are summarized in
[docs/architecture.md](docs/architecture.md). The canonical `.arrlab` package
contains `manifest.json`, `events.jsonl`, `analysis.json` and optional
`audio/*.wav`.

## Contributing

Community contributions are welcome. Start with
[CONTRIBUTING.md](CONTRIBUTING.md), follow the safety and evidence rules, and
run `./scripts/verify.sh` before requesting review. Bug reports and feature
requests have dedicated GitHub templates.

Security issues should follow [SECURITY.md](SECURITY.md) and must not be posted
as public issues. Third-party data and trademark boundaries are documented in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). The latest review is recorded
in [docs/security-audit-2026-08-06.md](docs/security-audit-2026-08-06.md).

## License

Arranger Lab is available under the [MIT License](LICENSE). Third-party names,
documentation, firmware, music and proprietary resources are not covered by
that license; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Current application version: **1.0.0**. See [CHANGELOG.md](CHANGELOG.md).
