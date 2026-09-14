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
  `godot --headless --path . -- --spike --self-test-a2`; prints
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
- `test_addon_server.gd` — GTD-011 addon server: arg parsing (defaults +
  `--test-driver-port`/`--test-driver-token` overrides), dormancy without
  `--test-driver` (no server child), `/health` shape (SPEC §5.1, exact
  envelope incl. `godot_version`), token auth (no/wrong → 401 UNAUTHORIZED,
  right → 200), port-conflict detection (second server on a fixed port →
  `start()` false; godottpd swallows listen errors, so the wrapper must check
  `TCPServer.is_listening()`).
- `test_api_dispatch.gd` — GTD-012 dispatch funnel: `/health` routes through
  the dispatcher queue (worker → submit → main-thread handler → 200 exact
  shape), malformed handler result (`_main_boom` → null) funnels to
  `500 INTERNAL_ERROR` with the server staying up (subsequent `/health`
  still 200), and FIFO ordering under load (3 worker threads × 50 submits
  each; per-worker sequence order preserved, 150/150 delivered).

## Addon structure (GTD-011)

`addons/godriver/` — the production addon (spike code stays in
`scratch/spike/` as reference):

- `plugin.cfg` / `plugin.gd` — EditorPlugin; `_enter_tree` registers the
  `Godriver` autoload (`*res://addons/godriver/driver.gd`). Godot 4 has no
  `remove_autoload_singleton`; removal is manual (documented in plugin.gd).
- `driver.gd` — autoload entry point. Dormant without `--test-driver`
  (user args after `--`). Static `parse_args()` (unit-testable): default port
  9090, `--test-driver-port=N` (0 = ephemeral, prints `GODRIVER_PORT=<n>`),
  `--test-driver-token=secret`. `PROCESS_MODE_ALWAYS`; applies the headless
  root-size fix (SPEC §5.10). Server start failure → `push_error` naming
  `--test-driver-port` + `quit(1)`.
- `http_server.gd` (`TestDriverServer`) — wraps vendored godottpd
  `HttpServer`, binds 127.0.0.1 only, `start() -> bool` verifies
  `is_listening()` (godottpd does not signal listen failures), exposes
  `bound_port` (actual bound port via `TCPServer.get_local_port()`).
- `api_handler.gd` (`TestDriverApi`) — route handlers + dispatch funnel;
  `SPEC_VERSION "0.1"`; token auth scans headers case-insensitively for
  `Authorization: Bearer <token>` (godottpd stores headers verbatim, mixed
  case possible). Empty configured token = auth disabled.

## Handler map + dispatch funnel (GTD-012)

The spike dispatcher moved into the addon as
`addons/godriver/dispatcher.gd` (`class_name TestDriverDispatcher`; the
dev project's `Dispatcher` autoload points at the same file, and
`driver.gd` instantiates its own child instance when active).

Request flow (every route, no exceptions):

```
godottpd worker thread
  → TestDriverApi.dispatch(handler_name, req, res)   [worker thread]
      auth check (thread-safe string scan)
      _extract_args() → plain-data Dictionary (strings/numbers only)
  → TestDriverDispatcher.submit(Callable(api, "_main_" + name).bind(args))
  → main thread _process drain → _main_<name>(args) -> {code, body}
  → res.json(code, body)                             [worker thread]
```

- **Handler registration map** — `TestDriverApi.routes`:
  `path -> {http_method: handler_name}`. `TestDriverServer.register_routes()`
  (public; re-callable for tests) wraps each entry so the handler executes
  through the queue. Adding an endpoint = add a `_main_<name>` method + a
  `routes` entry + an `_extract_args` case. Never touch SceneTree state
  outside `_main_*`.
- **Error funnel** — a `_main_*` handler that crashes (script error aborts
  the function → null result) or returns anything but
  `{code: int, body: Dictionary}` gets a `500 INTERNAL_ERROR` envelope; the
  dispatcher still posts the semaphore and keeps draining, so the server
  stays up. `_main_boom` is a permanent test hook returning null.
- **Thread rule** — godottpd objects (`HttpRequest`/`HttpResponse`) never
  cross the queue; only plain data extracted on the worker thread does.

Run the addon: `godot --headless --path . -- --test-driver` →
`[godriver] listening on http://127.0.0.1:9090`; `curl
http://127.0.0.1:9090/health` → SPEC §5.1 envelope. The spike server gates on
`--spike` instead, so spike and addon never fight over port 9090.

## A4 findings (feeds SPEC §6.1 validation)

- Long-poll frame targets must be **relative** to the current frame count —
  the counter runs from engine startup, so absolute targets are already in
  the past and the wait returns instantly.
- Awaiting an already-emitted `request_completed` deadlocks the check; when
  completion may precede the await, capture results via connected lambdas.
- `HTTPRequest` nodes freeze under a paused tree unless they (or an ancestor)
  run with `PROCESS_MODE_ALWAYS` — the test client must set this explicitly
  when testing paused-state endpoints.

## Node read endpoints (GTD-013)

- Route: raw regex ^/node/(?<npath>.+?)[/#?]?$ (godottpd compiles paths starting with ^ verbatim; named groups via equest.query_match.get_string()). Required patching upstream egister_router (left(0) → left(1), see godottpd VENDORED.md) — the raw-regex feature was unreachable before.
- _main_node splits the captured path at the LAST /property/: trailing segment → property read, otherwise node info. Edge case: a node named property as second-to-last segment is ambiguous — prefer test_id queries.
- TestDriverNodeHandler.resolve() MUST build an absolute NodePath ("/" + path): relative oot/... from the tree root looks for a child named oot and always 404s.
- TestDriverSerializer (addons/godriver/serializer.gd) is the canonical §4 implementation; handlers never inline-serialize.
- Suite: scratch/spike/test/unit/test_node_endpoints.gd (info shape, §4 round-trips, UNSUPPORTED_TYPE, error codes).
- GdUnit gotchas: failure messages diff-render strings with <...> markers (decoration, not corruption); helpers must not be named _get (Object virtual collision).

## test_id + group endpoints (GTD-014)

- Routes: plain `/node` (query form, handler `node_query`) and `/nodes` (handler `nodes`). The raw-regex `/node/<path>` route requires `/node/` + ≥1 char, so the two forms never collide.
- godottpd `_extract_query_params` AUTO-CONVERTS numeric query values (`test_id=123` → int 123) — `_extract_args` must `str()` every query value or numeric test_ids break.
- `find_by_test_id`: whole-tree DFS on the main thread (dispatcher), 200 `{test_id, path}` / 404 `TEST_ID_NOT_FOUND` / 409 `AMBIGUOUS_TEST_ID` with `details.matches` (SPEC §7 error-on-ambiguity).
- `list_group`: `get_tree().get_nodes_in_group()`, paginated (`limit` 1..1000 → else 400 `TYPE_MISMATCH` with `details.expected: "1..1000"`, `offset` clamped ≥ 0), `meta.total` = pre-pagination count, empty group = 200 (§7 exemption).
- limit/offset arrive as int/float/string depending on query text — coerce defensively in `_main_nodes`.
- Suite: scratch/spike/test/unit/test_testid_group_endpoints.gd (resolution semantics, numeric test_id coercion, pagination boundaries, error codes).
- GdUnit gotcha: the suite NODE persists across tests in a suite — fixtures added in `before_test` accumulate (group counts multiplied by run count). Free the previous fixture at the top of `before_test` (`queue_free` + one `process_frame`).

## Scene/state/inputmap reads (GTD-015)

- Routes: `/scene/current`, `/input/map`, `/state` (handlers in `addons/godriver/handlers/{scene_handler,input_handler,state_handler}.gd`).
- `/scene/current`: `{scene: scene_file_path, node: absolute path}`; 500 `INTERNAL_ERROR` when `tree.current_scene` is null — **GdUnit runs WITHOUT the project main scene**, so the unit test asserts the 500 branch; the 200 shape is verified e2e.
- `/input/map`: per-type event summaries (key → keycode/physical_keycode/device; mouse_button/joypad_button → button_index/device; joypad_motion → axis/axis_value/device; other → `{type}` only); snake-cased type via "InputEvent" prefix strip; device constants per §6 (keyboard 16, mouse 32, emulation -1 on 4.7).
- `/state`: reads project setting `godriver/state_autoload` (default "GameState"); resolves `/root/<name>`; values = properties with `PROPERTY_USAGE_SCRIPT_VARIABLE` in `get_property_list()` (engine built-ins excluded), serialized via TestDriverSerializer; 409 `STATE_AUTOLOAD_MISSING` with a details.hint naming the setting.
- Test gotchas: the state fixture must be added to `get_tree().root` directly (handler resolves `/root/<name>`), removed in `after_test`; GDScript has NO `bool(x)` constructor — `assert_bool(x)` takes the Variant directly.

## Atomic /reset (GTD-016)

- `/reset` is ASYNC and bypasses the sync dispatcher funnel: the worker submits a fast
  sync start-task (`_start_reset`) that launches the reset coroutine on the main thread,
  then polls a Mutex-guarded slot (bounded 15s > the 5s readiness bound). A crashed
  coroutine cannot hang the worker — the poll deadline fires → 500. Serialization guard:
  `_reset_in_flight` → 503 SERVER_BUSY for concurrent resets.
- Orphan sweep allowlist: current scene + ProjectSettings autoload/* + `godriver_keep`
  meta (escape hatch for test harnesses under /root) + engine auto-named `@`-prefixed
  nodes. The `@` rule is load-bearing: GdUnit's runner node is `/root/@Node@N` — sweeping
  it kills the test suite mid-run (found the hard way: suite hung with no report).
- State autoload reset: fresh `script.new()` instance → copy properties with
  `PROPERTY_USAGE_SCRIPT_VARIABLE` (NOT `& STORAGE` — plain non-exported vars lack
  STORAGE and would be skipped; same filter as TestDriverStateHandler.read_state).
- Engine-verified correction (SPEC rev 8): `is_node_ready()` is true once
  NOTIFICATION_READY dispatches — BEFORE a suspended `_ready()` concludes. A scene whose
  `_ready()` awaits forever still yields 200; the 504 bound is defensive only (scene
  never appears / engine hang). Games with async init MUST expose a readiness signal.
- godottpd `get_body_parsed()` needs a JSON content-type; `_dispatch_reset` falls back to
  `JSON.parse_string(req.body)` for header-less clients. Watch PowerShell quoting when
  curl-ing JSON bodies (use `--data-binary '{"..."}'` single-quoted).
- Suite: scratch/spike/test/unit/test_reset_isolation.gd (isolation: orphan/tween/
  time_scale/pause/state; async-ready caveat; tween modes). Cross-suite note: suites run
  alphabetically — test_reset_isolation loads the main scene, so later suites cannot
  assume `current_scene == null` (test_scene_state_inputmap frees it explicitly now).

## Input injection pipeline (GTD-020)

`POST /input/click` graduates the Spike B routing into `TestDriverInputHandler`
(static, main-thread via the dispatcher funnel):

- **Target resolution** (`resolve_target`): exactly one of `path` / `test_id`;
  test_id reuses GTD-014's whole-tree scan (`_scan_test_id`) raw — 404
  TEST_ID_NOT_FOUND / 409 AMBIGUOUS_TEST_ID with `details.matches`.
- **Routing** (engine-source verified, viewport.cpp/base_button.cpp):
  - Root-viewport Controls: motion + press + release direct to the owning
    viewport `push_input(ev, true)`; coords = `get_global_rect()` center
    (already viewport-canvas space — the affine_inverse mapping applies only
    from WINDOW coordinates).
  - SubViewportContainer-embedded: hover motion through the ROOT viewport at
    window coords (`container.get_global_transform_with_canvas() *
    (sub.get_final_transform() * (sub_pos * stretch_shrink))`), press/release
    direct to the owning viewport (mouse-button delivery needs no
    mouse_in_viewport — gui_find_control runs unconditionally).
  - Standalone SubViewport: `notify_mouse_entered()` before the motion.
- **Hover gate**: BaseButton::on_action_event requires `status.hovering` for
  mouse presses; hovering is set ONLY by NOTIFICATION_MOUSE_ENTER from the
  viewport hover walk (godot#89757).
- **Timing**: 200 = injected only; effects land next engine tick; auto-wait is
  client-side (GTD-026).

Test gotcha: the headless root Window is 64x64 — the shipped driver fixes
`root.size` at startup, but the dormant GdUnit autoload does not, so
`test_input_click.gd` sets `root.size` from project settings in `before_test`.
Suite: `test_input_click.gd` (4 tests: root click, subviewport click, test_id
click, error codes).

## Keyboard pipeline (GTD-021)

`POST /input/type` and `POST /input/key` (SPEC §5.3, rev 10).

**Typing** (`/input/type`): targeted path only — resolve Control, `grab_focus()`,
then one pressed+released `InputEventKey` (unicode set) per character via the
owning viewport `push_input(local=true)`. Never `Input.parse_input_event`
(typing needs a focused Control; the targeted path works headless).

**Keys** (`/input/key`): resolution order = InputMap action name first (first
`InputEventKey` of `action_get_events`), then `KEY_*` constant via the
GENERATED map `addons/godriver/handlers/key_map.gd` (192 entries).

Key findings:
- **ClassDB does NOT expose `@GlobalScope` constants** (`class_get_integer_constant_list("@GlobalScope")` errors "Cannot get class"), and `Expression` cannot resolve global enum constants either ("self can't be used because instance is null", even with a base instance). A GDScript lambda CAN reference `KEY_ENTER` directly — so the map is a generated `static var MAP := { "KEY_A": KEY_A, ... }` dictionary, parse-time checked (a stale entry fails the import loudly).
- The map was generated from `core/os/keyboard.h` (enum Key) of the pinned Godot source: C++ members are unprefixed (`ESCAPE`, `ENTER`); the binding adds `KEY_`. Exceptions already prefixed in source: `KEY_0`..`KEY_9`, `KEY_DELETE`. `KEY_SPECIAL` is internal (excluded). `KEY_CMD_OR_CTRL` is platform-conditional and NOT declared in GDScript on Windows (excluded — regenerate check catches it).
- **Global key form**: `Input.parse_input_event(press)` + `parse(release)` + `Input.flush_buffered_events()` — press and release land in the SAME frame, so held state (`Input.is_action_pressed`) is never observable. `Input.is_action_just_pressed` IS observable for the remainder of that frame; a probe node later in tree order than the dispatcher samples it in `_process` (test fixture `action_probe.gd`).
- Targeted key form (optional `path`/`test_id`): grab_focus + owning-viewport push — `ui_accept` on a focused Button fires `pressed` headless.
- GdUnit gotchas reused: JSON ints arrive as floats (`assert_float(...).is_equal(5.0)`); `TestDriverServer.setup()` returns void (do not assign).

## Version compat shims (GTD-022)

`addons/godriver/compat.gd` (TestDriverCompat) centralizes engine-version
handling so input endpoints behave identically on 4.3–4.7:

- `HAS_DEVICE_IDS` — runtime detection via `"DEVICE_ID_KEYBOARD" in InputEvent`
  (GH-116274 added the constants in 4.7).
- `device_id_keyboard()` / `device_id_mouse()` / `device_id_emulation()` —
  16 / 32 / -1 on 4.7+, 0 fallback on older engines (SPEC §6 device matrix).
- `apply_startup_settings()` — sets
  `Input.ignore_joypad_on_unfocused_application = false` (guarded by an
  `in Input` check) so synthetic joypad events process in headless/unfocused
  CI runs. Called from driver.gd `_ready` when the addon activates.

All injected events stamp `device` through compat (`_make_mouse_button`,
`_resolve_key`); `/input/map` reporting reads the events' own device fields,
so it stays consistent by construction.

## Scene transitions (GTD-023)

`POST /scene/load` (SPEC §5.4, rev 11) mirrors `/reset`'s readiness contract:
`change_scene_to_file` → await `process_frame` until `current_scene` changes →
poll `is_node_ready()` (5s bound → 504). Tween-kill and orphan-sweep steps are
SKIPPED (load is a transition, not a cleanup — /reset owns isolation).

- Async dispatch machinery duplicated from `_dispatch_reset` with a comment
  linking both (slot + Mutex polling, 15s worker bound). The in-flight guard
  (`_reset_in_flight`) is SHARED: a load and a reset must never interleave.
- `404 SCENE_NOT_FOUND` via `ResourceLoader.exists(path, "PackedScene")` —
  the type filter rejects non-scene resources (e.g. `project.godot`).
- Test gotcha: `/scene/current` is a GET route — POSTing to it 404s with an
  error envelope (no `data` key); unit tests read `get_tree().current_scene`
  directly instead.
- Concurrency-guard test pattern: call the main-thread start-tasks
  (`_start_scene_load` / `_start_reset`) back-to-back in the SAME frame —
  the first suspends at its first await holding the guard, the second
  deterministically returns 503.

## Asset inventory (GTD-024)

`GET /assets/loaded` (SPEC §5.9a, rev 12). DECISION GATE: Godot 4.7 exposes
NO public API to enumerate all loaded resources —
`ResourceLoader.list_handled_resources()` does not exist (verified against
the full 4.7.2 ClassDB method table). The endpoint therefore reports:

- `count` — engine-wide live resource count via
  `Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)` (usable for
  before/after leak assertions)
- `resources` — DRIVER-TRACKED inventory only: `TestDriverAssetsHandler.track()`
  is called by scene_handler after successful `/scene/load` (source
  "scene_load") and `/reset` (source "reset") transitions; static array,
  paginated limit 1..1000 / offset with `meta.total`

Full engine-wide inventory is deferred until Godot ships an enumeration API.

## UI layout inspection (GTD-025)

`GET /ui/layout/<path>` (SPEC §5.1, rev 13). Snapshot: `get_global_rect()`
bounds as flat Rect2 {x,y,w,h} (viewport-canvas coords — GTD-005 invariant;
offset-transform-aware on 4.7+), visibility, anchors (anchor_*/offset_* flat
floats), pivot, rotation, scale, mouse_filter. `?depth=N` recursion (max 16)
appends child Control layouts under `children` (non-Control children skipped).
Targeting reuses TestDriverInputHandler.resolve_target (path XOR test_id).

Routing: plain "/ui/layout" (test_id query) + raw-regex
"^/ui/layout/(?<npath>.+?)[/#?]?$" both map to the ui_layout handler;
_main_ui_layout translates the npath group into the "path" arg.

Gotcha: the recursive layout() returns the data Dictionary directly (NOT the
funnel shape) — the first draft wrongly indexed entry["body"]["data"].
