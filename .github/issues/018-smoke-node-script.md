---
title: GTD-018 · Smoke: Node script queries a running game
labels: area/client, type/feature, priority/P1, agent-ready, size/XS
milestone: v0.1
phase: 1
depends: 013, 014, 015, 017
resolution:
---

# GTD-018 · Smoke: Node script queries a running game

## Context

First cross-boundary proof of v0.1: the JS client talking to the live addon. Also validates SPEC §5's "stranger could write a client" claim.

## Goal

A committed 20-line Node script performs health → node → property → scene queries against a live game, green.

## Scope

**In scope:**

- `examples/smoke.mjs`: connect, `/health`, `/node/<path>`, property read, `/scene/current`, `/state`
- Script doubles as the CI executable-docs check for SPEC §5 `curl` examples (GTD-010)

**Out of scope:**

- Test-runner integration (Phase 3–4)

## Technical specification

- Uses only `@godriver/core` public API — no raw fetch in the example (docs honesty).

## Acceptance criteria

- [ ] Script exits 0 against a live game; every query's response matches SPEC §5 shapes
- [ ] Script fails with a clear typed error when the game is not running
- [ ] Committed under `examples/` and referenced from the README quickstart

## Testing

- [ ] The script IS the test; wired into CI in GTD-042.

## Documentation

- [ ] README quickstart references it; SPEC §5 `curl` examples validated by it.

## Files expected to change

```
examples/smoke.mjs
README.md   # quickstart link
```

## References

- SPEC §5
- PLAN §Documentation (executed examples)
- ROADMAP Phase 1

## Dependencies

**Blocked by:** [[dep:013]] [[dep:014]] [[dep:015]] [[dep:017]]

**Blocks:** — (v0.1 gate)
