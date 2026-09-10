---
title: GTD-012 · Dispatcher wired into the addon
labels: area/addon, type/feature, priority/P0, agent-ready, size/S
milestone: v0.1
phase: 1
depends: 011
resolution:
---

# GTD-012 · Dispatcher wired into the addon

## Context

The Phase-0 dispatcher (GTD-002) is spike-grade; the addon needs it as the single path from HTTP worker threads to SceneTree access (PLAN Constraints).

## Goal

All addon handlers execute through the main-thread task queue, with unit tests proving main-thread execution.

## Scope

**In scope:**

- Move `dispatcher.gd` into `addons/godot-test-driver/`; `api_handler.gd` routes every request through `submit()`
- Handler registration map (route → handler callable)
- Error funnel: handler exceptions → `500` envelope, never a crash

**Out of scope:**

- Individual endpoint handlers (GTD-013+)

## Technical specification

- Dispatcher runs `PROCESS_MODE_ALWAYS` (paused-dispatch guarantee, GTD-004-validated).
- Rationale for one queue (not per-handler): single drain point keeps ordering deterministic and testing simple.

## Acceptance criteria

- [ ] Every request path goes through the queue (no direct SceneTree access from worker threads)
- [ ] Handler exception → `500` with envelope error, server stays up
- [ ] Unit tests: main-thread execution assert, exception funnel, ordering (FIFO under load)

## Testing

- [ ] Scaffold unit tests (GTD-007) extended: dispatcher suite green headless.

## Documentation

- [ ] `docs/technical/addon-internals.md`: threading model + handler map sections completed.

## Files expected to change

```
addons/godot-test-driver/dispatcher.gd
addons/godot-test-driver/api_handler.gd
```

## References

- PLAN §Constraints, §File Structure
- ROADMAP Phase 1

## Dependencies

**Blocked by:** [[dep:011]] [[dep:007]]

**Blocks:** [[dep:013]]
