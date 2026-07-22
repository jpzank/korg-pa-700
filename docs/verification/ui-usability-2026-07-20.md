# UI usability verification: 2026-07-20

## Signed release build

- `outputs/Arranger Lab.app` builds in Release configuration, carries a valid ad-hoc signature and opens directly into the Show scene.
- The dependency-free harness passes all 209 checks.

## Native Show regression

- Selecting `Aí Já Era` opens the chart for reading without sending MIDI.
- With that repertoire row still holding keyboard focus, Space moved the chart scrollbar from `0.019` to `0.159`.
- Shift+Space returned the chart scrollbar to `0.019`.
- Repertoire rows remain exposed as accessible buttons with an `Abrir cifra` action.

## Inspection-service boundary

Opening the separate `Preparar show` scene can crash `SkyComputerUseService` version `26.715.1000451` with `EXC_BREAKPOINT / SIGTRAP`. Arranger Lab remains running and has no matching crash report. The product's native multi-window architecture is therefore preserved; the failure is isolated to the external inspection service.
