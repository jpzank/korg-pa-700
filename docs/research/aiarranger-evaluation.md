# AIArranger sandbox evaluation

## Scope

- Repository: `hieucat75/AIArranger`
- Pinned commit: `5e72ee6830efffc8c08cddb66fdcafdffcb42a8b`
- Location: ignored `work/aiarranger-sandbox`
- Policy: build and observe only; no modification, redistribution or code reuse.

## Licensing and fit

No software license is declared in the repository. Its primary domain is arranger generation/playback, not a universal instrument-control abstraction. It therefore remains a disposable interoperability sandbox rather than an Arranger Lab dependency.

## Validation record

| Check | Status | Evidence / limitation |
|---|---|---|
| Pinned clone | Passed | `git rev-parse HEAD` = `5e72ee6830efffc8c08cddb66fdcafdffcb42a8b`. |
| Headless build/tests | Passed | Release build 100%; CTest 81/81 passed. |
| macOS app build | Passed | JUCE 8.0.4 fetched by CMake; `AI Arranger.app` linked successfully using Command Line Tools. Warnings only. |
| `Pa700 KEYBOARD` input enumeration | Passed | Selected in the JUCE UI; status reported `In: connected`. |
| `Pa700 SOUND` output enumeration | Passed | Selected in the JUCE UI; status reported `Out: connected`. |
| Chord input | Passed | PA700 sent C–E–G on channel 1; the sandbox reported chord `C` and `rx: 6`. |
| Bundled style playback | Passed | Demo style played section 0 at 120 BPM; `tx` reached 62 after four seconds and the user confirmed audible accompaniment. |
| Panic and clean close | Passed | Stop and Panic raised `tx` to 100; the app then closed and the user confirmed no stuck notes. |

## Build record

- CMake installed with Homebrew: 4.4.0.
- Headless configuration: `BUILD_MACOS_APP=OFF`, Release.
- GUI configuration: `BUILD_MACOS_APP=ON`, Release.
- JUCE pin read directly from the sandbox: 8.0.4.
- The sandbox source tree was not modified (`git status --short` remained empty).

The sandbox's synthetic Korg harness does not perform real PA700 protocol mapping. Its 81 green tests support build health only; they do not promote any Arranger Lab mapping.

## Physical session — 2026-07-15

The first physical attempt exposed a stale USB connection: both clients enumerated the endpoints, but neither received notes or an identity reply. After the cable was reseated in the PA700 `USB DEVICE` port, macOS enumerated `Korg Inc. / Pa700` again and Arranger Lab received the identity response for manufacturer `42`, family `0060`, model `005D`, firmware `1.5.0`.

With the factory `Default` MIDI Preset selected, the PA700 sent these channel-1 events for C–E–G:

- Note On: `90 48 40`, `90 4C 41`, `90 4F 37`.
- Note Off: `80 48 38`, `80 4C 3D`, `80 4F 29`.

Arranger Lab received all six events independently. The sandbox was then isolated, reopened and configured with `Pa700 KEYBOARD` as input and `Pa700 SOUND` as output. It reported chord `C`, `rx: 6`, and both endpoints connected. The demo style ran in section 0 at 120 BPM and reached `tx: 62` after four seconds. Stop and Panic were executed, after which `tx` was 100. The application closed cleanly (`isRunning: false`), and the user confirmed both audible accompaniment and no stuck notes.

The sandbox source tree remained clean and pinned to `5e72ee6830efffc8c08cddb66fdcafdffcb42a8b`. No sandbox code, assets or fixtures were reused.

## Format boundary

Arranger Lab exports a compatibility CSV (`tick,status,data1,data2`) and Standard MIDI File. Its canonical `.arrlab` package remains JSONL because CSV/SMF cannot preserve endpoint, direction, protocol and arbitrary SysEx evidence losslessly.
