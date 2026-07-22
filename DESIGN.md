---
name: Arranger Lab
description: A precise macOS MIDI evidence bench for arranger keyboards
colors:
  signal-teal: "oklch(58% 0.085 185)"
  inbound-blue: "oklch(55% 0.085 220)"
  draft-amber: "oklch(61% 0.10 60)"
  verified-green: "oklch(56% 0.105 145)"
  safety-red: "oklch(56% 0.145 25)"
  stage-background: "oklch(18% 0.01 185)"
  stage-surface: "oklch(23% 0.01 185)"
  chord-amber: "oklch(75% 0.14 55)"
typography:
  body:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.35
  title:
    fontFamily: "SF Pro, -apple-system, system-ui, sans-serif"
    fontSize: "20px"
    fontWeight: 600
    lineHeight: 1.2
  data:
    fontFamily: "SF Mono, ui-monospace, monospace"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.3
rounded:
  control: "6px"
  status: "999px"
spacing:
  compact: "8px"
  standard: "16px"
  page: "24px"
components:
  button-primary:
    backgroundColor: "{colors.signal-teal}"
    textColor: "oklch(98% 0.005 185)"
    rounded: "{rounded.control}"
    padding: "6px 12px"
  button-danger:
    backgroundColor: "{colors.safety-red}"
    textColor: "oklch(98% 0.005 25)"
    rounded: "{rounded.control}"
    padding: "6px 12px"
---

# Design System: Arranger Lab

## Overview

**Creative North Star: "The Instrument Service Bench"**

Arranger Lab feels like a clean physical test bench beside a keyboard: tools stay where an operator expects them, signals are labeled, and every risky action has a visible guard. Native macOS structure provides familiarity while monospaced bytes and stable tables preserve engineering precision.

The system is technical, precise and sober. It explicitly rejects a loaded DAW, a generic SaaS dashboard, decorative AI styling and visual effects without operational meaning.

**Key Characteristics:**

- Native controls and predictable split navigation
- Dense evidence tables with clear direction and timestamps
- Restrained semantic color used only for signal, lifecycle and danger
- State-change motion only

## Colors

The palette uses one restrained signal accent plus semantic colors whose labels always repeat their meaning.

### Primary

- **Signal Teal:** primary actions, selection and connected laboratory controls.

### Secondary

- **Inbound Blue:** input direction in the MIDI monitor.
- **Draft Amber:** output direction and unverified lifecycle state.

### Tertiary

- **Verified Green:** evidence-backed lifecycle state only.
- **Safety Red:** Panic, destructive-risk confirmation and active recording stop.
- **Stage Background / Surface:** fixed dark, subtly teal neutrals used only in the Show window.
- **Chord Amber:** chord lines and transpose values in the Show reader.

### Neutral

- Native macOS window, sidebar, separator and text colors adapt to the user's appearance and accessibility settings.

**The Semantic Signal Rule.** Accent colors never decorate a surface; every colored element communicates direction, lifecycle, connection or risk.

## Typography

**Display Font:** SF Pro with the macOS system fallback
**Body Font:** SF Pro with the macOS system fallback
**Label/Mono Font:** SF Mono with the system monospace fallback

**Character:** Native text keeps the tool quiet. Fixed-width data makes bytes, timestamps and numeric comparisons stable under scanning.

### Hierarchy

- **Headline:** semibold 20px for page identity.
- **Title:** semibold system title for experiment and group identity.
- **Body:** regular 13px for controls and operational prose.
- **Label:** system caption for metadata and lifecycle tags.
- **Data:** regular 12px monospace for raw bytes, IDs, timestamps and values.

**The Bytes Stay Fixed Rule.** MIDI bytes, endpoint IDs, timestamps and exact numeric values always use the data face.

## Elevation

The app is flat by default and uses native tonal layering, separators and selection backgrounds. Shadows are not introduced by Arranger Lab; temporary macOS surfaces such as menus and alerts retain their platform elevation.

**The Bench Is Flat Rule.** If a static panel needs a shadow to be understood, its hierarchy is wrong.

## Components

### Buttons

- **Shape:** native gently curved controls with a 6px design-system reference.
- **Primary:** Signal Teal, reserved for the next safe workflow action.
- **Danger:** Safety Red with an explicit verb and SF Symbol; never icon-only.
- **Hover / Focus:** native macOS states and keyboard focus ring.

### Chips

- **Style:** compact capsule with low-opacity semantic fill and a visible `Draft` or `Verified` text label.
- **State:** color is redundant; the lifecycle word is always present.

### Cards / Containers

- **Corner Style:** native GroupBox or inset List structure.
- **Background:** adaptive macOS surfaces.
- **Shadow Strategy:** none.
- **Border:** native separator only.
- **Internal Padding:** 8px compact, 16px standard or 24px page rhythm.

### Inputs / Fields

- **Style:** native TextField, Picker, Stepper, Toggle and Slider controls.
- **Focus:** native focus ring and full keyboard navigation.
- **Error / Disabled:** disabled state plus explanatory status or alert; never opacity alone for errors.

### Navigation

The persistent split sidebar uses SF Symbols and text. The active page has one 20px title and a short operational subtitle; connection and Panic remain visible above every page.

The Show window responds structurally. Below 1180px it removes the redundant details inspector while preserving the repertoire rail and chart. Focus mode removes both side regions, locks annotation editing, centers the readable column, uses its own saved larger type size and enlarges the controls needed during a performance.

### MIDI Event Table

Direction combines arrow icon, `IN`/`OUT` text and semantic color. Bytes and timestamps are selectable monospace data. Clock and Active Sensing filters alter visibility only.

### Guided Test Rail

A six-step rail is the default entry point for musicians. Each step uses a numbered or checked circle, one plain-language instruction, live evidence and a single primary next action. Advanced raw MIDI tools remain in separate sidebar destinations.

### Operational State

Selecting a song opens it for reading and never sends MIDI. `Aplicar no PA700` is the only show-reader action that transmits the selected setup. `Configurada`, `Somente leitura`, `Em leitura` and `No PA700` describe separate states and are never collapsed into one label.

## Do's and Don'ts

### Do:

- **Do** keep connection state and Panic visible across all five workspaces.
- **Do** label every Draft and Verified mapping in text as well as color.
- **Do** use 24px page spacing and 8px compact spacing consistently.
- **Do** preserve native keyboard focus, reduced motion and adaptive system surfaces.
- **Do** open on the guided workflow and reveal raw MIDI controls only when the user deliberately chooses an advanced destination.

### Don't:

- **Don't** make Arranger Lab look like a loaded DAW.
- **Don't** use a generic SaaS dashboard grid or nested metric cards.
- **Don't** use decorative AI styling or visual effects without operational meaning.
- **Don't** hide bytes, destination, verification state or the consequences of dangerous actions.
- **Don't** add gradients, glass effects, ornamental shadows or color-only status indicators.
