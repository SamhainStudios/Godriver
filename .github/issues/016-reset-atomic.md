---
title: GTD-016 · /reset (atomic)
labels: area/addon, type/feature, priority/P0, agent-ready, size/S
milestone: v0.1
phase: 1
depends: 015
resolution: DONE 2026-09-10 — atomic /reset per §5.0, 33/33 GdUnit green + e2e curl verified. Files: addons/godriver/handlers/scene_handler.gd (reset coroutine: time_scale/pause → state-autoload reset via fresh script.new() copy → change_scene_to_file(main_scene from ProjectSettings, NOT reload_current_scene) → await process_frame until current_scene changes → poll is_node_ready() (5s bound → 504 SCENE_READY_TIMEOUT) → tweens per tween_mode kill|await (await = wait until get_processed_tweens empty or 5s, then kill leftovers) → orphan sweep queue_free-only → Input.flush_buffered_events(); 409 STATE_AUTOLOAD_MISSING when state autoload missing — reset still proceeds per SPEC); addons/godriver/api_handler.gd (_dispatch_reset: ASYNC dispatch — sync start-task launches the coroutine, worker polls a Mutex-guarded slot bounded 15s so a crashed coroutine can't hang the worker; _reset_in_flight guard → 503 SERVER_BUSY; tween_mode validation → 400 TYPE_MISMATCH; get_body_parsed needs JSON content-type → raw-body JSON.parse_string fallback). Suite scratch/spike/test/unit/test_reset_isolation.gd (3 tests: full isolation — orphan freed, tween killed, time_scale 1.0, unpaused, scene Main, state score 99→42, all while paused; async-ready caveat; tween modes) + fixture blocking_scene.{gd,tscn} (_ready awaits a never-firing signal). KEY FINDINGS: (1) ENGINE-VERIFIED SPEC CORRECTION (rev 8): is_node_ready() is true once NOTIFICATION_READY dispatches, BEFORE a suspended _ready() concludes — a scene whose _ready awaits forever yields 200, so the 504 is defensive-only (scene never appears/engine hang) and games with async init MUST expose a readiness signal; the brief's "504 tested with a scene whose _ready blocks" premise was engine-wrong — test now documents the caveat instead; (2) orphan sweep MUST skip engine auto-named @-prefixed nodes — GdUnit's runner is /root/@Node@N and sweeping it killed the suite (hang, no report); added godriver_keep meta escape hatch used by the test; (3) state reset filter = PROPERTY_USAGE_SCRIPT_VARIABLE only (plain vars lack STORAGE); (4) cross-suite ordering: test_reset_isolation loads the main scene → test_scene_state_inputmap's no-scene test now frees current_scene explicitly; (5) PowerShell curl quoting mangles JSON bodies — use --data-binary single-quoted. e2e: reset completes (scene/current → Main reloaded), invalid tween_mode → 400 TYPE_MISMATCH, 409 STATE_AUTOLOAD_MISSING is SPEC-correct for the dev project (no GameState autoload; reset proceeds). SPEC §5.0 verified + rev 8 entry; async-_ready guidance in addon-internals.md.
---

# GTD-016 · `/reset` (atomic)

## Context

`/reset` is scenario isolation — the single most correctness-critical endpoint (SPEC §5.0, hardened across three review rounds).

## Goal

Atomic reset: 200 resolves only after the new scene is live and ready; full teardown of tweens, orphans, watchers, determinism state.

## Scope

**In scope:**

- Full §5.0 sequence: reload main scene → reset state autoload → clear signal watchers → restore `time_scale`/pause → kill active tweens (`get_processed_tweens()`) → orphan sweep of `/root` children (`queue_free()` only, allowlist: main scene + driver autoload + ProjectSettings autoloads + internal debug nodes) → `Input.flush_buffered_events()`
- Readiness: `change_scene_to_file` → await `process_frame` until `current_scene` changes → poll `is_node_ready()`; bounded ~5s; timeout → `504 SCENE_READY_TIMEOUT`
- Optional `tween_mode: "kill"|"await"` (default kill)

**Out of scope:**

- ResourceLoader cache eviction (no public API — documented out-of-scope, SPEC §5.0; fixture in GTD-007)

## Technical specification

- Orphan sweep uses `queue_free()` never `free()` (deferred teardown — SPEC §5.0).
- Async-`_ready()` caveat documented: `is_node_ready()` true before async init concludes; games with async init SHOULD expose a readiness signal (SPEC §5.0).

## Acceptance criteria

- [ ] Automated isolation test: orphan node under `/root` freed, active `SceneTree.create_tween()` killed, `Engine.time_scale` back to 1.0, scene back to main — all verified post-reset
- [ ] 200 only after new scene `is_node_ready()`; readiness timeout → `504 SCENE_READY_TIMEOUT`
- [ ] Reset works while paused (dispatcher `PROCESS_MODE_ALWAYS`)
- [ ] Signal watchers cleared (no stale watcher fires after reset)

## Testing

- [ ] Self-tests: the isolation test above is automated (PLAN Acceptance Criteria); 504 path tested with a scene whose `_ready` blocks.

## Documentation

- [ ] SPEC §5.0 verified against implementation; async-`_ready()` guidance in `docs/technical/addon-internals.md`.

## Files expected to change

```
addons/godriver/handlers/scene_handler.gd   # reset logic
```

## References

- SPEC §5.0, §3 (504)
- PLAN §Acceptance Criteria (isolation test)
- ROADMAP Phase 1

## Dependencies

**Blocked by:** [[dep:015]]

**Blocks:** [[dep:023]] [[dep:030]] (watchers cleared by reset)
