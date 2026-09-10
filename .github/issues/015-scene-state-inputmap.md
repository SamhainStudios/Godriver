---
title: GTD-015 · /scene/current + /state + /input/map
labels: area/addon, type/feature, priority/P0, agent-ready, size/S
milestone: v0.1
phase: 1
depends: 013
resolution:
---

# GTD-015 · `/scene/current` + `/state` + `/input/map`

## Context

Scene metadata, game state, and the input map are the read-only situational-awareness endpoints — test preconditions and sanity checks lean on them (PLAN §Scene metadata endpoints).

## Goal

The three read-only situational endpoints per SPEC §5, each self-tested.

## Scope

**In scope:**

- `GET /scene/current`: scene name, path, child count (SPEC §5)
- `GET /state`: paused, fps, physics_active
- `GET /input/map`: all configured actions (name, keys, deadzone)

**Out of scope:**

- State writes (GTD-032), scene changes (GTD-023)

## Technical specification

- `/state` fps reads `Engine.get_frames_per_second()`; `physics_active` from `get_tree().physics_frame` activity — exact shape per SPEC §5 (fill during GTD-010).

## Acceptance criteria

- [ ] All three return SPEC §5 shapes against the fixture scene
- [ ] `/input/map` lists every action from the project's InputMap with correct keys/deadzone
- [ ] Each endpoint self-tested headless

## Testing

- [ ] Self-tests per endpoint (shape + values against known fixture state).

## Documentation

- [ ] SPEC §5 entries verified; `curl` examples executed.

## Files expected to change

```
addons/godot-test-driver/handlers/scene_handler.gd
addons/godot-test-driver/handlers/state_handler.gd
addons/godot-test-driver/handlers/input_handler.gd   # map only
```

## References

- SPEC §5
- PLAN §Scene metadata endpoints
- ROADMAP Phase 1

## Dependencies

**Blocked by:** [[dep:013]] [[dep:010]]

**Blocks:** [[dep:016]] [[dep:032]] [[dep:033]]
