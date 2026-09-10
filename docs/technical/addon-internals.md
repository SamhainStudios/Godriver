# Addon internals — threading model (draft, GTD-002)

> Working notes captured during Sprint 0 spikes. This file becomes the
> authoritative internals doc as the addon solidifies in Phase 1.

## Why a dispatcher exists

godottpd handles each HTTP request on its own worker `Thread`
(`HttpServer._perform_current_request` spawns one thread per request, tracked
in `HttpServer._threads`). Godot's SceneTree/node APIs are **not thread-safe**:
touching nodes, `get_tree()`, or any scene state from a worker thread is
undefined behavior. Therefore every node-touching operation requested over
HTTP must be marshaled onto the main thread.

## The dispatcher task queue

`Dispatcher` (autoload, `PROCESS_MODE_ALWAYS`) is a Mutex + Semaphore task
queue:

- **Worker side** — `submit(callable) -> Variant`: appends
  `{callable, semaphore, result}` to a Mutex-guarded array, then blocks on its
  private `Semaphore` until the result is posted.
- **Main side** — `_process` drains the whole queue each frame: pops each
  record, calls the callable, stores the result, posts the semaphore. A debug
  `assert(OS.get_thread_caller_id() == _main_id)` enforces the drain-site
  invariant.
- **Main-thread callers** execute inline (no queueing) to avoid self-deadlock.

### Why not `call_deferred`?

Deferred calls cannot pass a return value back to the caller. Test-driver
handlers need the *result* synchronously (the HTTP response is built from it),
so a blocking handoff is required.

### Pause resilience

The dispatcher runs with `PROCESS_MODE_ALWAYS`, so the queue keeps draining
while `get_tree().paused = true`. Without this, `/dev/pause` would freeze
every endpoint — including the one used to unpause. Verified by the A2
self-test (submit + drain while paused).

## Known deadlock pattern (do not block the main thread)

`Thread.wait_to_finish()` called from the main thread **deadlocks** if the
worker is inside `Dispatcher.submit()`: the worker waits for the main thread
to drain the queue, but the main thread is blocked in `wait_to_finish()` and
`_process` never runs. Main-thread code must poll (`while thread.is_alive():
await get_tree().process_frame`) instead of blocking. This bit the A2
self-test and is the reason the check polls across frames.

## Upstream hazard (GTD-003, DONE)

godottpd's worker threads write responses to the same `StreamPeerTCP` clients
that the main-thread `_process` polls — unsynchronized concurrent access to
the socket. Fixed by a per-client Mutex patch (GTD-003), logged as deviations
in `addons/godottpd/VENDORED.md` and proven by `spike_a3_stress.gd`
(10,000/10,000 byte-exact responses under concurrent load).

## Self-tests

- `scratch/spike/tests/spike_a2_check.gd` — run with
  `godot --headless --path . -- --test-driver --self-test-a2`; prints
  `SPIKE_A2_OK` on success. Covers: HTTP worker→dispatcher round trip,
  main-thread execution assert, paused drain, main-loop liveness under load.
- `scratch/spike/tests/spike_a3_stress.gd` — `--self-test-a3`; 10 threads ×
  1,000 raw-socket GETs, byte-exact verification → `SPIKE_A3_OK`.
- `scratch/spike/tests/spike_a4_check.gd` — `--self-test-a4`; long-poll cap
  (503 SERVER_BUSY), no starvation behind a blocked wait, paused dispatch
  end-to-end, counter-leak check → `SPIKE_A4_OK`.
- `scratch/spike/tests/spike_b_check.gd` — `--self-test-b`; click e2e:
  `/input/click` → Dispatcher → `Viewport.push_input` → `Button.pressed`,
  root-viewport button, SubViewportContainer-embedded button, 404 on missing
  node → `SPIKE_B_OK` (headless AND windowed).
- `scratch/spike/tests/spike_c_check.gd` — `--self-test-c`; `test_id`
  resolution: unique → 200, unknown → 404, duplicate → 409 AMBIGUOUS_MATCH,
  untagged node name is not a test_id → `SPIKE_C_OK`.

## Unit-test scaffold (GTD-007)

GdUnit4 v6.2.1 is vendored at `addons/gdUnit4/` (MIT, upstream
MikeSchulze/gdUnit4, tag `v6.2.1`). It runs green on the project's base
version, Godot 4.7.2 (12/12 unit tests, exit 0). Note: v6.x does **not**
compile on Godot 4.4 (GDScript parse errors in `GdUnitTestCIRunner.gd` —
v6.x requires newer type-inference); if 4.4 support is ever needed, fall
back to v5.1.1 (tag, commit `c924c7a`, declares 4.3/4.4/4.4.1 support).

Run headless:

```
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --add scratch/spike/test --ignoreHeadlessMode
```

- `--ignoreHeadlessMode` is required: the CLI tool refuses headless by default
  (its warning about UI-interaction tests does not apply to our unit tests).
- Exit code 0 = all green; 100 = test failures; 103 = headless refusal.
- XML/HTML reports land in `reports/report_N/` (gitignore candidate).

Suites (`scratch/spike/test/unit/`):

- `test_dispatcher.gd` — submit-from-thread returns the main-thread result;
  main-thread callers execute inline. Encodes the two GDScript gotchas:
  poll `while thread.is_alive()` (never `wait_to_finish()` from the main
  thread while a worker may be inside `submit()`), and lambdas capture outer
  locals **by value** (use a Dictionary to observe writes from a callable).
- `test_serializer.gd` — SPEC §4 frozen-shape round-trips
  (encode → JSON.stringify → JSON.parse → decode(target type)). Documents
  JSON fidelity semantics: ints arrive as floats (`7` → `7.0`; decode
  coerces back when the target type is int), NaN/Inf travel as strings,
  non-string dict keys are stringified, nested typed values stay encoded
  dicts unless decoded per-element, Callable/Signal unsupported.
- `test_resource_cache_isolation.gd` — .tres cache-pollution fixture (ported
  from the GUT reference in `spec/self-tests/`): mutating a loaded .tres in
  place leaks through the ResourceLoader cache (CACHE_MODE_REUSE);
  `duplicate(true)` before mutation keeps the cached copy pristine.

## A4 findings (feeds SPEC §6.1 validation)

- Long-poll frame targets must be **relative** to the current frame count —
  the counter runs from engine startup, so absolute targets are already in
  the past and the wait returns instantly.
- Awaiting an already-emitted `request_completed` deadlocks the check; when
  completion may precede the await, capture results via connected lambdas.
- `HTTPRequest` nodes freeze under a paused tree unless they (or an ancestor)
  run with `PROCESS_MODE_ALWAYS` — the test client must set this explicitly
  when testing paused-state endpoints.
