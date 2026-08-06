# ADR 0002: Declarative profiles with tested protocol drivers

- Status: Accepted
- Date: 2026-07-14

## Context

Simple mappings such as part volume are data, while identity negotiation, fragmented SysEx, clock scheduling and stateful vendor protocols require executable behavior and tests.

## Decision

Profiles are versioned JSON containing declarative identity, aliases, setup, channels, message templates, exact presets and evidence. Drivers validate and compile universal actions, interpret input and own complex protocol behavior. The operational API rejects Draft mappings; laboratory calls must explicitly opt into them.

## Consequences

New instruments can often start as profiles, while complex behavior gains a tested driver. Mapping confidence and lifecycle remain explicit and auditable.
