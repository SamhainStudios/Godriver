# ROADMAP — Godriver

Technical schedule of record. PLAN.md stays the *why* (motivation, competitive landscape, architecture rationale); SPEC.md stays the *what* (HTTP contract); this file is the *when and in what order*. Task briefs live in `.github/issues/` as numbered files (pattern borrowed from the WrongVersion project); they are seeded to GitHub when work starts and stay readable without a login.

## Rules

- One brief, one goal. If the goal needs two sentences, split the brief.
- Sizes: **XS** ≤ half day, **S** ≤ 1–2 days. Nothing larger is scheduled; if a task grows past S, split it.
- Every task carries: acceptance criteria (observable, testable), a testing plan, and a documentation deliverable (code without docs or tests is not done).
- Decided facts cite their source (`SPEC §`, `PLAN §`); open questions name who decides.
- Each brief's front matter has a `resolution:` field — filled with the exact file/section/commit when the work lands.
- Later-phase briefs are written when the phase approaches; this file carries the full task breakdown so nothing is lost.
- Editing: edit the file here, then create/update the GitHub issue manually. No sync-back.

## Release strategy

| Release  | Phases   | Content                                                              | Usable standalone? |
| -------- | -------- | -------------------------------------------------------------------- | ------------------ |
| **v0.1** | 0, 1, 2  | Core driver: HTTP addon + plain JS client (`@godriver/core`)          | Yes — no Cucumber needed |
| **v0.2** | 3, 4     | Cucumber BDD layer, assertions, determinism, CLI + watchdog, CI matrix | Yes                |
| **v0.3** | 5        | Visual regression (`pixelmatch` + `sharp`)                            | Optional package   |
| stretch  | 6        | Drag/gamepad/Go client/editor plugin/parallel                         | Per demand         |

## Task size legend

- **XS** — ≤ half day: single endpoint, single test file, single doc section.
- **S** — 1–2 days: one coherent subsystem (endpoint group + tests + docs), or one spike with a decision gate.

---

## Phase 0 — De-risking spikes (before any formal build)

**Goal:** prove the four riskiest assumptions before Sprint 1 writes a line of product code: (A) vendored godottpd + main-thread dispatch works and is thread-safe, (B) the full stack works end-to-end including headless input, (C) `test_id` metadata lookup works, (D) the addon can test itself in CI.

| #   | Task                                                        | Size | Depends | Key acceptance criteria (full set in brief)                                                                                                                                                                                                                   |
| --- | ----------------------------------------------------------- | ---- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 000 | Scratch Godot project scaffold + vendored godottpd          | XS   | —       | `scratch/spike/` opens in Godot without errors; `addons/godottpd/` vendored with pinned commit; `VENDORED.md` records upstream URL, commit, license, deviation procedure (`PLAN Constraints`).                                                                |
| 001 | Spike A1 — `/health` served from a running game             | S    | 000     | `curl http://127.0.0.1:9090/health` returns JSON from a running game; game loop unblocked (FPS stable ≥ 55 over 10 s while serving); decision gate recorded: **vendor vs hand-roll**.                                                                          |
| 002 | Spike A2 — main-thread dispatcher task queue                | S    | 001     | Mutex + per-request Semaphore queue; SceneTree queries execute on main thread (assert `Thread.get_caller_id()` == main in debug); request completes while game renders; dispatcher runs `PROCESS_MODE_ALWAYS`.                                                |
| 003 | Spike A3 — StreamPeerTCP thread-safety patch                | S    | 001     | Per-client mutex patched into vendored tree; concurrent `poll()` (main) + `send()` (worker) stress test shows zero corruption/errors over 10k requests; every deviation from upstream documented in `VENDORED.md`.                                            |
| 004 | Spike A4 — concurrency + paused-dispatch validation         | S    | 002, 003| ≥4 simultaneous connections with one blocked `/signal/wait`-style long-poll do not starve others (SPEC §6.1); `POST /dev/pause` then `GET /node/<path>` returns 200 while physics frozen; blocked-wait cap (`max_blocked_waits`) enforced with 503.            |
| 005 | Spike B — one click step end-to-end (incl. headless)        | S    | 002     | Cucumber.js → `@godriver/core` → addon → `Viewport.push_input` → button `pressed` signal → green scenario; same scenario green under `--headless` (godot#73557 routing); click on a `Control` inside a scaled `SubViewportContainer` lands correctly (`get_final_transform().affine_inverse()`). |
| 006 | Spike C — `test_id` metadata lookup                         | XS   | 000     | `GET /node?test_id=x` resolves a node with Inspector-set metadata, zero scripts; zero matches → 404; duplicate `test_id` → 409 with matching paths (`SPEC §7`).                                                                                               |
| 007 | Addon self-test scaffold + `.tres` cache-isolation fixture  | S    | 002     | GdUnit4 (or GUT) runs headless in CI; dispatcher + serializer unit tests pass; `spec/self-tests/test_resource_cache_isolation.gd` ported and green: mutated `.tres` via `res://` target leaks through `/reset` (documented pollution vector), `duplicate()`-based mutation does not leak. |

**Phase exit gate:** all four spikes green + decision gate written (vendor confirmed or fallback chosen). No Sprint 1 work starts before this gate.

**Testing:** every spike produces a runnable script or test that stays in the repo (spikes are not throwaway). **Docs:** `VENDORED.md` (000/003), spike findings recorded in each brief's Resolution.

---

## Phase 1 — Skeleton (v0.1)

**Goal:** the addon serves the read-only core of the API from a running game, and a plain JS client can query it. No input yet.

| #   | Task                                              | Size | Depends | Key acceptance criteria                                                                                                                                                                        |
| --- | ------------------------------------------------- | ---- | ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 010 | SPEC §5 endpoint reference (read-only endpoints)  | S    | —       | Every Phase-1 endpoint documented: method, params, response schema, status codes, copy-pasteable `curl` (`PLAN SPEC requirements`). A stranger could write a client from SPEC alone.            |
| 011 | Addon structure + activation flag + `/health`     | S    | 001–004 | `addons/godriver/` structure per `PLAN File Structure`; dormant unless `--test-driver` in `OS.get_cmdline_user_args()`; `/health` returns `{status, godot_version, spec_version}`; port taken → clear error; `--test-driver-port=N` override. |
| 012 | Dispatcher wired into the addon                   | S    | 011     | All handlers dispatch through the Phase-0 task queue; unit tests prove main-thread execution; no request blocks the main loop.                                                                  |
| 013 | `/node/<path>` + `/node/<path>/property/<name>`   | S    | 012     | Node info (type, children, properties) and property read per SPEC §5; unknown node → 404 (no crash); §4 Variant shapes round-trip (property tests from scaffold).                               |
| 014 | `GET /node?test_id=x` + `GET /nodes?group=y`      | S    | 013     | Spike C logic productionized; group query paginated (`limit=100` default, max 1000, `meta.total` — SPEC §5.2); ambiguity → 409.                                                                 |
| 015 | `/scene/current` + `/state` + `/input/map`        | S    | 013     | Scene metadata, game state (paused/fps/physics_active), input actions per SPEC §5; each has a self-test.                                                                                        |
| 016 | `/reset` (atomic)                                 | S    | 015     | Full §5.0 contract: reload main scene, reset state autoload, clear watchers, restore `time_scale`/pause, kill tweens, orphan sweep (`queue_free`), flush buffered input; 200 only after new scene `is_node_ready()`; readiness timeout → `504 SCENE_READY_TIMEOUT`; automated isolation test (orphan freed, tween killed, `time_scale` 1.0). |
| 017 | `@godriver/core` skeleton (fetch wrapper)         | S    | 011     | `js/core` npm package, ES modules + JSDoc, zero runner deps; `connect(port)` verifies `/health`; typed errors mapped from the envelope; `tsc --noEmit` type-test in CI.                         |
| 018 | Smoke: Node script queries a running game         | XS   | 013–017 | A 20-line Node script performs health → node → property → scene queries against a live game; script committed under `examples/`.                                                                |

**Testing:** every endpoint gets a GdUnit4/GUT self-test (request → handler → response shape) plus one client-side integration test where the client exists. **Docs:** SPEC §5 entries land with the endpoints they describe (010 first, updated per task); `docs/technical/addon-internals.md` started at 012.

---

## Phase 2 — Input & scene (v0.1)

**Goal:** the driver can *act* on the game: click, type, keys, scene changes — with the anti-heisenbug timing contract enforced.

| #   | Task                                            | Size | Depends | Key acceptance criteria                                                                                                                                                                                                                     |
| --- | ----------------------------------------------- | ---- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 020 | `POST /input/click`                             | S    | 014     | Targeted events route via owning `Viewport.push_input` (works headless, reaches SubViewports); coordinate transform invariant (`get_final_transform().affine_inverse()`); `NOTIFICATION_VP_MOUSE_ENTER` sent before first motion (godot#89757); 200 = injected only (SPEC §6); auto-wait is client-side. |
| 021 | `POST /input/type` + `POST /input/key`          | S    | 020     | Text typing into focused control; action keys (`ui_accept`…); global events fall back to `Input.parse_input_event` + `Input.flush_buffered_events()` (headless action-state workaround); works under `--headless`.                          |
| 022 | 4.7 device-ID + joypad-focus compatibility      | XS   | 021     | Injected events set `InputEvent.DEVICE_ID_KEYBOARD`/`DEVICE_ID_MOUSE` on 4.7+ (device=0 on 4.3–4.6); `Input.ignore_joypad_on_unfocused_application = false` at startup (`PLAN Constraints`).                                                |
| 023 | `POST /scene/load`                              | S    | 016     | Scene change with readiness semantics mirroring `/reset` (504 on timeout); invalid path → 404.                                                                                                                                              |
| 024 | `GET /assets/loaded`                            | S    | 015     | Loaded resources list (path, type, vram) per SPEC §5.                                                                                                                                                                                       |
| 025 | `GET /ui/layout/<path>`                         | S    | 013     | Control tree anchors/size/position/visibility; bounds via `get_global_rect()`, offset-transform-aware on 4.7+ (SPEC §5.1).                                                                                                                   |
| 026 | JS client: input + scene methods                | S    | 017, 020–023 | `click()`, `type()`, `pressKey()`, `loadScene()` with one-frame auto-wait encoded in interaction steps (`PLAN Input Ordering`); integration tests against a live game.                                                                   |

**Testing:** input endpoints get both unit tests (event construction, transform math) and live integration tests (click actually presses a Button, headless included). **Docs:** SPEC §5 input entries; `docs/technical/addon-internals.md` gains the input-injection pipeline section.

---

## Phase 3 — Signals, assertions & determinism (v0.2)

**Goal:** the driver can *observe and wait*: signals, assertions, state injection, determinism controls. Cucumber layer starts here.

| #   | Task                                              | Size | Depends | Key acceptance criteria                                                                                                                                                                                        |
| --- | ------------------------------------------------- | ---- | ------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 030 | `/signal/watch` + `/signal/poll` + `/signal/wait` | S    | 016     | Watch/poll/wait per SPEC §5; long-poll bounded by `max_blocked_waits` (503 beyond cap); signal connect/disconnect main-thread-only (godot#117396); wait timeout → explicit error shape.                        |
| 031 | `/assert/visible|enabled|property`                | S    | 014     | Server-side assertions return pass/fail (not throw); client wraps them into auto-retrying polls.                                                                                                                |
| 032 | `/state/set` + `/state/schema` (+ `target`)       | S    | 015     | Coercion table per SPEC §8 (frozen); null writes type-dependent (nullable allowed, value types → 400 NULL_NOT_ALLOWED); optional `target` (node or `.tres` path) → 404 TARGET_NOT_FOUND; unknown key → 400 + valid keys. |
| 033 | `/dev/seed`, `/dev/time_scale`, `/dev/pause`      | S    | 015     | Global RNG seeding (limitation documented: per-instance `RandomNumberGenerator` unaffected — SPEC §9); `time_scale` affects timers/animations not wall-clock; pause freezes per pause-mode; dispatcher stays responsive while paused (Phase-0 validated). |
| 034 | JS client: waits + auto-retrying assertions       | S    | 030–032 | `waitVisible()`, `assertVisible(path, timeout=3000)` poll until deadline, 50–100ms interval (Playwright parity); no hidden sleeps; HTTP agent `maxSockets ≥ max_blocked_waits` (SPEC §6.1).                    |
| 035 | Cucumber layer: World + hooks + first steps       | S    | 034     | `js/cucumber` package: `GodotWorld`, hook order (BeforeAll→Before→After→AfterAll), first ~15 steps (navigation + interaction); `@godriver/core` stays Cucumber-free (enforced by a dependency check in CI).     |

**Testing:** signal watcher gets a race test (watch → fire → poll under load); determinism endpoints get a reproducibility test (same seed → same sequence). **Docs:** SPEC §5; `docs/technical/determinism.md`; `STEP_LIBRARY.md` generation starts at 035.

---

## Phase 4 — Polish & CI (v0.2)

**Goal:** CI-grade: watchdog, matrix, reporters, example suite, real docs.

| #   | Task                                        | Size | Depends | Key acceptance criteria                                                                                                                                                                                                                   |
| --- | ------------------------------------------- | ---- | ------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 040 | Headless validation suite                   | S    | 021     | Full endpoint sweep green under `--headless`; `/screenshot/*` → `400 HEADLESS_RENDERING_DISABLED`; `/input/*` works headless.                                                                                                              |
| 041 | `@godriver/cli` + fail-fast watchdog        | S    | 035     | CLI launches Godot, runs Cucumber, exit codes 0/1/2; watchdog: health-tick timeout (15s default) → dump stderr, kill, exit 2; catches graceful stalls AND hard crashes (process-exit detection).                                            |
| 042 | CI matrix                                   | S    | 040     | Godot 4.3 / 4.5 / 4.7 × Linux + Windows × ±headless, all green (the "4.3+ floor" claim is only true if tested); addon self-tests run in every cell.                                                                                        |
| 043 | JUnit XML reporter + exit codes             | XS   | 041     | Cucumber.js JUnit output consumed by CI; exit codes verified in CI.                                                                                                                                                                       |
| 044 | Example suite + README                      | S    | 041     | 5–10 Gherkin scenarios over a real game flow; README = 60-second pitch + quickstart; every doc example executed in CI.                                                                                                                     |
| 045 | Step library to 62 steps + STEP_LIBRARY.md  | S    | 035     | All 62 steps implemented across the 9 categories (`PLAN Step Library`); `STEP_LIBRARY.md` generated from step definitions (cannot drift); composability guide (Primitives/Compositions/Assertions) included; docs encourage Screen Objects. |

**Testing:** CI is the test. **Docs:** `docs/getting-started.md`, `docs/basic-usage.md`, `docs/advanced-usage.md`, `docs/technical/architecture.md` complete by end of phase (Diátaxis structure per PLAN Documentation).

---

## Phase 5 — Visual regression (v0.3)

**Goal:** screenshot capture + baseline diffing. Linux/Windows only; SDR-only; requires active rendering context.

| #   | Task                                        | Size | Depends | Key acceptance criteria                                                                                                                                                                    |
| --- | ------------------------------------------- | ---- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 050 | `/screenshot/capture` + `/screenshot/region`| S    | 040     | Full-viewport and node-bounds PNG; headless → `400 HEADLESS_RENDERING_DISABLED`; HDR → `400 HDR_NOT_SUPPORTED`; driver-parity requirement documented.                                       |
| 051 | `js/visual` — VisualComparator              | S    | 050     | `pixelmatch` (threshold default 1%) + `sharp`; region-of-interest; exclusion masks by `test_id` or rects (`PLAN Visual`).                                                                   |
| 052 | Baseline workflow + diff report             | S    | 051     | `UPDATE_BASELINE=true` regeneration; HTML diff report on failure; heatmap `--diff-output` debug flag; baselines git-tracked; Cucumber step `Then the screen should match baseline "..."`.    |

**Testing:** golden-image tests with known diffs; CI runs visual tests on Linux (xvfb + llvmpipe, driver parity documented). **Docs:** `docs/guides/visual-regression.md`.

---

## Phase 6 — Stretch (briefs written when approached)

Drag & drop, gamepad input, Go client, editor plugin, test recording, parallel instances. Plus the recorded v0.2+ deferrals in `PLAN §Deferred` (OpenAPI 3.1, SSE `/signal/stream`, `/perf/*`, `/input/touch`, Screen Object generator, flaky-test mode, session replay, VS Code ext, GitHub Action, macOS headless rendering). No briefs yet — each gets one when scheduled.

---

## Dependency graph

```
000 (scaffold+vendor)
  |
001 (health) ---- 003 (tcp mutex)
  |         \
002 (dispatcher) 006 (test_id)
  |    \           |
  |     004 (concurrency+pause)
  |     007 (self-test scaffold)
  |     005 (e2e click spike)
  |
== Phase exit gate ==
  |
011 (addon+health) -- 010 (SPEC §5) -- 017 (js core)
  |      \
012 (dispatcher) 013 (node) -- 014 (test_id/group) -- 015 (scene/state/inputmap) -- 016 (reset)
  |                                                                    |
  |                              020 (click) -- 021 (type/key) -- 022 (device ids)
  |                              023 (scene/load)  024 (assets)  025 (layout)
  |                                        \       |
  |                                         026 (js input/scene)
  |                                                 |
  |== v0.1 ==                                       |
030 (signals) -- 031 (assert) -- 032 (state) -- 033 (determinism)
  \                 \                \__________ 034 (js waits/assert) -- 035 (cucumber)
  |                                                              |
  |== v0.2 ==                                                    |
040 (headless sweep) -- 041 (cli+watchdog) -- 042 (matrix) -- 043 (junit) -- 044 (examples+readme)
                                                       045 (62 steps)
  |
  |== v0.3 ==
050 (screenshot) -- 051 (visual) -- 052 (baselines)
```

## Definition of done (per release)

- **v0.1:** Phase 0 gate passed; all Phase 1–2 acceptance criteria checked; addon self-tests green headless; SPEC §5 complete for shipped endpoints; `@godriver/core` published/linkable with zero runner deps.
- **v0.2:** CI matrix green (4.3/4.5/4.7 × Linux/Windows ± headless); watchdog proven against a killed process; 62-step library + generated STEP_LIBRARY.md; getting-started/basic-usage docs CI-verified.
- **v0.3:** visual suite green on Linux CI with driver parity; baselines workflow documented.

## Testing strategy (global)

- **Addon self-tests** (GdUnit4/GUT, headless): routing, dispatcher queue, §4 serializer round-trip property tests, input handlers, `/reset` isolation, `.tres` cache fixture. The addon tests itself — "who tests the tester" is answered in-repo.
- **Client integration tests**: `@godriver/core` against a live game process spawned by the test harness.
- **Docs tests**: every `curl` example and Gherkin snippet executed in CI.
- **CI matrix** is the compatibility claim's proof, not a nice-to-have.
