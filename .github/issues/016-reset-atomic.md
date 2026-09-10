---
title: GTD-016 · /reset (atomic)
labels: area/addon, type/feature, priority/P0, agent-ready, size/S
milestone: v0.1
phase: 1
depends: 015
resolution:
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
addons/godot-test-driver/handlers/scene_handler.gd   # reset logic
```

## References

- SPEC §5.0, §3 (504)
- PLAN §Acceptance Criteria (isolation test)
- ROADMAP Phase 1

## Dependencies

**Blocked by:** [[dep:015]]

**Blocks:** [[dep:023]] [[dep:030]] (watchers cleared by reset)
