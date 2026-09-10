---
title: GTD-023 · POST /scene/load — scene change with readiness semantics
labels: area/addon, area/scene, type/feature, priority/P1, size/S
milestone: v0.1
phase: 2
depends: 016
resolution: DONE 2026-09-10 — scene_handler.gd load_scene coroutine (MISSING_PARAM → ResourceLoader.exists(path,"PackedScene") → 404 SCENE_NOT_FOUND → change_scene_to_file → await process_frame until current_scene changes → poll is_node_ready() 5s → 504; tween/orphan steps SKIPPED per brief); api_handler _dispatch_scene_load + _start_scene_load mirroring _dispatch_reset exactly (slot+Mutex polling 15s) with the in-flight guard _reset_in_flight SHARED between load and reset. test_scene_load.gd 3 tests green (valid load ready + tree reflects new scene + script state live; 404/400 errors incl. non-scene resource; shared-guard test via back-to-back _start_scene_load/_start_reset calls in the SAME frame → deterministic 503). FULL SUITE 48/48 exit 0. e2e curl verified (load alt → 200 {loaded,scene_ready:true}; /scene/current → AltScene; res://nope.tscn → 404 SCENE_NOT_FOUND; load main back → 200). Findings: /scene/current is a GET route (POSTing 404s with error envelope, no data key — unit tests read current_scene directly); coroutine-without-await is a PARSE error in 4.7 (concurrency tested via direct start-task calls instead of racing HTTP requests). SPEC rev 11 (§5.4 + Appendix C); addon-internals.md "Scene transitions (GTD-023)".
---

# GTD-023 · POST /scene/load — scene change with readiness semantics

## Context

`/reset` (GTD-016) reloads the project main scene with full atomicity: 200 only
after the new scene is live and ready, 504 SCENE_READY_TIMEOUT on bound timeout,
503 SERVER_BUSY while a scene transition is in flight. `/scene/load` gives tests
the same contract for arbitrary scenes. SPEC §5.0 defines the shared semantics.

## Goal

`POST /scene/load {"path": "res://game/levels/level_1.tscn"}` changes the current
scene with /reset's readiness semantics.

## Scope

**In scope:**

- `TestDriverSceneHandler.load(tree, path)` — coroutine mirroring `reset()`:
  change_scene_to_file → await process_frame until current_scene changes →
  poll is_node_ready() (RESET_READINESS_MS bound → 504) → tween/orphan steps
  SKIPPED (load is a transition, not a cleanup — document the difference)
- api_handler: async dispatch path like reset (in-flight guard → 503 SERVER_BUSY,
  worker polls slot, 15s deadline)
- Error codes: 400 MISSING_PARAM, 404 SCENE_NOT_FOUND (path not loadable —
  ResourceLoader.exists check), 504 SCENE_READY_TIMEOUT, 503 SERVER_BUSY
- Response: `200 {"loaded":"<path>","scene_ready":true}`

**Out of scope:** additive scene instantiation (add_child scenes — v0.2);
PackedScene preloading cache behavior (documented in §5.0 resource-cache block).

## Technical specification

- Reuse reset's `_scene_timeout` / slot-polling machinery — extract shared
  helpers if trivial, otherwise duplicate with a comment linking both
- SCENE_NOT_FOUND is a NEW Appendix A code (404)

## Acceptance criteria

- [ ] Load a valid scene → 200, /scene/current reflects the new scene, ready
- [ ] Invalid path → 404 SCENE_NOT_FOUND; missing param → 400
- [ ] Concurrent load/reset → 503 SERVER_BUSY (in-flight guard shared)
- [ ] GdUnit suite green; full suite stays green

## Testing

- [ ] Unit: `test_scene_load.gd` — valid load, 404, 400, 503 guard
- [ ] Live e2e: curl load → /scene/current

## Documentation

- [ ] SPEC §5.0 /scene/load entry + Appendix A SCENE_NOT_FOUND (rev 9)
- [ ] addon-internals.md: scene-transition section (shared machinery note)

## Files expected to change

```
addons/godriver/handlers/scene_handler.gd
addons/godriver/api_handler.gd
scratch/spike/test/unit/test_scene_load.gd
scratch/spike/test/fixtures/ (second loadable scene)
spec/SPEC.md
docs/technical/addon-internals.md
.github/issues/023-scene-load.md
```

## References

- SPEC §5.0 (readiness semantics, resource-cache block)
- GTD-016 resolution (reset machinery)
- ROADMAP Phase 2

## Dependencies

**Blocked by:** [[dep:016]]

**Blocks:** [[dep:026]]
