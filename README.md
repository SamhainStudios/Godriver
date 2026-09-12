# Godriver

> Automated E2E and Cucumber BDD testing framework for **Godot 4**.

Godriver combines a lightweight, thread-safe GDScript HTTP addon with a suite of Node 24+ packages (`@godriver/core`, `@godriver/cucumber`, `@godriver/cli`) to enable deterministic end-to-end testing, input injection, state mutation, and Cucumber BDD testing against running Godot engine instances.

---

## Features

* Zero-Dependency Core: `@godriver/core` has zero external runtime dependencies—built entirely on Node 24+ native `fetch`.
* Playwright-Parity Assertions: Auto-retrying assertion polling (`assertVisible`, `assertEnabled`, `assertProperty`) that resolves timing issues and prevents flaky tests.
* Input Injection: Click `Control` nodes or `Area2D` hotspots, type text into `LineEdit` controls, and dispatch `InputMap` actions seamlessly under `--headless`.
* **Determinism Controls**: Seed global RNG (`/dev/seed`), control `Engine.time_scale`, and pause physics or processing while keeping HTTP inspection active.
* **Fail-Fast Watchdog**: `@godriver/cli` monitors engine health during test execution and dumps `stderr` logs on engine stalls or crashes.

---

## Architecture & Packages

| Package / Module | Description | Path |
|---|---|---|
| **Addon** | GDScript HTTP server addon for Godot 4 | [`addons/godriver`](addons/godriver) |
| **`@godriver/core`** | Zero-dependency Node 24+ HTTP client | [`js/core`](js/core) |
| **`@godriver/cucumber`** | BDD `GodotWorld`, lifecycle hooks, and step library | [`js/cucumber`](js/cucumber) |
| **`@godriver/cli`** | Engine process launcher & fail-fast watchdog runner | [`js/cli`](js/cli) |

---

## Quickstart (3 Steps)

### 1. Copy Addons to your Godot Project
Copy both required folders into your Godot project's `addons/` directory:
- `addons/godriver`
- `addons/godriver`

Then open **Project -> Project Settings -> Plugins** in Godot and enable **Godriver Test Driver**.

### 2. Add `.gdignore` to `node_modules`
Prevent Godot from attempting to import JS files as engine resources by creating an empty `.gdignore` in your JS directory:

```bash
touch node_modules/.gdignore
```

### 3. Install & Run Tests
Install `@godriver/cli` and run your Cucumber feature suite:

```bash
npm install --save-dev @godriver/core @godriver/cucumber @godriver/cli

# Run feature suite with Godot launcher & watchdog
npx godriver --godot /path/to/godot --project .
```

---

## Quick Code Example

```javascript
import { connect } from "@godriver/core";

// Connect to running Godot instance
const driver = await connect(9999);

// Inspect health & current scene
const health = await driver.health();
console.log(`Connected to Godot ${health.godot_version}`);

// Click a button by test_id and assert label text
await driver.click("test_id:btn_submit");
await driver.assertProperty("/root/Main/StatusLabel", "text", "Submitted!");

driver.close();
```

---

## Documentation & Links

* [Getting Started Guide](docs/getting-started.md) — Step-by-step setup, `setState` order, and GDScript setter patterns.
* [HTTP Specification (SPEC v0.1)](spec/SPEC.md) — Complete HTTP endpoint envelope & contract reference.
* [License](LICENSE) — MIT License.
