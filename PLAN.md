# Godot UI Automation Test Driver

A lightweight, external UI test driver for Godot 4.x — a GDScript addon that exposes an HTTP REST API inside the running game, paired with a JavaScript client using Cucumber.js that orchestrates tests from the command line.

## Motivation

Automated UI testing in Godot is underdeveloped compared to web (Selenium, Playwright) and mobile (Appium) ecosystems. Several projects are tackling this, but each has trade-offs:

| Project                         | Architecture                        | Client          | Engine Mod           | Gap                                         |
| ------------------------------- | ----------------------------------- | --------------- | -------------------- | ------------------------------------------- |
| **godot-e2e**                   | GDScript addon + TCP                | Python (pytest) | None                 | Python-only, no JS/Go client                |
| **PlayGodot**                   | Custom Godot fork + native protocol | Python (async)  | Custom fork required | Heavy adoption barrier                      |
| **GodotTestDriver**             | C# integration drivers              | C#              | None                 | Requires .NET                               |
| **GdUnit4**                     | In-engine test runner               | GDScript/C#     | None                 | Inside-engine, not external driver          |
| **GUT**                         | In-engine unit tests                | GDScript        | None                 | Inside-engine, not external driver          |
| **godot-ui-automation**         | GDScript record-replay              | In-engine only  | None                 | Screenshot-only, no programmatic API        |
| **Godot Stagehand** (mrf)       | GDScript addon + Go binary (WebSocket/JSON-RPC) | JS / Go / MCP | None                 | Already ships screenshots, signal waits, JUnit XML + exit codes; binary is both standalone CLI and MCP server |
| **godot-mcp** (tugcantopaloglu) | GDScript/C# + MCP                   | TypeScript      | None                 | 157+ tools, MCP protocol; runtime server on TCP 9090 (port collision risk) |
| **godot-mcp** (hybridindie)     | GDScript addon + Python MCP         | Python          | None                 | AI-focused, not test-focused                |
| **godot-cli** (mattias800)      | Node.js TCP client (29 commands, port 9900) | JavaScript | None              | TCP protocol, not REST                      |
| **beckett-godot-mcp** (commercial) | In-editor MCP plugin             | MCP clients     | None                 | Deterministic playtesting (freeze/step-N-frames/replay) already shipped; commercial ($15), MCP-only |
| **godot-cli-control** (ClaymanTwinkle) | WebSocket bridge + reuse daemon | Python (pytest) | None              | Python-only; pytest fixtures, no BDD/Gherkin |
| **Godot Agent CLI** (tibormester) | GDScript addon + TCP/NDJSON       | Node.js         | None                 | AI/agent-oriented ("Playwright-for-Godot"), not test-focused |

### What's Missing

The external-driver field is crowded (a dozen MCP-based tools alone, most editor-control/AI-focused rather than test-focused), but no existing tool combines:

1. **HTTP/REST API** — standard, language-agnostic, debuggable with curl/Postman (competitors use TCP, WebSocket, NDJSON, JSON-RPC, or MCP)
2. **JavaScript client** — uses Cucumber.js with Gherkin `.feature` files, no extra runtime beyond Node.js (closest analog, godot-cli-control, is Python/pytest)
3. **Pure GDScript addon** — no C#/.NET, works with standard Godot builds
4. **Test-focused** — not AI/MCP-oriented, purpose-built for E2E testing

Known near-misses: Godot Stagehand (JSON-RPC, JS-friendly, already ships screenshots/signal waits/JUnit but MCP-first), beckett-godot-mcp (deterministic playtesting but commercial and MCP-only). The unclaimed niche is specifically **HTTP/REST + Gherkin/Cucumber.js external test driving**, not general external driving of Godot.

### Inspiration: Watershed Ecosystem

The [Watershed](https://github.com/Watershed-Labs/watershed) test automation ecosystem (MIT, Cucumber-based) provides patterns we adopt directly:

| Watershed Package                | Godot Equivalent                      | What We Take                                          |
| -------------------------------- | ------------------------------------- | ----------------------------------------------------- |
| `@watershed-labs/screenshot`     | `screenshot_handler.gd` + `js/visual` | Capture layer (GDScript sends PNG, JS processes)      |
| `@watershed-labs/visual`         | `js/visual`                           | `pixelmatch` + `sharp` for baseline diffing           |
| `@watershed-labs/world`          | `BaseScreen.js`                       | Lifecycle contract: init → registerCleanup → teardown |
| `@watershed-labs/hooks`          | `support/hooks.js`                    | Before/After hook execution order                     |
| `@watershed-labs/config`         | `godriver.config.js`                  | Singleton config, frozen on load                      |
| `@watershed-labs/assertions`     | `support/world.js`                    | Cucumber World with step definitions                  |
| `@watershed-labs/driver-factory` | `godriver.connect()`                  | Session management, unique ports per worker           |

**Key Watershed patterns applied:**

- **Singleton vs Class** — config/reporter are singletons; driver/network are per-scenario classes
- **Parallel safety** — worker-scoped ports (`9090 + CUCUMBER_WORKER_ID`)
- **Hook order** — BeforeAll → Before → After → AfterAll with clear responsibilities
- **Two-phase reporting** — workers write JSON, coordinator merges to final report
- **`pixelmatch` (MIT) + `sharp` (Apache 2.0)** — same battle-tested visual regression stack

## Goal

Build a **lightweight, external UI test driver for Godot 4.x** — a GDScript addon that exposes an HTTP REST API inside the running game, paired with a JavaScript client using Cucumber.js that orchestrates tests from the command line.

The system should feel like Selenium WebDriver: find elements, interact with them, assert state, run in CI. Tests are written as Gherkin `.feature` files for living documentation.

## Architecture

```
┌─────────────────────┐         HTTP/JSON        ┌──────────────────────┐
│   JS Test Runner    │ ◄─────────────────────► │   Godot Game         │
│   (Node.js + Cucumber│   localhost:9090         │   + GDScript Addon   │
│   .js)              │                          │   (HTTP server)      │
│   - reads .feature  │                          │   - scene tree access│
│   - drives game     │                          │   - input simulation │
│   - asserts results │                          │   - node queries     │
│   - reports CI      │                          │   - signal watchers  │
└─────────────────────┘                          └──────────────────────┘
```

### Singleton vs Class Pattern (from Watershed)

| Pattern       | JS Client Packages                      | Why                                               |
| ------------- | --------------------------------------- | ------------------------------------------------- |
| **Singleton** | `config.js`, `reporter.js`, `logger.js` | Shared state, must be consistent across scenarios |

| **Class** | `GodotDriver (js/core)`, `VisualComparator (js/visual)` | Per-scenario isolation, no state bleed |

```javascript
// Singleton — imported directly, never instantiated
import { config } from './config.js';

import { logger } from './logger.js';
// Class — instantiated inside the Cucumber World, once per scenario
class GodotWorld extends World {
  async init() {
    this.driver = await GodotDriver.create(config.get('port'));
    this.screenshot = new ScreenshotCapture(this.driver);
    this.visual = new VisualComparator(this.driver, config.get('visual'));
  }
}
```

### Monorepo Package Design (Language Extensibility by Construction)

Split by **language first**, then by **functionality** inside each language:

- Top level = one directory per client language: `js/` today, future `python/`, `go/`, `csharp/`
- The addon sits at top level (`addons/`) — it is the single engine-side implementation. Godot only speaks GDScript, so there is nothing to port: every language client talks to the same addon.
- Inside each language directory, packages by functionality, all mirroring the same shape: **core (HTTP client) → runner layer (Cucumber/behave/godog) → tools (visual, cli)**
- `spec/SPEC.md` sits above every language — the single language-neutral contract

| Package                              | Depends on       | Purpose                                                                                            | Port target                                                   |
| ------------------------------------ | ---------------- | -------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| `spec/SPEC.md`                       | —                | HTTP API contract (endpoints, JSON shapes, errors). Single source of truth.                        | Any language reads this                                       |
| `addons/godot-test-driver/`          | —                | Engine-side HTTP server. Single implementation, language-independent (Godot only speaks GDScript). | —                                                             |
| `js/core` → `@godriver/core`         | —                | HTTP client: nodes, input, state, waits. **No Cucumber, no test-runner deps.**                     | Python/Go/C# ports reimplement ONLY this                      |
| `js/cucumber` → `@godriver/cucumber` | core             | World, hooks, 60+ pre-built steps                                                                  | Each language has its own BDD layer (behave, godog, Reqnroll) |
| `js/visual` → `@godriver/visual`     | core             | `pixelmatch` + `sharp` baseline diffing                                                            | Port only if needed                                           |
| `js/cli` → `@godriver/cli`           | cucumber, visual | Launch Godot, run Cucumber, exit codes                                                             | Trivial per language                                          |

**Extraction rule (from Watershed):** code needed by two or more consumers goes down a level. The addon never knows Cucumber exists. Core never knows Gherkin exists.

## SPEC.md Contract Requirements

> **Status: `spec/SPEC.md` v0.1 draft EXISTS** — §1–§4, §6–§9 decided (Variant shapes frozen, state coercion table frozen, §6.1 concurrency contract set). §5 endpoint reference = Sprint 1. The spec is the authoritative document; this section remains as the requirements checklist.

`SPEC.md` is the language boundary — every future client (Python, Go, C#) is written against it and nothing else. It must be complete enough that someone could write a client **without reading the GDScript**. Required sections:

1. **Base conventions** — URL scheme (`http://127.0.0.1:9090`), activation flag (`--test-driver`), token semantics (`--test-driver-token`), `Content-Type: application/json; charset=utf-8`.
2. **Response envelope** — ONE success shape and ONE error shape used by every endpoint. Error body carries: machine-readable `code`, human `message`, and where relevant `valid` alternatives (e.g. `/state/set` unknown key → 400 with the list of valid keys).
3. **Status code contract** — what each code means and when it fires: `400` (bad input / unknown key), `404` (node/scene not found), `409` (conflict: port taken, state autoload missing, ambiguous test_id), `500` (internal).
4. **JSON ↔ Variant mapping table** — how `Vector2`, `Vector3`, `Color`, `NodePath`, `Object`, `null`, ints/floats/bools/arrays/dicts serialize and deserialize. **The section most likely to cause cross-language client divergence if left implicit — be pedantic here.**
5. **Endpoint reference** — method, path, path/query/body params with types, response schema, status codes, and a copy-pasteable `curl` per endpoint.
6. **Timing guarantees** — which endpoints are synchronous vs fire-and-forget, default timeout, and the input ordering contract (below).
7. **test_id resolution rules** — scope (whole tree vs current scene), first-match vs error-on-ambiguity, behavior on zero matches (`404`) and multiple matches (`409` with the list of matching paths).
8. **State autoload contract** — how the autoload is discovered (project setting `godot_test_driver/state_autoload`, default `GameState`), type coercion rules, unknown-key error shape, `GET /state/schema` response shape.
9. **Determinism semantics** — what `/dev/seed` seeds (global RNG via `seed()`; per-instance `RandomNumberGenerator` NOT affected unless documented), what `/dev/time_scale` affects (`Engine.time_scale`: timers, animations, physics — NOT wall-clock awaits), what `/dev/pause` freezes (physics + process per pause mode; UI input behavior per pause mode).

### Input Ordering Semantics (the anti-heisenbug clause)

`POST /input/click` returning `200` means **injected** (via the target node's `Viewport.push_input`, falling back to `Input.parse_input_event` for global events) — nothing more. It does NOT mean processed by the frame loop. The contract:

- All input endpoints inject and return immediately (fire-and-forget)
- Correctness is the client's responsibility: explicit `POST /wait/frames?n=1` or `GET /signal/wait` after injection
- SPEC states this on every input endpoint; the pre-built steps encode it (each interaction step waits one frame internally — auto-wait, Playwright-style)

Making this explicit prevents an entire class of heisenbugs where tests pass on fast machines and flake on slow ones.

### Why HTTP over TCP/WebSocket/Native Protocol

- **Debuggable**: `curl http://localhost:9090/health` — works immediately
- **Language-agnostic**: any language with HTTP client can drive tests
- **Firewall-friendly**: standard port, standard protocol
- **No custom serialization**: JSON is universal, no binary Variant format
- **godot-e2e uses raw TCP, PlayGodot uses native binary protocol** — HTTP is the unexplored middle ground

### Why JavaScript

- **JSON is native** — the HTTP addon speaks JSON, JS speaks JSON. No marshaling code.
- **Cucumber.js as test runner** — Gherkin `.feature` files + step definitions, living documentation
- **No extra runtime** — Node.js is already on every dev machine and CI system
- **Godot web export** — many Godot devs already know JS
- **npm ecosystem** — screenshot comparison, CI reporters, everything exists
- **Performance irrelevant** — bottleneck is the game process (60fps = 16ms/frame), not the client

## Features

### Phase 1 — Core Driver (MVP)

| Feature          | Description                                                                         |
| ---------------- | ----------------------------------------------------------------------------------- |
| HTTP API addon   | GDScript addon exposing REST endpoints on `localhost:9090`                          |
| Activation flag  | Dormant unless launched with `--test-driver` flag (inspired by godot-e2e's `--e2e`) |
| Node discovery   | `GET /node/<path>` — fetch node info (type, children, properties)                   |
| Property read    | `GET /node/<path>/property/<name>` — read any node property                         |
| Input simulation | `POST /input/click`, `POST /input/type`, `POST /input/key`                          |
| Scene load       | `POST /scene/load` — change to a different scene                                    |
| Health check     | `GET /health` — verify addon is running                                             |
| Reset            | `POST /reset` — reload main scene, reset state autoload, clear signal watchers, restore `time_scale`/pause (scenario isolation) |
| Scene metadata   | `GET /scene/current` — current scene name, root node, child count                   |
| Game state       | `GET /state` — paused, FPS, physics_active, scene_tree_hash                         |
| Input map        | `GET /input/map` — all configured actions, keys, deadzones                          |
| Asset manifest   | `GET /assets/loaded` — currently loaded resources (textures, sounds, scenes)        |
| Layout scan      | `GET /ui/layout/<path>` — control tree: anchors, size, position, visibility         |
| test_id lookup   | `GET /node?test_id=x` — resolve node by metadata (no scripts required)              |
| Group query      | `GET /nodes?group=y` — all nodes in a group                                         |
| State schema     | `GET /state/schema` — list valid state keys from the state autoload                 |

### Phase 2 — Assertions & Signals

| Feature            | Description                                                                       |
| ------------------ | --------------------------------------------------------------------------------- |
| Node assertions    | `POST /assert/visible`, `POST /assert/enabled`, `POST /assert/property`           |
| Signal watching    | `POST /signal/watch` — register for a signal, `GET /signal/poll` — check if fired |
| Timeout support    | `GET /signal/wait?name=X&timeout=5` — block until signal or timeout               |
| Wait for condition | `POST /wait` — poll a condition until true or timeout                             |
| Frame sync         | `POST /wait/frames?n=10` — wait N physics frames                                  |
| State injection    | `POST /state/set` — write typed values to the state autoload (convention)         |
| RNG seed           | `POST /dev/seed` — deterministic random (game testing requirement)                |
| Time scale         | `POST /dev/time_scale` — fast-forward timers/animations                           |
| Physics pause      | `POST /dev/pause` — freeze world for UI assertions                                |
| Save load          | `POST /dev/save/load` — preconditions via save file                               |

### Phase 3 — JS Client SDK

| Feature                 | Description                                                       |
| ----------------------- | ----------------------------------------------------------------- |
| JS client library       | `godriver.click(path)`, `godriver.readProperty(path, prop)`, etc. |
| Cucumber.js integration | World class + step definitions: `Given I click "path/to/button"`  |
| Custom steps            | `waitVisible(path, timeout)`, `assertText(path, expected)`        |
| Headless mode           | Run Godot game headless (`--headless` flag) with addon active     |
| CI integration          | Exit code 0 on pass, 1 on fail; JUnit XML output                  |
| CLI runner              | `npx cucumber-js features/ --require support/`                    |
| **Fail-fast watchdog**  | `@godriver/cli` health-tick timeout (default 15s): if the game stops answering `/health`, dump Godot stderr, kill the process, exit code 2 — no silent hangs in CI. Must catch BOTH failure classes: graceful stalls (main loop hangs, socket still open) AND hard engine crashes (Vulkan/OpenGL driver panics, segfaults — Godot dies without closing the socket cleanly; detect via process-exit event + unresponsive socket, not just health ticks) |

### Phase 4 — Advanced

| Feature               | Description                                                 |
| --------------------- | ----------------------------------------------------------- |
| Drag & drop           | `POST /input/drag` — simulated drag between two nodes       |
| Gamepad input         | `POST /input/gamepad` — controller button/axis simulation   |
| **Visual regression** | `POST /screenshot/capture` + SSIM comparison with baselines — **requires active rendering context; NOT available under `--headless`** (see Constraints) |
| Parallel tests        | Multiple Godot instances, each with own port                |
| Test discovery        | Auto-scan test spec files in a directory                    |
| Go client             | Single binary alternative for CI (port later if needed)     |

#### Visual Regression (Phase 4 Detail)

| Method                             | Accuracy   | Speed  | Use Case                                     |
| ---------------------------------- | ---------- | ------ | -------------------------------------------- |
| **pixelmatch** (Watershed default) | High       | Fast   | Pixel diff with tolerance threshold          |
| Region-of-interest                 | High       | Fast   | Compare specific UI element, not full screen |
| Heatmap diff                       | Debug tool | Medium | Visualize where differences are              |
| **SSIM** (structural similarity)   | High       | Medium | Perceptual similarity (optional)             |

**Stack (same as Watershed's `create-egret`):**

- **`pixelmatch`** (MIT) — pixel diffing with configurable threshold (default 1%)
- **`sharp`** (Apache 2.0) — image resize, format conversion, region cropping
- **No cloud dependency** — all diffs run locally, baselines git-tracked
- **Exclusion masks**: baseline comparison accepts an array of regions to ignore — by `test_id` (resolved to bounds at capture time) or explicit rects — for dynamic elements (timers, rotating icons, FPS counters)
- Future (not v0.1): perceptual diffing (ΔE / SSIM) if the pixelmatch threshold proves too brittle across host OSes

**Approach:**

1. `POST /screenshot/capture` — full viewport PNG via GDScript addon
2. `POST /screenshot/region` — capture specific node bounds only
3. Cucumber step: `Then the screen should match baseline "main-menu"` with `pixelmatch` threshold
4. Heatmap as `--diff-output` flag for debugging (not assertion itself)
5. Baseline images stored in `baselines/`, regenerated with `UPDATE_BASELINE=true`
6. HTML diff report generated on failure (like Watershed's `getDiffReport()`)

## Pre-built Step Library (~62 steps, target ≥80% coverage)

Users write Gherkin only; custom JS steps only for game-specific logic. Validated against the 11 real `.feature` files in `WrongVersion/test/demo/`.

**Composability guide** (ships with `STEP_LIBRARY.md`): steps are categorized as **Primitives** (click, type, wait, read — map 1:1 to endpoints), **Compositions** (press button = click + wait for signal; change scene = load + wait ready — built from primitives), and **Assertions**. The guide shows how to build custom game-specific steps from primitives, so the 62-step library reads as a toolbox, not a mandate.

| Category           | Count | Examples                                                                                                                                                                               |
| ------------------ | ----- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Navigation         | 10    | `When I press the button with test_id "start"`, `When I change to scene "Workshop"`, `When I go back to previous scene`                                                                |
| Interaction        | 12    | `When I click "path"`, `When I type "text" into "path"`, `When I press key "ui_accept"`, `When I drag from "a" to "b"`                                                                 |
| Assertions         | 10    | `Then the node "X" should exist`, `Then the element with test_id "score" should have text "100"`, `Then the node "X" should be visible`, `Then the current scene should be "Workshop"` |
| Waits              | 6     | `Then I wait for node "X" to exist`, `Then I wait for the signal "loaded"`, `Then I wait 0.5 seconds`                                                                                  |
| State verification | 8     | `Then the game should be paused`, `Then the scene "X" should be loaded`, `Then the node "X" should have property "visible" equal to true`                                              |
| State injection    | 4     | `Given the game state is:`, `Given the player has item "wrench"`, `Given the player life is 1`                                                                                         |
| Determinism        | 4     | `Given the RNG is seeded with 12345`, `Given the time scale is 5.0`, `Given the physics is paused`                                                                                     |
| Visual             | 4     | `Then the screen should match baseline "main-menu"`, `Then the region at x,y,w,h should match baseline "hud"`                                                                          |
| Preconditions      | 4     | `Given the game is running`, `Given a new game has started`, `Given the save "fixture1" is loaded`                                                                                     |

## Requirements

### Must Have

- **No C# / dotnet dependency** — pure GDScript addon
- **Godot 4.3+ compatible** (floor: 4.3; CI matrix tests 4.3 / 4.5 / 4.7 — see Constraints)
- **External control** — tests run from outside Godot, not inside
- **HTTP API** — standard REST, no custom protocols
- **Input simulation** — click, keyboard, basic mouse movement
- **Node querying** — read node tree, properties, visibility, enabled state
- **Signal observation** — detect when signals fire
- **Headless capable** — works with `--headless` for CI
- **Exit code reporting** — pass/fail reflected in process exit code
- **Activation flag** — addon dormant unless `--test-driver` flag passed

### Nice to Have

- Screenshot comparison (visual regression) — **Resolved: `pixelmatch` + `sharp`** (same as Watershed's `@watershed-labs/visual`)
- Test recording (capture user actions, replay as test spec)
- Hot reload — tests can be sent to a running game without restart
- Godot Editor plugin — run tests from within the editor UI
- Go client (port for zero-runtime CI if needed)

### Constraints

- Request handling must never block the main loop; all SceneTree access (queries, input injection, state mutation) MUST dispatch to the main thread via a thread-safe task queue (Mutex + per-request completion Semaphore, drained in `_process`)
  - The dispatcher autoload MUST run with `process_mode = PROCESS_MODE_ALWAYS` — otherwise `/dev/pause` freezes the queue and every HTTP request hangs while the game is paused
- Vendored godottpd's `StreamPeerTCP` writes (worker threads) MUST be synchronized against main-thread `poll()`/`get_status()` access (per-client mutex, patched into the vendored tree)
- **Vendoring policy (godottpd)**: review upstream `bit-garden/godottpd` every 2 Godot minor versions; patch security/threading fixes within 30 days; all deviations from upstream documented in `VENDORED.md` (pinned commit + reason per deviation). When Godot 5.0 nears, re-evaluate vendor-vs-hand-roll before the migration.
- **Self-testing strategy**: the addon tests itself — GdUnit4 (or GUT) unit tests for the HTTP server routing, dispatcher task queue, Variant serializer (§4 round-trip property tests), and input injection handlers, run headless in CI. The test driver is itself tested; "who tests the tester" is answered in-repo, not by hand-verification.
- **CI matrix**: Godot **4.3 (floor), 4.5 (middle), 4.7 (latest)** × Linux + Windows, with and without `--headless`. "4.3+ compatible" is a claim; the matrix is what makes it true.
- Addon must not interfere with game input handling
- Default port 9090, configurable via project settings
  - KNOWN COLLISIONS on 9090: tugcantopaloglu/godot-mcp's runtime interaction server and Smalldy/godot-bridge both also default to TCP 127.0.0.1:9090. Document `--test-driver-port` prominently in the README; startup should log a clear error/warning if the port is already bound
- Visual regression requires an active rendering context (virtual display: xvfb + llvmpipe, `--rendering-driver opengl3`) — strictly incompatible with `--headless` (RendererDummy disables all rendering; `ViewportTexture.get_image()` returns null). `/screenshot/*` under `--headless` → `400 HEADLESS_RENDERING_DISABLED`
- **Visual regression platform scope: Linux/Windows-only for v0.1.** `xvfb` is X11-only — there is no macOS headless-rendering path for screenshots; macOS is an open question for v0.2+ (no unreliable workaround documented)
- **Visual baselines are SDR-only.** Godot 4.7 HDR output is a display feature, not a diff feature — HDR EXR/PQ data is incompatible with pixelmatch's SDR pipeline. `/screenshot/*` rejects HDR capture requests (`400 HDR_NOT_SUPPORTED`); baselines captured with HDR output disabled
- **Godot 4.7 input compatibility**: injected events set `device` to `InputEvent.DEVICE_ID_KEYBOARD`/`DEVICE_ID_MOUSE` on 4.7+ (GH-116274 changed keyboard/mouse device IDs from 0); driver forces `Input.ignore_joypad_on_unfocused_application = false` so injected gamepad input works in unfocused CI windows
- Visual baselines MUST be captured with the same rendering method/driver as CI (driver parity) — a Vulkan-GPU baseline will not diff clean against llvmpipe
- API responses must be JSON
- Timeout on all blocking operations (default 5s)
- Client uses ES modules (no TypeScript compilation step); **type safety via JSDoc + generated `.d.ts`** — `@godriver/core` ships TypeScript definitions generated from JSDoc annotations (checked in CI via `tsc --noEmit` on a type-test file), so TS users get full types without the library taking on a build step
- Monorepo: `@godriver/core` must stay Cucumber-free — language ports reimplement only core + their own BDD layer
- `@godriver/core` API follows Playwright-style locator conventions (`driver.locator('test_id:start_button').click()`) — first-class for Vitest/Jest/Node test runner users; Cucumber is a layer on top, not a requirement
- **Auto-retrying assertions are explicit**: assertion helpers (`assertVisible(path, timeout=3000)`, etc.) poll until the deadline before throwing (Playwright-style) — no hidden sleeps, no instant-fail races; poll interval 50–100ms (Playwright parity); documented in client constraints and implemented in Sprint 3
- Pre-built Gherkin steps are building blocks, not a mandate: step-library docs MUST encourage Screen Objects (encapsulate clicks/queries/signal-waits per screen) and declarative business-language features over procedural click-scripts

## Element Identification: `test_id` via Node Metadata

The `data-test-id` equivalent in Godot is **node metadata** — set in the Inspector on any node, zero scripts.

Inspector → Node → Metadata → add `test_id = "start_button"`.

| Method                    | Script required | Use                                              |
| ------------------------- | --------------- | ------------------------------------------------ |
| **Metadata `test_id`**    | No              | Primary — stable across refactors                |
| **Groups**                | No              | Collections — `GET /nodes?group=enemies`         |
| Node name                 | No              | Quick scripts when unique                        |
| Node path                 | No              | Fallback — brittle, avoid in features            |
| ~~`@export var test_id`~~ | ~~Yes~~         | Rejected: requires a script on every tested node |

```gherkin
When I click the element with test_id "start_button"
Then the element with test_id "score" should have text "100"
```

## Screen Abstraction Pattern

Inspired by the Page Object pattern from web testing, but adapted for Godot's scene-based architecture:

| Web (Page Object)        | Godot (Screen)                   | Purpose                       |
| ------------------------ | -------------------------------- | ----------------------------- |
| `BasePage.js`            | `BaseScreen.js`                  | Core: find, click, read, wait |
| `PlayerPage.js`          | `WorkshopScreen.js`              | Domain-specific actions       |
| `DashboardPage.js`       | `MainScreen.js`                  | Scene-specific selectors      |
| CSS selectors (`By.css`) | Node paths (`/root/Main/Player`) | Element identification        |
| `driver.findElement()`   | `client.getNode()`               | Element lookup                |

**BaseScreen** provides:

- `findByTestId(id)` — resolve via `GET /node?test_id=...` (preferred)
- `getNode(path)` — get node info (type, children, properties)
- `click(path)` — simulate click at node position
- `readProperty(path, prop)` — read node property
- `waitForNode(path, timeout)` — wait for node to exist
- `waitForSignal(path, signal, timeout)` — wait for signal emission
- `getCurrentScene()` — get active scene metadata
- `getGameState()` — get paused/FPS/physics state
- `getInputMap()` — get all configured input actions
- `getLoadedAssets()` — get currently loaded resources
- `getUILayout(path)` — get control anchors/size/position

**Scene metadata endpoints** enable:

- `GET /scene/current` — verify which scene is loaded
- `GET /state` — check game is running, not paused
- `GET /input/map` — discover what actions exist before testing
- `GET /assets/loaded` — verify resource loading (textures, sounds)
- `GET /ui/layout/<path>` — check UI positioning and sizing
- Scene transitions as test preconditions (e.g., "Given the player is in the workshop")

## State Injection & Determinism

### State Injection Convention (no config, no wrapper code)

`POST /state/set` writes to the project's **state autoload** — convention over configuration:

- Addon looks for autoload named `GameState` (configurable: `godot_test_driver/state_autoload` project setting)
- Keys must match properties on that autoload; JSON values coerced to declared types (`"3"` → int, `"true"` → bool, arrays/dicts pass through)
- Unknown key → `400` with valid keys from `GET /state/schema`

```gherkin
Given the game state is:
  | key         | value      |
  | player_life | 1          |
  | items_held  | ["wrench"] |
```

Alternative precondition channel: **fixture scenes** — `POST /scene/load {"scene": "res://test/fixtures/workshop_broken.tscn"}`.

### Determinism Controls (non-negotiable for games)

| Endpoint                                   | Purpose                          |
| ------------------------------------------ | -------------------------------- |
| `POST /dev/seed {"seed": 12345}`           | Deterministic RNG                |
| `POST /dev/time_scale {"scale": 5.0}`      | Fast-forward timers/animations   |
| `POST /dev/pause {"enabled": true}`        | Freeze physics for UI assertions |
| `POST /dev/save/load {"slot": "fixture1"}` | Precondition via save file       |

Without seed control, identical runs diverge — flaky tests guaranteed. Ships in Sprint 3, not as an afterthought.

## Competitive Positioning

### vs Watershed (inspiration, not competitor)

| Aspect   | Watershed              | Godot Test Driver     |
| -------- | ---------------------- | --------------------- |
| Target   | Web/mobile/API testing | Godot game UI testing |
| Engine   | Selenium/Appium        | GDScript HTTP addon   |
| Runner   | Cucumber.js (BDD)      | Cucumber.js (BDD)     |
| Visual   | `pixelmatch` + `sharp` | Same (adopted)        |
| Protocol | WebDriver BiDi         | HTTP REST             |

**Relationship**: We adopt Watershed's patterns, World class, and visual regression stack. They are web/mobile; we are game-specific. No overlap.

### vs godot-e2e (closest competitor)

| Aspect        | godot-e2e                | Our Plan                 |
| ------------- | ------------------------ | ------------------------ |
| Protocol      | Raw TCP + JSON           | HTTP REST + JSON         |
| Client        | Python (pytest)          | JavaScript (Cucumber.js) |
| Godot version | 4.3+                     | 4.3+ (floor)             |
| Activation    | `--e2e` flag             | `--test-driver` flag     |
| Debugging     | Custom TCP client needed | `curl` works             |
| CI setup      | Python + pip + venv      | Node.js (already in CI)  |

**Our edge**: HTTP is debuggable with curl, Cucumber.js gives BDD living documentation, wider Godot compat.

### vs PlayGodot

| Aspect           | PlayGodot                  | Our Plan                 |
| ---------------- | -------------------------- | ------------------------ |
| Engine mod       | Custom Godot fork required | Standard Godot           |
| Protocol         | Native binary Variant      | HTTP REST + JSON         |
| Client           | Python (async)             | JavaScript (Cucumber.js) |
| Adoption barrier | Build custom Godot         | Copy addon folder        |

**Our edge**: No custom engine build. Standard Godot works.

### vs godot-cli / Godot Stagehand (JS-friendly peers)

| Aspect      | godot-cli / Godot Stagehand                             | Our Plan                    |
| ----------- | ------------------------------------------------------- | --------------------------- |
| Protocol    | TCP/JSON (godot-cli), WebSocket/JSON-RPC (Stagehand)    | HTTP REST                   |
| Test runner | Custom CLI / bundled runners (JUnit XML out)            | Cucumber.js (BDD)           |
| Purpose     | Agent tooling / general driving                         | E2E test automation         |
| API style   | Command-based (29 commands)                             | RESTful (resource-oriented) |

**Our edge**: HTTP is debuggable with any tool, Cucumber.js gives living documentation, REST is more standard than TCP commands or JSON-RPC. Stagehand already ships screenshots, signal waits and JUnit XML — our differentiation is the REST contract + Gherkin BDD layer, not the transport alone.

### Deferred: WebSocket/SSE event channel (v0.2 consideration)

An event-driven push channel (WebSocket/JSON-RPC, CDP/BiDi-style) would eliminate long-polling for `/signal/wait` and stream signals, frame ticks and console logs. Deferred deliberately:

- Vendored godottpd speaks HTTP/1.1 only — a WS channel means hand-rolling a server, the single riskiest item this plan avoids
- SPEC §6.1 already bounds long-polling cost (503 + configurable `max_blocked_waits` cap, validated in Spike A)
- Revisit for v0.2 only if blocked-wait telemetry shows real starvation in production use

### Deferred to v0.2+ (recorded, not specced)

Improvements identified during external review that are real but out of v0.1 scope. Recorded here so they aren't lost; each gets a spec change only when scheduled:

- **OpenAPI 3.1 YAML** alongside SPEC.md — enables generated client SDKs, request validation, mock servers. SPEC.md stays the human-readable source of truth; the YAML is derived.
- **SSE signal streaming** (`/signal/stream`) — HTTP/1.1-compatible push channel; feasibility depends on whether vendored godottpd supports chunked streaming responses (verify in Spike A before committing)
- **`/v1` URL versioning** with a deprecation policy — deferred until a second major version actually exists; premature for v0.x
- **`/perf/*` endpoints** (fps, frame_time, memory) — performance regression detection; a real gap vs GdUnit4, but out of v0.1 scope. Implementation basis when scheduled: `Performance.get_monitor()` (`TIME_FPS`, `MEMORY_STATIC`, `OBJECT_NODE_COUNT`, `RENDER_TOTAL_DRAW_CALLS_IN_FRAME`)
- **`/ui/layout3d`** — screen-space projection of 3D world-space UI; v0.1 covers Control trees only
- **`/net/*` multiplayer simulation** (latency/packet loss/bandwidth) — multiplayer testing is a distinct product surface
- **Token rotation/scopes** — v0.1's optional static bearer token is adequate for localhost CI; revisit if remote-device testing ever ships
- **`/input/touch`** (synthetic touch, incl. 4.7's built-in `VirtualJoystick` node) — VirtualJoystick reads `InputEventScreenTouch`/`ScreenDrag`, NOT joypad events, so it does NOT belong under `/input/gamepad`; a touch endpoint is the correct home, deferred as a v0.2 nicety
- **Screen Object generator** (`npx godriver generate-screen <Name>`), **flaky-test detection mode** (run scenario N times, report flake rate), **session replay** (record HTTP traffic, replay deterministically), **benchmark mode**, **VS Code extension**, **reusable GitHub Action** (`uses: godriver/action@v1`)
- **macOS headless rendering** — open question (private `CGVirtualDisplay` API or equivalent); until solved, visual regression stays Linux/Windows-only

## Acceptance Criteria

### Addon (GDScript)

- [ ] Addon registers as autoload, starts HTTP server on game launch
- [ ] Dormant unless `--test-driver` flag is passed
- [ ] `GET /health` returns `{"status": "ok", "godot_version": "4.x", "spec_version": "0.1"}`
- [ ] `GET /node/path/to/node` returns `{"type": "Button", "visible": true, "children": [...]}`
- [ ] `GET /node/path/to/node/property/text` returns `{"value": "Click Me"}`
- [ ] `POST /input/click` with `{"path": "path/to/button"}` triggers button press
- [ ] `POST /input/type` with `{"text": "hello"}` types into focused element
- [ ] `POST /input/key` with `{"key": "ui_accept"}` sends action key
- [ ] `POST /scene/load` with `{"scene": "res://scenes/main.tscn"}` loads scene
- [ ] `POST /signal/watch` with `{"path": "node", "signal": "pressed"}` registers watcher
- [ ] `GET /signal/poll` returns `{"fired": true, "args": []}` or `{"fired": false}`
- [ ] `GET /scene/current` returns `{"scene": "Main", "path": "/root/Main", "children_count": 5}`
- [ ] `GET /state` returns `{"paused": false, "fps": 60, "physics_active": true}`
- [ ] `GET /input/map` returns `{"actions": [{"name": "move_right", "keys": [D, Right], "deadzone": 0.5}]}`
- [ ] `GET /assets/loaded` returns `{"resources": [{"path": "res://icon.svg", "type": "Texture2D", "vram_kb": 12}]}`
- [ ] `GET /ui/layout/<path>` returns `{"anchors": {...}, "size": {...}, "position": {...}, "visible": true}`
- [ ] All endpoints return proper HTTP status codes (200, 400, 404, 500)
- [ ] Addon works in headless mode (`--headless --audio-driver Dummy`)
- [ ] Addon self-tests pass in CI: GdUnit4/GUT unit tests for HTTP routing, dispatcher task queue, §4 Variant serializer round-trip, input injection handlers
- [ ] No crashes when querying non-existent nodes (returns 404, not crash)
- [ ] No interference with game's own input processing
- [ ] `GET /node?test_id=x` resolves nodes by metadata without scripts
- [ ] `POST /state/set` writes typed values to the state autoload (unknown key → 400 + valid keys)
- [ ] `POST /dev/seed` makes runs reproducible

### JS Client

- [ ] `godriver.connect(port)` establishes connection, verifies health
- [ ] `godriver.click(path)` clicks a node
- [ ] `godriver.readProperty(path, prop)` returns property value
- [ ] `godriver.waitVisible(path, timeout)` polls until node visible
- [ ] `godriver.assertVisible(path)` throws if node not visible
- [ ] Cucumber World class with step definitions for all operations
- [ ] Pre-built step library (62 steps) covering navigation, interaction, assertions, waits, state, determinism, visual
- [ ] Input injection works under `--headless` (Viewport.push_input routing) and reaches nodes inside SubViewports
- [ ] `/reset` isolation: orphan node under `/root` freed, active `SceneTree.create_tween()` killed, `Engine.time_scale` back to 1.0, scene back to main scene — verified by an automated test
- [ ] `@godriver/core` has zero Cucumber dependencies (the portable contract)
- [ ] `spec/SPEC.md` complete enough to write a client without reading GDScript (envelope, status codes, Variant mapping, timing)
- [ ] Proper error handling — connection refused, timeout, 404
- [ ] Clean exit codes (0 pass, 1 fail, 2 error)
- [ ] `npx cucumber-js features/ --require support/` discovers and runs tests

### Integration

- [ ] Example test (Cucumber) that loads a scene, clicks a button, asserts result
- [ ] README with setup instructions, API reference, example test run
- [ ] Works on Windows (primary), Linux (secondary)
- [ ] CI pipeline example (GitHub Actions) with headless Godot

## Roadmap

**Release strategy (scope management):** v0.1 = Sprint 0–2 (core driver — useful standalone via the plain JS client, no Cucumber required) → v0.2 = Sprint 3–4 (Cucumber BDD layer) → v0.3 = Sprint 5 (visual regression). Cucumber and Visual are optional packages; the core driver ships and delivers value without them.

### Sprint 0 — De-risking Spikes (before Week 1)

The riskiest assumptions get proven before any formal build:

- [ ] **Spike A — HTTP server & Dispatch**: vendor `godottpd` (MIT, current fork `bit-garden/godottpd`) into a scratch Godot project, serve `/health` from a running game, hit it with `curl`. Success: JSON response, game loop unblocked (stable FPS). Implement the **Mutex/Semaphore main-thread task queue** and validate that SceneTree queries execute on the main thread. Validate **StreamPeerTCP thread safety** between main-thread `poll()` and worker-thread `send()` (patch vendored tree with a per-client mutex). Also validate **concurrency**: ≥4 simultaneous connections with one blocked `/signal/wait` must not starve others (SPEC §6.1). Also validate **paused dispatch resilience**: `POST /dev/pause {"enabled": true}` then `GET /node/<path>` must return `200` while physics/game logic is frozen (dispatcher runs `PROCESS_MODE_ALWAYS`). **Decision gate: vendor GodotTPD vs hand-roll** — hand-rolling HTTP/1.1 parsing is the single riskiest item in this plan.
- [ ] **Spike B — World contract**: `GodotWorld` + ONE step (`When I click "..."`) end-to-end: Cucumber.js → `@godriver/core` → addon → input simulation → assertion. Success: one green scenario. Validates the integration before any of the 62 steps are written. **Also validates headless input**: the same click scenario must pass under `--headless` via `Viewport.push_input` routing (godot#73557 — `Input.parse_input_event` is a no-op headless), including the **coordinate-transform invariant**: a click on a `Control` inside a scaled `SubViewportContainer` (stretch mode `canvas_items`) must land correctly via `get_final_transform().affine_inverse()` mapping.
- [ ] **Spike C — test_id lookup**: metadata scan + `GET /node?test_id=x` on a sample scene. Success: resolves without scripts.
- [ ] **Addon self-test scaffold**: GdUnit4 (or GUT) project wired into CI, running headless — starts with dispatcher/serializer unit tests, grows per sprint. The addon is tested by its own tests, not by hand. Includes the **`.tres` cache-isolation fixture**: mutate a disk-backed `.tres` via `/state/set` with a `res://` target → `/reset` → assert the in-memory cache still returns the mutated value (documenting the §5.0 pollution vector), then assert `duplicate()`-based mutation does NOT leak. Reference implementation captured at `spec/self-tests/test_resource_cache_isolation.gd` (GUT-based; convert to GdUnit4 assertions when the scaffold is wired); requires fixture `res://test/fixtures/mutable_stat_resource.tres` (minimal Resource with int `base_health`)

### Sprint 1 — Skeleton (Week 1)

- [ ] Fill §5 endpoint reference in `spec/SPEC.md` (v0.1 draft exists — §1–§4, §6–§9 already decided)
- [ ] Create GDScript addon structure under `addons/godot-test-driver/`
- [ ] Implement HTTP server on vendored godottpd + main-thread dispatcher task queue (works on 4.3+)
- [ ] `--test-driver` activation flag (dormant by default)
- [ ] `/health` endpoint
- [ ] `/reset` endpoint — reload main scene, reset state autoload, clear watchers, restore `time_scale`/pause
- [ ] `/node/<path>` endpoint (basic node info)
- [ ] `GET /node?test_id=x` — metadata-based lookup (no scripts required)
- [ ] `/node/<path>/property/<name>` endpoint
- [ ] `/scene/current` endpoint (scene metadata)
- [ ] `/state` endpoint (paused, FPS, physics_active)
- [ ] `/input/map` endpoint (configured input actions)
- [ ] JS client: `npm init`, basic `fetch()` wrapper
- [ ] Manual test: Node script queries a running game

### Sprint 2 — Input & Scene (Week 2)

- [ ] `POST /input/click` — simulate mouse click at node position
- [ ] `POST /input/type` — simulate keyboard input
- [ ] `POST /input/key` — send action keys (ui_accept, ui_cancel, etc.)
- [ ] Injected events carry explicit `device` IDs on Godot 4.7+ (`InputEvent.DEVICE_ID_KEYBOARD`/`DEVICE_ID_MOUSE` — GH-116274); driver sets `Input.ignore_joypad_on_unfocused_application = false` at startup
- [ ] `POST /scene/load` — change scenes
- [ ] `GET /assets/loaded` — list loaded resources (textures, sounds, scenes)
- [ ] `GET /ui/layout/<path>` — control tree anchors/size/position
- [ ] JS client: `click()`, `type()`, `loadScene()`, `getAssets()`, `getLayout()`
- [ ] Verify input doesn't conflict with game's own input handling

### Sprint 3 — Signals & Assertions (Week 3)

- [ ] `POST /signal/watch` + `GET /signal/poll` + `GET /signal/wait`
- [ ] `POST /assert/visible`, `POST /assert/enabled`, `POST /assert/property`
- [ ] JS client: `waitVisible()`, `assertVisible()`, `assertProperty()` — assertions are auto-retrying (poll until deadline, Playwright-style; e.g. `assertVisible(path, timeout=3000)`)
- [ ] Cucumber step definitions for all operations
- [ ] `POST /state/set` + `GET /state/schema` (state autoload convention)
- [ ] Determinism endpoints: `/dev/seed`, `/dev/time_scale`, `/dev/pause`
- [ ] Timeout handling on all wait operations
- [ ] Error responses with meaningful messages

### Sprint 4 — Polish & CI (Week 4)

- [ ] Headless mode testing and validation
- [ ] `@godriver/cli` fail-fast watchdog: health-tick timeout (default 15s) → dump Godot stderr, kill process, exit code 2; covers both graceful stalls and hard crashes (segfault/driver panic — process-exit detection, not just health ticks)
- [ ] CI matrix: Godot 4.3 / 4.5 / 4.7 × Linux + Windows, with and without `--headless` (the "4.3+ floor" claim is only true if tested)
- [ ] JUnit XML reporter for Cucumber.js
- [ ] Exit code reporting
- [ ] Example test suite (5-10 Gherkin scenarios covering a real game flow)
- [ ] README with full API reference
- [ ] Basic CI pipeline example (GitHub Actions)

### Sprint 5 — Visual Regression (Week 5)

- [ ] `POST /screenshot/capture` — full viewport PNG via GDScript
- [ ] `POST /screenshot/region` — capture specific node bounds
- [ ] Install `pixelmatch` + `sharp` as dependencies
- [ ] `js/visual` — VisualComparator class (same API as Watershed's `@watershed-labs/visual`)
- [ ] Cucumber step: `Then the screen should match baseline "main-menu"` with `pixelmatch` threshold (default 1%)
- [ ] Baseline management: `UPDATE_BASELINE=true` flag (same as Watershed)
- [ ] HTML diff report on failure: `getDiffReport()` (same as Watershed)
- [ ] Heatmap diff output: `--diff-output` flag for debugging
- [ ] Region-of-interest comparison for UI elements

### Sprint 6 — Extras (Stretch)

- [ ] Drag & drop simulation
- [ ] Gamepad input simulation
- [ ] Go client (port for zero-runtime CI)
- [ ] Godot Editor plugin (run tests from editor)
- [ ] Test recording mode
- [ ] Parallel tests (multiple Godot instances)

## Documentation

An industry-grade framework ships docs as a first-class deliverable, structured after **Diátaxis** (tutorial → how-to → reference → explanation):

| Type                            | Location                            | Content                                                                                                                                                                                 |
| ------------------------------- | ----------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Tutorial** (learning)         | `docs/getting-started.md`           | Install addon + client, first passing test in 5 minutes                                                                                                                                 |
| **How-to** (tasks)              | `docs/basic-usage.md`               | Writing features with the pre-built steps, running via `js/cli`, reading reports                                                                                                        |
| **How-to** (tasks)              | `docs/advanced-usage.md`            | Custom step definitions, extending the World, parallel workers, CI integration (GitHub Actions/GitLab), state injection, fixture scenes, determinism controls, visual baseline workflow |
| **Reference** (lookup)          | `docs/STEP_LIBRARY.md`              | Every pre-built step: signature, parameters, Gherkin example, error modes                                                                                                               |
| **Reference** (lookup)          | `spec/SPEC.md`                      | HTTP API: endpoint, request/response JSON, status codes                                                                                                                                 |
| **Explanation** (understanding) | `docs/technical/architecture.md`    | Process model, HTTP boundary, package design                                                                                                                                            |
| **Explanation** (understanding) | `docs/technical/addon-internals.md` | Handler map, threading model, input injection pipeline, test_id resolution                                                                                                              |
| **Explanation** (understanding) | `docs/technical/determinism.md`     | Why games are non-deterministic, seeding strategy, time-scale gotchas                                                                                                                   |
| **Guides** (task-oriented)      | `docs/guides/`                      | Visual regression, testing game state, debugging flaky tests, porting to another language, migrating from manual QA                                                                     |

**Principles:**

- Every endpoint documented with a copy-pasteable `curl` example and JSON response
- Every pre-built step has a runnable Gherkin example — `STEP_LIBRARY.md` is generated from step definitions so it cannot drift
- All doc examples are executed in CI (docs that lie are worse than no docs)
- Root `README.md` = 60-second pitch + quickstart; each `js/*` package gets its own README
- `CHANGELOG.md` per SemVer release; docs versioned with the code

**Definition of done (v1.0):** getting-started + basic-usage + STEP_LIBRARY + SPEC complete and CI-verified; advanced-usage and guides land incrementally per sprint.

## Open Questions

1. ~~**HTTP server implementation**~~ **Resolved: vendor GodotTPD (MIT), hand-roll only as fallback** — Godot has no built-in HTTP server class, but we don't need to write one: `godottpd` (132★, MIT, ExpressJS-style `HttpRouter` API; original deprecated → current fork `bit-garden/godottpd`) and `godot-rest-api-server` (built on GodotTPD) already solve HTTP/1.1 parsing + threading in GDScript. Sprint 0 Spike A validates vendoring; a hand-rolled minimal parser over `TCPServer` remains the fallback. **Evaluated and rejected: `abrusle/godottpd` fork** — adds TLS (`StreamPeerTLS`) and CORS, both out of scope for a localhost-only test driver (token auth suffices; clients are not browsers); identical threading model (thread-per-request off main thread) so it removes none of the hazards; README contradicts its own source on TLS support. If HTTPS is ever needed (remote device testing), it is a deliberate spec change — and the transport mutex should then be written against the `StreamPeer` base class.
2. ~~**Port conflict handling**~~ **Resolved: fail hard, configurable, opt-in ephemeral** — default 9090; taken port → fail with a clear error (predictability in CI beats magic). Override via `--test-driver-port=N`. Opt-in `--test-driver-port=0` = OS-assigned ephemeral port, printed to stdout so the client can discover it.
3. ~~**Addon isolation**~~ **Resolved: EditorPlugin + dormant autoload** — EditorPlugin registers the server autoload on enable; the autoload checks `OS.get_cmdline_user_args()` and stays dormant unless `--test-driver` is present. Zero overhead in shipped builds.
4. ~~**Authentication**~~ **Resolved: localhost-only, optional token** — server binds to `127.0.0.1` only. The API is read-mostly + input simulation (not command execution like godot-mcp), so tokens are friction by default. Optional `--test-driver-token` for shared CI machines.
5. ~~**Reuse vs build**~~ **Resolved: build from scratch, study godot-e2e** — their transport is JSON-over-TCP framing, fundamentally incompatible with HTTP/1.1 (the transport half is unusable). Study their input-synthesis handlers. The real asset is `SPEC.md`, which no fork provides.
6. ~~**Godot version floor**~~ **Resolved: 4.3+** — everything used (`TCPServer`, `Thread`, `Input.parse_input_event`, `get_meta`, `OS.get_cmdline_user_args`, viewport screenshots) exists by 4.3 with stable threading. CI-tested against latest stable (4.7).
7. ~~**SSIM library** — Use `sharp` (npm) for image processing, or `jimp` (pure JS, no native deps)?~~ **Resolved: `sharp` + `pixelmatch`** — same stack as Watershed (`@watershed-labs/visual`), battle-tested, MIT + Apache 2.0 licenses, no pure-JS alternative needed.
8. ~~**Element identification**~~ **Resolved: Node metadata `test_id`** — set via Inspector on any node, zero scripts; groups for collections; node path fallback.
9. ~~**State injection target**~~ **Resolved: convention over configuration** — writes to the project's state autoload (default `GameState`, configurable via project setting), JSON→typed-var coercion, unknown keys → 400 + `GET /state/schema`.

**All 9 questions resolved — no open items.**

## File Structure

```
godot-test-driver/                        ← monorepo (split by LANGUAGE, then by functionality)
├── PLAN.md
├── LICENSE
├── README.md
├── spec/                                 ← language-neutral
│   └── SPEC.md                           ← HTTP API contract — the language boundary
├── docs/                                 ← documentation (Diátaxis: tutorial / how-to / reference / explanation)
│   ├── getting-started.md                ← tutorial: first test in 5 minutes
│   ├── basic-usage.md                    ← how-to: write features with the pre-built steps
│   ├── advanced-usage.md                 ← how-to: custom steps, parallel runs, CI, state injection
│   ├── STEP_LIBRARY.md                   ← reference: all 62 steps with Gherkin examples
│   ├── guides/                           ← task-oriented guides
│   │   ├── visual-regression.md
│   │   ├── testing-game-state.md
│   │   ├── debugging-flaky-tests.md
│   │   └── porting-to-another-language.md
│   └── technical/                        ← explanation & internals
│       ├── architecture.md
│       ├── addon-internals.md
│       └── determinism.md
├── addons/                               ← engine-side: SINGLE implementation, language-independent
│   ├── godot-test-driver/
│       ├── plugin.cfg
│       ├── plugin.gd                     ← autoload entry point
│       ├── http_server.gd                ← HTTP routing layer (on vendored godottpd — see Open Q1 / Spike A)
│       ├── api_handler.gd                ← route requests to handlers
│       └── handlers/
│           ├── node_handler.gd           ← discovery + test_id metadata lookup
│           ├── input_handler.gd          ← input simulation + input map
│           ├── signal_handler.gd         ← signal watching
│           ├── scene_handler.gd          ← scene metadata + load
│           ├── state_handler.gd          ← state injection + game state
│           ├── asset_handler.gd          ← loaded resources + UI layout
│           ├── determinism_handler.gd    ← RNG seed, time scale, pause
│           └── screenshot_handler.gd     ← viewport/node screenshots
│   └── godottpd/                         ← vendored MIT HTTP server (bit-garden/godottpd fork) — pending Sprint 0 Spike A
│       ├── VENDORED.md                   ← upstream URL, pinned commit, license, how-to-update procedure
│       └── LICENSE                       ← upstream MIT license preserved in the vendored tree
├── js/                                   ← LANGUAGE: JavaScript ("type": "module" everywhere)
│   ├── package.json                      ← npm workspaces root
│   ├── core/                             ← functionality: HTTP client (ZERO runner deps)
│   │   ├── package.json
│   │   └── src/
│   │       ├── client.js                 ← request/response, error mapping
│   │       ├── nodes.js                  ← node/test_id/group queries
│   │       ├── input.js                  ← click/type/key/drag
│   │       ├── state.js                  ← state injection + determinism
│   │       └── waits.js                  ← polling helpers
│   ├── cucumber/                         ← functionality: BDD layer (depends on core only)
│   │   ├── package.json
│   │   ├── cucumber.js                   ← Cucumber config
│   │   └── src/
│   │       ├── world.js                  ← GodotWorld extends World
│   │       ├── hooks.js                  ← Before/After order
│   │       └── steps/                    ← the 62 pre-built steps
│   │           ├── navigation.steps.js
│   │           ├── interaction.steps.js
│   │           ├── assertion.steps.js
│   │           ├── wait.steps.js
│   │           ├── state.steps.js
│   │           └── determinism.steps.js
│   ├── visual/                           ← functionality: pixelmatch + sharp
│   │   ├── package.json
│   │   └── src/visual.js
│   └── cli/                              ← functionality: orchestrator
│       ├── package.json
│       └── src/cli.js                    ← launches Godot, runs Cucumber, exit codes
├── python/                               ← FUTURE: mirrors js/ shape (core → behave layer → tools)
├── baselines/                            ← screenshot baselines (per project)
│   └── .gitkeep
└── examples/                             ← consuming-project example
    ├── features/
    │   ├── start_game.feature
    │   └── workshop.feature
    └── step_definitions/
        └── game.steps.js
```

### Consuming from WrongVersion (or any Godot project)

**Godot addon** — copy `addons/godot-test-driver/` into your project:

```bash
cp -r godot-test-driver/addons/godot-test-driver/ WrongVersion/addons/
```

**JS client** — install via npm or symlink:

```bash
# Option A: npm link (development)
cd godot-test-driver/js/core && npm link
cd WrongVersion/test && npm link @godriver/core @godriver/cucumber

# Option B: git submodule
git submodule add <repo-url> WrongVersion/test/driver

# Option C: copy (simplest)
cp -r godot-test-driver/js/ WrongVersion/test/driver/
```

**Test specs** — live in the consuming project:

```
WrongVersion/test/
├── PLAN.md                  ← game-specific test plan
├── driver/                  ← symlink or copy of godot-test-driver
├── features/                ← Gherkin feature files
│   ├── start_new_game.feature
│   ├── pause_menu.feature
│   └── workshop.feature
├── step_definitions/        ← step implementations
│   ├── navigation.steps.js
│   └── game_state.steps.js
├── screens/                 ← screen abstractions for this game
│   ├── BaseScreen.js
│   ├── MainScreen.js
│   └── WorkshopScreen.js
├── support/                 ← World, hooks, reporters
│   ├── world.js
│   ├── hooks.js
│   └── reporter.js
└── baselines/               ← screenshot baselines
```
