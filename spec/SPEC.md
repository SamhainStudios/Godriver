# Godot Test Driver — HTTP API Specification

Version: 0.1 (draft, rev 6)
Status: Sprint 1 deliverable — §1–§4, §6–§9 decided; §5 endpoint reference filled during Sprint 1
Scope: The language-neutral contract. Every client (JS, Python, Go, C#)
       implements against this document and nothing else.

---

## 1. Base Conventions

- **Transport**: HTTP/1.1 over TCP. Server runs inside the game process.
- **Host binding**: `127.0.0.1` only. The server never binds to `0.0.0.0`.
- **Base URL**: `http://127.0.0.1:9090`
- **Port override**: `--test-driver-port=N` (CLI user arg) or project setting `godot_test_driver/port`.
- **Port collisions**: 9090 is also the default runtime port of tugcantopaloglu/godot-mcp's interaction server and Smalldy/godot-bridge. If either addon is installed in the same project, override via `--test-driver-port=N`.
- **Ephemeral port**: `--test-driver-port=0` → OS-assigned; actual port printed to stdout as `GODRIVER_PORT=<n>` for client discovery.
- **Activation**: server dormant unless `--test-driver` is present in `OS.get_cmdline_user_args()`. Dormant = zero listeners, zero per-frame cost.
- **Token (optional)**: `--test-driver-token=<secret>` → every request must carry `Authorization: Bearer <secret>`; missing/wrong → `401 UNAUTHORIZED`. No token flag → no auth.
- **Content-Type**: `application/json; charset=utf-8` for all requests and responses. Bodies are UTF-8 JSON.
- **Spec versioning**: this document follows SemVer. Clients pin a version; additive changes bump minor, breaking changes bump major (Appendix C).

## 2. Response Envelope

Success (every endpoint, every 2xx):

```json
{ "ok": true, "data": { } }
```

Error (every endpoint, every 4xx/5xx):

```json
{ "ok": false, "error": { "code": "UNKNOWN_KEY", "message": "human-readable", "details": { } } }
```

- `code` is a stable machine-readable string (Appendix A). Never repurposed.
- `details` is optional; carries alternatives (valid keys, matching paths, expected/actual types).
- `data` is absent on errors. `data: null` on success means "succeeded, nothing to return" — distinct from an error. Endpoints that return `data: null` on success: `POST /reset` (returns `data` with `reloaded_scene` — NOT null), `POST /dev/seed`, `POST /dev/time_scale`, `POST /dev/pause`, `POST /dev/save/load`, `POST /signal/watch`, `POST /input/*` (fire-and-forget). All `GET` endpoints always return a populated `data` object.
- Idempotency: all `GET`s are safe to retry. `/input/*` POSTs are NOT idempotent (retry = duplicate input). `/state/set` and `/dev/*` are idempotent (last-write-wins).

## 3. Status Code Contract

| Code | Meaning | When it fires |
| ---- | ------- | ------------- |
| 200  | OK      | request handled; see envelope |
| 400  | Bad request | malformed JSON, unknown key, type mismatch, unsupported Variant type |
| 401  | Unauthorized | token configured but missing/incorrect |
| 404  | Not found | node path / test_id / scene / property does not exist |
| 409  | Conflict | state autoload missing, ambiguous test_id |
| 503  | Server busy | concurrent blocked-wait limit exceeded |
| 504  | Gateway timeout | `/reset` scene-readiness wait exceeded its bound (engine hang or async-loading scene) |
| 500  | Internal | unhandled server error (bug) |

- Rule: node not found → `404 NODE_NOT_FOUND`; malformed path syntax → `400 BAD_PATH`; node exists but property missing → `404 PROPERTY_NOT_FOUND`.
- Rule: state-autoload unknown key → `400 UNKNOWN_KEY` with valid keys in `details`.

## 4. JSON ↔ Godot Variant Mapping

**⚠ Divergence-prone. Be pedantic. These shapes are frozen; never change them.**

| Godot type    | JSON shape            | Notes / edge cases |
| ------------- | --------------------- | ------------------ |
| null          | `null`                | Distinguishable from missing key: property absent → `404 PROPERTY_NOT_FOUND`; property present with null → `200 {"value": null}`. As a **write** target, null is type-dependent (§8): allowed for `Object`/`Resource`-typed and untyped (`Variant`) properties — the idiomatic clear; rejected (`400 NULL_NOT_ALLOWED`) for value types (int/float/bool/String/Vector*/Color/NodePath) |
| bool          | `true` / `false`      | |
| int           | number                | 64-bit; JS clients: precision guaranteed only to 2^53 |
| float         | number                | NaN/Inf serialize as strings `"NaN"`, `"Infinity"`, `"-Infinity"` (JSON has no literals) |
| String        | string                | |
| StringName    | string                | no distinction on the wire |
| NodePath      | string                | serialized verbatim: `/root/...` absolute, `res://...` resource, relative stays relative — no conversion. **Known engine limitation (Godot 4.7, godot#116104)**: binary serialization of `NodePath` is not byte-deterministic (padding bytes from uninitialized memory). Round-trip guarantees hold at the **semantic** level, not the byte level — clients must not hash/compare raw serialized bytes. |
| Object/Node   | string (node path)    | absolute path from `/root` (e.g. `/root/Main/UI/Button`). Never a live reference. NOT round-trippable: writing an object value → `400 UNSUPPORTED_TYPE` |
| Array         | array                 | typed arrays (`Array[int]`) serialize as plain arrays — typed-ness is lost on read and not restored on write |
| Dictionary    | object                | non-string keys stringified (`3` → `"3"`) — lossy, documented |
| Vector2       | `{"x":..,"y":..}`     | object shape, frozen (not arrays) |
| Vector3       | `{"x":..,"y":..,"z":..}` | |
| Vector4       | `{"x":..,"y":..,"z":..,"w":..}` | |
| Color         | `{"r":..,"g":..,"b":..,"a":..}` | 0–1 floats |
| Vector2i/3i/4i | `{"x":..,...}`        | integer components, same object shapes as the float vectors |
| Rect2          | `{"x":..,"y":..,"w":..,"h":..}` | flat wire shape (brevity); required by `/ui/layout` |
| Rect2i         | `{"x":..,"y":..,"w":..,"h":..}` | integer components |
| Quaternion     | `{"x":..,"y":..,"z":..,"w":..}` | explicit component names — prevents XYZW/WXYZ ordering bugs in clients |
| Basis          | `{"x":{"x":..,"y":..,"z":..},"y":{...},"z":{...}}` | column vectors as named objects |
| Transform2D    | `{"x":{"x":..,"y":..},"y":{...},"origin":{"x":..,"y":..}}` | basis columns + origin, all named objects |
| Transform3D    | `{"basis":{"x":{...},"y":{...},"z":{...}},"origin":{"x":..,"y":..,"z":..}}` | basis columns + origin, all named objects |
| AABB           | `{"position":{...},"size":{...}}` | Vector3 components |
| Plane          | `{"normal":{...},"d":..}` | |
| Callable/Signal | —                   | **unsupported in v0.1** → `400 UNSUPPORTED_TYPE` |

- **Round-trip guarantee**: read → write → read is lossless for all supported types (modulo documented losses: typed arrays, non-string dict keys).
- **Unsupported types**: reject with `400 UNSUPPORTED_TYPE`. Never silently coerce.
- `var_to_str()`/`str_to_var()` are NOT the wire format (this is a JSON contract; Object types don't round-trip through them). They MAY be used internally for human-readable error `details` only.

## 5. Endpoint Reference

### 5.0 Lifecycle

#### `POST /reset`

Resets the game to a clean baseline for scenario isolation.

- Params: `{"tween_mode": "kill" | "await"}` (optional; default `"kill"`)
- Actions (in order, dispatched to the main thread):
  1. Resolve all pending blocked `/signal/wait`s immediately with `{"signaled": false, "reset": true}` (never leave them hanging for the 30s timeout)
  2. Disconnect all active signal watchers
  3. Reset `Engine.time_scale` to `1.0` and `get_tree().paused` to `false`
  4. Reset the state autoload to its initial property values (autoloads persist across scene changes — a scene reload alone does NOT reset them)
  5. Load the main scene via `change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))` — NOT `reload_current_scene()`, which reloads whatever scene is current after `/scene/load`
  6. Handle tweens per `tween_mode`: `"kill"` (default) — iterate `get_tree().get_processed_tweens()` and `kill()` each (tweens created via `SceneTree.create_tween()` are bound to the tree, NOT the scene, and survive `change_scene_to_file`; callbacks would leak into the new scenario). `"await"` — wait for signal-bound tweens (created via 4.7's `Tween.tween_await(signal)`) to complete before proceeding; use only when tween completion is part of the fixture semantics. A reset must never hang by default, so `"kill"` is the default.
  7. Sweep orphan nodes: `queue_free()` (NEVER `free()` — deferred teardown avoids destroying nodes while pending callables/signals are still in the frame's call queue) every direct child of `/root` NOT on the allowlist: the main scene instance, the test driver autoload, all autoloads registered in `ProjectSettings` (`autoload/*`), and internal Godot debug nodes attached to `/root` in debug builds
  8. Flush the input queue: `Input.flush_buffered_events()` — discard injected-but-unprocessed input from the previous scenario
- Out-of-scope (documented limitation): audio bus layouts, OS clipboard, and singletons created outside the state contract are NOT reset by `/reset`; tests must not rely on cross-scenario audio/clipboard state.
- **Resource-cache out-of-scope (⚠ cross-scenario pollution vector)**: `/reset` does NOT evict the `ResourceLoader` memory cache — Godot provides no public API to clear it wholesale, and cached entries persist across scene changes while refcount > 0 (`CACHE_MODE_REUSE` is the load default). Consequence: if a test mutates a disk-backed `.tres` (e.g. via `/state/set` with a `res://` target), a later `/reset` + scene reload returns the **mutated** in-memory resource, not the on-disk original. Rules:
  - Tests that mutate Resource targets MUST call `Resource.duplicate()` first and mutate the copy, or accept that the mutation persists for the rest of the session.
  - Restoring an on-disk original over a mutated cache entry requires `take_over_path()` on a fresh load — documented as an advanced fixture pattern, not automated by `/reset`.
  - Covered by a dedicated self-test fixture (Sprint 0: `.tres` cache isolation across resets).
- Response: `{"ok": true, "data": {"reloaded_scene": "res://Main.tscn", "scene_ready": true}}`
- **Atomicity contract**: `/reset` resolves `200` only after the new scene is live and ready — the driver calls `change_scene_to_file`, then awaits `process_frame` until `get_tree().current_scene` changes, then awaits the new scene's readiness (poll `is_node_ready()` rather than awaiting `ready`, which may already have fired by the time the driver observes the scene change). The readiness wait is bounded (default ~5s); **on timeout the response is `504 SCENE_READY_TIMEOUT`** — a scene that isn't ready after the bound is an abnormal condition (engine hang or a scene whose `_ready()` defers initialization asynchronously), and returning success-shaped data would mask it. Tests fail immediately instead of asserting against a half-loaded tree. Clients no longer need a follow-up `/wait/frames` before asserting.
- **Async-initialization caveat**: `is_node_ready()` returns `true` as soon as `_ready()` has *started and returned synchronously* — a scene that kicks off async work inside `_ready()` (e.g. `await get_tree().create_timer(...)`, deferred sub-resource loading) reports ready before that work concludes. `/reset` cannot detect this (there is no engine-level "fully initialized" signal). Games with async init SHOULD expose a readiness signal testable via `/signal/wait`; document this in client docs.
- Status codes: `200`, `409 STATE_AUTOLOAD_MISSING` (reset proceeds without state step), `504 SCENE_READY_TIMEOUT`, `500 INTERNAL`

For each endpoint:

- Method + path
- Path / query / body params (name, type, required, default)
- Response schema
- Status codes it can return
- Copy-pasteable `curl` example
- One-line timing note (sync vs fire-and-forget)

Sections:
- 5.0 Lifecycle (`/reset`)
- 5.1 Health & metadata (`/health` — returns `godot_version` (e.g. `"4.7.2"`) and `spec_version` for client compatibility checks; `/scene/current`, `/state`, `/input/map`, `/assets/loaded`, `/ui/layout/<path>` — layout bounds use `get_global_rect()` and are offset-transform-aware on 4.7+ via `Control.offset_transform_*`)
- 5.2 Node queries (`/node/<path>`, `/node?test_id=`, `/nodes?group=` — **paginated**: `?limit=100&offset=0`, defaults `limit=100` max `1000`; response carries `meta.total` so clients can page through large scenes without OOM/timeouts, `/node/<path>/property/<name>`)
- 5.3 Input (`/input/click`, `/input/type`, `/input/key`, `/input/drag`, `/input/gamepad`)
- 5.4 Scene (`/scene/load`)
- 5.5 Signals (`/signal/watch`, `/signal/poll`, `/signal/wait`)
- 5.6 Assertions (`/assert/visible`, `/assert/enabled`, `/assert/property`)
- 5.7 Waits (`/wait`, `/wait/frames` — implementation note: `/wait/frames` awaits `get_tree().process_frame` N times; NEVER `Timer`s, `SceneTreeTimer`s, or thread sleeps, which are subject to `time_scale`/pause and would break the wait's own semantics. `process_frame` is also the pause-safe choice: the signal keeps ticking while `get_tree().paused = true` (the dispatcher runs with `PROCESS_MODE_ALWAYS`), whereas reliance on `physics_frame` under pause is not guaranteed across engine versions — frame-wait operations MUST advance via `process_frame` only)
- 5.8 State (`/state/set`, `/state/schema`) — **⚠ see §8**
- 5.9 Determinism (`/dev/seed`, `/dev/time_scale`, `/dev/pause`, `/dev/save/load`)
- 5.10 Screenshots (`/screenshot/capture`, `/screenshot/region`) — **⚠ requires an active rendering context; see §5.10 note**

### 5.10 Screenshots — rendering-context requirement

`--headless` routes to `RendererDummy` and disables ALL rendering code: `ViewportTexture.get_image()` returns null/black and screenshots are **impossible**, not merely inconsistent. Therefore:

- `/screenshot/*` requests while running with `--headless` → `400 HEADLESS_RENDERING_DISABLED` (never a blank PNG, never an engine assertion)
- Headless detection: `DisplayServer.get_name() == "headless"`
- Visual test pipelines REQUIRE a virtual display: `xvfb-run --auto-servernum godot --rendering-driver opengl3` (software GL / llvmpipe) or SwiftShader/lavapipe
- **Platform scope for v0.1: visual regression is Linux/Windows-only.** `xvfb` is an X11 utility and does not exist on macOS; there is no documented macOS headless-rendering path for screenshot capture. macOS headless rendering (e.g. via private `CGVirtualDisplay` APIs) is an open question deferred to v0.2+ — no workaround is documented because none is reliable.
- **HDR capture is NOT supported for visual regression.** Godot 4.7's HDR output is a display/presentation feature, not a pixel-diff feature: HDR EXR/PQ data is incompatible with `pixelmatch`'s SDR PNG pipeline and produces meaningless diffs. Baselines MUST be captured with HDR output disabled (SDR). `/screenshot/*` requests that ask for HDR capture (`color_image`/EXR output) → `400 HDR_NOT_SUPPORTED`.
- **Driver parity rule**: baselines MUST be captured with the same rendering method/driver as CI — a Vulkan-GPU baseline will not diff clean against llvmpipe
- **Headless layout defense**: on startup under `--headless`, the driver explicitly sets `get_tree().root.size` from the `display/window/size/viewport_width/height` project settings (DisplayServer returns dummy values headless; this guarantees `/ui/layout` bounds evaluate against the intended resolution). Validated in CI.

## 6. Timing Guarantees

**⚠ Anti-heisenbug clause. Every input endpoint restates this.**

- Input endpoints inject events and return immediately. Injection routing:
  1. Targeted requests (click/type/drag with `test_id`/`path`): the driver resolves the node's owning `Viewport` and injects via `Viewport.push_input(event)` — this reaches nodes inside embedded `SubViewport`s (which never receive OS-level input automatically) and **works under `--headless`** (see below).
  2. Global events with no target (`/input/key` without target, `/input/gamepad`): fall back to `Input.parse_input_event`, **followed immediately by `Input.flush_buffered_events()`** — confirmed in the godot#73557 thread as the supported workaround: manual flushing delivers buffered events headless AND updates action state (`Input.is_action_just_pressed` / `get_vector` work). **Scope of the flush**: it drains the OS event queue into `_input()` and updates `Input` action state, but handlers in `_physics_process` / `_unhandled_input` still run on their next engine tick — the flush is delivery, not effect. The client-side 1-frame auto-wait (below) remains mandatory.
- **Headless input support**: `Input.parse_input_event` is a **no-op under `--headless`** (godotengine/godot#73557 — DisplayServerHeadless never flushes buffered events). Because targeted routing uses `Viewport.push_input` and the fallback flushes manually, `/input/*` WORKS under `--headless` (unlike `/screenshot/*`). Validated end-to-end in Sprint 0 Spike B.
- **Rejected alternative**: `--display-driver mock` (DisplayServerMock) is NOT a viable headless-input workaround — the mock driver is registered only by the test-runner binary (`tests/test_main.cpp`), not by `main.cpp`, so standard editor/release binaries and export templates cannot use it. Do not document it as an option.
- Known caveat: pushing `InputEventMouseMotion` into a viewport requires that viewport to have received `NOTIFICATION_VP_MOUSE_ENTER` at least once (godot#89757, regression fixed post-4.3-dev); the driver sends an enter notification before the first motion injection.
- **Device IDs (Godot 4.7 breaking change, GH-116274)**: keyboard/mouse device IDs changed from `0` to `InputEvent.DEVICE_ID_KEYBOARD` (16) / `InputEvent.DEVICE_ID_MOUSE` (32) in 4.7 — some joypads may use `0`. Injected events MUST set `device` explicitly to the matching constant (on 4.3–4.6, where the constants don't exist, device stays `0`). Games that check `event.device == 0` to identify keyboard/mouse will misbehave on 4.7 regardless of the driver — that is an engine-level breaking change, documented here so test authors understand failures.
- **Joypad focus setting**: on startup the driver sets `Input.ignore_joypad_on_unfocused_application = false` (4.7+; no-op on older versions) so injected gamepad input is processed even when the game window is unfocused in CI.
- **Signal thread-safety invariant**: all signal `connect`/`disconnect` calls (signal watchers, `/reset` teardown) happen on the **main thread only** — signal connection bookkeeping is not thread-safe (godotengine/godot#117396). Worker threads never touch signal connections directly; teardown requests are dispatched through the main-thread queue like everything else.
- **Coordinate-transform invariant (mouse events)**: before injecting a mouse event targeted at a node inside a `Viewport`, the driver transforms coordinates into that viewport's local canvas space: `local = target_viewport.get_final_transform().affine_inverse() * global_pos` (handles stretch modes `canvas_items`/`viewport`, `SubViewportContainer` scaling, camera offsets). `event.position` = local, `event.global_position` = global. Covered explicitly in Spike B.
- **200 ≠ processed.** 200 = injected into the target viewport's input pipeline.
- Correctness is the client's responsibility:
  - `POST /wait/frames` to advance frames
  - `GET /signal/wait` to block on a signal
- **Auto-wait contract (client-side)**: pre-built interaction steps wait `interaction_autowait_frames` (default **1**) internally after each injection.
  - This is *delivery* confirmation (event reached the input queue), NOT *effect* confirmation (button `pressed` emitted, handler ran, side effects propagated).
  - Games with frame-bound side effects (scene transitions, deferred state mutations) must raise this value or add explicit `Then I wait for the signal "..."` steps.
  - Configurable per client: `GODRIVER_AUTOWAIT_FRAMES` env var / World option. This is a client-library setting, not a server setting.
- Synchronous endpoints (reads, asserts): response reflects state at the **next main-loop tick** after the request arrives — the server dispatches all SceneTree access to the game's main thread, so handling happens on the following frame, not mid-request.
- Main-thread drain stall: the dispatch queue drains in `_process`; a long synchronous main-thread operation (e.g. `/scene/load` of a heavy scene, `ResourceLoader.load()` of large assets) blocks draining for its duration — concurrent requests queue behind it and may hit client timeouts. Clients SHOULD use long timeouts around `/scene/load`; threaded loading (`ResourceLoader.load_threaded_request`) is a possible future enhancement.
- Fire-and-forget endpoints: all `/input/*`.
- Default timeout for blocking endpoints: 30s (per-endpoint overrides in §5).

### 6.1 Blocking-endpoint concurrency

**⚠ Server-capacity contract. Answered explicitly:**

- `/signal/wait` blocks **only its own connection**, never the server.
- Server MUST sustain **≥4 concurrent connections** (blocked waits included). **Sprint 0 Spike A validates this against vendored godottpd**; the hand-rolled fallback must meet the same bar.
- Limit exceeded → `503 SERVER_BUSY` with `Retry-After` header. The cap applies to **concurrent blocked waits** (not to all request threads); the limit is configurable via project setting `godot_test_driver/max_blocked_waits` (default 8), and the ≥4-connection guarantee always holds.
- Clients using pipelining/keep-alive: issue blocking calls on a dedicated connection (standard HTTP connection pooling handles this).
- **Client-side pool sizing (JS client)**: long-polling holds connections open for up to the endpoint timeout. The JS client MUST size its HTTP agent pool so `maxSockets ≥ max_blocked_waits` (plus headroom for non-blocking calls) — otherwise parallel CI workers starve the pool waiting for blocked waits. **Set `maxSockets` explicitly regardless of library defaults**: Node's plain `http.Agent` defaults to `Infinity`, but common tooling (custom agents, Axios instances, Undici pools) enforces default pools as low as 4–6 connections — never rely on the default. This is the mitigation until SSE streaming (v0.2) removes held connections entirely.
- Blocked waits cap at the endpoint timeout (30s default), then return `200 {"data": {"signaled": false, "timed_out": true}}` — timeout is a normal outcome, not an error.

## 7. `test_id` Resolution Rules

- Read from: node metadata key `test_id` (exact name, string value).
- Resolution scope: **whole scene tree** from `/root` (not just current scene) — deterministic and matches the user mental model.
- Match semantics: **error-on-ambiguity**. Zero matches → `404 TEST_ID_NOT_FOUND`. Multiple matches → `409 AMBIGUOUS_TEST_ID` with `details.matches: [paths]`.
- Precedence for a bare string identifier: exact node path (if it resolves) → `test_id` metadata → node name → error. Explicit prefixes force a mode: `path:/x`, `test_id:x`, `name:x`, `group:x`.
- Groups (`GET /nodes?group=`) return ALL matches — collections are exempt from ambiguity errors.

## 8. State Autoload Contract

**⚠ Divergence-prone. Coercion rules frozen here.**

- Discovery: project setting `godot_test_driver/state_autoload`, default name `GameState`. Looked up among autoloads at server start.
- **Target expansion**: `/state/set` and `/state/schema` accept an optional `"target"` param. Default (no target) = the configured state autoload. A target may be a node path (`/root/Main/InventoryManager`) or a Resource path (`res://data/player_stats.tres`). Invalid/unresolvable target → `404 TARGET_NOT_FOUND`. `409 STATE_AUTOLOAD_MISSING` applies only when no target is given and no state autoload is configured.
- **⚠ Resource-target cache semantics**: writing to a `res://` target mutates the **in-memory `ResourceLoader` cache entry**, not the disk file — and the cache persists across `/reset` (see §5.0). Mutating a disk-backed `.tres` therefore leaks across scenarios. Prefer node targets, or `duplicate()` the resource before mutation (§5.0 rules).
- Absent autoload (no target given) → `/state/set` and `/state/schema` return `409 STATE_AUTOLOAD_MISSING` with a configuration hint in `details`. All other endpoints unaffected.
- `/state/set` coercion — JSON value coerced to the **declared type of the target property**:

| Target type | Accepted JSON | Rejected |
| ----------- | ------------- | -------- |
| int         | integral number, `"3"` | `3.5` → `400 TYPE_MISMATCH` |
| float       | number, `"3.14"` | non-numeric string |
| bool        | `true`/`false`, `"true"`/`"false"` | `"1"` |
| String      | string, number, bool (stringified) | null || Vector2     | `{"x":..,"y":..}`, `[x,y]` | wrong arity |
| Color       | `{"r":..,"g":..,"b":..,"a":..}`, `"#RRGGBBAA"` | out-of-range → 400 (no clamping) |
| Array       | array (untyped) | |
| Dictionary  | object | |
| NodePath    | string | |

- `null` writes are **type-dependent**:
  - **Allowed** when the target property's declared type is nullable — `Object`, `Resource`, Variant-typed (`Variant`), or untyped properties. This is the idiomatic clear (e.g. `{"equipped_weapon": null}` unequips).
  - **Rejected** (`400 NULL_NOT_ALLOWED`) for value types — `int`, `float`, `bool`, `String`, `Vector*`, `Color`, `NodePath` — where null has no meaning and accidental clears are worse than an explicit zero-value write.
- Coercion failure → `400 TYPE_MISMATCH` with `details.expected` / `details.actual`.
- Unknown key → `400 UNKNOWN_KEY` with `details.valid_keys`.
- `GET /state/schema` response:

```json
{ "ok": true, "data": { "autoload": "GameState", "properties": [ { "name": "player_life", "type": "int", "value": 3 } ] } }
```

  (discovered via `Object.get_property_list()` on the autoload)
- Atomicity: single-key writes are atomic; multi-key bodies are applied in order with no transaction rollback (documented limitation).

## 9. Determinism Semantics

- `/dev/seed {"seed": N}` — seeds the **global RNG** (`seed(N)`).
- **Constraint (project-level)**: per-instance `RandomNumberGenerator` objects are NOT affected (Godot has no registry of them). Games using `RandomNumberGenerator.new()` internally get **no benefit** from `/dev/seed` unless refactored to route randomness through the global RNG or a seeded autoload. This is a real limitation vs frame-freeze approaches (e.g. beckett-godot-mcp's freeze/step, which pauses execution rather than seeding RNG) — for games with instance-local RNGs, prefer `/dev/pause` + `/dev/time_scale`.
- Mid-run reseeding: allowed; takes effect on next RNG use.
- `/dev/time_scale {"scale": F}` — sets `Engine.time_scale`. Affects: `Timer` nodes, `SceneTreeTimer`, `Tween`, animations, `_process` delta scaling. Does NOT affect: wall-clock (`Time.get_unix_time_from_system`), OS-level timers, real-time awaits outside the SceneTree.
- `/dev/pause {"enabled": B}` — sets `get_tree().paused`. Freezes: `_process`/`_physics_process` (per node `process_mode`), `Timer` (default), physics. Input follows each node's pause mode — UI with `PROCESS_MODE_WHEN_PAUSED` still receives input (this is how pause menus are tested).
- `/dev/save/load {"slot": "fixture1"}` — loads the save file at the conventional path `user://<slot>.save`, written by the game's own save system. Fixture convention: fixture saves are committed to the repo and copied into `user://` by test setup.
- Flakiness guidance: tests asserting on random content REQUIRE `/dev/seed`; tests with timers > 1s SHOULD use `/dev/time_scale`; UI assertions under pause SHOULD use `/dev/pause`.
- Engine-level determinism flags (documented CI practices; no dedicated endpoints in v0.1):
  - `--fixed-fps <fps>` CLI arg — constant frame delta, decouples processing from the host CPU clock
  - `Engine.max_fps` / `Engine.physics_ticks_per_second` — set high (e.g. 1000) headlessly to accelerate simulation
  - `RenderingServer.render_loop_enabled = false` + `RenderingServer.force_draw()` — frame-synchronized visual snapshots in non-headless CI (xvfb + software GL): disable the continuous render loop, advance logic, draw exactly once, capture

---

## Appendix A — Error Code Registry

Stable machine-readable codes. Never repurpose a code.

| Code | HTTP | Meaning |
| ---- | ---- | ------- |
| BAD_JSON | 400 | body is not valid JSON |
| BAD_PATH | 400 | node path malformed |
| UNKNOWN_KEY | 400 | state key not on autoload |
| TYPE_MISMATCH | 400 | coercion failed |
| NULL_NOT_ALLOWED | 400 | null write rejected |
| UNSUPPORTED_TYPE | 400 | Variant type not in §4 |
| TEST_ID_NOT_FOUND | 404 | no node carries this test_id |
| NODE_NOT_FOUND | 404 | path does not resolve |
| PROPERTY_NOT_FOUND | 404 | node lacks the property |
| SCENE_NOT_FOUND | 404 | scene resource missing |
| TARGET_NOT_FOUND | 404 | `/state/*` target node/resource path does not resolve |
| AMBIGUOUS_TEST_ID | 409 | multiple nodes match |
| STATE_AUTOLOAD_MISSING | 409 | no state autoload configured |
| UNAUTHORIZED | 401 | token invalid or missing |
| HEADLESS_RENDERING_DISABLED | 400 | `/screenshot/*` requested while running with `--headless` (RendererDummy active) |
| HDR_NOT_SUPPORTED | 400 | `/screenshot/*` requested HDR capture (EXR/`color_image`); visual regression is SDR-only |
| SERVER_BUSY | 503 | wait capacity exceeded |
| SCENE_READY_TIMEOUT | 504 | `/reset` scene-readiness wait exceeded its bound (~5s default); engine hang or async-initializing scene |
| INTERNAL | 500 | unhandled server error |

## Appendix B — Example Curl Session

One narrative example: health → node lookup → click → wait → assert.

```bash
curl http://127.0.0.1:9090/health
curl "http://127.0.0.1:9090/node?test_id=start_button"
curl -X POST http://127.0.0.1:9090/input/click \
     -H "Content-Type: application/json" \
     -d '{"test_id":"start_button"}'
curl -X POST http://127.0.0.1:9090/wait/frames \
     -H "Content-Type: application/json" -d '{"n": 2}'
curl -X POST http://127.0.0.1:9090/assert/visible \
     -H "Content-Type: application/json" -d '{"test_id":"main_menu"}'
```

## Appendix C — Changelog of This Spec

Breaking vs additive changes. Client implementations pin a spec version.

- **0.1 (draft)** — initial contract. §1–§4, §6–§9 decided; §5 endpoint reference = Sprint 1 work.
- **0.1 (draft, rev 2)** — added §5.0 `/reset` lifecycle endpoint; §5.10 headless rendering contract (`400 HEADLESS_RENDERING_DISABLED`, xvfb/llvmpipe CI requirement, driver-parity rule); §6 timing clarified (handling = next main-loop tick); §6.1 cap scoped to blocked waits, configurable via `godot_test_driver/max_blocked_waits`.
- **0.1 (draft, rev 3)** — §4 expanded: frozen structured shapes for Rect2/Rect2i (flat `x,y,w,h`), Transform2D/3D (named basis columns + origin), Basis, Quaternion, Vector2i/3i/4i, AABB, Plane (math types no longer rejected); §5.0 `/reset` hardened (tween kill via `get_processed_tweens()`, orphan-node sweep with autoload/debug-node allowlist using `queue_free()`, input flush); §6 input routing changed to `Viewport.push_input` (reaches SubViewports, works under `--headless` — godot#73557) with `Input.parse_input_event` fallback for global events, plus the viewport coordinate-transform invariant for mouse events; §6 documents main-thread drain stall; §5.10 headless root-size initialization; §9 documents `--fixed-fps`/FPS-acceleration/`force_draw()` CI practices.
- **0.1 (draft, rev 4)** — Godot 4.7 alignment + contract hardening: §4 NodePath footnote (binary serialization not byte-deterministic, godot#116104 — semantic round-trip only); §5.0 `/reset` gains optional `tween_mode` (`"kill"` default | `"await"` for signal-bound tweens via 4.7's `Tween.tween_await`); §5.1 `/health` returns `godot_version` + `spec_version`; §5.2 `GET /nodes?group=` paginated (`limit`/`offset`, `meta.total`); §5.10 visual regression scoped Linux/Windows-only for v0.1 (no macOS xvfb path exists — macOS headless rendering is a v0.2+ open question) and HDR capture explicitly unsupported (`400 HDR_NOT_SUPPORTED`, baselines stay SDR); §6 injected events set `device` to `InputEvent.DEVICE_ID_KEYBOARD`/`DEVICE_ID_MOUSE` on 4.7+ (GH-116274 breaking change), joypad-unfocused setting forced off, and signal connect/disconnect restricted to the main thread (godot#117396); §2 enumerates endpoints returning `data: null`.
- **0.1 (draft, rev 5)** — QA-round hardening: §6 global-event fallback now calls `Input.flush_buffered_events()` after `parse_input_event` (confirmed headless workaround for godot#73557, delivers events AND updates action state); `--display-driver mock` documented as rejected (registered only in test-runner binaries); §5.0 `/reset` atomicity — 200 resolves only after the new scene is live and ready (`is_node_ready()` polling, bounded ~5s, timeout → `200` with `scene_ready: false`); §8 null writes allowed for nullable target types (Object/Resource/Variant/untyped — idiomatic clearing), `NULL_NOT_ALLOWED` kept for value types; §8 optional `target` param on `/state/set` + `/state/schema` (node or Resource path; invalid → `404 TARGET_NOT_FOUND`, new Appendix A code); §5.7 `/wait/frames` implementation note (await `process_frame` N times, never timers/sleeps); §6.1 client-side HTTP agent pool sizing (`maxSockets ≥ max_blocked_waits`) to prevent pool starvation in parallel CI.
- **0.1 (draft, rev 6)** — edge-case hardening from sixth review: §5.0 `/reset` readiness timeout changed from `200 {scene_ready: false}` to **`504 SCENE_READY_TIMEOUT`** (new Appendix A code + §3 row) — a half-loaded tree must fail tests immediately, not mask a hang; documented async-`_ready()` caveat (`is_node_ready()` is true before async init concludes; games with async init SHOULD expose a readiness signal); §5.0 + §8 document the **ResourceLoader cache pollution vector** — `/reset` does not evict the resource cache (no public API), so mutating disk-backed `.tres` targets leaks across scenarios; rules: `duplicate()` before mutation, `take_over_path()` as advanced restore; §4 null row cross-references §8 write semantics; §5.7 pause semantics corrected — `process_frame` keeps ticking while paused (dispatcher `PROCESS_MODE_ALWAYS`), `physics_frame` reliance under pause not guaranteed, frame waits use `process_frame` only; §6 flush scope clarified (delivery into `_input()`/action state, not effect — `_physics_process`/`_unhandled_input` handlers run next tick; 1-frame auto-wait stays mandatory); §6.1 pool sizing hardened (set `maxSockets` explicitly; common tooling defaults are 4–6, never rely on defaults).
- Policy: additive changes bump minor; breaking changes bump major. Clients pin a spec version.
