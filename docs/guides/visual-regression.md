# Visual regression guide (GTD-052)

End-to-end workflow for screenshot baselines with Godriver: capture, store, compare, and report.

## Requirements and constraints

- **Driver parity**: baselines and CI captures must run with the same rendering driver (Vulkan vs llvmpipe produce pixel differences). Never mix drivers between baseline creation and comparison.
- **Platform scope (v0.1)**: Linux and Windows only. macOS headless rendering is an open question deferred to v0.2+.
- **SDR only**: HDR captures are rejected by the addon (`400 HDR_NOT_SUPPORTED`); baselines are SDR-only.
- **Headless**: `/screenshot/*` endpoints return `400 HEADLESS_RENDERING_DISABLED` under `--headless`. Visual tests need a windowed (or xvfb) run.

## Packages

| Package | Role |
|---|---|
| `@godriver/core` | `driver.screenshot()` / `driver.screenshotRegion()` capture (GTD-050) |
| `@godriver/visual` | `compare()`, `BaselineStore`, `assertMatchesBaseline()`, HTML report (GTD-051/052) |
| `@godriver/cucumber` | `Then the screen should match baseline "..."` steps (GTD-052) |

## Baseline conventions

- Baselines live under `tests/baselines/` (override with `GODRIVER_BASELINES_DIR`).
- Each baseline is a pair: `<name>.png` + `<name>.json` sidecar (`{driver, width, height, roi, exclude, updatedAt}`).
- **Baselines are git-tracked.** Mismatch artifacts under `artifacts/visual/` (override with `GODRIVER_ARTIFACTS_DIR`) are gitignored.

## Workflow

### 1. Capture a baseline

```sh
UPDATE_BASELINE=true node --test your-visual.test.js
```

First run without a baseline and without `UPDATE_BASELINE=true` throws `BaselineMissingError` with guidance. With the flag set, the capture is written as the baseline (plus sidecar) and the assertion passes.

### 2. Assert in tests

```js
import { connect } from "@godriver/core";
import { BaselineStore, assertMatchesBaseline } from "@godriver/visual";

const driver = await connect(9090);
const store = new BaselineStore(); // tests/baselines + artifacts/visual
await assertMatchesBaseline(store, "main_menu", {
	screenshot: driver.screenshot.bind(driver),
	threshold: 0.01,
	// roi: { x, y, w, h },            // restrict comparison
	// exclude: { rects: [...] },      // mask dynamic regions (clocks, cursors)
});
```

On mismatch the assertion writes `artifacts/visual/<name>/{actual,diff,report}.png|html` and throws `BaselineMismatchError` carrying the report path.

### 3. Regenerate after an intentional change

```sh
UPDATE_BASELINE=true node --test your-visual.test.js
```

Review the diff in the report before committing the new baseline.

### 4. Debug a passing test

```sh
GODRIVER_DIFF_OUTPUT=1 node --test your-visual.test.js
```

Writes the diff PNG + report even when the comparison passes.

## HTML diff report

`report.html` is self-contained (images inlined as base64): side-by-side baseline/actual/diff, the mismatch stats, and the baseline sidecar metadata. Open it directly from `artifacts/visual/<name>/report.html`.

## Cucumber steps

Register alongside the built-in steps:

```js
import { registerSteps } from "@godriver/cucumber";
import { registerVisualSteps } from "@godriver/cucumber/steps/visual";

registerSteps(Cucumber);
registerVisualSteps(Cucumber);
```

```gherkin
Then the screen should match baseline "main_menu"
Then the screen should match baseline "hud" at node "/root/Main/HUD"
Then the screen should match baseline "portrait" at test_id "hud_root"
```

Baselines/artifacts directories honor the same env vars; `UPDATE_BASELINE=true` works identically.

## Responsive baselines (GTD-053)

`POST /window/resize` (JS: `driver.resize(width, height, opts)`) changes the root window size at runtime, so one test session can exercise multiple resolutions:

```js
const driver = await connect(9090);
const original = await driver.windowState();

for (const [w, h] of [[1280, 720], [1920, 1080], [800, 600]]) {
	await driver.resize(w, h);
	await driver.waitFrames(2); // let layout settle
	await assertMatchesBaseline(store, `menu_${w}x${h}`, {
		screenshot: driver.screenshot.bind(driver),
	});
}

// restore
await driver.resize(original.size.width, original.size.height);
```

Name baselines per resolution (`menu_1280x720.png`) since the comparator rejects size mismatches by default. Stretch overrides (`stretchMode`, `aspect`, `scale`) let you test the game's `canvas_items`/`viewport` scaling paths explicitly. Always restore the original size afterwards (later suites/screenshots depend on it).

## CI notes

- Run visual tests on the same OS + rendering driver as baseline creation (driver parity).
- Keep `UPDATE_BASELINE` unset in CI; baselines come from the repo.
- Upload `artifacts/visual/` as the CI artifact on failure for triage.
