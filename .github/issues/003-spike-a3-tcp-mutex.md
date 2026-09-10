---
title: GTD-003 · Spike A3: StreamPeerTCP thread-safety patch
labels: area/addon, type/spike, priority/P0, agent-ready, size/S
milestone: v0.1
phase: 0
depends: 001
resolution: DONE (2026-09-10) — per-client Mutex patch in addons/godottpd (http_server.gd: _peer_locks + _lock_for(), guarded main-thread reads in _process/_remove_disconnected_clients, client_lock handed to worker; http_response.gd: send_raw/send_partial wrapped in one critical section, null-safe for standalone use). Stress test scratch/spike/tests/spike_a3_stress.gd (10 threads × 1000 raw-socket GETs, main loop pumping): 10000/10000 byte-exact 200s → SPIKE_A3_OK exit 0. Both files logged in VENDORED.md deviation table with rationale; patch isolated to the two files.
---

# GTD-003 · Spike A3: StreamPeerTCP thread-safety patch

## Context

Vendored godottpd writes responses from worker threads while the main thread calls `poll()`/`get_status()` on the same `StreamPeerTCP` objects — unsynchronized access is a corruption/crash hazard (PLAN Constraints).

## Goal

A per-client mutex patched into the vendored tree, proven under concurrent stress.

## Scope

**In scope:**

- Per-client `Mutex` guarding all `StreamPeerTCP` reads/writes in the vendored godottpd
- Stress test: concurrent main-thread `poll()` + worker-thread `send()`
- Every deviation from upstream documented in `VENDORED.md` (pinned commit + reason)

**Out of scope:**

- Rewriting godottpd's threading model (GTD-004 covers concurrency limits)

## Technical specification

- Patch shape: wrap each peer's `put_data`/`get_data`/`poll` call sites with `mutex.lock()`/`unlock()` (or a small `MutexedPeer` wrapper) — minimal diff, documented per file in `VENDORED.md`.
- Rationale for per-client (not global) mutex: a global lock would serialize all responses and reintroduce head-of-line blocking.

## Acceptance criteria

- [ ] 10,000 mixed requests (parallel clients + main-thread poll) complete with zero corrupted responses or engine errors
- [ ] `VENDORED.md` lists every patched file with the reason
- [ ] Patch is isolated (no unrelated upstream edits)

## Testing

- [ ] `scratch/spike/tests/spike_a3_stress.gd`: N worker threads hammering `/health` while the game runs; asserts all 200s and byte-exact bodies; prints SPIKE_A3_OK.

## Documentation

- [ ] `VENDORED.md` deviation log filled.

## Files expected to change

```
addons/godottpd/**                   # mutex patch
addons/godottpd/VENDORED.md          # deviation log
scratch/spike/tests/spike_a3_stress.gd
```

## References

- PLAN §Constraints (StreamPeerTCP rule), §Sprint 0 Spike A
- ROADMAP Phase 0

## Dependencies

**Blocked by:** [[dep:001]]

**Blocks:** [[dep:004]]
