---
title: GTD-001 · Spike A1: serve /health from a running game
labels: area/addon, type/spike, priority/P0, agent-ready, size/S
milestone: v0.1
phase: 0
depends: 000
resolution: Landed 2026-09-10 — `scratch/spike/scripts/spike_server.gd` (autoload, dormant without `--test-driver`); `curl http://127.0.0.1:9090/health` → 200 `{"ok":true,"data":{"status":"ok"}}` from a backgrounded headless game; self-test `-- --test-driver --self-test` → `SPIKE_A1_OK` exit 0 (60 sequential requests, 361 main-loop frames elapsed — loop not starved; windowed 10s FPS ≥55 gate deferred to manual check). Decision gate: **vendor confirmed** — godottpd current API is constructor-based routers (`HttpRouter.new(path, {get: Callable})`), handlers `(request, response) -> bool`, per-request worker Threads confirmed in source (feeds GTD-002/003). Findings in `addons/godottpd/VENDORED.md`.
---

# GTD-001 · Spike A1: serve `/health` from a running game

## Context

The single riskiest assumption in the plan is that a vendored GDScript HTTP server can run inside a live game without blocking the main loop (PLAN Open Q1). This spike proves or kills it before any product code.

## Goal

`curl http://127.0.0.1:9090/health` returns JSON from a running game whose loop stays unblocked.

## Scope

**In scope:**

- Minimal autoload starting godottpd on `127.0.0.1:9090` when `--test-driver` is in `OS.get_cmdline_user_args()`
- `GET /health` → `{"ok": true, "data": {"status": "ok"}}` (envelope per SPEC §2)
- FPS stability measurement while serving

**Out of scope:**

- Dispatcher queue (GTD-002), TCP mutex (GTD-003)

## Technical specification

- godottpd `HttpRouter` API (verify current bit-garden API surface first; PLAN notes it moved away from ExpressJS-style).
- Decision gate: **vendor vs hand-roll**. Hand-rolling HTTP/1.1 parsing is the single riskiest item in the plan; vendor is the default unless the spike fails.

## Acceptance criteria

- [ ] `curl /health` returns the envelope JSON with HTTP 200
- [ ] Game FPS ≥ 55 averaged over 10 s while serving requests
- [ ] Server dormant without `--test-driver` flag
- [ ] Decision gate written in Resolution: vendor confirmed (or fallback chosen with rationale)

## Testing

- [ ] `scratch/spike/tests/spike_a1_check.gd` (headless script): starts server, self-queries via HTTPRequest, asserts envelope, prints SPIKE_A1_OK.

## Documentation

- [ ] Resolution records godottpd API-surface findings (any drift from ExpressJS-style assumptions).

## Files expected to change

```
scratch/spike/scripts/spike_server.gd   # autoload: server bootstrap + /health route
scratch/spike/tests/spike_a1_check.gd
```

## References

- SPEC §1 (base conventions), §2 (envelope)
- PLAN §Open Questions 1, §Sprint 0 Spike A
- ROADMAP Phase 0

## Dependencies

**Blocked by:** [[dep:000]]

**Blocks:** [[dep:002]] [[dep:003]] [[dep:011]]
