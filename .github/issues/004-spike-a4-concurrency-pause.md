---
title: GTD-004 · Spike A4: concurrency + paused-dispatch validation
labels: area/addon, type/spike, priority/P0, agent-ready, size/S
milestone: v0.1
phase: 0
depends: 002, 003
resolution: DONE (2026-09-10) — spike_server.gd: /wait/long long-poll route (relative frame target, 5s timeout) with Mutex-guarded blocked-wait counter + 503 SERVER_BUSY over cap 8; /dev/pause POST (dispatcher-marshaled); /node?path= existence check (query-param form — spike router only matches single segments); /health now reports blocked_waits; SpikeServer PROCESS_MODE_ALWAYS. Check scratch/spike/tests/spike_a4_check.gd → SPIKE_A4_OK exit 0: 3 rapid /health in 104ms behind a blocked long-poll (no starvation); 9th concurrent long-poll got 503 SERVER_BUSY; /node 200 while paused + 404 for missing node; blocked_waits back to 0 (no leak). Findings: (1) long-poll targets must be RELATIVE to current frame count (counter runs from startup); (2) awaiting an already-emitted request_completed deadlocks — capture via connected lambdas when completion may precede the await; (3) HTTPRequest nodes freeze under paused trees unless PROCESS_MODE_ALWAYS (check node + its HTTPRequests set ALWAYS). Feeds SPEC §6.1 validation note.
---

# GTD-004 · Spike A4: concurrency + paused-dispatch validation

## Context

SPEC §6.1 bounds long-polling with a `max_blocked_waits` cap (503 beyond it); the dispatcher must keep serving while the game is paused (`PROCESS_MODE_ALWAYS`). Both behaviors must be proven, not assumed.

## Goal

Prove ≥4 simultaneous connections with one blocked long-poll do not starve others, and the dispatcher serves while paused.

## Scope

**In scope:**

- A `/signal/wait`-style long-poll route (blocks up to timeout) to create a blocked connection
- `max_blocked_waits` counter + `503 SERVER_BUSY` beyond cap
- Paused-dispatch check: `POST /dev/pause {"enabled": true}` then `GET /node/<path>` → 200

**Out of scope:**

- Real signal endpoints (GTD-030); production routes (Phase 1)

## Technical specification

- Blocked-wait accounting: increment on long-poll start, decrement on completion/timeout; over cap → immediate `503 SERVER_BUSY` (SPEC §6.1, cap default 8).
- Paused-dispatch works because the dispatcher runs `PROCESS_MODE_ALWAYS` (validated in GTD-002); this spike proves it end-to-end through HTTP.

## Acceptance criteria

- [ ] 4 concurrent clients: 1 blocked long-poll + 3 rapid `/health` — the 3 all answer within 500 ms
- [ ] `max_blocked_waits + 1` concurrent long-polls → the last gets `503 SERVER_BUSY`
- [ ] With the tree paused, `GET /node/<path>` returns 200 while physics is frozen
- [ ] Blocked-wait counter never leaks (returns to 0 after all waits finish/timeout)

## Testing

- [ ] `scratch/spike/tests/spike_a4_check.gd`: scripted concurrent HTTPRequest clients; asserts ordering, 503 cap, paused 200; prints SPIKE_A4_OK.

## Documentation

- [ ] Findings recorded in Resolution (feeds SPEC §6.1 validation note).

## Files expected to change

```
scratch/spike/scripts/spike_server.gd   # long-poll route + wait counter
scratch/spike/tests/spike_a4_check.gd
```

## References

- SPEC §6.1 (concurrency contract)
- PLAN §Sprint 0 Spike A (paused-dispatch resilience)
- ROADMAP Phase 0

## Dependencies

**Blocked by:** [[dep:002]] [[dep:003]]

**Blocks:** [[dep:011]]
