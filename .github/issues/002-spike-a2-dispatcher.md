---
title: GTD-002 · Spike A2: main-thread dispatcher task queue
labels: area/addon, type/spike, priority/P0, agent-ready, size/S
milestone: v0.1
phase: 0
depends: 001
resolution: DONE (2026-09-10) — dispatcher.gd (Mutex+Semaphore queue, PROCESS_MODE_ALWAYS, inline path for main-thread callers, drain-site assert via OS.get_thread_caller_id/_main_id); wired as autoload + /scene/current route in spike_server.gd; self-test scratch/spike/tests/spike_a2_check.gd → SPIKE_A2_OK exit 0 (HTTP worker round trip, main-thread assert, paused drain, 140 frames/20 reqs). API note: Godot 4.4 has no Thread.get_caller_id()/Thread.wait() — use OS.get_thread_caller_id()/OS.get_main_thread_id() and wait_to_finish(). Deadlock documented: main thread must never block in wait_to_finish() while a worker is inside submit() — poll is_alive() across frames instead. Threading model drafted in docs/technical/addon-internals.md.
---

# GTD-002 · Spike A2: main-thread dispatcher task queue

## Context

godottpd handles requests on worker threads; Godot's SceneTree/node APIs are not thread-safe. Every node-touching call must marshal onto the main thread via a thread-safe task queue (PLAN Constraints).

## Goal

A Mutex + per-request-Semaphore task queue that executes SceneTree queries on the main thread without blocking the game loop.

## Scope

**In scope:**

- `dispatcher.gd`: `submit(callable) -> result` API — worker thread submits, main thread drains in `_process`, worker blocks on its Semaphore until the result is ready
- Dispatcher autoload runs with `process_mode = PROCESS_MODE_ALWAYS` (else `/dev/pause` freezes the queue — PLAN Constraints)
- Debug assertion that handlers execute on the main thread

**Out of scope:**

- TCP-level thread safety (GTD-003), concurrency limits (GTD-004)

## Technical specification

- Queue: `Mutex`-guarded array of `{callable, semaphore, result}` records; `_process` drains all pending, sets results, posts semaphores.
- Rationale for Mutex+Semaphore over `call_deferred`: workers need the *return value* synchronously; deferred calls cannot pass results back.

## Acceptance criteria

- [ ] A worker-thread request that reads `get_tree().current_scene` returns the correct value
- [ ] Debug assert confirms handler ran on main thread (`Thread.get_caller_id()` matches main)
- [ ] Game loop unblocked: FPS ≥ 55 while 10 requests/s are served
- [ ] Dispatcher still drains while `get_tree().paused = true` (PROCESS_MODE_ALWAYS)

## Testing

- [ ] `scratch/spike/tests/spike_a2_check.gd`: spawns a Thread, submits a scene query, asserts result + main-thread execution, prints SPIKE_A2_OK.

## Documentation

- [ ] Threading model section drafted for `docs/technical/addon-internals.md`.

## Files expected to change

```
scratch/spike/scripts/dispatcher.gd
scratch/spike/tests/spike_a2_check.gd
```

## References

- PLAN §Constraints (dispatch rule), §Sprint 0 Spike A
- SPEC §6 (timing)
- ROADMAP Phase 0

## Dependencies

**Blocked by:** [[dep:001]]

**Blocks:** [[dep:004]] [[dep:005]] [[dep:007]] [[dep:012]]
