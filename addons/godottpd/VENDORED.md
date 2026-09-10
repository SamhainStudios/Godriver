# VENDORED — godottpd

Upstream: https://github.com/bit-garden/godottpd (MIT)
Pinned commit: `dc7b9f45efebc48c3588980926752a7a7d8c5e8d`
Vendored on: 2026-09-10
License: MIT — preserved in this tree (`LICENSE`, upstream `LICENSE.md`).

## Update procedure

1. Clone upstream, note the new commit hash.
2. Re-apply every deviation listed below (or confirm upstream fixed it and drop the patch).
3. Re-run the full spike/self-test suite (`scratch/spike/tests/`).
4. Update the pinned commit here and in the deviation log.

Review cadence: every 2 Godot minor versions; security/threading fixes within 30 days (PLAN §Constraints). Re-evaluate vendor-vs-hand-roll when Godot 5.0 nears.

## Deviations from upstream

| File | Deviation | Reason |
| ---- | --------- | ------ |
| `http_server.gd` | Added `_peer_locks` Dictionary + `_lock_for(client)` helper; `_process` wraps `poll()`/`get_status()`/`get_available_bytes()`/`get_utf8_string()` in the per-client mutex; `_remove_disconnected_clients()` guards status reads and reaps mutexes of disconnected clients; `__perform_current_request` hands `response.client_lock = _lock_for(client)` to the worker. | Upstream writes responses from worker threads while the main thread polls/reads the same `StreamPeerTCP` — unsynchronized concurrent access (corruption/crash hazard). Per-client (not global) mutex avoids serializing all responses / head-of-line blocking. Proven by `spike_a3_stress.gd`: 10,000/10,000 byte-exact responses under concurrent load. |
| `http_response.gd` | Added `client_lock: Mutex` var; `send_raw()` and `send_partial()` wrap all `put_data` calls in one critical section (lock/unlock; no-op when `client_lock` is null, preserving standalone upstream behavior). | Same threading hazard as above — worker-thread writes must be serialized against main-thread reads of the same peer. |
| `http_server.gd` | `register_router()`: `router.path.left(0)` → `left(1)` when detecting raw-regex paths. | Upstream bug: `left(0)` returns `""`, so the documented raw-regex path feature (paths starting with `^`) was unreachable — every pattern went through `_path_to_regexp`, making multi-segment parameterized routes impossible. Found while implementing GTD-013 (`^/node/<path>` routes). |

## Upstream observations (not patched)

- `http_server.gd` contains a stray empty `uhh()` function — upstream slop, harmless, left untouched.
- `bind_address` defaults to `"*"` (all interfaces). The driver always sets `"127.0.0.1"` at startup (SPEC §1: localhost-only).
- Requests are handled on a worker `Thread` per request (`_perform_current_request`), while main-thread `_process` polls the same `StreamPeerTCP` objects the worker writes responses to — the unsynchronized access GTD-003 patches with a per-client mutex.
- Handler callables receive `(HttpRequest, HttpResponse)` and return `bool` (true = handled). Router API is constructor-based: `HttpRouter.new(path, {get: Callable, post: Callable, ...})` — no longer ExpressJS-style method registration (PLAN Open Q1 note).

- Raw-regex routes: a router path starting with ^ is compiled verbatim; named capture groups are readable via request.query_match.get_string("<name>") (used by the driver for /node/<path> routes).
