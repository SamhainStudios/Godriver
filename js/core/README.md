# @godriver/core

Portable HTTP client for the [Godot Test Driver](../../README.md) addon — the
contract layer every language port reimplements. Zero runner dependencies,
ES modules, Node 18+ (built-in fetch).

## Install

```bash
npm install @godriver/core
```

## Connect

```js
import { connect } from "@godriver/core";

// Game launched with: godot --path . -- --test-driver
const driver = await connect(9090);

const health = await driver.health();
// { status: "ok", godot_version: "4.7.2", spec_version: "0.1" }
```

`connect()` verifies `/health` before returning — a refused connection fails
immediately with a typed `ConnectionError`, not on your first real request.

## Quickstart (runnable)

[`examples/smoke.mjs`](../../examples/smoke.mjs) is a committed end-to-end
smoke script: launch a game with the addon
(`godot --headless --path . -- --test-driver`), then run
`node examples/smoke.mjs 9090` — it exercises `/health`, `/node/<path>`,
property reads, `/scene/current`, `/state`, and the typed-error path, exiting
0 only when every response matches its SPEC §5 shape. It doubles as the
executable-docs check for the SPEC `curl` examples.

### Options

```js
const driver = await connect(9090, {
  host: "127.0.0.1",     // addon binds 127.0.0.1 only
  token: "s3cret",       // when launched with --test-driver-token=s3cret
  timeoutMs: 5000,       // per-request timeout (AbortSignal)
  maxSockets: 16,        // undici pool size — see below
});
```

### Pool sizing (SPEC §6.1)

The addon caps concurrent long-polls at `max_blocked_waits` (8). Node's
default undici pool is 4–6 sockets, so parallel tests issuing long-polls
would starve. `@godriver/core` sets `maxSockets: 16` explicitly — raise it
if your suite runs more concurrent long-polls than the addon cap.

## Error model

Every enveloped error (`{ok: false, error: {code, message, details}}`)
surfaces as a typed `DriverError`:

```js
import { connect, DriverError, ConnectionError } from "@godriver/core";

try {
  await driver.request("/node/does/not/exist");
} catch (e) {
  if (e instanceof ConnectionError) {
    // addon unreachable / timeout — check the game is running
  } else if (e instanceof DriverError) {
    e.code;    // "NODE_NOT_FOUND" (SPEC Appendix A)
    e.status;  // 404
    e.details; // structured details or null
  }
}
```

Error codes are the frozen registry in SPEC Appendix A
(`NODE_NOT_FOUND`, `AMBIGUOUS_TEST_ID`, `SERVER_BUSY`, `UNAUTHORIZED`, …).
A malformed envelope (non-JSON, missing `ok`) maps to
`DriverError` code `INTERNAL_ERROR`.

## Low-level requests

`driver.request(path, init)` unwraps the envelope and returns `data` directly:

```js
const node = await driver.request("/node/root/Main");
// { path: "/root/Main", name: "Main", type: "Node2D", ... }

await driver.request("/reset", { method: "POST", body: { tween_mode: "kill" } });
```

## Type checking

Types are JSDoc-inferred; CI runs `tsc --noEmit` against the type-test file
(`test/types.test.ts`). No TypeScript build step — the package ships plain JS.

## Responsive testing (GTD-053)

```js
const state = await driver.windowState(); // { size, viewport_size, content_scale_size, stretch }
await driver.resize(1280, 720, { stretchMode: "canvas_items", aspect: "keep_width" });
// ... assert layout / capture baselines at this resolution ...
await driver.resize(state.size.width, state.size.height); // restore
```

`resize()` posts `/window/resize` and waits one frame (same auto-wait as
click/type). See `docs/guides/visual-regression.md` for the per-resolution
baseline recipe.

## Held-key testing (GTD-054)

```js
await driver.keyDown("move_right");
// ... assert held state across frames (Input.is_action_pressed is true) ...
await driver.keyUp("move_right");
```

`keyDown`/`keyUp` inject only the pressed/released event (same key resolution
as `pressKey`: InputMap action first, then `KEY_*` constants). A `keyDown`
without a matching `keyUp` leaves the action held; `/reset` does not release
held keys.
