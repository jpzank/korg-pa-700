# ADR 0001: Keep the control platform independent from AIArranger

- Status: Accepted
- Date: 2026-07-14

## Context

AIArranger is a useful external reference for CoreMIDI enumeration, arranger playback and CSV/SMF fixtures. Its repository declares no software license and its product domain is an arranger engine rather than instrument control.

## Decision

Arranger Lab is implemented independently in SwiftUI/CoreMIDI. AIArranger is cloned at the pinned commit only under the ignored `work/aiarranger-sandbox` directory, built and evaluated without modification. No source, assets or fixtures are copied into Arranger Lab.

## Consequences

The sandbox may validate interoperability and exported formats, but it is neither a dependency nor a source of implementation code. Evaluation findings are recorded in `docs/research/aiarranger-evaluation.md`.
