---
title: GTD-012 · Dispatcher wired into the addon
labels: area/addon, type/feature, priority/P0, agent-ready, size/S
milestone: v0.1
phase: 1
depends: 011
resolution: DONE 2026-09-10 — dispatcher moved into the addon as addons/godriver/dispatcher.gd (class_name TestDriverDispatcher; dev project's Dispatcher autoload now points at this file, spike copy deleted; driver.gd instantiates its own child instance when active — shipped games only have the addon). api_handler.gd rewritten: routes map (path → {method: handler_name}), dispatch() worker-thread entry (auth scan → _extract_args plain-data Dictionary → dispatcher.submit(Callable(api, "_main_"+name).bind(args)) → funnel), _main_* handlers run on main thread and return {code, body}; _main_health returns SPEC §5.1 envelope; _main_boom = permanent test hook returning null. Error funnel: crashed handler (script error → null) or malformed result → 500 INTERNAL_ERROR envelope; dispatcher still posts the semaphore and keeps draining → server stays up. http_server.gd: setup(port, token, dispatcher=null) (own dispatcher when none passed), public register_routes() wrapping every route entry through api.dispatch. Thread rule enforced: godottpd objects never cross the queue, only plain data. GdUnit suite scratch/spike/test/unit/test_api_dispatch.gd (3 tests): /health routes through dispatcher (200 exact shape), crash funnel 500 + server stays up (subsequent /health 200), FIFO ordering under load (3 threads × 50 submits, per-worker order preserved, 150/150). Full suite 20/20 green exit 0. End-to-end: `-- --test-driver` → curl /health 200 exact envelope through the new dispatch path; spike self-test-a2 green with Dispatcher autoload pointing at the addon file. Debugging findings: (1) test helper named `_get` collided with Object's virtual `_get(StringName)` → parse error "function signature doesn't match the parent" — renamed to `_http_get`; (2) GDScript runtime errors abort only the errored function (returning null to the caller), NOT the dispatcher's drain loop — this is what makes the funnel safe without try/catch. Docs: addon-internals.md "Handler map + dispatch funnel (GTD-012)" section (request-flow diagram, handler contract, thread rule) + test_api_dispatch suite entry.
---

# GTD-012 · Dispatcher wired into the addon

## Context

The Phase-0 dispatcher (GTD-002) is spike-grade; the addon needs it as the single path from HTTP worker threads to SceneTree access (PLAN Constraints).

## Goal

All addon handlers execute through the main-thread task queue, with unit tests proving main-thread execution.

## Scope

**In scope:**

- Move `dispatcher.gd` into `addons/godriver/`; `api_handler.gd` routes every request through `submit()`
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
addons/godriver/dispatcher.gd
addons/godriver/api_handler.gd
```

## References

- PLAN §Constraints, §File Structure
- ROADMAP Phase 1

## Dependencies

**Blocked by:** [[dep:011]] [[dep:007]]

**Blocks:** [[dep:013]]
