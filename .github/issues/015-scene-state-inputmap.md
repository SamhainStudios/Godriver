---
title: GTD-015 · /scene/current + /state + /input/map
labels: area/addon, type/feature, priority/P0, agent-ready, size/S
milestone: v0.1
phase: 1
depends: 013
resolution: DONE 2026-09-10 — three read-only endpoints, 30/30 GdUnit green + e2e curl verified. Files: addons/godriver/handlers/scene_handler.gd (current: {scene: scene_file_path, node: absolute path}; 500 INTERNAL_ERROR when tree.current_scene null), addons/godriver/handlers/input_handler.gd (input_map: per-type event summaries — key keycode/physical_keycode/device, mouse_button/joypad_button button_index/device, joypad_motion axis/axis_value/device, other {type} only; snake-case type via "InputEvent" prefix strip; device constants §6: keyboard 16, mouse 32, emulation -1), addons/godriver/handlers/state_handler.gd (read_state: project setting godriver/state_autoload default "GameState", resolves /root/<name>, values = PROPERTY_USAGE_SCRIPT_VARIABLE props only via get_property_list, serialized per §4 via TestDriverSerializer; 409 STATE_AUTOLOAD_MISSING with details.hint naming the setting); api_handler.gd routes +/scene/current +/input/map +/state. Suite scratch/spike/test/unit/test_scene_state_inputmap.gd (3 tests) + fixture scratch/spike/test/fixtures/game_state.gd (score/player_name/hard_mode/inventory). Findings: (1) GdUnit runs WITHOUT the project main scene — tree.current_scene is null, so the unit test asserts the 500 INTERNAL_ERROR branch and the 200 shape is verified e2e (curl: {"scene":"res://scratch/spike/scenes/main.tscn","node":"/root/Main"}); (2) state fixture must be added to get_tree().root directly (handler resolves /root/<name>), removed in after_test; (3) GDScript has NO bool(x) constructor — assert_bool takes the Variant directly (runtime error 'Invalid call. Nonexistent bool constructor'); (4) e2e /input/map shows device=16 on key events, device=-1 on joypad (emulation), ui_accept present. SPEC §5.1/§5.8 verified; curl examples executed.
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
addons/godriver/handlers/scene_handler.gd
addons/godriver/handlers/state_handler.gd
addons/godriver/handlers/input_handler.gd   # map only
```

## References

- SPEC §5
- PLAN §Scene metadata endpoints
- ROADMAP Phase 1

## Dependencies

**Blocked by:** [[dep:013]] [[dep:010]]

**Blocks:** [[dep:016]] [[dep:032]] [[dep:033]]
