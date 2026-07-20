# Arranger Lab

Arranger Lab is an internal macOS MIDI laboratory for discovering and verifying manufacturer-independent arranger keyboard actions. The PA700 is the first hardware profile. External or generative AI remains outside v1; the app includes a deterministic local assistant that recognizes only exact Verified catalogue names and arranger variations. The bundled PA700 resources now include the complete Sound catalogue, all 379 factory Styles and all 298 factory Keyboard Sets from the official firmware-1.5 documentation.

Current release: **1.0.0**. See [CHANGELOG.md](CHANGELOG.md) and the [v1.0.0 acceptance checklist](docs/release/v1.0.0-checklist.md).

## Run

Requirements: macOS 14+, Swift 5.10+ and a CoreMIDI device.

```sh
swift run ArrangerLabApp
swift run ArrangerLabTestHarness
./scripts/build-app.sh
./scripts/release.sh
open "outputs/Arranger Lab.app"
```

The packaged app is ad-hoc signed for local use. Microphone access is requested only when a short evidence clip starts. Sessions are written to `~/Library/Application Support/Arranger Lab/Experiments`, outside this repository.

## Architecture

- `ArrangerLabCore`: universal actions, profiles, PA700 driver, parser, capture, diff and export.
- `ArrangerLabMIDI`: CoreMIDI discovery, hot-plug, send/receive, replay, MIDI clock and Panic.
- `ArrangerLabAudio`: short WAV recording and evidence metrics.
- `ArrangerLabApp`: separate SwiftUI windows for Show, show preparation and the MIDI laboratory.
- `ArrangerLabTestHarness`: dependency-free unit/integration harness for machines without XCTest.

The canonical `.arrlab` package contains `manifest.json`, `events.jsonl`, `analysis.json` and `audio/*.wav`. Compatibility `export.csv` and `export.mid` are generated alongside them.

The app opens directly in **Show**, a dark, high-contrast set-list view with one-touch SongBook recall. The bundled catalogs include **Boteco Jul3 - goJam** with 57 songs and **Showboat Jul 23** with the 26 songs from its goJam set list, both in show order. A separate **Showboat Jul 23 · Piano · Bloco A** prepares the requested ten-song running order with keys, transpose values and USER · JPD Piano/Rhodes references. Each Showboat song has its source key, artist and structured, editable lyrics/chords stored locally, so stage use does not depend on goJam and does not retain a PDF. **Preparar show** can also extract additional text-based PDFs, treating each selected file as one song; only the structured chart is saved and the PDF is discarded. It stores independent per-show SongBook numbers and operator references for transpose, Upper 1/2/3, Lower, effects and notes. Upper and Lower sounds are selected from a searchable browser that opens on captured User slots and also includes the complete Factory, Legacy and GM/XG libraries. A preset remains blocked on stage until it has been sent and physically confirmed on the PA700. Reimporting a catalog restores missing songs without overwriting edits. Show data is stored separately under `~/Library/Application Support/Arranger Lab/Experiments/Show`, while the older scenes and set lists remain unchanged under `Scenes`.

For every active song, Show keeps **Tom nas mãos**, **Transpose PA700** and **Tom que soa** visible together. The preparation editor can transpose recognized chord lines by semitones without changing the lyrics or silently changing the SongBook reference.

The **Laboratório** window preserves the Verified controls, searchable PA700 resources, musical assistant, legacy scenes, sound mapping, guided tests, MIDI monitor, capture/diff and raw send tools. Open the three windows with Command-1, Command-2 and Command-3. Toggle-only controls such as Auto Fill and Memory remain excluded from legacy scenes until their state can be observed reliably.

## Safety model

- Operational driver calls reject every Draft mapping.
- Laboratory actions opt into Draft explicitly and retain that label.
- Panic sends All Notes Off and All Sound Off on every MIDI channel plus Stop.
- Stop, disconnect, replay completion, failures and app close trigger Panic.
- Expert mode requires typing `PA700`, expires on disconnect/close, shows the destination and requires a second confirmation for arbitrary SysEx.
- Automatic replay excludes SysEx unless a future tested allow-list explicitly permits it.

## PA700 setup

Keep firmware 1.5.0. On the keyboard, create MIDI Preset `ArrangerLab` in the first empty slot without overwriting a preset: channels 1/2/3 are Upper 1/2/3, channel 4 is Lower and channel 16 is Control. Permit the CC/PC traffic needed by the experiment and only known SysEx.

For arranger Start/Stop, temporarily select Style Play and `Clock Source = External USB`, run the 120 BPM experiment, press Stop, then restore `Internal`. The software does not change panel configuration automatically.

## Verification status

Identity is Verified against the live reply `F0 7E 7F 06 02 42 60 00 5D 00 01 05 00 00 F7`. Right/layer 1 part volume is also Verified: the capture contains outgoing `B0 07 20`, `B0 07 40`, `B0 07 5F`, PA700 firmware 1.5.0, the confirmed ArrangerLab preset, manual confirmation and four WAV clips. RMS increased strictly from −52.23 to −43.38 dBFS (8.85 dB total).

The exact `Classic Piano` preset is Verified as `CC0=121, CC32=4, PC=0` on Upper1 channel 1. A1 and A2 repeated the same bytes, while `Jimmy Organ` produced `121.13.18`. Averaged spectral distances were A1–A2 0.078398, A1–B 0.386705 and A2–B 0.417488.

Arranger transport is Verified in Style Play with Clock Source temporarily set to External USB: the capture contains one `FA`, 2010 `F8` clocks at 120 BPM, three `FC`, 32 All Notes Off and 32 All Sound Off events. The 41.91-second mono/48 kHz WAV, physical Start/Stop confirmations and restoration to Internal are recorded in `Arranger-Transport-2026-07-15T17-27-58Z.arrlab`.

SongBook selection is Verified with the dedicated internal entry `9000 — ArrangerLab Test`. The channel-16 capture is `BF 63 02`, `BF 62 40`, `BF 06 5A`, `BF 26 00`; the user supplied a panel photo showing `SBook: ArrangerLab Te...` after selection. The canonical package is `SongBook-9000-2026-07-15T18-06-22Z.arrlab`.

On launch, the guided workflow loads the newest compatible Verified `.arrlab` from Application Support. Prior evidence is shown as saved verification without mixing historical events into the live MIDI monitor.

The seventh guided step discovers exact presets without guessed values: it marks the live input, extracts a complete channel-1 `CC0.CC32.PC`, records short A–B–A WAV clips with a fixed stimulus, compares spectral distances and saves a dedicated package. Promotion requires matching A1/A2 bytes, a different B, the spectral rule and the displayed-name confirmation.

The eighth guided step persists a safety reminder as soon as External USB is confirmed, records 120 BPM Clock plus Start/Stop and audio, requires physical confirmation, sends Panic, and cannot verify until the user confirms Clock Source was restored to Internal.

The ninth guided step selects the dedicated SongBook entry through the configured Control channel, displays the exact bytes before sending, requires the panel name confirmation and saves a focused package before promotion.

Bulk sound catalogs are saved under `~/Library/Application Support/Arranger Lab/Experiments/Catalogs` and the latest compatible session is restored on launch. **Por foto** groups every Program Change under a numbered screen: photograph the PA700 page, start a screen, touch the visible sounds from left to right and top to bottom, then end it. Names are pasted one per line and are applied only when their count exactly matches the captured MIDI addresses; conflicts cause an atomic rejection. The original **Um por vez** workflow remains available. Repeated selections increase an occurrence counter instead of creating duplicate catalog entries. Export stays disabled while names are pending; exported entries preserve the exact bytes and remain `Draft`, with physical confirmation and audio evidence handled separately.
