# @godriver/cli

Command line interface and fail-fast watchdog runner for Godriver.

## Install

```sh
npm install @godriver/cli
```

## Usage

```sh
# Launch the game (headless by default), wait for /health, run your test suite
godriver --godot /path/to/godot --project . -- cucumber-js features/

# Windowed run (watch the game while tests drive it)
godriver --no-headless --project . -- npm test
```

Flags: `--godot <path>` (or `GODOT_BIN` env), `--project <dir>`, `--port <n>`
(or `GODRIVER_PORT`), `--no-headless`. Everything after `--` is passed to the
test runner.

## Watchdog

The built-in watchdog polls `/health` while the game runs. If the health tick
deadline (default 15s) expires, it dumps the game's stderr, kills the process,
and the CLI exits with code 2 — fail-fast for CI instead of a hung job.

Exit codes: `0` success, `1` test failure, `2` infra error (game crash/watchdog).

See the [repo docs](https://github.com/SamhainStudios/godriver/tree/master/js/cli#readme)
for details.

## Screen Object generator (GTD-056)

```sh
# against a running game (launched with --test-driver)
godriver generate --port 9090 --out screens.generated.js
```

Walks the scene tree via the driver API, collects every node carrying
`test_id` metadata, and emits an ES module exporting `TEST_IDS` (test_id to
absolute path) plus a `GameScreens` class with generic helpers:
`click(name)`, `type(name, text)`, `expectVisible(name)`, `property(name)`,
`setProperty(name, prop, value)` (GTD-055 seeding), `waitForSignal(name,
signal)`. Extend the generated class with game-specific flows; re-run the
generator after scene changes.
