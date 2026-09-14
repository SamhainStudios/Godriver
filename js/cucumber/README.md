# @godriver/cucumber

Cucumber BDD world, hooks, and step definitions for Godriver.

## Install

```sh
npm install @godriver/cucumber
```

Peer dependencies: `@cucumber/cucumber` (10.x or 11.x) and, for the visual
steps, `@godriver/visual`.

## Usage

```js
import { GodotWorld, registerHooks, registerSteps } from "@godriver/cucumber";
import { registerVisualSteps } from "@godriver/cucumber/steps/visual";

registerHooks(Cucumber);
registerSteps(Cucumber);
registerVisualSteps(Cucumber); // optional, requires @godriver/visual
```

Set `GODRIVER_PORT` / `GODRIVER_HOST` to point the World's driver at the game
(defaults `9090` / `127.0.0.1`).

## Built-in steps

| Step | Behavior |
| --- | --- |
| `Given I load scene {string}` | `driver.loadScene(path)` |
| `When I click {string}` | `driver.click(target)` |
| `When I click test_id {string}` | `driver.click(id, { testId: true })` |
| `When I type {string} into {string}` | `driver.type(target, text)` |
| `When I press key {string}` | `driver.pressKey(key)` |
| `Then I should see {string}` / `I should not see {string}` | visibility assertions |
| `Then node {string} should be enabled` | enabled assertion |
| `Then node {string} property {string} should be {string}` | property assertion |
| `When I watch signal {string} on {string}` / `Then I wait for signal {string} on {string}` | signal wait |
| `When I set state {string} to {string}` | state write |
| `When I set time scale to {float}` / `I pause the game` / `I unpause the game` | determinism controls |

## Visual steps (GTD-052)

```gherkin
Then the screen should match baseline "main_menu"
Then the screen should match baseline "hud" at node "/root/Main/HUD"
Then the screen should match baseline "portrait" at test_id "hud_root"
```

- Baselines: `GODRIVER_BASELINES_DIR` (default `tests/baselines/`), git-tracked.
- Mismatch artifacts: `GODRIVER_ARTIFACTS_DIR` (default `artifacts/visual/`),
  gitignored; a self-contained `report.html` is written on failure.
- `UPDATE_BASELINE=true` captures/regenerates baselines.

See `docs/guides/visual-regression.md` for the full workflow.
