# Godriver

> Automated E2E and Cucumber BDD testing framework for **Godot 4**.

Godriver combines a lightweight, thread-safe GDScript HTTP addon with a suite of Node 24+ packages (`@godriver/core`, `@godriver/cucumber`, `@godriver/cli`) to enable deterministic end-to-end testing, input injection, state mutation, and Cucumber BDD testing against running Godot engine instances.

---

## Features

* **Zero-Dependency Core**: `@godriver/core` has zero external runtime dependencies, built entirely on Node 24+ native `fetch`.
* **Playwright-Parity Assertions**: Auto-retrying assertion polling (`assertVisible`, `assertEnabled`, `assertProperty`, `assertText`) that resolves timing issues and prevents flaky tests.
* **Resilient Target Resolution**: Target nodes by scene tree path or metadata-based `test_id` (`driver.click("test_id:btn_submit")`).
* **Input Injection**: Click `Control` nodes or `Area2D` hotspots, type text into `LineEdit` controls, and dispatch `InputMap` actions under `--headless`.
* **Determinism Controls**: Seed global RNG (`/dev/seed`), control `Engine.time_scale`, and pause physics or processing while keeping HTTP inspection active.
* **State Seeding**: Write any node property (`driver.setProperty`) to arrange a specific game state — teleport the player, set counters, update labels — without replaying the flow.
* **Held-Key Testing**: `keyDown`/`keyUp` split endpoints make held key state (`is_action_pressed`) observable across frames.
* **Responsive Testing**: `driver.resize(w, h)` changes the root window at runtime; assert layout and capture per-resolution baselines.
* **Visual Regression**: `driver.screenshot()` + `@godriver/visual` (pixelmatch diffing, baselines, HTML diff reports).
* **Screen Object Generator**: `godriver generate` scans the live scene tree and emits a typed Screen Objects module from every `test_id` node.
* **Fail-Fast Watchdog**: `@godriver/cli` monitors engine health during test execution and dumps `stderr` logs on engine stalls or crashes.

---

## Architecture & Packages

| Package / Module | Description |
|---|---|
| Addon | GDScript HTTP server addon for Godot 4 |
| `@godriver/core` | Zero-dependency Node 24+ HTTP client |
| `@godriver/cucumber` | BDD `GodotWorld`, lifecycle hooks, and step library |
| `@godriver/cli` | Engine process launcher & fail-fast watchdog runner |
| `@godriver/visual` | Pixelmatch comparator + baseline workflow (`assertMatchesBaseline`) |

---

## Quickstart

See the [Getting Started Guide](getting-started.md) for full installation instructions.

```bash
npm install --save-dev @godriver/core @godriver/cucumber @godriver/cli
npx godriver --godot /path/to/godot --project .
```

---

## Quick Code Example

```javascript
import { connect } from "@godriver/core";

const driver = await connect(9999);
await driver.reset();

const health = await driver.health();
console.log(`Connected to Godot ${health.godot_version}`);

await driver.click("test_id:btn_submit");
await driver.assertText("test_id:status_label", "Submitted!");

await driver.loadScene("scenes/level_2.tscn", { tweenMode: "await" });
driver.close();
```

---

## Headless Mode Considerations

Running tests under Godot's `--headless` mode has specific engine characteristics:

- **Input & Hotspots**: `Control` clicking, typing, and `Area2D` collision object clicking work out-of-the-box. Godriver includes an automatic direct delivery fallback for `Area2D` hotspots in headless mode where `_process_picking()` may not tick.
- **Scene Changes**: Button handlers that call `change_scene_to_file()` are fully supported and will not crash the runner.
- **Audio**: No audio hardware exists under `--headless`; tests should avoid asserting on audio playback state.
- **Rendering**: Screen visual diffs require a virtual framebuffer (`xvfb` / software OpenGL).

---

## Documentation

- [Getting Started](getting-started.md) — 3-step setup, `setState` conventions, and `test_id` usage
- [API Reference](api-reference.md) — Complete reference for all HTTP endpoints and request/response shapes
- [HTTP API Specification](specification/spec.md) — Formal HTTP endpoint contract and architectural guarantees (SPEC v0.1)
- [Troubleshooting](troubleshooting.md) — Solutions for common pitfalls

## License

[MIT License](https://github.com/samhainstudios/godot-test-driver/blob/master/LICENSE)
